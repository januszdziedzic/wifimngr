// Thin wrapper around hostapd_cli for wifimngr.
// All helpers take an ifname and return either a parsed object or null.

import * as fs from "fs";

const CTRL_DIR = "/var/run/hostapd";

// key_mgmt token -> canonical security name
const key_mgmt_map = {
	"WPA-PSK":              "WPA2PSK",
	"WPA-PSK-SHA256":       "WPA2PSK",
	"FT-PSK":               "WPA2PSK",
	"SAE":                  "WPA3PSK",
	"SAE-EXT-KEY":          "WPA3PSK",
	"FT-SAE":               "WPA3PSK",
	"FT-SAE-EXT-KEY":       "WPA3PSK",
	"WPA-EAP":              "WPA2EAP",
	"WPA-EAP-SHA256":       "WPA2EAP",
	"FT-EAP":               "WPA2EAP",
	"WPA-EAP-SUITE-B":      "WPA3EAP",
	"WPA-EAP-SUITE-B-192":  "WPA3EAP",
	"OWE":                  "OWE",
	"DPP":                  "DPP",
};

// Run `hostapd_cli ... <cmd>` and return stdout as a trimmed string,
// or null on error / FAIL / UNKNOWN COMMAND.
function run(ifname, cmd) {
	let fp = fs.popen(`hostapd_cli -p ${CTRL_DIR} -i ${ifname} ${cmd} 2>/dev/null`, "r");
	if (!fp)
		return null;
	let data = fp.read("all");
	fp.close();
	if (!data)
		return null;
	data = trim(data);
	if (data == "" || data == "FAIL" || data == "UNKNOWN COMMAND")
		return null;
	return data;
}

// Run a command and parse its key=value output into an object.
function kv(ifname, cmd) {
	let data = run(ifname, cmd);
	if (!data)
		return null;
	let out = {};
	for (let line in split(data, "\n")) {
		let eq = index(line, "=");
		if (eq < 0)
			continue;
		out[substr(line, 0, eq)] = substr(line, eq + 1);
	}
	return out;
}

function get_config(ifname) {
	return kv(ifname, "get_config");
}

function status(ifname) {
	return kv(ifname, "status");
}

// Convert a hostapd get_config object into a canonical security string
// like WPA2PSK, WPA3PSK, WPA2PSK+WPA3PSK, NONE.
function format_security(cfg) {
	if (!cfg?.key_mgmt || cfg.key_mgmt == "NONE" || cfg.key_mgmt == "")
		return (cfg?.wpa == "0" || !cfg?.wpa) ? "NONE" : null;
	let seen = {};
	let names = [];
	for (let tok in split(cfg.key_mgmt, " ")) {
		let name = key_mgmt_map[tok];
		if (!name || seen[name])
			continue;
		seen[name] = true;
		push(names, name);
	}
	return length(names) ? join("+", names) : cfg.key_mgmt;
}

// Return the pairwise encryption string or null.
function encryption(cfg) {
	return cfg?.rsn_pairwise_cipher || cfg?.pairwise_cipher || cfg?.group_cipher || null;
}

// Fetch a live beacon as a hex string via `hostapd_cli raw DUMP_BEACON`.
function dump_beacon(ifname) {
	let hex = run(ifname, "raw DUMP_BEACON");
	if (!hex || length(hex) < 76)
		return null;
	return hex;
}

// Offset (in hex chars) of the first IE in a beacon:
// 24B MAC hdr + 8B timestamp + 2B beacon_int + 2B cap = 36B = 72 hex chars.
const IES_OFFSET = 72;

// Walk beacon IEs starting at IES_OFFSET and invoke cb(id, ext_id, data_hex)
// for each element. ext_id is null for non-extension IEs.
function walk_ies(hex, cb) {
	let p = IES_OFFSET;
	let end = length(hex);
	while (p + 4 <= end) {
		let id = +("0x" + substr(hex, p, 2));
		let len = +("0x" + substr(hex, p + 2, 2));
		let data_start = p + 4;
		let data_end = data_start + len * 2;
		if (data_end > end)
			break;
		let data = substr(hex, data_start, len * 2);
		let ext_id = null;
		if (id == 255 && len >= 1) {
			ext_id = +("0x" + substr(data, 0, 2));
			data = substr(data, 2);
		}
		cb(id, ext_id, data);
		p = data_end;
	}
}

// Determine if the SSID is hidden by inspecting the live beacon.
// Returns true/false when detected, null when unavailable.
function beacon_hidden(hex) {
	if (!hex || length(hex) < IES_OFFSET + 4)
		return null;
	// First IE is always SSID (tag 0).
	if (substr(hex, IES_OFFSET, 2) != "00")
		return null;
	return substr(hex, IES_OFFSET + 2, 2) == "00";
}

// Slice `count` bytes out of a hex string starting at byte offset `off`.
function hex_slice(hex, off, count) {
	return substr(hex, off * 2, count * 2);
}

// Read a single byte (as integer) at byte offset `off` in a hex string.
function hex_byte(hex, off) {
	return +("0x" + substr(hex, off * 2, 2));
}

function parse_ht(body) {
	// HT Capabilities element (26 bytes):
	//   2B HT Cap Info | 1B A-MPDU Params | 16B Supported MCS Set
	//   | 2B HT Ext Cap | 4B TX Beamforming | 1B ASEL
	if (length(body) < 2 * 26)
		return null;
	return {
		caps: hex_slice(body, 0, 2),
		mcs:  hex_slice(body, 3, 16),
	};
}

function parse_vht(body) {
	// VHT Capabilities element (12 bytes):
	//   4B VHT Cap Info | 8B VHT Supported MCS and NSS Set
	if (length(body) < 2 * 12)
		return null;
	return {
		caps: hex_slice(body, 0, 4),
		mcs:  hex_slice(body, 4, 8),
	};
}

function parse_he(body) {
	// HE Capabilities element (after ext_id byte):
	//   6B MAC Caps | 11B PHY Caps | variable MCS/NSS | optional PPE
	if (length(body) < 2 * 17)
		return null;
	let mac = hex_slice(body, 0, 6);
	let phy = hex_slice(body, 6, 11);
	let phy0 = hex_byte(phy, 0);
	let phy6 = hex_byte(phy, 6);
	// MCS groups (4B each): always <=80; +160MHz if phy[0]&0x08; +80+80 if phy[0]&0x10
	let mcs_bytes = 4;
	if (phy0 & 0x08) mcs_bytes += 4;
	if (phy0 & 0x10) mcs_bytes += 4;
	let mcs = hex_slice(body, 17, mcs_bytes);
	let ppe_off = 17 + mcs_bytes;
	let ppe = (phy6 & 0x80) && length(body) > ppe_off * 2
		? substr(body, ppe_off * 2)
		: "";
	return { phy_caps: phy, mac_caps: mac, mcs, ppe };
}

function parse_eht(body, he_phy0) {
	// EHT Capabilities element (after ext_id byte):
	//   2B MAC Caps | 9B PHY Caps | variable MCS/NSS | optional PPE
	if (length(body) < 2 * 11)
		return null;
	let mac = hex_slice(body, 0, 2);
	let phy = hex_slice(body, 2, 9);
	let eht_phy0 = hex_byte(phy, 0);
	// PPE Thresholds Present: EHT phy byte 5 bit 3 (0x08)
	let phy5 = hex_byte(phy, 5);
	// MCS/NSS size (per IEEE 802.11be):
	//   if HE phy[0] has any channel width bit set (mask 0xfe):
	//     base 3B for <=80; +3B if HE 160MHz (HE phy[0] & 0x08); +3B if EHT 320MHz (EHT phy[0] & 0x02)
	//   else 20MHz-only: 4B
	let mcs_bytes;
	if ((he_phy0 ?? 0) & 0xfe) {
		mcs_bytes = 3;
		if (he_phy0 & 0x08) mcs_bytes += 3;
		if (eht_phy0 & 0x02) mcs_bytes += 3;
	} else {
		mcs_bytes = 4;
	}
	let mcs = hex_slice(body, 11, mcs_bytes);
	let ppe_off = 11 + mcs_bytes;
	let ppe = (phy5 & 0x08) && length(body) > ppe_off * 2
		? substr(body, ppe_off * 2)
		: "";
	return { phy_caps: phy, mac_caps: mac, mcs, ppe };
}

// Extract HT/VHT/HE/EHT capabilities from a beacon into the same structured
// form used by wifi_device get_status (caps/mcs for HT/VHT; mac/phy/mcs/ppe
// for HE/EHT).
function beacon_caps(hex) {
	if (!hex)
		return {};
	let raw = {};
	walk_ies(hex, (id, ext, data) => {
		if (id == 45)                       raw.ht  = data;
		else if (id == 191)                 raw.vht = data;
		else if (id == 255 && ext == 35)    raw.he  = data;
		else if (id == 255 && ext == 108)   raw.eht = data;
	});
	let out = {};
	let ht = raw.ht ? parse_ht(raw.ht) : null;
	if (ht) out.ht = ht;
	let vht = raw.vht ? parse_vht(raw.vht) : null;
	if (vht) out.vht = vht;
	let he_phy0 = null;
	let he = raw.he ? parse_he(raw.he) : null;
	if (he) {
		out.he = he;
		he_phy0 = hex_byte(he.phy_caps, 0);
	}
	let eht = raw.eht ? parse_eht(raw.eht, he_phy0) : null;
	if (eht) out.eht = eht;
	return out;
}

// Back-compat: fetch beacon and return hidden state in one call.
function hidden(ifname) {
	return beacon_hidden(dump_beacon(ifname));
}

export default {
	kv,
	get_config,
	status,
	format_security,
	encryption,
	dump_beacon,
	beacon_hidden,
	beacon_caps,
	hidden,
};

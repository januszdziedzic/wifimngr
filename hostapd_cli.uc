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

// Determine if the SSID is hidden by inspecting the live beacon.
// Returns true/false when detected, null when unavailable.
function hidden(ifname) {
	let hex = run(ifname, "raw DUMP_BEACON");
	if (!hex || length(hex) < 76)
		return null;
	// 802.11 beacon: 24B MAC hdr + 12B fixed (timestamp/beacon_int/cap) = 36B,
	// then IEs. First IE is always SSID (tag 0). Hex offset = 36*2 = 72.
	if (substr(hex, 72, 2) != "00")
		return null;
	return substr(hex, 74, 2) == "00";
}

export default {
	kv,
	get_config,
	status,
	format_security,
	encryption,
	hidden,
};

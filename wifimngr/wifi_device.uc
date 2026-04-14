import * as nl80211 from "nl80211";
import * as wifi_opclass from "wifi_opclass";

const band_names = { "0": "2g", "1": "5g", "3": "6g" };
const iftype_names = { "managed": "sta", "ap": "ap", "ibss": "adhoc", "mesh_point": "mesh", "monitor": "monitor", "p2p_client": "p2p_client", "p2p_go": "p2p_go" };
const iftype_num_names = { "2": "sta", "3": "ap", "7": "mesh" };
const MAX_AGE = 600;

function to_hex(arr) {
	let s = "";
	for (let b in arr)
		s += sprintf("%02x", b);
	return s;
}

function int_to_hex(val, bytes) {
	let s = "";
	for (let i = 0; i < bytes; i++) {
		s += sprintf("%02x", (val >> (i * 8)) & 0xff);
	}
	return s;
}

function ht_mcs_to_hex(mcs) {
	if (!mcs)
		return "";

	let bytes = [];
	for (let i = 0; i < 16; i++)
		push(bytes, 0);

	// Bytes 0-9: RX MCS bitmask
	for (let idx in mcs.rx_mcs_indexes)
		bytes[idx >> 3] |= (1 << (idx & 7));

	// Byte 12: TX params
	if (mcs.tx_mcs_set_defined)
		bytes[12] |= 1;
	if (mcs.tx_rx_mcs_set_equal)
		bytes[12] |= 2;
	if (mcs.tx_max_spatial_streams)
		bytes[12] |= ((mcs.tx_max_spatial_streams & 3) << 2);
	if (mcs.tx_unequal_modulation)
		bytes[12] |= 0x10;

	return to_hex(bytes);
}

function vht_mcs_to_hex(mcs) {
	if (!mcs)
		return "";

	// 2 bits per stream in MCS map: 0=MCS0-7, 1=MCS0-8, 2=MCS0-9, 3=not supported
	let rx_map = 0xffff, tx_map = 0xffff;

	for (let entry in mcs.rx_mcs_set) {
		let s = entry.streams - 1;
		let max_mcs = entry.mcs_indexes[length(entry.mcs_indexes) - 1];
		let val = (max_mcs >= 9) ? 2 : (max_mcs >= 8) ? 1 : 0;
		rx_map = (rx_map & ~(3 << (s * 2))) | (val << (s * 2));
	}
	for (let entry in mcs.tx_mcs_set) {
		let s = entry.streams - 1;
		let max_mcs = entry.mcs_indexes[length(entry.mcs_indexes) - 1];
		let val = (max_mcs >= 9) ? 2 : (max_mcs >= 8) ? 1 : 0;
		tx_map = (tx_map & ~(3 << (s * 2))) | (val << (s * 2));
	}

	return int_to_hex(rx_map, 2) +
	       int_to_hex(mcs.rx_highest_data_rate ?? 0, 2) +
	       int_to_hex(tx_map, 2) +
	       int_to_hex(mcs.tx_highest_data_rate ?? 0, 2);
}

function he_mcs_to_hex(mcs) {
	if (!mcs || !length(mcs))
		return "";

	// HE MCS-NSS Support field: per bandwidth (80, 160, 80+80)
	// each has 4 bytes: 2 bytes Rx MCS map + 2 bytes Tx MCS map
	// 2 bits per stream: 0=MCS0-7, 1=MCS0-9, 2=MCS0-11, 3=not supported
	let s = "";
	for (let bw_entry in mcs) {
		let rx_map = 0xffff, tx_map = 0xffff;

		for (let entry in bw_entry.rx_mcs_set) {
			let ns = entry.streams - 1;
			let max_mcs = entry.mcs_indexes[length(entry.mcs_indexes) - 1];
			let val = (max_mcs >= 10) ? 2 : (max_mcs >= 8) ? 1 : 0;
			rx_map = (rx_map & ~(3 << (ns * 2))) | (val << (ns * 2));
		}
		for (let entry in bw_entry.tx_mcs_set) {
			let ns = entry.streams - 1;
			let max_mcs = entry.mcs_indexes[length(entry.mcs_indexes) - 1];
			let val = (max_mcs >= 10) ? 2 : (max_mcs >= 8) ? 1 : 0;
			tx_map = (tx_map & ~(3 << (ns * 2))) | (val << (ns * 2));
		}

		s += int_to_hex(rx_map, 2) + int_to_hex(tx_map, 2);
	}
	return s;
}

function popcount(v) {
	let c = 0;
	while (v) { c += v & 1; v >>= 1; }
	return c;
}

function he_ppe_to_hex(ppe) {
	if (!ppe || !length(ppe) || !ppe[0])
		return "";

	// PPE Thresholds: 7-bit header + (NSTS+1) * popcount(RU_bitmask) * 6 bits
	let nsts = ppe[0] & 0x7;
	let ru_bitmask = (ppe[0] >> 3) & 0xf;
	let total_bits = 7 + (nsts + 1) * popcount(ru_bitmask) * 6;
	let total_bytes = (total_bits + 7) >> 3;

	return to_hex(slice(ppe, 0, total_bytes));
}

// Find the best netdev on a phy for scanning: prefer station, then any other.
// Filter by band frequencies to pick an interface on the correct radio.
function find_scan_dev(wiphy, freq_set) {
	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_INTERFACE,
		nl80211.const.NLM_F_DUMP, {}
	);
	if (!r)
		return null;

	let ifaces = type(r) == "array" ? r : [ r ];
	let sta_dev = null;
	let fallback = null;

	for (let iface in ifaces) {
		if (iface.wiphy != wiphy || !iface.dev)
			continue;

		// If we have band freqs, only consider interfaces on matching frequencies
		if (freq_set && iface.wiphy_freq && !freq_set[iface.wiphy_freq])
			continue;

		if (iface.iftype == nl80211.const.NL80211_IFTYPE_STATION)
			sta_dev ??= iface.dev;
		else
			fallback ??= iface.dev;
	}

	return sta_dev ?? fallback;
}

// Fetch and merge wiphy_bands for this device's wiphy
function get_wiphy_bands() {
	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_WIPHY,
		nl80211.const.NLM_F_DUMP,
		{ split_wiphy_dump: true }
	);
	if (!r)
		return null;

	// With DUMP + split, response is array; merge bands from all parts
	// and filter by our wiphy index
	let parts = type(r) == "array" ? r : [ r ];
	let bands = {};
	let iftype_ext_capa = {};

	for (let part in parts) {
		if (part.wiphy != null && part.wiphy != this.wiphy)
			continue;

		if (part.iftype_ext_capa) {
			for (let entry in part.iftype_ext_capa) {
				let name = iftype_num_names[entry.iftype] ?? entry.iftype;
				iftype_ext_capa[name] = entry;
			}
		}

		if (!part.wiphy_bands)
			continue;

		for (let i, band in part.wiphy_bands) {
			if (!band)
				continue;

			let cur = bands[i] ??= { frequencies: [], freq_info: {}, bitrates: [] };

			for (let freq in band.freqs) {
				if (freq.disabled)
					continue;
				push(cur.frequencies, freq.freq);
				let fi = {
					txpower: freq.max_tx_power ? freq.max_tx_power / 100 : 0,
					dfs: !!freq.radar,
				};
				if (freq.radar) {
					const dfs_states = [ "usable", "unavailable", "available" ];
					fi.dfs_state = dfs_states[freq.dfs_state] ?? "unknown";
					// Weather radar band (5600-5650 MHz) requires 10min CAC
					fi.cac_time = (freq.freq >= 5600 && freq.freq <= 5650) ? 600 : 60;
				}
				cur.freq_info[freq.freq] = fi;
			}

			for (let rate in band.bitrates)
				push(cur.bitrates, rate.bitrate);

			if (band.ht_capa != null)
				cur.ht_capa = band.ht_capa;
			if (band.ht_mcs_set)
				cur.ht_mcs_set = band.ht_mcs_set;
			if (band.vht_capa != null)
				cur.vht_capa = band.vht_capa;
			if (band.vht_mcs_set)
				cur.vht_mcs_set = band.vht_mcs_set;

			if (band.iftype_data) {
				cur.iftype_data ??= {};
				for (let itd in band.iftype_data) {
					for (let itype in itd.iftypes) {
						let name = iftype_names[itype] ?? itype;
						cur.iftype_data[name] = itd;
					}
				}
			}
		}
	}

	this.iftype_ext_capa = iftype_ext_capa;
	return bands;
}

function get_band_freqs() {
	let bands = this.get_wiphy_bands();
	if (!bands)
		return null;

	for (let idx, band in bands) {
		if ((band_names[idx] ?? idx) == this.band)
			return band.frequencies;
	}

	return null;
}

function get_band_freq_set() {
	let freqs = this.get_band_freqs();
	if (!freqs)
		return null;

	let set = {};
	for (let f in freqs)
		set[f] = true;
	return set;
}

function get_status() {
	let bands = this.get_wiphy_bands();
	if (!bands)
		return null;

	let status = {
		wiphy: this.wiphy,
		name: this.name,
		band: this.band,
	};

	for (let idx, band in bands) {
		if ((band_names[idx] ?? idx) != this.band)
			continue;

		if (length(band.frequencies))
			status.frequencies = band.frequencies;
		if (length(band.bitrates))
			status.bitrates = band.bitrates;

		// HT/VHT are band-level caps (always present if supported)
		let base_caps = {};
		if (band.ht_capa != null) {
			base_caps.ht = {
				caps: int_to_hex(band.ht_capa, 2),
				mcs: ht_mcs_to_hex(band.ht_mcs_set),
			};
		}
		if (band.vht_capa != null) {
			base_caps.vht = {
				caps: int_to_hex(band.vht_capa, 4),
				mcs: vht_mcs_to_hex(band.vht_mcs_set),
			};
		}

		// HE/EHT are per-iftype (from iftype_data)
		if (band.iftype_data && length(band.iftype_data)) {
			for (let name, itd in band.iftype_data) {
				let caps = { ...base_caps };

				if (itd.he_cap_phy) {
					caps.he = {
						phy_caps: to_hex(itd.he_cap_phy),
						mac_caps: to_hex(itd.he_cap_mac),
						mcs: he_mcs_to_hex(itd.he_cap_mcs_set),
						ppe: he_ppe_to_hex(itd.he_cap_ppe),
					};
				}
				if (itd.eht_cap_phy) {
					caps.eht = {
						phy_caps: to_hex(itd.eht_cap_phy),
						mac_caps: to_hex(itd.eht_cap_mac),
						mcs: to_hex(itd.eht_cap_mcs_set ?? []),
						ppe: to_hex(itd.eht_cap_ppe ?? []),
					};
				}

				let ext = this.iftype_ext_capa?.[name];
				if (ext) {
					if (ext.eml_capability != null)
						caps.eml_capability = int_to_hex(ext.eml_capability, 2);
					if (ext.mld_capa_and_ops != null)
						caps.mld_capa_and_ops = int_to_hex(ext.mld_capa_and_ops, 2);
				}

				status[name + "_caps"] = caps;
			}
		} else if (length(base_caps)) {
			status.caps = base_caps;
		}
		break;
	}

	return status;
}

function get_e4() {
	let bands = this.get_wiphy_bands();
	if (!bands)
		return null;

	for (let idx, band in bands) {
		if ((band_names[idx] ?? idx) != this.band)
			continue;

		let survey = this.get_survey();
		return wifi_opclass.get_preferences(band.freq_info, survey);
	}

	return null;
}

function update_scan_cache(dev) {
	let results = nl80211.request(
		nl80211.const.NL80211_CMD_GET_SCAN,
		nl80211.const.NLM_F_DUMP,
		{ dev }
	);

	if (!results)
		return;

	let freq_set = this.get_band_freq_set();
	let now = time();

	for (let entry in results) {
		let bss = entry.bss;
		if (!bss || !bss.bssid)
			continue;

		// Only cache results matching this radio's band
		if (freq_set && !freq_set[bss.frequency])
			continue;

		let info = {
			bssid: bss.bssid,
			frequency: bss.frequency,
			signal: bss.signal_mbm ? bss.signal_mbm / 100 : null,
			last_seen: now,
		};

		if (bss.information_elements) {
			for (let ie in bss.information_elements) {
				if (ie.type == 0)
					info.ssid = ie.data;
			}
		}

		this.scan_cache[bss.bssid] = info;
	}

	// Evict stale entries
	for (let bssid, entry in this.scan_cache) {
		if (now - entry.last_seen > MAX_AGE)
			delete this.scan_cache[bssid];
	}
}

function get_scan_results() {
	let now = time();
	let results = [];

	for (let bssid, entry in this.scan_cache) {
		push(results, {
			bssid: entry.bssid,
			ssid: entry.ssid,
			frequency: entry.frequency,
			signal: entry.signal,
			age: now - entry.last_seen,
		});
	}

	return results;
}

function get_survey() {
	let freq_set = this.get_band_freq_set();
	let dev = find_scan_dev(this.wiphy, freq_set);
	if (!dev)
		return null;

	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_SURVEY,
		nl80211.const.NLM_F_DUMP,
		{ dev }
	);
	if (!r)
		return null;

	let parts = type(r) == "array" ? r : [ r ];
	let out = [];
	for (let p in parts) {
		let s = p.survey_info;
		if (!s || !s.frequency)
			continue;
		if (freq_set && !freq_set[s.frequency])
			continue;
		let entry = { frequency: s.frequency };
		if (s.noise != null)        entry.noise = s.noise;
		if (s.in_use)               entry.in_use = true;
		if (s.time != null)         entry.active = s.time;
		if (s.busy != null)         entry.busy = s.busy;
		if (s.ext_busy != null)     entry.ext_busy = s.ext_busy;
		if (s.time_rx != null)      entry.rx = s.time_rx;
		if (s.time_tx != null)      entry.tx = s.time_tx;
		if (s.scan != null)         entry.scan = s.scan;
		if (s.time_bss_rx != null)  entry.bss_rx = s.time_bss_rx;
		push(out, entry);
	}
	return out;
}

function trigger_scan() {
	let freq_set = this.get_band_freq_set();
	let dev = find_scan_dev(this.wiphy, freq_set);
	if (!dev)
		return false;

	let msg = { dev };
	let freqs = this.get_band_freqs();
	if (freqs && length(freqs))
		msg.scan_frequencies = freqs;

	return nl80211.request(
		nl80211.const.NL80211_CMD_TRIGGER_SCAN,
		0, msg
	);
}

function ubus_methods(cursor) {
	let self = this;
	return {
		config: {
			call: function(req) {
				cursor.load("wireless");
				req.reply(cursor.get_all("wireless", self.name));
			}
		},
		status: {
			call: function(req) {
				let s = self.get_status();
				if (!s) {
					req.reply({ error: "phy not found" });
					return;
				}
				req.reply(s);
			}
		},
		scan: {
			call: function(req) {
				let ret = self.trigger_scan();
				if (ret == false) {
					req.reply({ error: "scan trigger failed: " + nl80211.error() });
					return;
				}

				let results = self.get_scan_results();
				req.reply({ status: "scan_triggered", results });
			}
		},
		scan_results: {
			call: function(req) {
				req.reply({ results: self.get_scan_results() });
			}
		},
		survey: {
			call: function(req) {
				let s = self.get_survey();
				if (s == null) {
					req.reply({ error: "survey failed: " + nl80211.error() });
					return;
				}
				req.reply({ survey: s });
			}
		},
		e4: {
			call: function(req) {
				let prefs = self.get_e4();
				if (!prefs) {
					req.reply({ error: "phy not found" });
					return;
				}
				req.reply({ pref_opclass: prefs });
			}
		},
	};
}

const device_proto = {
	get_wiphy_bands,
	get_band_freqs,
	get_band_freq_set,
	get_status,
	get_e4,
	update_scan_cache,
	get_scan_results,
	trigger_scan,
	get_survey,
	ubus_methods,
};

let instances = {};

export function create(name, wiphy, band) {
	let self = instances[name];
	if (self) {
		self.wiphy = wiphy;
		self.band = band;
		return self;
	}

	self = proto({
		name,
		wiphy,
		band,
		scan_cache: {},
	}, device_proto);

	instances[name] = self;
	return self;
};

export function get(name) {
	return instances[name];
};

export function on_scan_event(ifname) {
	// Find which device owns this ifname by checking its wiphy
	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_INTERFACE, 0,
		{ dev: ifname }
	);
	if (!r)
		return;

	// Update all devices on this wiphy — each filters by its own band
	for (let name, dev in instances) {
		if (dev.wiphy == r.wiphy)
			dev.update_scan_cache(ifname);
	}
};

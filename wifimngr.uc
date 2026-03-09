#!/usr/bin/ucode -S

import * as ubus from "ubus";
import * as uloop from "uloop";
import * as uci from "uci";
import * as nl80211 from "nl80211";
import { readfile } from "fs";

uloop.init();
let conn = ubus.connect();
let cursor = uci.cursor();
let published = {};
let reload_timer;

// scan_cache[ifname][bssid] = { bssid, ssid, frequency, signal, last_seen }
let scan_cache = {};

// Max age before evicting stale entries (10 minutes)
const MAX_AGE = 600;

// Get ifname mapping from network.wireless status
function get_wireless_status() {
	let status = conn.call("network.wireless", "status");
	if (!status)
		return {};

	let map = {};
	for (let radio, rdata in status) {
		for (let iface in rdata.interfaces) {
			if (iface.section && iface.ifname)
				map[iface.section] = iface.ifname;
		}
	}
	return map;
}

// Resolve ifindex to ifname
function ifindex_to_ifname(ifindex) {
	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_INTERFACE,
		nl80211.const.NLM_F_DUMP, {}
	);
	if (!r) return null;
	for (let iface in r) {
		let idx = +readfile("/sys/class/net/" + iface.dev + "/ifindex");
		if (idx == ifindex)
			return iface.dev;
	}
	return null;
}

// Update scan cache for a given ifname
function update_scan_cache(ifname) {
	let results = nl80211.request(
		nl80211.const.NL80211_CMD_GET_SCAN,
		nl80211.const.NLM_F_DUMP,
		{ dev: ifname }
	);

	if (!results)
		return;

	let now = time();
	scan_cache[ifname] ??= {};

	for (let entry in results) {
		let bss = entry.bss;
		if (!bss || !bss.bssid)
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

		scan_cache[ifname][bss.bssid] = info;
	}

	// Evict stale entries
	for (let bssid, entry in scan_cache[ifname]) {
		if (now - entry.last_seen > MAX_AGE)
			delete scan_cache[ifname][bssid];
	}
}

// Get cached results with per-entry age
function get_cached_results(ifname) {
	let cache = scan_cache[ifname];
	if (!cache)
		return [];

	let now = time();
	let results = [];
	for (let bssid, entry in cache) {
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

// nl80211 scan event listener
nl80211.listener((msg) => {
	let ifname = msg.msg?.dev;
	if (!ifname) {
		let ifindex = msg.msg?.ifindex;
		if (ifindex)
			ifname = ifindex_to_ifname(ifindex);
	}
	if (!ifname)
		return;

	if (msg.cmd == nl80211.const.NL80211_CMD_TRIGGER_SCAN) {
		printf("wifimngr: scan started on %s\n", ifname);
	}

	if (msg.cmd == nl80211.const.NL80211_CMD_NEW_SCAN_RESULTS) {
		printf("wifimngr: scan results ready on %s\n", ifname);
		update_scan_cache(ifname);
		printf("wifimngr: %d BSS entries cached for %s\n",
			length(scan_cache[ifname]), ifname);
	}

	if (msg.cmd == nl80211.const.NL80211_CMD_SCAN_ABORTED) {
		printf("wifimngr: scan aborted on %s\n", ifname);
	}
}, [
	nl80211.const.NL80211_CMD_TRIGGER_SCAN,
	nl80211.const.NL80211_CMD_NEW_SCAN_RESULTS,
	nl80211.const.NL80211_CMD_SCAN_ABORTED,
]);

function publish_entries() {
	if (length(published)) {
		conn.disconnect();
		conn = ubus.connect();
		published = {};
	}

	cursor.load("wireless");
	let ifname_map = get_wireless_status();

	// Register wifi.radio.X for each wifi-device
	cursor.foreach("wireless", "wifi-device", function(s) {
		let name = s[".name"];
		let obj_name = "wifi.radio." + name;
		published[obj_name] = conn.publish(obj_name, {
			config: {
				call: function(req) {
					cursor.load("wireless");
					req.reply(cursor.get_all("wireless", name));
				}
			}
		});
	});

	// Register wifi.ap.X or wifi.sta.X using real ifname
	cursor.foreach("wireless", "wifi-iface", function(s) {
		let section = s[".name"];
		let mode = s.mode || "ap";
		let prefix = (mode == "sta") ? "wifi.sta." : "wifi.ap.";
		let ifname = s.ifname || ifname_map[section];

		if (!ifname) {
			printf("wifimngr: no ifname for %s, skipping\n", section);
			return;
		}

		let obj_name = prefix + ifname;
		published[obj_name] = conn.publish(obj_name, {
			config: {
				call: function(req) {
					cursor.load("wireless");
					req.reply(cursor.get_all("wireless", section));
				}
			},
			scan: {
				call: function(req) {
					let results = get_cached_results(ifname);
					if (length(results)) {
						req.reply({ results });
						return;
					}

					let ret = nl80211.request(
						nl80211.const.NL80211_CMD_TRIGGER_SCAN,
						0, { dev: ifname }
					);
					if (ret == false) {
						req.reply({ error: "scan trigger failed: " + nl80211.error() });
						return;
					}
					req.reply({ status: "scan_triggered" });
				}
			},
			scan_results: {
				call: function(req) {
					req.reply({ results: get_cached_results(ifname) });
				}
			},
		});
	});

	printf("wifimngr: published %d entries\n", length(published));
}

function schedule_reload() {
	if (reload_timer)
		reload_timer.cancel();
	reload_timer = uloop.timer(2000, () => {
		printf("wifimngr: reloading\n");
		publish_entries();
		reload_timer = null;
	});
}

// Initial publish
publish_entries();

// Listen for wireless config changes
conn.listener("config.change", (event, msg) => {
	if (msg.config == "wireless") {
		printf("wifimngr: wireless config changed\n");
		schedule_reload();
	}
});

// Listen for netifd wireless setup done
conn.listener("netifd.wireless.done", () => {
	printf("wifimngr: wireless setup done\n");
	schedule_reload();
});

// SIGHUP handler
uloop.signal("SIGHUP", () => {
	printf("wifimngr: SIGHUP received\n");
	schedule_reload();
});

uloop.run();

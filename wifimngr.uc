#!/usr/bin/ucode -S

import * as ubus from "ubus";
import * as uloop from "uloop";
import * as uci from "uci";
import * as nl80211 from "nl80211";
import { readfile } from "fs";
import * as wifi_iface from "wifi_iface";
import * as wifi_device from "wifi_device";

uloop.init();
let conn = ubus.connect();
let cursor = uci.cursor();
let published = {};
let reload_timer;

// Parse network.wireless status into ifname and wiphy maps
function get_wireless_status() {
	let status = conn.call("network.wireless", "status");
	if (!status)
		return { ifnames: {}, wiphys: {} };

	let ifnames = {};
	let radios = {};

	for (let radio, rdata in status) {
		let info = { band: rdata.config?.band };

		// Get wiphy from first interface on this radio
		for (let iface in rdata.interfaces) {
			if (iface.section && iface.ifname)
				ifnames[iface.section] = iface.ifname;

			if (info.wiphy == null && iface.ifname) {
				let r = nl80211.request(
					nl80211.const.NL80211_CMD_GET_INTERFACE, 0,
					{ dev: iface.ifname }
				);
				if (r)
					info.wiphy = r.wiphy;
			}
		}

		radios[radio] = info;
	}

	return { ifnames, radios };
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
		wifi_device.on_scan_event(ifname);
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
	let ws = get_wireless_status();

	// Register wifi.radio.X for each wifi-device
	cursor.foreach("wireless", "wifi-device", function(s) {
		let name = s[".name"];
		let info = ws.radios[name];

		if (!info || info.wiphy == null) {
			printf("wifimngr: no wiphy for %s, skipping\n", name);
			return;
		}

		let dev = wifi_device.create(name, info.wiphy, info.band);
		let obj_name = "wifi.radio." + name;
		published[obj_name] = conn.publish(obj_name, dev.ubus_methods(cursor));

		printf("wifimngr: registered %s (wiphy=%d, band=%s)\n", obj_name, info.wiphy, info.band);
	});

	// Register wifi.ap.X or wifi.sta.X using real ifname
	cursor.foreach("wireless", "wifi-iface", function(s) {
		let section = s[".name"];
		let mode = s.mode || "ap";
		let prefix = (mode == "sta") ? "wifi.sta." : "wifi.ap.";
		let ifname = s.ifname || ws.ifnames[section];

		if (!ifname) {
			printf("wifimngr: no ifname for %s, skipping\n", section);
			return;
		}

		let iface = wifi_iface.create(ifname, section, mode);
		let obj_name = prefix + ifname;
		published[obj_name] = conn.publish(obj_name, iface.ubus_methods(cursor));

		printf("wifimngr: registered %s (section=%s)\n", obj_name, section);
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

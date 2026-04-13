#!/usr/bin/ucode -S

import * as ubus from "ubus";
import * as uloop from "uloop";
import * as uci from "uci";
import * as nl80211 from "nl80211";
import { readfile, realpath, lsdir } from "fs";
import * as wifi_iface from "wifi_iface";
import * as wifi_device from "wifi_device";

uloop.init();
let conn = ubus.connect();
let event_conn = ubus.connect();
let cursor = uci.cursor();
let published = {};
let reload_timer;

// Resolve phy name from UCI option path by matching against
// /sys/class/ieee80211/*/device symlinks (same logic as C wifimngr)
function phy_from_path(path) {
	let prefix = "platform/";
	let phys = lsdir("/sys/class/ieee80211");
	if (!phys)
		return null;

	for (let phy in phys) {
		let link = realpath(`/sys/class/ieee80211/${phy}/device`);
		if (!link)
			continue;

		// Normalize: strip /sys/devices/ prefix
		let devprefix = "/sys/devices/";
		if (substr(link, 0, length(devprefix)) == devprefix)
			link = substr(link, length(devprefix));

		// Strip platform/ prefix if path contains /pci (like netifd does)
		if (substr(link, 0, length(prefix)) == prefix && index(link, "/pci") >= 0)
			link = substr(link, length(prefix));

		if (link == path)
			return phy;
	}
	return null;
}

// Get wiphy index from phy name via sysfs
function phy_to_wiphy(phyname) {
	let idx = readfile(`/sys/class/ieee80211/${phyname}/index`);
	if (idx == null)
		return null;
	return +trim(idx);
}

// Resolve a wifi-device UCI section to { phy, wiphy, band }
function resolve_radio(s) {
	let phyname = s.phy;

	if (!phyname && s.path)
		phyname = phy_from_path(s.path);

	// Default: try section name as phy name
	if (!phyname)
		phyname = s[".name"];

	let wiphy = phy_to_wiphy(phyname);
	if (wiphy == null)
		return null;

	return { phy: phyname, wiphy, band: s.band };
}

// Parse network.wireless status to get ifname mapping for wifi-iface sections
function get_iface_names() {
	let status = conn.call("network.wireless", "status");
	if (!status)
		return {};

	let ifnames = {};
	for (let radio, rdata in status) {
		for (let iface in rdata.interfaces) {
			if (iface.section && iface.ifname)
				ifnames[iface.section] = iface.ifname;
		}
	}
	return ifnames;
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

	// Register wifi.radio.X for each wifi-device
	// Resolve phy from UCI option phy/path via sysfs - no live interfaces needed
	cursor.foreach("wireless", "wifi-device", function(s) {
		let name = s[".name"];

		if (s.disabled == "1")
			return;

		let info = resolve_radio(s);

		if (!info) {
			printf("wifimngr: no phy for %s, skipping\n", name);
			return;
		}

		let dev = wifi_device.create(name, info.wiphy, info.band);
		let obj_name = "wifi.radio." + name;
		published[obj_name] = conn.publish(obj_name, dev.ubus_methods(cursor));

		printf("wifimngr: registered %s (phy=%s, wiphy=%d, band=%s)\n",
			obj_name, info.phy, info.wiphy, info.band);
	});

	// Register wifi.ap.X or wifi.sta.X using real ifname
	let ifnames = get_iface_names();

	cursor.foreach("wireless", "wifi-iface", function(s) {
		if (s.disabled == "1")
			return;

		let section = s[".name"];
		let mode = s.mode || "ap";
		let prefix = (mode == "sta") ? "wifi.sta." : "wifi.ap.";
		let ifname = s.ifname || ifnames[section];

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

// Register event listeners before initial publish so we don't miss
// netifd.wireless.done if it fires during startup.
event_conn.listener("config.change", (event, msg) => {
	if (msg.config == "wireless") {
		printf("wifimngr: wireless config changed\n");
		schedule_reload();
	}
});

event_conn.listener("ubus.object.add", (event, msg) => {
	if (msg.path && substr(msg.path, 0, 8) == "hostapd.") {
		printf("wifimngr: hostapd object added: %s\n", msg.path);
		schedule_reload();
	}
});

event_conn.listener("ubus.object.remove", (event, msg) => {
	if (msg.path && substr(msg.path, 0, 8) == "hostapd.") {
		printf("wifimngr: hostapd object removed: %s\n", msg.path);
		schedule_reload();
	}
});

uloop.signal("SIGHUP", () => {
	printf("wifimngr: SIGHUP received\n");
	schedule_reload();
});

// Initial publish
publish_entries();

// If hostapd objects already exist, reload to pick up interfaces
let objs = event_conn.list("hostapd.*");
if (objs && length(objs))
	schedule_reload();

uloop.run();

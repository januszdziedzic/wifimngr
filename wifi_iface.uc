import * as nl80211 from "nl80211";
import * as fs from "fs";
import hostapd from "hostapd_cli";

function hostapd_info(ifname) {
	let cfg = hostapd.get_config(ifname);
	let st = hostapd.status(ifname);
	if (!cfg && !st)
		return null;
	let info = {};
	if (st?.state != null)
		info._state = st.state;
	if (st?.beacon_int != null)
		info.beacon_int = +st.beacon_int;
	if (st?.dtim_period != null)
		info.dtim_period = +st.dtim_period;
	let sec = hostapd.format_security(cfg);
	if (sec)
		info.security = sec;
	let enc = hostapd.encryption(cfg);
	if (enc)
		info.encryption = enc;
	let h = hostapd.hidden(ifname);
	if (h != null)
		info._hidden = h;
	return info;
}

function netdev_operstate(ifname) {
	let fp = fs.open(`/sys/class/net/${ifname}/operstate`, "r");
	if (!fp)
		return null;
	let s = fp.read("all");
	fp.close();
	return s ? trim(s) : null;
}

const iftype_map = {
	[nl80211.const.NL80211_IFTYPE_STATION]: "sta",
	[nl80211.const.NL80211_IFTYPE_AP]: "ap",
	[nl80211.const.NL80211_IFTYPE_ADHOC]: "adhoc",
	[nl80211.const.NL80211_IFTYPE_MESH_POINT]: "mesh",
	[nl80211.const.NL80211_IFTYPE_MONITOR]: "monitor",
	[nl80211.const.NL80211_IFTYPE_P2P_CLIENT]: "p2p_client",
	[nl80211.const.NL80211_IFTYPE_P2P_GO]: "p2p_go",
};

const bw_map = { "0": 20, "1": 20, "2": 40, "3": 80, "4": 8080, "5": 160, "8": 320 };

function freq_to_chan(freq) {
	if (freq == null)
		return null;
	if (freq == 2484)
		return 14;
	if (freq < 2484)
		return (freq - 2407) / 5;
	if (freq >= 4910 && freq <= 4980)
		return (freq - 4000) / 5;
	if (freq < 5950)
		return (freq - 5000) / 5;
	if (freq == 5935)
		return 2;
	if (freq <= 45000)
		return (freq - 5950) / 5;
	return null;
}

function format_mlo_link(link) {
	let out = {
		link_id: link.link_id,
		link_addr: link.mac,
		channel: freq_to_chan(link.wiphy_freq),
		frequency: link.wiphy_freq,
		bandwidth: bw_map[link.channel_width] ?? link.channel_width,
		center_freq1: link.center_freq1,
	};
	if (link.center_freq2)
		out.center_freq2 = link.center_freq2;
	if (link.wiphy_tx_power_level != null)
		out.txpower = link.wiphy_tx_power_level / 100;
	if (link.mlo_link_disabled)
		out.disabled = true;
	return out;
}

function get_status(cursor) {
	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_INTERFACE, 0,
		{ dev: this.ifname }
	);
	if (!r)
		return null;

	let uci = null;
	if (cursor) {
		cursor.load("wireless");
		uci = cursor.get_all("wireless", this.section);
	}

	let status = {
		ifname: this.ifname,
		enabled: !!r.ssid,
		status: "stopped",
		mode: iftype_map[r.iftype] ?? "unknown",
		ssid: r.ssid,
		hidden: !!(uci && (uci.hidden == "1" || uci.hidden == 1 || uci.hidden == true)),
		bssid: r.mac,
		wiphy: r.wiphy,
	};

	if (r.mlo_links == null) {
		status.channel = freq_to_chan(r.wiphy_freq);
		status.frequency = r.wiphy_freq;
		status.bandwidth = bw_map[r.channel_width] ?? r.channel_width;
		status.center_freq1 = r.center_freq1;
		if (r.center_freq2)
			status.center_freq2 = r.center_freq2;
	}

	if (r.iftype == nl80211.const.NL80211_IFTYPE_AP) {
		let hinfo = hostapd_info(this.ifname);
		if (hinfo) {
			if (hinfo._state == "ENABLED")
				status.status = "running";
			if (hinfo._hidden != null)
				status.hidden = hinfo._hidden;
			delete hinfo._state;
			delete hinfo._hidden;
			for (let k in hinfo)
				status[k] = hinfo[k];
		}
	} else {
		if (netdev_operstate(this.ifname) == "up")
			status.status = "running";
	}

	if (r.mlo_links != null) {
		let links = [];
		for (let link in r.mlo_links)
			push(links, format_mlo_link(link));
		status.mlo_links = links;
	}

	return status;
}

function ubus_methods(cursor) {
	let self = this;
	return {
		config: {
			call: function(req) {
				cursor.load("wireless");
				req.reply(cursor.get_all("wireless", self.section));
			}
		},
		status: {
			call: function(req) {
				let s = self.get_status(cursor);
				if (!s) {
					req.reply({ error: "interface not found" });
					return;
				}
				req.reply(s);
			}
		},
	};
}

const iface_proto = {
	get_status,
	ubus_methods,
};

// All iface instances keyed by ifname
let instances = {};

export function create(ifname, section, mode) {
	let self = instances[ifname];
	if (self) {
		self.section = section;
		self.mode = mode;
		return self;
	}

	self = proto({
		ifname,
		section,
		mode,
	}, iface_proto);

	instances[ifname] = self;
	return self;
};

export function get(ifname) {
	return instances[ifname];
};

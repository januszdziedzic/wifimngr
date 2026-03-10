import * as nl80211 from "nl80211";

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

function get_status() {
	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_INTERFACE, 0,
		{ dev: this.ifname }
	);
	if (!r)
		return null;

	let status = {
		mode: iftype_map[r.iftype] ?? "unknown",
		ssid: r.ssid,
		frequency: r.wiphy_freq,
		channel_width: bw_map[r.channel_width] ?? r.channel_width,
		center_freq1: r.center_freq1,
	};

	if (r.center_freq2)
		status.center_freq2 = r.center_freq2;

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
				let s = self.get_status();
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

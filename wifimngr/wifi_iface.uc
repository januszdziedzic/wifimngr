import * as nl80211 from "nl80211";
import * as fs from "fs";
import hostapd from "hostapd_cli";
import wpa from "wpa_cli";

function hostapd_info(ifname) {
	let cfg = hostapd.get_config(ifname);
	let st = hostapd.status(ifname);
	let beacon = hostapd.dump_beacon(ifname);
	if (!cfg && !st && !beacon)
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
	if (beacon) {
		let h = hostapd.beacon_hidden(beacon);
		if (h != null)
			info._hidden = h;
		let caps = hostapd.beacon_caps(beacon);
		if (length(caps))
			info.caps = caps;
	}
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

const bw_map = { "0": 20, "1": 20, "2": 40, "3": 80, "4": 8080, "5": 160, "6": 5, "7": 10, "13": 320 };

function freq_to_chan(freq) {
	if (freq == null)
		return null;
	if (freq == 2484)
		return 14;
	if (freq < 2484)
		return (freq - 2407) / 5;
	if (freq >= 4910 && freq <= 4980)
		return (freq - 4000) / 5;
	if (freq == 5935)
		return 2;
	if (freq < 5950)
		return (freq - 5000) / 5;
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

function get_noise(ifname) {
	let r = nl80211.request(
		nl80211.const.NL80211_CMD_GET_SURVEY,
		nl80211.const.NLM_F_DUMP, { dev: ifname }
	);
	if (!r) return null;
	let parts = type(r) == "array" ? r : [ r ];
	for (let p in parts) {
		if (p.survey_info?.in_use && p.survey_info?.noise != null)
			return p.survey_info.noise;
	}
	return null;
}

function nss_from_vht_mcs_map(map_hex) {
	let map = +("0x" + map_hex);
	let nss = 0;
	for (let i = 0; i < 8; i++) {
		if (((map >> (i * 2)) & 3) != 3)
			nss = i + 1;
	}
	return nss;
}

function nss_from_ht_mcs(mcs_hex) {
	let nss = 0;
	for (let i = 0; i < 4; i++) {
		let byte = +("0x" + substr(mcs_hex, i * 2, 2));
		if (byte)
			nss = i + 1;
	}
	return nss;
}

function sta_nss(data) {
	if (data.rx_vht_mcs_map)
		return nss_from_vht_mcs_map(data.rx_vht_mcs_map);
	if (data.ht_mcs_bitmask)
		return nss_from_ht_mcs(data.ht_mcs_bitmask);
	return null;
}

function sta_standard(flags, freq) {
	if (!flags) return null;
	let is_2g = (freq && freq < 3000);
	let is_6g = (freq && freq > 5935);
	let parts = [];
	if (is_6g) {
		if (index(flags, "[HE]") >= 0)
			push(parts, "802.11ax");
		if (index(flags, "[EHT]") >= 0)
			push(parts, "be");
	} else {
		if (is_2g)
			push(parts, "802.11b/g");
		else
			push(parts, "802.11a");
		if (index(flags, "[HT]") >= 0)
			push(parts, "n");
		if (index(flags, "[VHT]") >= 0)
			push(parts, "ac");
		if (index(flags, "[HE]") >= 0)
			push(parts, "ax");
		if (index(flags, "[EHT]") >= 0)
			push(parts, "be");
	}
	return join("/", parts);
}

function sta_bandwidth(data) {
	let bw = 20;

	if (data.ht_caps_info) {
		let ht = +data.ht_caps_info;
		if (ht & 2) bw = 40;
	}
	if (data.vht_caps_info) {
		let vht = +data.vht_caps_info;
		let chw = (vht >> 2) & 3;
		bw = chw ? 160 : 80;
	}
	if (data.he_capab && length(data.he_capab) >= 34) {
		// HE PHY byte 0 starts at offset 12 (mac=6B)
		let phy0 = +("0x" + substr(data.he_capab, 12, 2));
		if (phy0 & 0x08) bw = 160;
		else if (phy0 & 0x04) bw = 80;
		else if (phy0 & 0x02) bw = 40;
	}
	if (data.eht_capab && length(data.eht_capab) >= 8) {
		// EHT PHY byte 0 starts at offset 4 (mac=2B)
		let ephy0 = +("0x" + substr(data.eht_capab, 4, 2));
		if (ephy0 & 0x02) bw = 320;
	}
	return bw;
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
		enabled: !(uci && (uci.disabled == "1" || uci.disabled == 1 || uci.disabled == true)),
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
			for (let k in hinfo) {
				if (r.mlo_links != null && k == "caps")
					continue;
				status[k] = hinfo[k];
			}
		}
	} else {
		if (netdev_operstate(this.ifname) == "up")
			status.status = "running";
		// mesh/sta are managed by wpa_supplicant; SSID isn't exposed via nl80211
		let wst = wpa.status(this.ifname);
		if (wst?.ssid != null && wst.ssid != "")
			status.ssid = wst.ssid;
	}

	if (r.mlo_links != null) {
		let links = [];
		for (let link in r.mlo_links) {
			let out = format_mlo_link(link);
			if (r.iftype == nl80211.const.NL80211_IFTYPE_AP) {
				let beacon = hostapd.dump_beacon(this.ifname, link.link_id);
				if (beacon) {
					let caps = hostapd.beacon_caps(beacon);
					if (length(caps))
						out.caps = caps;
				}
			}
			push(links, out);
		}
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
		blocked_stas: {
			call: function(req) {
				let data = hostapd.run_cmd(self.ifname, 'raw DENY_ACL SHOW');
				let macs = [];
				if (data) {
					for (let line in split(data, "\n")) {
						line = trim(line);
						if (match(line, /^[0-9a-fA-F:]{17}/))
							push(macs, substr(line, 0, 17));
					}
				}
				req.reply({ blocked_stas: macs });
			}
		},
		block_sta: {
			args: { sta: "", block: 0 },
			call: function(req) {
				let sta = req.args?.sta;
				let block = req.args?.block ?? 1;
				if (!sta) {
					req.reply({ error: "sta required" });
					return;
				}
				let cmd = block
					? `raw DENY_ACL ADD_MAC ${sta}`
					: `raw DENY_ACL DEL_MAC ${sta}`;
				let ret = hostapd.run_cmd(self.ifname, cmd);
				req.reply({ status: ret ? "ok" : "fail" });
			}
		},
		list_neighbor: {
			call: function(req) {
				let data = hostapd.run_cmd(self.ifname, "show_neighbor");
				let nbrs = [];
				if (data) {
					for (let line in split(data, "\n")) {
						let m = match(line, /nr=([0-9a-fA-F]+)/);
						if (!m || length(m[1]) < 26)
							continue;
						let nr = m[1];
						let bssid = sprintf("%s:%s:%s:%s:%s:%s",
							substr(nr, 0, 2), substr(nr, 2, 2),
							substr(nr, 4, 2), substr(nr, 6, 2),
							substr(nr, 8, 2), substr(nr, 10, 2));
						let bi = +("0x" + substr(nr, 12, 2))
							| (+("0x" + substr(nr, 14, 2)) << 8)
							| (+("0x" + substr(nr, 16, 2)) << 16)
							| (+("0x" + substr(nr, 18, 2)) << 24);
						push(nbrs, {
							bssid,
							bssid_info: sprintf("0x%x", bi),
							reg: +("0x" + substr(nr, 20, 2)),
							channel: +("0x" + substr(nr, 22, 2)),
							phy: +("0x" + substr(nr, 24, 2)),
						});
					}
				}
				req.reply({ neighbors: nbrs });
			}
		},
		add_neighbor: {
			args: { bssid: "", channel: 0, bssid_info: "", reg: 0, phy: 0 },
			call: function(req) {
				let a = req.args;
				if (!a?.bssid) {
					req.reply({ error: "bssid required" });
					return;
				}
				// Build nr= hex: bssid(6B) + bssid_info(4B LE) + reg(1B) + channel(1B) + phy(1B)
				let nr = replace(a.bssid, /:/g, "");
				let bi = +(a.bssid_info ?? 0);
				nr += sprintf("%02x%02x%02x%02x", bi & 0xff, (bi >> 8) & 0xff,
					(bi >> 16) & 0xff, (bi >> 24) & 0xff);
				nr += sprintf("%02x", +(a.reg ?? 0));
				nr += sprintf("%02x", +(a.channel ?? 0));
				nr += sprintf("%02x", +(a.phy ?? 0));
				// Get SSID from hostapd status
				let st = hostapd.status(self.ifname);
				let ssid = st?.ssid?.[0] || "";
				let cmd = `set_neighbor ${a.bssid} ssid="${ssid}" nr=${nr}`;
				let ret = hostapd.run_cmd(self.ifname, cmd);
				req.reply({ status: ret ? "ok" : "fail" });
			}
		},
		del_neighbor: {
			args: { bssid: "" },
			call: function(req) {
				let bssid = req.args?.bssid;
				if (!bssid) {
					req.reply({ error: "bssid required" });
					return;
				}
				let st = hostapd.status(self.ifname);
				let ssid = st?.ssid?.[0] || "";
				let cmd = `remove_neighbor ${bssid} ssid="${ssid}"`;
				let ret = hostapd.run_cmd(self.ifname, cmd);
				req.reply({ status: ret ? "ok" : "fail" });
			}
		},
		request_neighbor: {
			args: { client: "", opclass: 0, channel: 0, duration: 0,
				mode: "", bssid: "", reporting_detail: 0, ssid: "",
				channel_report: [], request_element: [] },
			call: function(req) {
				let a = req.args;
				if (!a?.client) {
					req.reply({ error: "client required" });
					return;
				}
				// Build beacon request hex:
				// opclass(1B) + channel(1B) + rand_interval(2B LE) + duration(2B LE) + mode(1B) + bssid(6B) + subelements
				let opclass = +(a.opclass ?? 0);
				let channel = +(a.channel ?? 0);
				let duration = +(a.duration ?? 100);
				let mode_str = a.mode ?? "passive";
				let mode = (mode_str == "active") ? 1 : (mode_str == "table") ? 2 : 0;
				let bssid = a.bssid ? replace(a.bssid, /:/g, "") : "ffffffffffff";
				let hex = sprintf("%02x%02x0000%02x%02x%02x%s",
					opclass, channel,
					duration & 0xff, (duration >> 8) & 0xff,
					mode, bssid);
				// SSID subelement (id=0)
				if (a.ssid != null && a.ssid != "") {
					let ssid_hex = "";
					for (let i = 0; i < length(a.ssid); i++)
						ssid_hex += sprintf("%02x", ord(a.ssid, i));
					hex += sprintf("00%02x%s", length(a.ssid), ssid_hex);
				}
				// Reporting Detail subelement (id=2)
				if (a.reporting_detail != null)
					hex += sprintf("02%02x%02x", 1, +(a.reporting_detail));
				// Channel Report subelement (id=51)
				if (a.channel_report && length(a.channel_report)) {
					for (let cr in a.channel_report)
						hex += sprintf("33%02x%s", length(cr) / 2, cr);
				}
				// Request Element subelement (id=10)
				if (a.request_element && length(a.request_element)) {
					let elems = "";
					for (let e in a.request_element)
						elems += sprintf("%02x", +e);
					hex += sprintf("0a%02x%s", length(a.request_element), elems);
				}
				let cmd = `req_beacon ${a.client} ${hex}`;
				hostapd.run_cmd(self.ifname, cmd);
				req.reply({ status: "ok" });
			}
		},
		request_btm: {
			args: { sta: "", target_ap: [], mode: 0, disassoc_tmo: 0,
				validity_int: 0, dialog_token: 0, bssterm_dur: 0,
				mbo_reason: 0, mbo_cell_pref: 0, mbo_reassoc_delay: 0 },
			call: function(req) {
				let a = req.args;
				if (!a?.sta) {
					req.reply({ error: "sta required" });
					return;
				}
				let cmd = `bss_tm_req ${a.sta}`;
				// Add neighbor targets
				if (a.target_ap) {
					for (let ap in a.target_ap)
						cmd += ` neighbor=${ap}`;
				}
				let mode = +(a.mode ?? 0);
				if (mode & 0x01)
					cmd += " pref=1";
				if (mode & 0x04)
					cmd += " disassoc_imminent=1";
				if (mode & 0x02)
					cmd += " abridged=1";
				if (a.disassoc_tmo)
					cmd += ` disassoc_timer=${a.disassoc_tmo}`;
				if (a.validity_int)
					cmd += ` valid_int=${a.validity_int}`;
				if (a.dialog_token)
					cmd += ` dialog_token=${a.dialog_token}`;
				if (a.bssterm_dur)
					cmd += ` bss_term=0,${a.bssterm_dur}`;
				if (a.mbo_reason || a.mbo_cell_pref || a.mbo_reassoc_delay)
					cmd += ` mbo=${a.mbo_reason ?? 0}:${a.mbo_reassoc_delay ?? 0}:${a.mbo_cell_pref ?? 0}`;
				let ret = hostapd.run_cmd(self.ifname, cmd);
				req.reply({ status: ret ? "ok" : "fail" });
			}
		},
		disconnect: {
			args: { sta: "String", reason: 0 },
			call: function(req) {
				let sta = req.args?.sta;
				let reason = req.args?.reason ?? 1;
				if (!sta) {
					req.reply({ error: "sta required" });
					return;
				}
				let ret = hostapd.run_cmd(self.ifname,
					`deauthenticate ${sta} reason=${reason}`);
				req.reply({ status: ret ? "ok" : "fail" });
			}
		},
		assoclist: {
			call: function(req) {
				let macs = hostapd.list_stas(self.ifname);
				req.reply({ assoclist: macs });
			}
		},
		stations: {
			call: function(req) {
				let macs = hostapd.list_stas(self.ifname);
				let noise = get_noise(self.ifname);
				let iface = nl80211.request(
					nl80211.const.NL80211_CMD_GET_INTERFACE, 0,
					{ dev: self.ifname }
				);
				// Build per-link info map for MLD AP
				let link_info = {};
				let ap_max_bw = bw_map[iface?.channel_width] ?? 20;
				let ap_max_freq = iface?.wiphy_freq;
				if (iface?.mlo_links) {
					for (let link in iface.mlo_links) {
						let bw = bw_map[link.channel_width] ?? 20;
						link_info[link.link_id] = {
							bssid: link.mac,
							frequency: link.wiphy_freq,
							channel: freq_to_chan(link.wiphy_freq),
							bandwidth: bw,
						};
						if (bw > ap_max_bw) ap_max_bw = bw;
						if (link.wiphy_freq > (ap_max_freq ?? 0))
							ap_max_freq = link.wiphy_freq;
					}
				}
				let freq = ap_max_freq;
				let stas = [];
				for (let mac in macs) {
					let data = hostapd.sta_info(self.ifname, mac);
					if (!data)
						continue;
					let rssi = data.signal ? +data.signal : null;
					let sta = { mac };
					if (data.aid)
						sta.aid = +data.aid;
					// Query nl80211 for MLD assoc link id
					let nlsta = nl80211.request(
						nl80211.const.NL80211_CMD_GET_STATION, 0,
						{ dev: self.ifname, mac }
					);
					if (nlsta?.mlo_link_id != null)
						sta.assoc_link_id = nlsta.mlo_link_id;
					if (nlsta?.mld_addr)
						sta.mld_addr = nlsta.mld_addr;
					// Collect per-link peer addresses from peer_addr[N]
					// and query each link's BSS for per-link caps via
					// hostapd_cli -i <ifname>_link<N>.
					let sta_links = [];
					for (let k in data) {
						let m = match(k, /^peer_addr\[([0-9]+)\]$/);
						if (!m) continue;
						let lid = +m[1];
						let entry = { link_id: lid, peer_addr: data[k] };
						let li = link_info[lid];
						if (li) {
							entry.bssid = li.bssid;
							entry.frequency = li.frequency;
							entry.channel = li.channel;
						}
						let link_ifname = `${self.ifname}_link${lid}`;
						let ldata = hostapd.sta_info(link_ifname, mac);
						if (ldata) {
							let lbw_sta = sta_bandwidth(ldata);
							let lbw_ap = li?.bandwidth ?? 20;
							entry.bandwidth = (lbw_sta < lbw_ap) ? lbw_sta : lbw_ap;
							let lnss = sta_nss(ldata);
							if (lnss)
								entry.nss = lnss;
							let lrssi = ldata.signal ? +ldata.signal : null;
							let lnoise = get_noise(link_ifname);
							if (lrssi != null)
								entry.rssi = lrssi;
							if (lnoise != null)
								entry.noise = lnoise;
							if (lrssi != null && lnoise != null)
								entry.snr = lrssi - lnoise;
							let lstd = sta_standard(ldata.flags, li?.frequency);
							if (lstd)
								entry.standard = lstd;
							let lcaps = hostapd.sta_caps(ldata);
							if (length(lcaps))
								entry.caps = lcaps;
						} else if (li) {
							entry.bandwidth = li.bandwidth;
						}
						push(sta_links, entry);
					}
					if (length(sta_links))
						sta.mlo_links = sta_links;
					if (!length(sta_links)) {
						let nss = sta_nss(data);
						if (nss)
							sta.nss = nss;
						let sta_bw = sta_bandwidth(data);
						sta.bandwidth = (sta_bw < ap_max_bw) ? sta_bw : ap_max_bw;
						if (rssi != null)
							sta.rssi = rssi;
						if (noise != null)
							sta.noise = noise;
						if (rssi != null && noise != null)
							sta.snr = rssi - noise;
						let std = sta_standard(data.flags, freq);
						if (std)
							sta.standard = std;
					}
					if (data.connected_time)
						sta.connected_time = +data.connected_time;
					if (data.inactive_msec)
						sta.inactive_msec = +data.inactive_msec;
					if (data.rx_bytes)
						sta.rx_bytes = +data.rx_bytes;
					if (data.tx_bytes)
						sta.tx_bytes = +data.tx_bytes;
					if (data.rx_packets)
						sta.rx_packets = +data.rx_packets;
					if (data.tx_packets)
						sta.tx_packets = +data.tx_packets;
					if (data.rx_rate_info)
						sta.rx_rate = +data.rx_rate_info;
					if (data.tx_rate_info)
						sta.tx_rate = +data.tx_rate_info;
					if (!length(sta_links)) {
						let caps = hostapd.sta_caps(data);
						if (length(caps))
							sta.caps = caps;
					}
					push(stas, sta);
				}
				req.reply({ stations: stas });
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

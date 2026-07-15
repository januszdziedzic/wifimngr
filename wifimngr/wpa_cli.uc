// Thin wrapper around wpa_cli for wifimngr.
// Used for interfaces managed by wpa_supplicant (mesh and station), where
// SSID/state are not exposed via hostapd. All helpers take an ifname and
// return either a parsed object or null.

import * as fs from "fs";

const CTRL_DIR = "/var/run/wpa_supplicant";

// Run `wpa_cli ... <cmd>` and return stdout as a trimmed string,
// or null on error / FAIL / UNKNOWN COMMAND.
function run(ifname, cmd) {
	let fp = fs.popen(`wpa_cli -p ${CTRL_DIR} -i ${ifname} ${cmd} 2>/dev/null`, "r");
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

function status(ifname) {
	return kv(ifname, "status");
}

export default {
	run_cmd: run,
	kv,
	status,
};

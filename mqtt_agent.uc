#!/usr/bin/ucode -S
/**
 * MQTT Agent v2 — uses native mosquitto.so ucode module
 *
 * Topic layout:
 *   Subscribe:  <agent_id>/cmd
 *   Publish:    <agent_id>/status
 *
 * Incoming JSON:
 *   { "action": "ping" }
 *   { "action": "get_status" }
 *   { "action": "get_uptime" }
 *   { "action": "...", "reply_topic": "custom/reply" }
 */

import * as mqtt  from 'mosquitto';
import * as uloop from 'uloop';
import * as uci   from 'uci';
import * as fs    from 'fs';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

function get_hostname() {
	let c = uci.cursor();
	let hostname = c.get("system", "@system[0]", "hostname");
	if (hostname)
		return hostname;
	// fallback to /proc/sys/kernel/hostname
	let f = fs.open("/proc/sys/kernel/hostname", "r");
	if (f) {
		let h = trim(f.read("all"));
		f.close();
		if (h) return h;
	}
	return "ucode-agent";
}

const CFG = {
	host:      "127.0.0.1",
	port:      1883,
	agent_id:  get_hostname(),
	keepalive: 60,
};

const CMD_TOPIC    = CFG.agent_id + "/cmd";
const STATUS_TOPIC = CFG.agent_id + "/status";

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

function logi(msg) { warn("[mqtt] " + msg + "\n"); }
function loge(msg) { warn("[mqtt] ERROR: " + msg + "\n"); }

// ---------------------------------------------------------------------------
// Action handlers
// ---------------------------------------------------------------------------

function read_file_trim(path) {
	let f = fs.open(path, "r");
	if (!f) return null;
	let d = trim(f.read("all"));
	f.close();
	return d;
}

function action_get_uptime() {
	let raw = read_file_trim("/proc/uptime");
	if (!raw) return { error: "cannot read /proc/uptime" };
	let parts = split(raw, " ");
	return {
		uptime_seconds: +parts[0],
		idle_seconds:   +parts[1],
	};
}

function action_get_status() {
	let uptime  = action_get_uptime();
	let meminfo = {};
	let mf = fs.open("/proc/meminfo", "r");
	if (mf) {
		let line;
		while ((line = mf.read("line")) != null) {
			let m = match(trim(line), /^(\w+):\s+(\d+)/);
			if (m) meminfo[m[1]] = +m[2];
		}
		mf.close();
	}
	return {
		agent:     CFG.agent_id,
		uptime:    uptime,
		mem_total: meminfo.MemTotal     || 0,
		mem_free:  meminfo.MemFree      || 0,
		mem_avail: meminfo.MemAvailable || 0,
	};
}

// ---------------------------------------------------------------------------
// Command dispatcher
// ---------------------------------------------------------------------------

let g_client = null;

function dispatch_command(topic, payload) {
	let req;
	try {
		req = json(payload);
	} catch(e) {
		loge("invalid JSON: " + payload);
		return;
	}

	if (type(req) != "object" || !req.action) {
		loge("missing 'action' field");
		return;
	}

	let reply_topic = req.reply_topic || STATUS_TOPIC;
	let action      = req.action;

	let result = null;
	let err    = null;

	if (action == "ping") {
		result = { pong: true };
	} else if (action == "get_uptime") {
		result = action_get_uptime();
	} else if (action == "get_status") {
		result = action_get_status();
	} else {
		err = "unknown action: " + action;
		loge(err);
	}

	let reply = err
		? { agent: CFG.agent_id, action: action, error:  err    }
		: { agent: CFG.agent_id, action: action, result: result };

	g_client.publish(reply_topic, sprintf("%J", reply), 0, false);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

uloop.init();

g_client = mqtt.new(CFG.agent_id, true);

g_client.on_connect(function(rc) {
	if (rc != 0) {
		loge(sprintf("broker rejected connection (code %d)", rc));
		return;
	}
	logi("connected to broker");
	g_client.subscribe(CMD_TOPIC, 0);
	g_client.publish(STATUS_TOPIC,
		sprintf("%J", { agent: CFG.agent_id, online: true }), 0, true);
});

g_client.on_disconnect(function(rc) {
	logi(sprintf("disconnected (rc=%d), will reconnect automatically", rc));
});

g_client.on_message(function(topic, payload, qos, retain) {
	if (topic == CMD_TOPIC)
		dispatch_command(topic, payload);
});

g_client.on_subscribe(function(mid, granted_qos) {
	logi("subscribed to " + CMD_TOPIC);
});

// Automatic reconnect: 1s initial, 30s max, exponential backoff
g_client.reconnect_delay_set(1, 30, true);

// Last-will so subscribers know when agent dies unexpectedly
g_client.will_set(STATUS_TOPIC,
	sprintf("%J", { agent: CFG.agent_id, online: false }), 0, true);

g_client.connect(CFG.host, CFG.port, CFG.keepalive);
g_client.loop_start();

logi(sprintf("starting — broker=%s:%d  id=%s  cmd=%s",
	CFG.host, CFG.port, CFG.agent_id, CMD_TOPIC));

uloop.signal("SIGTERM", function() {
	logi("SIGTERM — disconnecting");
	g_client.publish(STATUS_TOPIC,
		sprintf("%J", { agent: CFG.agent_id, online: false }), 0, true);
	g_client.loop_stop();
	g_client.disconnect();
	uloop.end();
});

uloop.signal("SIGINT", function() {
	logi("SIGINT — disconnecting");
	g_client.loop_stop();
	g_client.disconnect();
	uloop.end();
});

uloop.run();

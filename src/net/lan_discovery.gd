class_name LanDiscovery
extends RefCounted
## UDP LAN discovery. A hosting game broadcasts a small presence packet once a
## second; menus run a listener and show the servers heard recently. One
## object plays one role (use the static constructors).
##
## Timekeeping is caller-driven (pass dt) so this works identically in the
## game loop and in headless tests.

const DISCOVERY_PORT := 24643
const MAGIC := "XSPACEWAR1"
const ADVERTISE_INTERVAL := 1.0
const EXPIRE_AFTER := 3.5          ## seconds without a packet before delisting

var bind_ok := false               ## listener only: whether the port bind worked
var info := {}                     ## advertiser only: name/port/max/mode (+players)
var servers := {}                  ## listener only: "ip:port" -> server info

var _udp := PacketPeerUDP.new()
var _is_advertiser := false
var _target_ip := "255.255.255.255"
var _target_port := DISCOVERY_PORT
var _accum := ADVERTISE_INTERVAL   ## send immediately on the first tick
var _clock := 0.0

## `target_ip` overrides the broadcast address (tests use 127.0.0.1).
static func advertiser(p_info: Dictionary, target_ip := "255.255.255.255",
		target_port := DISCOVERY_PORT) -> LanDiscovery:
	var d := LanDiscovery.new()
	d._is_advertiser = true
	d.info = p_info.duplicate()
	d._target_ip = target_ip
	d._target_port = target_port
	d._udp.set_broadcast_enabled(true)
	return d

static func listener(port := DISCOVERY_PORT, bind_address := "*") -> LanDiscovery:
	var d := LanDiscovery.new()
	d.bind_ok = d._udp.bind(port, bind_address) == OK
	return d

func advertise(dt: float, players: int) -> void:
	if not _is_advertiser:
		return
	_accum += dt
	if _accum < ADVERTISE_INTERVAL:
		return
	_accum = 0.0
	info["players"] = players
	var msg := info.duplicate()
	msg["magic"] = MAGIC
	_udp.set_dest_address(_target_ip, _target_port)
	_udp.put_packet(var_to_bytes(msg))

## Drain received packets and return the current (non-expired) server list.
func poll(dt: float) -> Array:
	_clock += dt
	# Cap packets drained per frame so a UDP flood (accidental or hostile) on
	# the LAN can't stall the main thread for the whole drain (issue #11).
	var budget := 64
	while _udp.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var bytes := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var v: Variant = bytes_to_var(bytes)
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = v
		if String(d.get("magic", "")) != MAGIC:
			continue
		# Untrusted broadcast: validate field types (a crafted packet with
		# port/players/max as Arrays would raise in int()) and cap the name.
		for k in ["port", "players", "max", "mode"]:
			var fv: Variant = d.get(k, 0)
			if typeof(fv) != TYPE_INT and typeof(fv) != TYPE_FLOAT:
				d[k] = 0
		d["name"] = String(d.get("name", "?")).left(24)
		d.erase("magic")
		d["ip"] = ip
		d["last_seen"] = _clock
		servers["%s:%d" % [ip, int(d.get("port", 0))]] = d
	for key in servers.keys():
		if _clock - float(servers[key]["last_seen"]) > EXPIRE_AFTER:
			servers.erase(key)
	return servers.values()

func close() -> void:
	_udp.close()

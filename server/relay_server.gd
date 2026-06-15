class_name RelayServer
extends RefCounted
## The standalone relay/master service (see server/relay_main.gd to run it).
##
## Master role: game hosts REGISTER (getting a short room code) and heartbeat
## player counts; browsers LIST the open rooms. Relay role: clients JOIN a
## room code and the relay forwards opaque game packets between each client
## and its room's host, preserving the reliable/unreliable channel class.
## Both endpoints only ever dial OUT to the relay, so it works behind NAT
## with no port forwarding and no platform services.

var _conn := ENetConnection.new()
var _open := false
var _rooms := {}        ## code -> {"host": peer, "clients": {pid: peer}, "info": {...}}
var _peer_info := {}    ## peer -> {"role": "host"|"client", "code": String, "pid"?: int}
var _next_pid := 1
var _rng := RandomNumberGenerator.new()

# Public-facing DoS hardening: this service answers the open internet, so a
# single peer must not be able to burn CPU/forwarding or exhaust memory.
## Packets we ACT ON from one peer per pump. Excess is still drained from ENet
## (the queue can't back up) but not processed. Sits far above any legitimate
## burst — a host fanning one snapshot out to a full room stays well under it.
const MAX_PACKETS_PER_PUMP_PER_PEER := 64
## Ceiling on concurrent rooms so REGISTER-flooding can't grow memory unbounded.
const MAX_ROOMS := 256

func open(port := RelayProtocol.DEFAULT_PORT, bind_address := "*", max_peers := 128) -> Error:
	_rng.randomize()
	var err := _conn.create_host_bound(bind_address, port, max_peers, NetProtocol.CHANNELS)
	_open = err == OK
	return err

func room_count() -> int:
	return _rooms.size()

func pump() -> void:
	if not _open:
		return
	var per_peer := {}  # peer -> packets acted on this pump (flood cap)
	for _i in range(256):
		var ev: Array = _conn.service(0)
		var t := int(ev[0])
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = ev[1]
		match t:
			ENetConnection.EVENT_DISCONNECT:
				_on_leave(peer)
			ENetConnection.EVENT_RECEIVE:
				var pkt := peer.get_packet()  # always drain, even when over the cap
				var n := int(per_peer.get(peer, 0))
				if n >= MAX_PACKETS_PER_PUMP_PER_PEER:
					continue  # this peer is flooding — ignore the rest this pump
				per_peer[peer] = n + 1
				_on_packet(peer, pkt)

func close() -> void:
	if not _open:
		return
	_conn.flush()
	_conn.destroy()
	_open = false
	_rooms.clear()
	_peer_info.clear()

# --------------------------------------------------------------------------

func _on_packet(peer: ENetPacketPeer, bytes: PackedByteArray) -> void:
	var msg := NetProtocol.unpack(bytes)
	if msg.is_empty():
		return
	var d: Dictionary = msg["data"]
	match int(msg["type"]):
		RelayProtocol.REGISTER:
			_register(peer, d)
		RelayProtocol.UPDATE:
			_update(peer, d)
		RelayProtocol.LIST:
			_send(peer, RelayProtocol.SERVERS, {"list": _room_list()}, true)
		RelayProtocol.JOIN:
			_join(peer, d)
		RelayProtocol.FWD:
			_forward(peer, d)
		RelayProtocol.KICK:
			_kick(peer, d)

## int() that tolerates hostile Variant types instead of raising.
static func _as_int(v: Variant, fallback: int) -> int:
	match typeof(v):
		TYPE_INT: return v
		TYPE_FLOAT: return int(v)
		TYPE_STRING: return int(v) if String(v).is_valid_int() else fallback
		_: return fallback

func _register(peer: ENetPacketPeer, d: Dictionary) -> void:
	if _peer_info.has(peer):
		return
	if _rooms.size() >= MAX_ROOMS:
		return  # at capacity — refuse silently; the host gets no code and times out
	var code := _new_code()
	_rooms[code] = {"host": peer, "clients": {}, "info": {
		"name": String(d.get("name", "?")).left(24),
		"max": clampi(_as_int(d.get("max", 16), 16), 2, 16),
		"mode": _as_int(d.get("mode", 0), 0),
		"players": 1,
	}}
	_peer_info[peer] = {"role": "host", "code": code}
	_send(peer, RelayProtocol.ROOM, {"code": code}, true)

func _update(peer: ENetPacketPeer, d: Dictionary) -> void:
	var room := _room_of(peer, "host")
	if not room.is_empty():
		room["info"]["players"] = _as_int(d.get("players", 1), 1)

func _join(peer: ENetPacketPeer, d: Dictionary) -> void:
	if _peer_info.has(peer):
		return
	var code := String(d.get("code", "")).to_upper()
	if not _rooms.has(code):
		_send(peer, RelayProtocol.JOINED, {"ok": false, "why": "room not found"}, true)
		return
	var room: Dictionary = _rooms[code]
	if room["clients"].size() >= int(room["info"]["max"]) + 8:
		_send(peer, RelayProtocol.JOINED, {"ok": false, "why": "room full"}, true)
		return
	var pid := _next_pid
	_next_pid += 1
	room["clients"][pid] = peer
	_peer_info[peer] = {"role": "client", "code": code, "pid": pid}
	_send(peer, RelayProtocol.JOINED, {"ok": true, "code": code}, true)
	_send(room["host"], RelayProtocol.PEER, {"pid": pid}, true)

func _forward(peer: ENetPacketPeer, d: Dictionary) -> void:
	var inf: Dictionary = _peer_info.get(peer, {})
	if inf.is_empty():
		return
	var room: Dictionary = _rooms.get(inf["code"], {})
	if room.is_empty():
		return
	# Untrusted fields: validate types before use — a crafted FWD with a
	# non-buffer "d" or non-numeric "ch"/"pid" must be dropped, not raise.
	var ch_v: Variant = d.get("ch", NetProtocol.CH_STATE)
	var d_v: Variant = d.get("d")
	var pid_v: Variant = d.get("pid", -1)
	if typeof(d_v) != TYPE_PACKED_BYTE_ARRAY \
			or (typeof(ch_v) != TYPE_INT and typeof(ch_v) != TYPE_FLOAT) \
			or (typeof(pid_v) != TYPE_INT and typeof(pid_v) != TYPE_FLOAT):
		return
	var ch := int(ch_v)
	var reliable := ch == NetProtocol.CH_CONTROL
	var payload: PackedByteArray = d_v
	if String(inf["role"]) == "host":
		var target: ENetPacketPeer = room["clients"].get(int(pid_v))
		if target != null:
			_send(target, RelayProtocol.FWD, {"ch": ch, "d": payload}, reliable)
	else:
		_send(room["host"], RelayProtocol.FWD,
			{"pid": int(inf["pid"]), "ch": ch, "d": payload}, reliable)

func _kick(peer: ENetPacketPeer, d: Dictionary) -> void:
	var room := _room_of(peer, "host")
	if room.is_empty():
		return
	var pid := int(d.get("pid", -1))
	var client: ENetPacketPeer = room["clients"].get(pid)
	if client == null:
		return
	room["clients"].erase(pid)
	_peer_info.erase(client)
	_send(client, RelayProtocol.CLOSED, {"why": "removed by host"}, true)

func _on_leave(peer: ENetPacketPeer) -> void:
	var inf: Dictionary = _peer_info.get(peer, {})
	if inf.is_empty():
		return
	_peer_info.erase(peer)
	var code: String = inf["code"]
	if not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	if String(inf["role"]) == "host":
		for pid in room["clients"]:
			var c: ENetPacketPeer = room["clients"][pid]
			_send(c, RelayProtocol.CLOSED, {"why": "host left"}, true)
			_peer_info.erase(c)
		_conn.flush()
		_rooms.erase(code)
	else:
		room["clients"].erase(int(inf["pid"]))
		_send(room["host"], RelayProtocol.LEAVE, {"pid": int(inf["pid"])}, true)

# --------------------------------------------------------------------------

func _room_of(peer: ENetPacketPeer, role: String) -> Dictionary:
	var inf: Dictionary = _peer_info.get(peer, {})
	if inf.is_empty() or String(inf["role"]) != role:
		return {}
	return _rooms.get(inf["code"], {})

func _room_list() -> Array:
	var out: Array = []
	for code in _rooms:
		var info: Dictionary = (_rooms[code]["info"] as Dictionary).duplicate()
		info["code"] = code
		out.append(info)
	return out

func _new_code() -> String:
	while true:
		var code := ""
		for _i in range(RelayProtocol.CODE_LEN):
			code += RelayProtocol.CODE_ALPHABET[_rng.randi_range(0, RelayProtocol.CODE_ALPHABET.length() - 1)]
		if not _rooms.has(code):
			return code
	return ""  # unreachable

func _send(peer: ENetPacketPeer, type: int, payload: Dictionary, reliable: bool) -> void:
	if peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		peer.send(NetProtocol.CH_CONTROL if reliable else NetProtocol.CH_STATE,
			NetProtocol.pack(type, payload),
			ENetPacketPeer.FLAG_RELIABLE if reliable else 0)

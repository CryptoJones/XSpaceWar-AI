class_name RelayHostTransport
extends RefCounted
## Host transport that runs the game through a relay server: the host makes
## one outbound ENet connection (NAT-friendly), REGISTERs to get a room code,
## and sees joining clients as integer pids. Game packets ride in FWD
## envelopes; reliability of the envelope mirrors the game channel's class.
## Same duck-typed API as DirectHostTransport.

var failed := false

var _conn := ENetConnection.new()
var _relay: ENetPacketPeer
var _open := false
var _code := ""
var _reg := {}
var _acc := 999.0   ## send the first UPDATE immediately after ROOM

func open(cfg: Dictionary) -> Error:
	var err := _conn.create_host(1, NetProtocol.CHANNELS)
	if err != OK:
		return err
	_relay = _conn.connect_to_host(String(cfg["ip"]), int(cfg["port"]), NetProtocol.CHANNELS)
	if _relay == null:
		return ERR_CANT_CONNECT
	_reg = {
		"name": String(cfg.get("name", "XSpaceWar")),
		"max": int(cfg.get("max", 12)),
		"mode": int(cfg.get("mode", 0)),
	}
	_open = true
	return OK

## The room code assigned by the relay ("" until registration completes).
func room_code() -> String:
	return _code

func poll() -> Array:
	var out: Array = []
	if not _open:
		return out
	for _i in range(128):
		var ev: Array = _conn.service(0)
		var t := int(ev[0])
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		match t:
			ENetConnection.EVENT_CONNECT:
				_send_relay(RelayProtocol.REGISTER, _reg, true)
			ENetConnection.EVENT_DISCONNECT:
				failed = true
			ENetConnection.EVENT_RECEIVE:
				_translate(_relay.get_packet(), out)
	return out

func _translate(bytes: PackedByteArray, out: Array) -> void:
	var msg := NetProtocol.unpack(bytes)
	if msg.is_empty():
		return
	var d: Dictionary = msg["data"]
	match int(msg["type"]):
		RelayProtocol.ROOM:
			_code = String(d.get("code", ""))
		RelayProtocol.PEER:
			out.append({"t": "connect", "peer": int(d.get("pid", -1))})
		RelayProtocol.LEAVE:
			out.append({"t": "disconnect", "peer": int(d.get("pid", -1))})
		RelayProtocol.FWD:
			out.append({"t": "data", "peer": int(d.get("pid", -1)),
				"bytes": d.get("d", PackedByteArray())})

func send(pid: int, bytes: PackedByteArray, reliable: bool, channel: int) -> void:
	_send_relay(RelayProtocol.FWD, {"pid": pid, "ch": channel, "d": bytes}, reliable)

func kick(pid: int) -> void:
	_send_relay(RelayProtocol.KICK, {"pid": pid}, true)

func tick(dt: float, players: int) -> void:
	if _code == "":
		return
	_acc += dt
	if _acc >= 1.0:
		_acc = 0.0
		_send_relay(RelayProtocol.UPDATE, {"players": players}, true)

func _send_relay(type: int, payload: Dictionary, reliable: bool) -> void:
	if _relay != null and _relay.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_relay.send(NetProtocol.CH_CONTROL if reliable else NetProtocol.CH_STATE,
			NetProtocol.pack(type, payload),
			ENetPacketPeer.FLAG_RELIABLE if reliable else 0)

func close() -> void:
	if not _open:
		return
	if _relay != null and _relay.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_relay.peer_disconnect()
	_conn.flush()
	_conn.destroy()
	_open = false

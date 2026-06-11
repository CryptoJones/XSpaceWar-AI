class_name RelayClientTransport
extends RefCounted
## Client transport that joins a game through a relay server by room code.
## "connect" is surfaced once the relay confirms the JOIN; game packets ride
## in FWD envelopes. Same duck-typed API as DirectClientTransport.

var _conn := ENetConnection.new()
var _relay: ENetPacketPeer
var _open := false
var _code := ""

func open(cfg: Dictionary) -> Error:
	var err := _conn.create_host(1, NetProtocol.CHANNELS)
	if err != OK:
		return err
	_relay = _conn.connect_to_host(String(cfg["ip"]), int(cfg["port"]), NetProtocol.CHANNELS)
	if _relay == null:
		return ERR_CANT_CONNECT
	_code = String(cfg.get("code", "")).to_upper()
	_open = true
	return OK

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
				_send_relay(RelayProtocol.JOIN, {"code": _code}, true)
			ENetConnection.EVENT_DISCONNECT:
				out.append({"t": "disconnect", "why": "relay connection lost"})
			ENetConnection.EVENT_RECEIVE:
				_translate(_relay.get_packet(), out)
	return out

func _translate(bytes: PackedByteArray, out: Array) -> void:
	var msg := NetProtocol.unpack(bytes)
	if msg.is_empty():
		return
	var d: Dictionary = msg["data"]
	match int(msg["type"]):
		RelayProtocol.JOINED:
			if bool(d.get("ok", false)):
				out.append({"t": "connect"})
			else:
				out.append({"t": "disconnect", "why": String(d.get("why", "join refused"))})
		RelayProtocol.FWD:
			out.append({"t": "data", "bytes": d.get("d", PackedByteArray())})
		RelayProtocol.CLOSED:
			out.append({"t": "disconnect", "why": String(d.get("why", "room closed"))})

func send(bytes: PackedByteArray, reliable: bool, channel: int) -> void:
	_send_relay(RelayProtocol.FWD, {"ch": channel, "d": bytes}, reliable)

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

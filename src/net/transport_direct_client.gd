class_name DirectClientTransport
extends RefCounted
## Client transport over a plain ENet connection (LAN / direct IP play).
## All client transports share this duck-typed API:
##   open(cfg) -> Error, poll() -> Array[{t, bytes?, why?}],
##   send(bytes, reliable, channel), close()

var _conn := ENetConnection.new()
var _peer: ENetPacketPeer
var _open := false

func open(cfg: Dictionary) -> Error:
	var err := _conn.create_host(1, NetProtocol.CHANNELS)
	if err != OK:
		return err
	_peer = _conn.connect_to_host(String(cfg["ip"]), int(cfg["port"]), NetProtocol.CHANNELS)
	if _peer == null:
		return ERR_CANT_CONNECT
	_open = true
	return OK

func poll() -> Array:
	var out: Array = []
	if not _open:
		return out
	for _i in range(64):
		var ev: Array = _conn.service(0)
		var t := int(ev[0])
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		match t:
			ENetConnection.EVENT_CONNECT:
				out.append({"t": "connect"})
			ENetConnection.EVENT_DISCONNECT:
				out.append({"t": "disconnect", "why": "connection lost"})
			ENetConnection.EVENT_RECEIVE:
				out.append({"t": "data", "bytes": _peer.get_packet()})
	return out

func send(bytes: PackedByteArray, reliable: bool, channel: int) -> void:
	if _peer != null and _peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_peer.send(channel, bytes, ENetPacketPeer.FLAG_RELIABLE if reliable else 0)

func close() -> void:
	if not _open:
		return
	if _peer != null and _peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_peer.peer_disconnect()
	_conn.flush()
	_conn.destroy()
	_open = false

class_name DirectHostTransport
extends RefCounted
## Host transport over a plain bound ENet socket (LAN / direct IP play).
## Peers are opaque keys (here: the ENetPacketPeer itself). All host
## transports share this duck-typed API:
##   open(cfg) -> Error, poll() -> Array[{t, peer, bytes?}],
##   send(peer, bytes, reliable, channel), kick(peer),
##   tick(dt, players), close(), failed: bool

var failed := false

var _conn := ENetConnection.new()
var _open := false

func open(cfg: Dictionary) -> Error:
	var err := _conn.create_host_bound(String(cfg.get("bind", "*")), int(cfg["port"]),
		int(cfg.get("max_peers", 12)), NetProtocol.CHANNELS)
	_open = err == OK
	return err

func poll() -> Array:
	var out: Array = []
	if not _open:
		return out
	for _i in range(64):
		var ev: Array = _conn.service(0)
		var t := int(ev[0])
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = ev[1]
		match t:
			ENetConnection.EVENT_CONNECT:
				out.append({"t": "connect", "peer": peer})
			ENetConnection.EVENT_DISCONNECT:
				out.append({"t": "disconnect", "peer": peer})
			ENetConnection.EVENT_RECEIVE:
				out.append({"t": "data", "peer": peer, "bytes": peer.get_packet()})
	return out

func send(peer: ENetPacketPeer, bytes: PackedByteArray, reliable: bool, channel: int) -> void:
	if peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		peer.send(channel, bytes, ENetPacketPeer.FLAG_RELIABLE if reliable else 0)

func kick(peer: ENetPacketPeer) -> void:
	_conn.flush()
	peer.peer_disconnect_later()

## The peer's remote IP — the address lever for host bans on direct/LAN.
func peer_address(peer: ENetPacketPeer) -> String:
	return peer.get_remote_address() if peer != null else ""

func tick(_dt: float, _players: int) -> void:
	pass

func close() -> void:
	if not _open:
		return
	_conn.flush()
	_conn.destroy()
	_open = false

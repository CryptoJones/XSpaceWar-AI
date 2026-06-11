class_name NetHost
extends RefCounted
## Authoritative LAN game host. Wraps a running GameSession: pumps ENet,
## hands joining players a bot's ship (and hands it back to a bot when they
## leave), applies remote inputs, steps the session, and broadcasts state
## snapshots at a fixed rate. Also advertises the game for LAN discovery.
##
## Drive it from the renderer (or a headless test) by calling
## `update(dt, local_input)` once per fixed step instead of session.update().

const DEFAULT_PORT := 24642
const SNAPSHOT_INTERVAL := 1.0 / 20.0
const MAX_SERVICE_EVENTS := 64

var session: GameSession
var port := DEFAULT_PORT
var server_name := "XSpaceWar"

var _conn := ENetConnection.new()
var _open := false
var _peers := {}              ## ENetPacketPeer -> ship_id
var _inputs := {}             ## ship_id -> latest input payload
var _acked := {}              ## ship_id -> highest input sequence received
var _advertiser: LanDiscovery
var _event_accum: Array = []  ## forwarded events since the last snapshot
var _snap_accum := 0.0

func _init(p_session: GameSession) -> void:
	session = p_session

func open(p_port := DEFAULT_PORT, advertise := true, p_server_name := "XSpaceWar",
		bind_address := "*") -> Error:
	port = p_port
	server_name = p_server_name
	var err := _conn.create_host_bound(bind_address, port, 12, NetProtocol.CHANNELS)
	if err != OK:
		return err
	_open = true
	if advertise:
		_advertiser = LanDiscovery.advertiser({
			"name": server_name, "port": port,
			"max": session.num_ships, "mode": session.mode, "players": 1,
		})
	return OK

func update(dt: float, local_input: Dictionary) -> void:
	if not _open:
		return
	_pump()

	var human := session.human_ship()
	if human != null and human.alive and not local_input.is_empty():
		NetProtocol.apply_input(human, local_input)
	for sid in _inputs:
		var ship := session.world.ship_by_id(sid)
		if ship != null and ship.alive:
			NetProtocol.apply_input(ship, _inputs[sid])

	session.update(dt)

	for ev in session.world.events:
		if String(ev.get("type", "")) in NetProtocol.FORWARDED_EVENTS:
			_event_accum.append(ev)

	_snap_accum += dt
	if _snap_accum >= SNAPSHOT_INTERVAL:
		_snap_accum = 0.0
		_broadcast_snapshot()

	if _advertiser != null:
		_advertiser.advertise(dt, player_count())

func player_count() -> int:
	return _peers.size() + 1

func _broadcast_snapshot() -> void:
	_event_accum = _event_accum.slice(maxi(0, _event_accum.size() - 64))  # bound backlog
	if _peers.is_empty():
		_event_accum.clear()
		return
	var thrust_ids: Array = []
	for ev in session.world.events:
		if String(ev.get("type", "")) == "thrust":
			thrust_ids.append(ev["ship"])
	var bytes := NetProtocol.pack(NetProtocol.MSG_SNAPSHOT,
		NetProtocol.snapshot_of(session.world, thrust_ids, _event_accum, _acked))
	_event_accum = []
	for peer in _peers:
		peer.send(NetProtocol.CH_STATE, bytes, 0)

func _pump() -> void:
	for _i in range(MAX_SERVICE_EVENTS):
		var ev: Array = _conn.service(0)
		var type := int(ev[0])
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = ev[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				pass  # ship assigned on MSG_HELLO, not on raw connect
			ENetConnection.EVENT_DISCONNECT:
				_drop_peer(peer)
			ENetConnection.EVENT_RECEIVE:
				_on_packet(peer, peer.get_packet())

func _on_packet(peer: ENetPacketPeer, bytes: PackedByteArray) -> void:
	var msg := NetProtocol.unpack(bytes)
	if msg.is_empty():
		return
	var data: Dictionary = msg["data"]
	match int(msg["type"]):
		NetProtocol.MSG_HELLO:
			_on_hello(peer, data)
		NetProtocol.MSG_INPUT:
			if _peers.has(peer):
				var sid: int = _peers[peer]
				var q := int(data.get("q", 0))
				if q >= int(_acked.get(sid, 0)):
					_acked[sid] = q
					_inputs[sid] = data

func _on_hello(peer: ENetPacketPeer, data: Dictionary) -> void:
	if _peers.has(peer):
		return
	if int(data.get("v", -1)) != NetProtocol.VERSION:
		_reject(peer, "protocol version mismatch")
		return
	# A joining player takes over a bot's ship; no bots left = server full.
	var bot_ids := session.bots.keys()
	if bot_ids.is_empty():
		_reject(peer, "server full")
		return
	var sid: int = bot_ids[0]
	session.bots.erase(sid)
	_peers[peer] = sid
	var pname := String(data.get("name", "")).strip_edges().left(16)
	session.ship_names[sid] = pname if pname != "" else "PILOT-%d" % sid
	peer.send(NetProtocol.CH_CONTROL,
		NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, sid)),
		ENetPacketPeer.FLAG_RELIABLE)

func _reject(peer: ENetPacketPeer, why: String) -> void:
	peer.send(NetProtocol.CH_CONTROL,
		NetProtocol.pack(NetProtocol.MSG_REJECT, {"why": why}),
		ENetPacketPeer.FLAG_RELIABLE)
	_conn.flush()
	peer.peer_disconnect_later()

func _drop_peer(peer: ENetPacketPeer) -> void:
	if not _peers.has(peer):
		return
	var sid: int = _peers[peer]
	_peers.erase(peer)
	_inputs.erase(sid)
	_acked.erase(sid)
	session.ship_names.erase(sid)
	# Hand the ship back to a bot so the match keeps its full roster.
	session.bots[sid] = BotController.new(session.world, sid, session.difficulty)

func close() -> void:
	if not _open:
		return
	for peer in _peers:
		peer.peer_disconnect()
	_conn.flush()
	_conn.destroy()
	_open = false
	_peers.clear()
	_inputs.clear()
	if _advertiser != null:
		_advertiser.close()
		_advertiser = null

class_name NetHost
extends RefCounted
## Authoritative game host. Wraps a running GameSession: pumps its transport,
## hands joining players a bot's ship (and hands it back to a bot when they
## leave), applies remote inputs, steps the session, and broadcasts state
## snapshots at a fixed rate.
##
## Runs over either transport: `open()` binds a direct ENet socket (LAN play,
## with UDP discovery advertising) and `open_relay()` registers a room on a
## relay server for internet play (room code via `room_code()`). Peers are
## opaque transport keys. Drive it from the renderer (or a headless test) by
## calling `update(dt, local_input)` once per fixed step.

const DEFAULT_PORT := 24642
const SNAPSHOT_INTERVAL := 1.0 / 20.0

var session: GameSession
var port := DEFAULT_PORT
var server_name := "XSpaceWar"

var _t = null                 ## duck-typed host transport (direct or relay)
var _open := false
var _peers := {}              ## transport peer key -> ship_id
var _names := {}              ## transport peer key -> player name (survives rebuilds)
var _inputs := {}             ## ship_id -> latest input payload
var _acked := {}              ## ship_id -> highest input sequence received
var _advertiser: LanDiscovery
var _event_accum: Array = []  ## forwarded events since the last snapshot
var _snap_accum := 0.0

func _init(p_session: GameSession) -> void:
	session = p_session
	# When the session rebuilds (match restart), every connected player needs
	# a ship in the NEW world and a fresh WELCOME describing it.
	session.on_regenerate = _on_session_rebuilt

func _on_session_rebuilt() -> void:
	if not _open or _peers.is_empty():
		return
	_inputs.clear()
	_acked.clear()
	for peer in _peers:
		if int(_peers[peer]) < 0:
			# Spectators just need the new arena recipe.
			_t.send(peer,
				NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, -1)),
				true, NetProtocol.CH_CONTROL)
			continue
		var bot_ids := session.bots.keys()
		if bot_ids.is_empty():
			_reject(peer, "no ship available after restart")
			continue
		var sid: int = bot_ids[0]
		session.bots.erase(sid)
		_peers[peer] = sid
		session.ship_names[sid] = String(_names.get(peer, "PILOT-%d" % sid))
		_t.send(peer,
			NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, sid)),
			true, NetProtocol.CH_CONTROL)

func open(p_port := DEFAULT_PORT, advertise := true, p_server_name := "XSpaceWar",
		bind_address := "*") -> Error:
	port = p_port
	server_name = p_server_name
	_t = DirectHostTransport.new()
	var err: Error = _t.open({"port": port, "bind": bind_address, "max_peers": 32})
	if err != OK:
		return err
	_open = true
	if advertise:
		_advertiser = LanDiscovery.advertiser({
			"name": server_name, "port": port,
			"max": session.num_ships, "mode": session.mode, "players": 1,
		})
	return OK

## Host an internet game through a relay server (see server/relay_main.gd).
func open_relay(relay_ip: String, relay_port: int, p_server_name := "XSpaceWar") -> Error:
	server_name = p_server_name
	_t = RelayHostTransport.new()
	var err: Error = _t.open({"ip": relay_ip, "port": relay_port,
		"name": server_name, "max": session.num_ships, "mode": session.mode})
	if err != OK:
		return err
	_open = true
	return OK

## Relay room code ("" until the relay assigns one / for direct hosting).
func room_code() -> String:
	return _t.room_code() if _open and _t is RelayHostTransport else ""

## True when the transport has irrecoverably failed (e.g. relay link lost).
func transport_failed() -> bool:
	return _open and bool(_t.failed)

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
	_t.tick(dt, player_count())

func player_count() -> int:
	# Dedicated servers have no host pilot — count only real humans.
	var n := 1 if session.human_ship_id >= 0 else 0
	for peer in _peers:
		if int(_peers[peer]) >= 0:
			n += 1
	return n

func _spectator_count() -> int:
	var n := 0
	for peer in _peers:
		if int(_peers[peer]) < 0:
			n += 1
	return n

func _broadcast_snapshot() -> void:
	_event_accum = _event_accum.slice(maxi(0, _event_accum.size() - 64))  # bound backlog
	if _peers.is_empty():
		_event_accum.clear()
		return
	var thrust_ids: Array = []
	for ev in session.world.events:
		if String(ev.get("type", "")) == "thrust":
			thrust_ids.append(ev["ship"])
	var snap := NetProtocol.snapshot_of(session.world, thrust_ids, _event_accum, _acked)
	snap["mo"] = NetProtocol.match_state_of(session)
	var bytes := NetProtocol.pack(NetProtocol.MSG_SNAPSHOT, snap)
	_event_accum = []
	for peer in _peers:
		_t.send(peer, bytes, false, NetProtocol.CH_STATE)

func _pump() -> void:
	for ev in _t.poll():
		match String(ev["t"]):
			"connect":
				pass  # ship assigned on MSG_HELLO, not on raw connect
			"disconnect":
				_drop_peer(ev["peer"])
			"data":
				_on_packet(ev["peer"], ev["bytes"])

func _on_packet(peer, bytes: PackedByteArray) -> void:
	var msg := NetProtocol.unpack(bytes)
	if msg.is_empty():
		return
	var data: Dictionary = msg["data"]
	match int(msg["type"]):
		NetProtocol.MSG_HELLO:
			_on_hello(peer, data)
		NetProtocol.MSG_PING:
			_t.send(peer, NetProtocol.pack(NetProtocol.MSG_PONG, data),
				false, NetProtocol.CH_STATE)
		NetProtocol.MSG_INPUT:
			if _peers.has(peer):
				var sid: int = _peers[peer]
				if sid < 0:
					return  # spectators don't drive ships
				var q := int(data.get("q", 0))
				if q >= int(_acked.get(sid, 0)):
					_acked[sid] = q
					_inputs[sid] = data

## Dedicated-server mode: the host machine flies nothing — its pilot slot
## becomes one more bot for joiners to take over. Call again after each
## auto-restart (regeneration recreates the human slot).
static func convert_to_dedicated(p_session: GameSession) -> void:
	var hid := p_session.human_ship_id
	if hid < 0:
		return
	p_session.human_ship_id = -1
	var hship := p_session.world.ship_by_id(hid)
	if hship == null:
		return
	p_session.bots[hid] = BotController.new(p_session.world, hid, p_session.difficulty)
	p_session.ship_names[hid] = BotController.callsign(hship.hull_seed)

func _on_hello(peer, data: Dictionary) -> void:
	if _peers.has(peer):
		return
	if int(data.get("v", -1)) != NetProtocol.VERSION:
		_reject(peer, "protocol version mismatch")
		return
	# Spectators get snapshots but no ship (sid -1).
	if bool(data.get("spec", false)):
		if _spectator_count() >= 8:
			_reject(peer, "spectator slots full")
			return
		_peers[peer] = -1
		_t.send(peer,
			NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, -1)),
			true, NetProtocol.CH_CONTROL)
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
	if pname == "":
		pname = "PILOT-%d" % sid
	# A name already on the roster (live player, ghost not yet timed out,
	# or a bot callsign) gets a numeric suffix: PILOT, PILOT-2, PILOT-3…
	var taken := {}
	for n in session.ship_names.values():
		taken[String(n).to_upper()] = true
	if taken.has(pname.to_upper()):
		var k := 2
		while taken.has(("%s-%d" % [pname, k]).to_upper()):
			k += 1
		pname = "%s-%d" % [pname, k]
	_names[peer] = pname
	session.ship_names[sid] = pname
	_t.send(peer,
		NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, sid)),
		true, NetProtocol.CH_CONTROL)

func _reject(peer, why: String) -> void:
	_t.send(peer, NetProtocol.pack(NetProtocol.MSG_REJECT, {"why": why}),
		true, NetProtocol.CH_CONTROL)
	_t.kick(peer)

func _drop_peer(peer) -> void:
	if not _peers.has(peer):
		return
	var sid: int = _peers[peer]
	_peers.erase(peer)
	_names.erase(peer)
	if sid < 0:
		return  # spectator: nothing to hand back
	_inputs.erase(sid)
	_acked.erase(sid)
	# Hand the ship back to a bot (with its own callsign again).
	session.bots[sid] = BotController.new(session.world, sid, session.difficulty)
	var ship := session.world.ship_by_id(sid)
	session.ship_names[sid] = BotController.callsign(ship.hull_seed) if ship != null else ""

func close() -> void:
	if not _open:
		return
	for peer in _peers:
		_t.kick(peer)
	_t.close()
	_open = false
	_peers.clear()
	_inputs.clear()
	_acked.clear()
	if _advertiser != null:
		_advertiser.close()
		_advertiser = null

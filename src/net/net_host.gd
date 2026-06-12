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
## Trusted-server mode: a joiner whose name matches a connected player
## KICKS that session (ghost or otherwise) and inherits its ship — score,
## lives, everything. Default OFF: on public servers a name is not an
## identity, and reclaim would let anyone hijack by typing your name.
var reclaim_names := false
var _names_hash := 0          ## last broadcast roster-names hash
var _failure_handled := false ## transport-death cleanup ran
var _ev_tick := -1            ## last world tick whose events were forwarded
var server_name := "XSpaceWar"

var _t = null                 ## duck-typed host transport (direct or relay)
var _open := false
var _peers := {}              ## transport peer key -> ship_id
var _names := {}              ## transport peer key -> player name (survives rebuilds)
var _inputs := {}             ## ship_id -> latest input payload
var _acked := {}              ## ship_id -> highest input sequence received
var _ban_names := {}          ## UPPERCASED banned callsign -> true
var _ban_addrs := {}          ## banned peer address (direct/LAN only) -> true
var aim := AimAnalyzer.new()  ## host-side aim-anomaly heuristics (warnings only)
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
	_ev_tick = -1
	aim.reset()   # ship ids are reassigned in the rebuilt world
	for peer in _peers.keys():
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
	# Relay-link death emits no per-peer disconnects — without this, every
	# joined ship stays assigned to an unreachable peer (stale inputs
	# reapplied forever). Hand them all back to bots once.
	if bool(_t.failed) and not _failure_handled:
		_failure_handled = true
		for peer in _peers.keys():
			_drop_peer(peer)

	var human := session.human_ship()
	if human != null and human.alive and not local_input.is_empty():
		NetProtocol.apply_input(human, local_input)
	for sid in _inputs:
		var ship := session.world.ship_by_id(sid)
		if ship != null and ship.alive:
			NetProtocol.apply_input(ship, _inputs[sid])

	session.update(dt)
	# Watch every connected human pilot for impossible aim (warnings, not bans).
	aim.observe(session.world, _watched_ids())

	for ev in session.world.events:
		if int(ev.get("tk", -1)) < _ev_tick:
			continue  # forward exactly once (stamps lag the post-step tick by one)
		if String(ev.get("type", "")) in NetProtocol.FORWARDED_EVENTS:
			_event_accum.append(ev)
	_ev_tick = session.world.tick

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
	snap["g"] = session.generation
	# Roster names ride snapshots whenever they change (joins, reclaims,
	# restarts) — previously only YOUR OWN welcome carried them, so other
	# players saw newcomers as bot callsigns forever.
	var names_now := hash(session.ship_names)
	if names_now != _names_hash:
		_names_hash = names_now
		snap["nm"] = session.ship_names.duplicate()
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
	p_session.dedicated = true   # rebuilds keep every slot botted (no kick on restart)
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
	# Banned callsign or address (direct/LAN) — turned away before any slot.
	if _is_banned(peer, String(data.get("name", ""))):
		_reject(peer, "You are banned from this server.")
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
	var pname := NetProtocol.sanitize_name(String(data.get("name", "")))
	if pname == "":
		pname = "PILOT-%d" % sid
	# Trusted reclaim: same name = same pilot. Kick the old session (a
	# ghost that hasn't timed out, usually) and hand over its ship intact.
	if reclaim_names:
		for old_peer in _peers.keys():
			if String(_names.get(old_peer, "")).to_upper() == pname.to_upper() \
					and int(_peers[old_peer]) >= 0:
				var keep_sid: int = _peers[old_peer]
				_t.kick(old_peer)
				_peers.erase(old_peer)
				_names.erase(old_peer)
				_inputs.erase(keep_sid)
				_acked.erase(keep_sid)
				_peers[peer] = keep_sid
				_names[peer] = pname
				session.ship_names[keep_sid] = pname
				# Give back the bot ship we grabbed before matching: without
				# this every reclaim orphaned one slot for the whole match.
				session.bots[sid] = BotController.new(session.world, sid, session.difficulty)
				_t.send(peer, NetProtocol.pack(NetProtocol.MSG_WELCOME,
					NetProtocol.welcome_of(session, keep_sid)), true, NetProtocol.CH_CONTROL)
				return
	# A name already on the roster (live player, ghost not yet timed out,
	# or a bot callsign) gets a random four-digit tag: PILOT-4827.
	var taken := {}
	for n in session.ship_names.values():
		taken[String(n).to_upper()] = true
	if taken.has(pname.to_upper()):
		var base := pname.left(11)   # tag fits the 16-char name invariant
		var tagged := pname
		while taken.has(tagged.to_upper()):
			tagged = "%s-%04d" % [base, randi_range(0, 9999)]
		pname = tagged
	_names[peer] = pname
	session.ship_names[sid] = pname
	_t.send(peer,
		NetProtocol.pack(NetProtocol.MSG_WELCOME, NetProtocol.welcome_of(session, sid)),
		true, NetProtocol.CH_CONTROL)

func _reject(peer, why: String) -> void:
	_t.send(peer, NetProtocol.pack(NetProtocol.MSG_REJECT, {"why": why}),
		true, NetProtocol.CH_CONTROL)
	# Forget the peer NOW: a reject mid-rebuild otherwise leaves a stale
	# old-generation sid in _peers, and the kick's later disconnect event
	# would hand that sid "back" to a bot — hijacking whichever live ship
	# owns the id in the new world.
	var sid: int = _peers.get(peer, -1)
	_peers.erase(peer)
	_names.erase(peer)
	if sid >= 0:
		_inputs.erase(sid)
		_acked.erase(sid)
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
	aim.forget(sid)   # drop the departed pilot's aim tallies
	# Hand the ship back to a bot (with its own callsign again).
	session.bots[sid] = BotController.new(session.world, sid, session.difficulty)
	var ship := session.world.ship_by_id(sid)
	session.ship_names[sid] = BotController.callsign(ship.hull_seed) if ship != null else ""

# --------------------------------------------------------------------------
# Moderation (host kick / ban). The architecture is already host-authoritative
# — this is the removal lever the host UI and the dedicated console drive.
# Names are not identities (a kicked griefer can rename and rejoin), so a ban
# also pins the peer's address WHEN the transport exposes one (direct/LAN); on
# the relay only the name is bannable. Deliberately commodity-grade — see #4.
# --------------------------------------------------------------------------

## Real (non-spectator) players currently connected, sorted by ship id:
## [{"sid": int, "name": String}]. The host UI lists these.
func connected_players() -> Array:
	var out: Array = []
	for peer in _peers:
		var sid: int = _peers[peer]
		if sid >= 0:
			out.append({"sid": sid,
				"name": String(_names.get(peer, session.ship_names.get(sid, "PILOT-%d" % sid)))})
	out.sort_custom(func(a, b): return int(a["sid"]) < int(b["sid"]))
	return out

func _peer_for_ship(sid: int):
	for peer in _peers:
		if int(_peers[peer]) == sid:
			return peer
	return null

## Ship ids of the connected human pilots — who the aim analyzer watches.
func _watched_ids() -> Array:
	var ids: Array = []
	for peer in _peers:
		if int(_peers[peer]) >= 0:
			ids.append(int(_peers[peer]))
	return ids

## Aim-anomaly surface for the host UI / dedicated console.
func aim_report() -> Array:
	return aim.report()

func is_aim_flagged(sid: int) -> bool:
	return aim.is_flagged(sid)

func aim_reasons(sid: int) -> Array:
	return aim.reasons_for(sid)

func _peer_addr(peer) -> String:
	return String(_t.peer_address(peer)) if _t != null and _t.has_method("peer_address") else ""

## Remove the player flying `sid`. `ban` also blocks their callsign (and
## address, on direct/LAN) from rejoining. Returns true if someone was removed.
func kick_ship(sid: int, reason := "Kicked by the host.", ban := false) -> bool:
	var peer = _peer_for_ship(sid)
	if peer == null:
		return false
	if ban:
		_ban_peer(peer)
	# REJECT rides a reliable channel and kick() flushes before disconnecting,
	# so the leaver sees WHY; _drop_peer hands the ship back to a fresh bot.
	_t.send(peer, NetProtocol.pack(NetProtocol.MSG_REJECT, {"why": reason}),
		true, NetProtocol.CH_CONTROL)
	_drop_peer(peer)
	_t.kick(peer)
	return true

## Kick every connected player whose callsign matches (case-insensitive) — the
## dedicated console's `/kick NAME`. Returns how many were removed. With
## `ban`, also blocks the name for absent griefers.
func kick_name(name: String, ban := false) -> int:
	var up := name.strip_edges().to_upper()
	var hits: Array[int] = []
	for p in connected_players():
		if String(p["name"]).to_upper() == up:
			hits.append(int(p["sid"]))
	var reason := "Banned by the host." if ban else "Kicked by the host."
	var n := 0
	for s in hits:
		if kick_ship(s, reason, ban):
			n += 1
	if ban:
		ban_name(name)
	return n

func ban_name(name: String) -> void:
	var up := NetProtocol.filter_name(name).to_upper()
	if up != "":
		_ban_names[up] = true

func unban_name(name: String) -> bool:
	return _ban_names.erase(NetProtocol.filter_name(name).to_upper())

func ban_list() -> Array:
	return _ban_names.keys()

func _ban_peer(peer) -> void:
	var nm := String(_names.get(peer, ""))
	if nm != "":
		_ban_names[nm.to_upper()] = true
	var addr := _peer_addr(peer)
	if addr != "":
		_ban_addrs[addr] = true

## True if this joiner is banned — by the callsign they asked for (matched
## against the sanitized request, not the post-tag name) or by address.
func _is_banned(peer, requested_name: String) -> bool:
	if _peer_addr(peer) in _ban_addrs and not _ban_addrs.is_empty():
		return true
	var up := NetProtocol.filter_name(requested_name).to_upper()
	return up != "" and _ban_names.has(up)

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

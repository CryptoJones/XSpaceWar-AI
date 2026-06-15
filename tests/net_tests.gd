extends SceneTree
## Headless integration tests for the M3 LAN netcode: protocol round-trips,
## a real host+client over loopback ENet (join, arena replication, input
## forwarding, snapshot sync, leaver re-botting), and UDP discovery.
##
## Run with:
##   godot --headless --path . --script res://tests/net_tests.gd

const DT := 1.0 / 60.0
const TEST_PORT := 25642
const DISC_PORT := 25643

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — net tests ===")
	_test_protocol_roundtrip()
	_test_snapshot_bounds()
	_test_packet_size_cap()
	_test_unpack_fuzz()
	_test_host_join_sync()
	_test_prediction()
	_test_spectator()
	_test_dedicated_server()
	_test_dedicated_restart_keeps_players()
	_test_stale_snapshot_dropped()
	_test_input_sequence_guard()
	_test_name_sanitization()
	_test_name_reclaim()
	_test_kick_and_ban()
	_test_discovery_loopback()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

## Distance on the toroidal arena (shortest path across wrap seams).
func _wrap_dist(a: Vector2, b: Vector2, size: float) -> float:
	var d := (a - b).abs()
	d.x = minf(d.x, size - d.x)
	d.y = minf(d.y, size - d.y)
	return d.length()

# --------------------------------------------------------------------------

func _test_protocol_roundtrip() -> void:
	var inp := {"u": -1.0, "t": true, "f": false, "h": true}
	var msg := NetProtocol.unpack(NetProtocol.pack(NetProtocol.MSG_INPUT, inp))
	_check("protocol: input round-trip",
		int(msg.get("type", -1)) == NetProtocol.MSG_INPUT
		and msg["data"]["u"] == -1.0 and msg["data"]["h"] == true)

	var w := SimWorld.new(SimConfig.from_seed(77))
	ArenaGen.populate(w, {"asteroid_density": 5})
	w.add_ship()
	w.step()
	var snap := NetProtocol.snapshot_of(w, [w.ships[0].id], [{"type": "fire", "ship": 1, "pos": Vector2(3, 4)}])
	var rt := NetProtocol.unpack(NetProtocol.pack(NetProtocol.MSG_SNAPSHOT, snap))
	_check("protocol: snapshot round-trip keeps ships/bodies/events",
		rt["data"]["s"].size() == 1 and rt["data"]["e"].size() == 1
		and rt["data"]["th"] == [w.ships[0].id])

	# The engine logs one ERR_INVALID_DATA for the malformed bytes below —
	# that's the point of the probe; the test passes when unpack returns {}.
	_check("protocol: garbage rejected",
		NetProtocol.unpack(PackedByteArray([9, 9, 9])).is_empty()
		and NetProtocol.unpack(var_to_bytes("nope")).is_empty())

func _test_snapshot_bounds() -> void:
	# A truncated or wrong-typed snapshot entry must be skipped, never crash the
	# client with an out-of-bounds index (issue #6).
	var w := SimWorld.new(SimConfig.from_seed(123))
	ArenaGen.populate(w, {"asteroid_density": 5})
	w.add_ship()
	w.step()
	var snap := NetProtocol.snapshot_of(w, [], [])
	# Corrupt every array category: a too-short entry and a wrong-typed entry.
	snap["s"] = [[w.ships[0].id], "not-an-array"]   # ship needs 13 fields
	snap["p"] = [[1, 2]]                             # torpedo needs 6
	snap["mn"] = [[1]]                               # mine needs 6
	snap["pk"] = [42]                                # pickup needs an array of 5
	snap["b"] = [[]]                                 # body needs 2
	var cw := SimWorld.new(SimConfig.from_seed(123))
	ArenaGen.populate(cw, {"asteroid_density": 5})
	cw.add_ship()
	var res = NetProtocol.apply_snapshot(cw, snap)  # must not crash
	_check("protocol: malformed snapshot entries skipped (no crash)",
		typeof(res) == TYPE_DICTIONARY
		and cw.torpedoes.is_empty() and cw.mines.is_empty() and cw.pickups.is_empty())

func _test_packet_size_cap() -> void:
	# Oversized inbound packets are rejected before the expensive bytes_to_var()
	# deserialization, denying the large-packet DoS vector (issue #13).
	var blob := PackedByteArray()
	blob.resize(NetProtocol.MAX_CLIENT_PACKET + 1)
	_check("protocol: oversized packet rejected at host cap",
		NetProtocol.unpack(blob, NetProtocol.MAX_CLIENT_PACKET).is_empty())
	# A normal-size valid packet still decodes under the same cap.
	var ok := NetProtocol.unpack(NetProtocol.pack(NetProtocol.MSG_PING, {"t": 1.0}),
		NetProtocol.MAX_CLIENT_PACKET)
	_check("protocol: in-bounds packet still decodes under host cap",
		int(ok.get("type", -1)) == NetProtocol.MSG_PING)

func _test_unpack_fuzz() -> void:
	# Lock in NetProtocol.unpack()'s contract against malformed/hostile input:
	# ONLY a 2-element [int, Dictionary] array decodes; every other shape is
	# refused without raising. The host runs this on every inbound packet, so a
	# crafted packet must never get past it (issue #13, v2.3.0 review).
	var cap := NetProtocol.MAX_CLIENT_PACKET
	var malformed := [
		var_to_bytes([1]),                # wrong arity (too short)
		var_to_bytes([1, {}, 3]),         # wrong arity (too long)
		var_to_bytes(["x", {}]),          # type id not an int
		var_to_bytes([1, "notadict"]),    # payload not a dictionary
		var_to_bytes([1, [2, 3]]),        # payload an array, not a dict
		var_to_bytes({"a": 1}),           # top-level dict, not an array
		var_to_bytes(42),                 # top-level scalar
	]
	var all_refused := true
	for b in malformed:
		if not NetProtocol.unpack(b, cap).is_empty():
			all_refused = false
	_check("protocol: every malformed packet shape is refused", all_refused)

	# Boundary: the size guard rejects STRICTLY-greater, so a packet whose size
	# equals the cap is allowed; one byte under the cap is not (off-by-one lock).
	var pkt := NetProtocol.pack(NetProtocol.MSG_PING, {"t": 1.0})
	var sz := pkt.size()
	_check("protocol: packet exactly at the cap decodes",
		int(NetProtocol.unpack(pkt, sz).get("type", -1)) == NetProtocol.MSG_PING,
		"size=%d" % sz)
	_check("protocol: one byte over the cap is rejected",
		NetProtocol.unpack(pkt, sz - 1).is_empty())

func _test_host_join_sync() -> void:
	var hsession := GameSession.new()
	hsession.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	hsession.ship_names[hsession.human_ship_id] = "HOSTGUY"
	var host := NetHost.new(hsession)
	var err := host.open(TEST_PORT, false, "test-arena", "127.0.0.1")
	_check("net: host binds", err == OK, "err=%d" % err)
	if err != OK:
		return

	var client := NetClient.new()
	err = client.open("127.0.0.1", TEST_PORT, "JOINER")
	_check("net: client opens", err == OK, "err=%d" % err)

	# Pump both ends; once joined, the client holds fire + mine drop.
	var fire := {"u": 0.0, "t": false, "f": true, "h": false, "m": true}
	var ticks_ready := -1
	var saw_client_torpedo_on_host := false
	var saw_torpedo_on_client := false
	var saw_client_mine_on_host := false
	var saw_mine_on_client := false
	for i in range(1200):
		host.update(DT, {})
		var ready := client.state == NetClient.State.READY
		client.update(DT, fire if ready else {})
		if ready and ticks_ready < 0:
			ticks_ready = i
		if ready:
			var sid := client.session.human_ship_id
			for t in hsession.world.torpedoes:
				if t.owner_id == sid:
					saw_client_torpedo_on_host = true
			for m in hsession.world.mines:
				if m.owner_id == sid:
					saw_client_mine_on_host = true
			if not client.session.world.torpedoes.is_empty():
				saw_torpedo_on_client = true
			if not client.session.world.mines.is_empty():
				saw_mine_on_client = true
		if ticks_ready >= 0 and i > ticks_ready + 360:
			break
		OS.delay_msec(1)

	_check("net: client reaches READY", client.state == NetClient.State.READY,
		"state=%d err=%s" % [client.state, client.error_msg])
	if client.state != NetClient.State.READY:
		host.close()
		client.close()
		return

	var hw := hsession.world
	var cw := client.session.world
	_check("net: arena replicated deterministically",
		cw.bodies.size() == hw.bodies.size() and cw.ships.size() == hw.ships.size(),
		"bodies %d/%d ships %d/%d" % [cw.bodies.size(), hw.bodies.size(), cw.ships.size(), hw.ships.size()])
	var bodies_match := true
	for bi in range(cw.bodies.size()):
		if cw.bodies[bi].radius != hw.bodies[bi].radius or cw.bodies[bi].kind != hw.bodies[bi].kind:
			bodies_match = false
			break
	_check("net: replicated bodies are identical", bodies_match)

	var sid := client.session.human_ship_id
	_check("net: client got a non-host ship", sid > 0 and sid != hsession.human_ship_id,
		"sid=%d" % sid)
	_check("net: host records joiner name",
		String(hsession.ship_names.get(sid, "")) == "JOINER")
	_check("net: joiner ship is no longer a bot on the host", not hsession.bots.has(sid))

	var hship := hw.ship_by_id(sid)
	var cship := cw.ship_by_id(sid)
	var dpos := hship.pos.distance_to(cship.pos)
	_check("net: client ship tracks host within tolerance", dpos < 60.0, "delta=%.1f" % dpos)
	_check("net: client fire input produced torpedoes on the host", saw_client_torpedo_on_host)
	_check("net: torpedoes replicate down to the client", saw_torpedo_on_client)
	_check("net: client mine input produced mines on the host", saw_client_mine_on_host)
	_check("net: mines replicate down to the client", saw_mine_on_client)
	_check("net: ping round-trip measured", client.rtt_ms >= 0,
		"rtt=%d" % client.rtt_ms)

	# Match restart: the host rebuilds and re-welcomes the client into the
	# NEW arena (fresh ship ids, names preserved).
	var gen_before := client.session.generation
	hsession.score_limit = 1
	hw.ship_by_id(hsession.human_ship_id).score = 1
	var restarted := false
	for i in range(1500):
		host.update(DT, {})
		client.update(DT, {})
		if client.session.generation > gen_before \
				and client.state == NetClient.State.READY \
				and client.session.world != null \
				and client.session.world.ships.size() == hsession.world.ships.size():
			restarted = true
			break
		OS.delay_msec(1)
	_check("net: match restart re-welcomes the client into the new arena", restarted,
		"gen %d -> %d" % [gen_before, client.session.generation])
	_check("net: joiner name survives the restart",
		String(hsession.ship_names.get(client.session.human_ship_id, "")) == "JOINER")
	hsession.score_limit = 0
	sid = client.session.human_ship_id  # fresh ship id in the new arena

	# Disconnect: the host should hand the ship back to a bot.
	client.close()
	for i in range(2000):
		host.update(DT, {})
		if hsession.bots.has(sid):
			break
		OS.delay_msec(1)
	_check("net: leaver's ship handed back to a bot", hsession.bots.has(sid))
	host.close()

func _test_dedicated_server() -> void:
	# A dedicated session has NO host pilot: every slot is a bot until a
	# player joins and takes one over.
	var hsession := GameSession.new()
	hsession.score_limit = 0
	hsession.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	NetHost.convert_to_dedicated(hsession)
	_check("dedicated: host has no pilot, all slots botted",
		hsession.human_ship_id == -1 and hsession.bots.size() == 4)
	var host := NetHost.new(hsession)
	var err := host.open(TEST_PORT + 7, false, "dedicated-test", "127.0.0.1")
	_check("dedicated: binds", err == OK, "err=%d" % err)
	if err != OK:
		return
	var client := NetClient.new()
	client.open("127.0.0.1", TEST_PORT + 7, "VISITOR")
	var got_ship := false
	for _i in range(600):
		host.update(DT, {})
		client.update(DT, {})
		if client.state == NetClient.State.READY and client.session.human_ship_id >= 0:
			got_ship = true
			break
		OS.delay_msec(1)
	_check("dedicated: joiner takes over a bot ship", got_ship
		and hsession.bots.size() == 3 and host.player_count() == 1
		and hsession.ship_names.values().has("VISITOR"),
		"bots=%d players=%d" % [hsession.bots.size(), host.player_count()])
	# Same name, no reclaim: the twin gets a random four-digit tag.
	var twin := NetClient.new()
	twin.open("127.0.0.1", TEST_PORT + 7, "VISITOR")
	var twin_name := ""
	for _i in range(600):
		host.update(DT, {})
		client.update(DT, {})
		twin.update(DT, {})
		if twin.state == NetClient.State.READY and twin.session.human_ship_id >= 0:
			twin_name = String(hsession.ship_names.get(twin.session.human_ship_id, ""))
			break
		OS.delay_msec(1)
	var re := RegEx.create_from_string("^VISITOR-\\d{4}$")
	_check("dedicated: name twin gets a random 4-digit tag",
		re.search(twin_name) != null, "name='%s'" % twin_name)
	twin.close()
	client.close()
	host.close()

func _test_spectator() -> void:
	var hsession := GameSession.new()
	hsession.start_skirmish(3, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var bots_before := hsession.bots.size()
	var host := NetHost.new(hsession)
	var err := host.open(TEST_PORT + 11, false, "spec-test", "127.0.0.1")
	_check("spectator: host binds", err == OK, "err=%d" % err)
	if err != OK:
		return
	var spec := NetClient.new()
	spec.open("127.0.0.1", TEST_PORT + 11, "WATCHER", true)
	for i in range(1200):
		host.update(DT, {})
		spec.update(DT, {})
		if spec.state == NetClient.State.READY and spec.session.world != null \
				and spec.session.world.tick > 0:
			break
		OS.delay_msec(1)
	_check("spectator: reaches READY with no ship",
		spec.state == NetClient.State.READY and spec.session.human_ship_id == -1,
		"state=%d sid=%d" % [spec.state, spec.session.human_ship_id])
	_check("spectator: consumes no bot ship", hsession.bots.size() == bots_before,
		"bots %d -> %d" % [bots_before, hsession.bots.size()])
	_check("spectator: receives the world via snapshots",
		spec.session.world != null
		and spec.session.world.ships.size() == hsession.world.ships.size()
		and spec.session.world.tick > 0)
	_check("spectator: not counted as a player", host.player_count() == 1)
	spec.close()
	host.close()

func _test_prediction() -> void:
	# Hold turn+thrust on the client and verify its locally-predicted ship
	# stays glued to the host's authoritative one. Pure extrapolation can't do
	# this (it doesn't know about the thrust); only predict+replay can.
	var hsession := GameSession.new()
	hsession.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var host := NetHost.new(hsession)
	var err := host.open(TEST_PORT + 7, false, "pred", "127.0.0.1")
	_check("prediction: host binds", err == OK, "err=%d" % err)
	if err != OK:
		return
	var client := NetClient.new()
	client.open("127.0.0.1", TEST_PORT + 7, "PRED")

	# The client legitimately runs a few ticks AHEAD of the host — that is the
	# point of prediction — so same-instant position diffs just measure
	# lead x speed. Instead require the client to sit ON the host's trajectory:
	# distance to (host_pos + host_vel * k*dt), minimized over a small tick
	# window k. A broken predictor (no replay) leaves the trajectory by
	# hundreds of units under sustained turn+thrust.
	var drive := {"u": 0.6, "t": true, "f": false, "h": false}
	var worst := 0.0
	var total := 0.0
	var samples := 0
	var ready_at := -1
	for i in range(1800):
		host.update(DT, {})
		var ready := client.state == NetClient.State.READY
		client.update(DT, drive if ready else {})
		if ready and ready_at < 0:
			ready_at = i
		if ready_at >= 0 and i > ready_at + 60:
			var sid := client.session.human_ship_id
			var hs := hsession.world.ship_by_id(sid)
			var cs := client.session.world.ship_by_id(sid)
			if hs != null and cs != null and hs.alive and cs.alive:
				var arena := hsession.world.config.arena_size
				var best := INF
				for k in range(-2, 7):
					best = minf(best, _wrap_dist(cs.pos, hs.pos + hs.vel * (DT * k), arena))
				worst = maxf(worst, best)
				total += best
				samples += 1
		if ready_at >= 0 and i > ready_at + 480:
			break
		OS.delay_msec(1)

	_check("prediction: client reached READY", ready_at >= 0)
	var mean := total / maxf(1.0, float(samples))
	_check("prediction: own ship rides the host trajectory under active input",
		samples > 40 and mean < 12.0 and worst < 60.0,
		"mean=%.1f worst=%.1f samples=%d" % [mean, worst, samples])
	_check("prediction: unacked input buffer stays bounded",
		client._pending_inputs.size() < 60, "pending=%d" % client._pending_inputs.size())
	client.close()
	host.close()

func _test_dedicated_restart_keeps_players() -> void:
	# A FULL dedicated server auto-restarts without kicking anyone: the
	# session.dedicated flag keeps rebuilt rosters all-bot.
	var hsession := GameSession.new()
	hsession.score_limit = 0
	hsession.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	NetHost.convert_to_dedicated(hsession)
	var host := NetHost.new(hsession)
	if host.open(TEST_PORT + 11, false, "restart-test", "127.0.0.1") != OK:
		_check("dedicated-restart: binds", false)
		return
	var c1 := NetClient.new()
	var c2 := NetClient.new()
	c1.open("127.0.0.1", TEST_PORT + 11, "ALPHA")
	c2.open("127.0.0.1", TEST_PORT + 11, "BRAVO")
	for _i in range(900):
		host.update(DT, {})
		c1.update(DT, {})
		c2.update(DT, {})
		if c1.state == NetClient.State.READY and c2.state == NetClient.State.READY \
				and c1.session.human_ship_id >= 0 and c2.session.human_ship_id >= 0:
			break
		OS.delay_msec(1)
	_check("dedicated-restart: full server seated", host.player_count() == 2)
	var gen_before := hsession.generation
	hsession.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	for _i in range(600):
		host.update(DT, {})
		c1.update(DT, {})
		c2.update(DT, {})
		OS.delay_msec(1)
	_check("dedicated-restart: nobody kicked on rebuild",
		hsession.generation == gen_before + 1 and host.player_count() == 2
		and c1.state == NetClient.State.READY and c2.state == NetClient.State.READY,
		"players=%d c1=%d c2=%d" % [host.player_count(), c1.state, c2.state])
	_check("names: existing clients learn other players' names",
		c1.session.ship_names.values().has("BRAVO")
		and c2.session.ship_names.values().has("ALPHA"),
		"c1 sees %s" % [c1.session.ship_names.values()])
	c1.close()
	c2.close()
	host.close()

func _test_stale_snapshot_dropped() -> void:
	# Old-generation snapshots in flight across a restart must not touch
	# the rebuilt world (their removed-body ids overlap fresh ids).
	var hsession := GameSession.new()
	hsession.score_limit = 0
	hsession.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var host := NetHost.new(hsession)
	if host.open(TEST_PORT + 13, false, "stale-test", "127.0.0.1") != OK:
		_check("stale-snap: binds", false)
		return
	var client := NetClient.new()
	client.open("127.0.0.1", TEST_PORT + 13, "GAMMA")
	for _i in range(600):
		host.update(DT, {})
		client.update(DT, {})
		if client.state == NetClient.State.READY and client.session.world != null:
			break
		OS.delay_msec(1)
	var stale := NetProtocol.snapshot_of(hsession.world, [], [], {})  # gen N
	stale["g"] = client.session.generation                # tag as current...
	client.session.generation += 1                        # ...then move client on
	var rocks_before := client.session.world.bodies.size()
	stale["rb"] = [client.session.world.bodies[0].id] if rocks_before > 0 else []
	client._on_packet(NetProtocol.pack(NetProtocol.MSG_SNAPSHOT, stale))
	_check("stale-snap: old-generation snapshot is ignored",
		client.session.world.bodies.size() == rocks_before,
		"bodies %d -> %d" % [rocks_before, client.session.world.bodies.size()])
	client.close()
	host.close()

func _test_input_sequence_guard() -> void:
	# A client controls its own ship's input sequence `q`. A hostile/buggy huge
	# q must NOT pin _acked high and suppress that ship's later legitimate
	# inputs (defence-in-depth, issue from the v2.3.0 review). We poke the host's
	# packet handler directly with a fake peer mapped to a ship id.
	var hs := GameSession.new()
	hs.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var host := NetHost.new(hs)
	var sid := 1
	var peer := "fake-peer"
	host._peers[peer] = sid

	var send := func(q: int, u: float) -> void:
		host._on_packet(peer, NetProtocol.pack(NetProtocol.MSG_INPUT, {"q": q, "u": u}))

	send.call(100, 0.5)
	_check("seq: first input re-bases _acked", int(host._acked.get(sid, -999)) == 100
		and host._inputs.has(sid))
	send.call(101, 0.25)
	_check("seq: in-order advance accepted", int(host._acked[sid]) == 101)
	# A jump far past the window is refused — _acked stays put.
	send.call(1 << 30, -1.0)
	_check("seq: implausible forward jump refused", int(host._acked[sid]) == 101)
	# ...and the next legitimate input still lands (the whole point of the fix:
	# the attack above would otherwise have pinned _acked at 2^30).
	send.call(102, 1.0)
	_check("seq: legit input after a jump attack still accepted",
		int(host._acked[sid]) == 102 and float(host._inputs[sid]["u"]) == 1.0)
	# A small backward q (reordered/stale duplicate) is dropped.
	send.call(50, 0.0)
	_check("seq: stale reordered input dropped", int(host._acked[sid]) == 102)

	# A q far BELOW the last accepted value is a sequence reset (rejoin / match
	# restart): re-base to it rather than ignore the ship forever.
	var sid2 := 2
	host._peers["peer2"] = sid2
	host._on_packet("peer2", NetProtocol.pack(NetProtocol.MSG_INPUT, {"q": 5000, "u": 0.0}))
	_check("seq: first input for second ship accepted", int(host._acked.get(sid2, -999)) == 5000)
	host._on_packet("peer2", NetProtocol.pack(NetProtocol.MSG_INPUT, {"q": 3, "u": 0.7}))
	_check("seq: large drop treated as a reset and re-based",
		int(host._acked[sid2]) == 3 and float(host._inputs[sid2]["u"]) == 0.7)

func _test_name_sanitization() -> void:
	_check("names: CJK and markup stripped, never empty",
		NetProtocol.sanitize_name("李雷[color=red]x") == "COLORREDX"
		and NetProtocol.sanitize_name("漢字漢字") == "PILOT"
		and NetProtocol.sanitize_name("  ace_42-X  ") == "ACE_42-X"
		and NetProtocol.sanitize_name("[b][/b]") == "BB"
		and NetProtocol.sanitize_name("x".repeat(40)).length() == 16,
		"got '%s' / '%s'" % [NetProtocol.sanitize_name("李雷[color=red]x"),
			NetProtocol.sanitize_name("[b][/b]")])

func _test_name_reclaim() -> void:
	# Trusted servers: rejoining with the same name kicks the ghost and
	# inherits its ship — score intact.
	var hsession := GameSession.new()
	hsession.score_limit = 0
	hsession.start_skirmish(3, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	NetHost.convert_to_dedicated(hsession)
	var host := NetHost.new(hsession)
	host.reclaim_names = true
	var err := host.open(TEST_PORT + 9, false, "reclaim-test", "127.0.0.1")
	if err != OK:
		_check("reclaim: binds", false, "err=%d" % err)
		return
	var ghost := NetClient.new()
	ghost.open("127.0.0.1", TEST_PORT + 9, "ACE")
	var ghost_sid := -1
	for _i in range(600):
		host.update(DT, {})
		ghost.update(DT, {})
		if ghost.state == NetClient.State.READY and ghost.session.human_ship_id >= 0:
			ghost_sid = ghost.session.human_ship_id
			break
		OS.delay_msec(1)
	_check("reclaim: first session takes a ship", ghost_sid >= 0)
	hsession.world.ship_by_id(ghost_sid).score = 5
	# The "ghost" stays connected (it never timed out); the SAME NAME rejoins.
	var back := NetClient.new()
	back.open("127.0.0.1", TEST_PORT + 9, "ACE")
	var back_sid := -1
	for _i in range(600):
		host.update(DT, {})
		back.update(DT, {})
		ghost.update(DT, {})
		if back.state == NetClient.State.READY and back.session.human_ship_id >= 0:
			back_sid = back.session.human_ship_id
			break
		OS.delay_msec(1)
	_check("reclaim: rejoiner inherits the ghost's ship and score",
		back_sid == ghost_sid
		and hsession.world.ship_by_id(back_sid).score == 5
		and host.player_count() == 1,
		"sid %d/%d players=%d" % [ghost_sid, back_sid, host.player_count()])
	_check("reclaim: the probed bot ship is handed back (no orphan)",
		hsession.bots.size() == 2, "bots=%d" % hsession.bots.size())
	back.close()
	ghost.close()
	host.close()

## Helper: pump host+client until `cond` (or timeout); returns the tick hit.
func _pump_until(host: NetHost, client: NetClient, cond: Callable, max_ticks := 600) -> int:
	for i in range(max_ticks):
		host.update(DT, {})
		client.update(DT, {})
		if cond.call():
			return i
		OS.delay_msec(1)
	return -1

func _dedicated_host(port: int, who: String) -> NetHost:
	var hs := GameSession.new()
	hs.score_limit = 0
	hs.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	NetHost.convert_to_dedicated(hs)
	var host := NetHost.new(hs)
	host.open(port, false, who, "127.0.0.1")
	return host

func _test_kick_and_ban() -> void:
	var host := _dedicated_host(TEST_PORT + 9, "kick-test")
	var hs := host.session

	# A player joins and takes a ship.
	var c := NetClient.new()
	c.open("127.0.0.1", TEST_PORT + 9, "GRIEFER")
	_pump_until(host, c, func(): return c.state == NetClient.State.READY and c.session.human_ship_id >= 0)
	var sid := c.session.human_ship_id
	_check("kick: joiner took a ship", sid >= 0 and not hs.bots.has(sid), "sid=%d" % sid)
	var roster := host.connected_players()
	_check("kick: connected_players lists the joiner",
		roster.size() == 1 and String(roster[0]["name"]) == "GRIEFER")

	# Kick: the client fails with the reason; the ship returns to a bot.
	_check("kick: kick_ship reports success", host.kick_ship(sid, "Kicked by the host."))
	_pump_until(host, c, func(): return c.state == NetClient.State.FAILED)
	_check("kick: kicked client disconnects with a reason",
		c.state == NetClient.State.FAILED and c.error_msg == "Kicked by the host.",
		"msg=%s" % c.error_msg)
	_check("kick: kicked ship handed back to a bot", hs.bots.has(sid))
	_check("kick: no players left", host.player_count() == 0)
	c.close()

	# Name ban (no address): that callsign is refused at join; unban restores it.
	host.ban_name("BANNED")
	_check("ban: name on the list", host.ban_list().has("BANNED"))
	var cb := NetClient.new()
	cb.open("127.0.0.1", TEST_PORT + 9, "BANNED")
	_pump_until(host, cb, func(): return cb.state == NetClient.State.FAILED)
	_check("ban: banned name rejected at join",
		cb.state == NetClient.State.FAILED and cb.error_msg == "You are banned from this server.",
		"msg=%s" % cb.error_msg)
	cb.close()
	_check("ban: unban removes the entry",
		host.unban_name("BANNED") and not host.ban_list().has("BANNED"))
	var cu := NetClient.new()
	cu.open("127.0.0.1", TEST_PORT + 9, "BANNED")
	var ok := _pump_until(host, cu, func(): return cu.state == NetClient.State.READY and cu.session.human_ship_id >= 0)
	_check("ban: unbanned name can join again", ok >= 0, "state=%d msg=%s" % [cu.state, cu.error_msg])
	cu.close()
	host.close()

	# Address ban (direct/LAN): kick-with-ban pins the IP, so a DIFFERENT
	# callsign from the same address is still refused.
	var host2 := _dedicated_host(TEST_PORT + 10, "addrban-test")
	var ca := NetClient.new()
	ca.open("127.0.0.1", TEST_PORT + 10, "AAA")
	_pump_until(host2, ca, func(): return ca.state == NetClient.State.READY and ca.session.human_ship_id >= 0)
	host2.kick_ship(ca.session.human_ship_id, "Banned by the host.", true)
	_pump_until(host2, ca, func(): return ca.state == NetClient.State.FAILED)
	ca.close()
	var cc := NetClient.new()
	cc.open("127.0.0.1", TEST_PORT + 10, "BBB")  # new name, same loopback address
	_pump_until(host2, cc, func(): return cc.state == NetClient.State.FAILED)
	_check("ban: a banned address blocks a renamed rejoin",
		cc.state == NetClient.State.FAILED and cc.error_msg == "You are banned from this server.",
		"state=%d msg=%s" % [cc.state, cc.error_msg])
	cc.close()
	host2.close()

func _test_discovery_loopback() -> void:
	var listen := LanDiscovery.listener(DISC_PORT, "127.0.0.1")
	_check("discovery: listener binds", listen.bind_ok)
	if not listen.bind_ok:
		return
	var adv := LanDiscovery.advertiser(
		{"name": "ad-test", "port": TEST_PORT, "max": 8, "mode": 0}, "127.0.0.1", DISC_PORT)
	var found: Array = []
	for i in range(500):
		adv.advertise(DT, 3)
		found = listen.poll(DT)
		if not found.is_empty():
			break
		OS.delay_msec(1)
	_check("discovery: advertised server is found",
		not found.is_empty() and String(found[0].get("name", "")) == "ad-test"
		and int(found[0].get("players", 0)) == 3,
		"found=%d" % found.size())
	adv.close()
	listen.close()

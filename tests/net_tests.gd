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
	_test_host_join_sync()
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

	# Pump both ends; once joined, the client holds the fire key.
	var fire := {"u": 0.0, "t": false, "f": true, "h": false}
	var ticks_ready := -1
	var saw_client_torpedo_on_host := false
	var saw_torpedo_on_client := false
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
			if not client.session.world.torpedoes.is_empty():
				saw_torpedo_on_client = true
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

	# Disconnect: the host should hand the ship back to a bot.
	client.close()
	for i in range(2000):
		host.update(DT, {})
		if hsession.bots.has(sid):
			break
		OS.delay_msec(1)
	_check("net: leaver's ship handed back to a bot", hsession.bots.has(sid))
	host.close()

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

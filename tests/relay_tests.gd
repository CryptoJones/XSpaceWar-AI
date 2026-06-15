extends SceneTree
## Headless integration tests for M4 online play: a real RelayServer plus a
## host and clients running through it in-process over loopback sockets —
## registration/room codes, the master server list, joining by code, full
## game sync through the forwarding hop, leave re-botting, and host departure.
##
## Run with:
##   godot --headless --path . --script res://tests/relay_tests.gd

const DT := 1.0 / 60.0
const RELAY_PORT := 25745

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — relay tests ===")
	_test_online_flow()
	_test_room_cap()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

func _test_online_flow() -> void:
	var relay := RelayServer.new()
	var err := relay.open(RELAY_PORT, "127.0.0.1")
	_check("relay: binds", err == OK, "err=%d" % err)
	if err != OK:
		return

	# --- Host registers and gets a room code. ---
	var hsession := GameSession.new()
	hsession.start_skirmish(6, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	hsession.ship_names[hsession.human_ship_id] = "RHOST"
	var host := NetHost.new(hsession)
	err = host.open_relay("127.0.0.1", RELAY_PORT, "relay-arena")
	_check("relay: host opens toward relay", err == OK, "err=%d" % err)

	var code := ""
	for i in range(600):
		relay.pump()
		host.update(DT, {})
		code = host.room_code()
		if code != "":
			break
		OS.delay_msec(1)
	_check("relay: host receives a room code", code.length() == RelayProtocol.CODE_LEN,
		"code='%s'" % code)
	_check("relay: room is tracked", relay.room_count() == 1)

	# --- Browser (master role) sees the room. ---
	var browser := RelayBrowser.new()
	browser.open("127.0.0.1", RELAY_PORT)
	for i in range(600):
		relay.pump()
		host.update(DT, {})
		browser.update(DT)
		if browser.done:
			break
		OS.delay_msec(1)
	var listed := browser.done and browser.error == "" and browser.servers.size() == 1 \
		and String(browser.servers[0].get("name", "")) == "relay-arena" \
		and String(browser.servers[0].get("code", "")) == code
	_check("relay: browser lists the room", listed,
		"done=%s err=%s n=%d" % [browser.done, browser.error, browser.servers.size()])

	# --- Two clients join by code and reach READY through the relay. ---
	var c1 := NetClient.new()
	c1.open_relay("127.0.0.1", RELAY_PORT, code, "RJOIN1")
	var c2 := NetClient.new()
	c2.open_relay("127.0.0.1", RELAY_PORT, code.to_lower(), "RJOIN2")  # case-insensitive
	var fire := {"u": 0.0, "t": false, "f": true, "h": false}
	var c1_torp_on_host := false
	var c1_sees_torps := false
	for i in range(2400):
		relay.pump()
		host.update(DT, {})
		c1.update(DT, fire if c1.state == NetClient.State.READY else {})
		c2.update(DT, {})
		if c1.state == NetClient.State.READY:
			var sid := c1.session.human_ship_id
			for t in hsession.world.torpedoes:
				if t.owner_id == sid:
					c1_torp_on_host = true
			if not c1.session.world.torpedoes.is_empty():
				c1_sees_torps = true
		if c1_torp_on_host and c1_sees_torps and c2.state == NetClient.State.READY:
			break
		OS.delay_msec(1)

	_check("relay: client 1 reaches READY", c1.state == NetClient.State.READY,
		"state=%d err=%s" % [c1.state, c1.error_msg])
	_check("relay: client 2 reaches READY (case-insensitive code)",
		c2.state == NetClient.State.READY, "state=%d err=%s" % [c2.state, c2.error_msg])
	if c1.state != NetClient.State.READY:
		host.close(); c1.close(); c2.close(); relay.close()
		return
	_check("relay: arena replicates through the relay",
		c1.session.world.bodies.size() == hsession.world.bodies.size())
	_check("relay: both pilots named on host",
		String(hsession.ship_names.get(c1.session.human_ship_id, "")) == "RJOIN1"
		and String(hsession.ship_names.get(c2.session.human_ship_id, "")) == "RJOIN2")
	_check("relay: client fire input crosses the relay (host torpedoes)", c1_torp_on_host)
	_check("relay: snapshots flow back (client sees torpedoes)", c1_sees_torps)

	# --- Bad room code is refused. ---
	var c3 := NetClient.new()
	c3.open_relay("127.0.0.1", RELAY_PORT, "ZZZZ", "RNOPE")
	for i in range(600):
		relay.pump()
		c3.update(DT, {})
		if c3.state == NetClient.State.FAILED:
			break
		OS.delay_msec(1)
	_check("relay: unknown room code refused", c3.state == NetClient.State.FAILED
		and c3.error_msg == "room not found", "err='%s'" % c3.error_msg)
	c3.close()

	# --- Client 2 leaves; its ship goes back to a bot. ---
	var sid2 := c2.session.human_ship_id
	c2.close()
	var rebotted := false
	for i in range(1200):
		relay.pump()
		host.update(DT, {})
		c1.update(DT, {})
		if hsession.bots.has(sid2):
			rebotted = true
			break
		OS.delay_msec(1)
	_check("relay: leaver's ship handed back to a bot", rebotted)

	# --- Host leaves; remaining client is told and the room dissolves. ---
	host.close()
	for i in range(1200):
		relay.pump()
		c1.update(DT, {})
		if c1.state == NetClient.State.FAILED:
			break
		OS.delay_msec(1)
	_check("relay: client told when host leaves", c1.state == NetClient.State.FAILED
		and c1.error_msg == "host left", "err='%s'" % c1.error_msg)
	_check("relay: room dissolved", relay.room_count() == 0)
	c1.close()
	relay.close()

func _test_room_cap() -> void:
	# REGISTER-flood guard: once the room table is full the relay refuses new
	# registrations instead of growing memory without bound (the public relay is
	# the most internet-exposed component; v2.3.0 review gap #1).
	var relay := RelayServer.new()
	if relay.open(RELAY_PORT + 5, "127.0.0.1") != OK:
		_check("relay-cap: binds", false)
		return
	for i in range(RelayServer.MAX_ROOMS):
		relay._rooms["RM%d" % i] = {"host": null, "clients": {}, "info": {}}
	_check("relay-cap: room table saturated", relay.room_count() == RelayServer.MAX_ROOMS)
	var hsession := GameSession.new()
	hsession.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var host := NetHost.new(hsession)
	host.open_relay("127.0.0.1", RELAY_PORT + 5, "overflow")
	var code := ""
	for i in range(300):
		relay.pump()
		host.update(DT, {})
		code = host.room_code()
		if code != "":
			break
		OS.delay_msec(1)
	_check("relay-cap: registration refused when full",
		code == "" and relay.room_count() == RelayServer.MAX_ROOMS, "code='%s'" % code)
	host.close()
	relay.close()

extends SceneTree
## Standalone DEDICATED GAME SERVER — the authoritative host with no human
## pilot, for a VPS or spare box. Players join over LAN, direct IP, or a
## relay; bots hold every slot until a human takes it (and resume when they
## leave a match restart later). Run:
##
##   godot --headless --path . --script res://server/dedicated_main.gd -- \
##       --port 24642 --name "Nebraska Arena" --ships 12 --score 15
##
## Options (all optional):
##   --port N         UDP game port (default 24642)
##   --relay ip[:p]   ALSO register on a relay so internet players can join
##   --name S         server name in browsers (default "Dedicated Arena")
##   --ships N        roster size 2-16 (default 12)
##   --mode ffa|team  (default ffa)        --diff 0-3      (default 1 Veteran)
##   --score N        first-to-N, 0=endless (default 10)
##   --time MIN       match clock, 0=off    --lives N       0=unlimited
##   --hazard 0-100   asteroid level        --star 5-100    star size (25=classic)
##   --planets 0-6    (default 2)           --map 2000-40000 arena edge
##   --respawn SEC    1-15 (default 6)      --edges          lethal boundary
##   --reclaim        TRUSTED servers: rejoining with the same name kicks
##                    the old session (ghosts) and inherits its ship/score.
##                    Leave OFF for public servers — names are not identity.

var host: NetHost
var session := GameSession.new()
var _last_usec := 0
var _status_accum := 0.0
var _seen_gen := -1

func _initialize() -> void:
	var a := {}
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i].begins_with("--"):
			a[args[i].substr(2)] = args[i + 1] if i + 1 < args.size() else "1"

	session.score_limit = int(a.get("score", "10"))
	session.time_limit = float(a.get("time", "0")) * 60.0
	session.lives = int(a.get("lives", "0"))
	session.hazard = clampf(float(a.get("hazard", "30")) / 100.0, 0.0, 1.0)
	session.star_scale = clampf(float(a.get("star", "25")) / 25.0, 0.2, 4.0)
	session.planet_count = int(a.get("planets", "2"))
	session.map_size = clampf(float(a.get("map", "40000")), 2000.0, 40000.0)
	session.respawn_seconds = float(a.get("respawn", "6"))
	session.lethal_edges = a.has("edges")
	var mode := GameSession.Mode.TEAM if String(a.get("mode", "ffa")) == "team" else GameSession.Mode.FFA
	session.start_skirmish(clampi(int(a.get("ships", "12")), 2, 16), mode,
		clampi(int(a.get("diff", "1")), 0, 3))
	NetHost.convert_to_dedicated(session)
	_seen_gen = session.generation

	host = NetHost.new(session)
	host.reclaim_names = a.has("reclaim")
	var server_name := String(a.get("name", "Dedicated Arena"))
	var err: Error
	if a.has("relay"):
		var rip := String(a["relay"])
		var rport := RelayProtocol.DEFAULT_PORT
		if ":" in rip:
			var parts := rip.rsplit(":", false, 1)
			rip = parts[0]
			rport = int(parts[1])
		err = host.open_relay(rip, rport, server_name)
		if err == OK:
			print("dedicated: hosting via relay %s:%d" % [rip, rport])
	else:
		var port := int(a.get("port", str(NetHost.DEFAULT_PORT)))
		err = host.open(port, true, server_name)
		if err == OK:
			print("dedicated: hosting on UDP %d" % port)
	if err != OK:
		printerr("dedicated: failed to open transport (error %d)" % err)
		quit(1)
		return
	print("dedicated: '%s' — %d slots, mode %s, score %d, lives %d" % [server_name,
		session.num_ships, "TEAM" if mode == GameSession.Mode.TEAM else "FFA",
		session.score_limit, session.lives])
	_last_usec = Time.get_ticks_usec()
	process_frame.connect(_tick)

func _tick() -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_usec) / 1_000_000.0, 0.0, 0.1)
	_last_usec = now
	host.update(dt, {})
	# Auto-restarts recreate the host pilot slot — hand it back to a bot.
	if session.generation != _seen_gen:
		_seen_gen = session.generation
		NetHost.convert_to_dedicated(session)
		print("dedicated: new match (gen %d)" % session.generation)
	_status_accum += dt
	if _status_accum >= 30.0:
		_status_accum = 0.0
		print("dedicated: players %d  tick %d  gen %d  room %s" % [host.player_count(),
			session.world.tick, session.generation,
			host.room_code() if host.room_code() != "" else "-"])
	if host.room_code() != "" and _seen_gen == session.generation:
		pass  # room code printed via status line
	OS.delay_msec(8)  # ~120Hz service loop, sim steps at its own fixed rate

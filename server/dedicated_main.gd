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
##   --ban NAME       Ban a callsign at boot (repeatable; also accepts a
##                    comma-separated list). --banfile PATH loads one per line
##                    AND is rewritten when bans change, so console ban/unban
##                    persist across restarts (the file is the ban store).
##   --record [DIR]   Record every match as a bit-exact replay for cheating
##                    adjudication (DIR default user://replays, see #4).
##
## Live moderation console (when stdin is a terminal): type `help`, or
##   kick <name> | ban <name> | unban <name> | players | watch | bans
## (`watch` lists pilots the aim-anomaly heuristics flagged — warnings only.)

var host: NetHost
var session := GameSession.new()
var _last_usec := 0
var _status_accum := 0.0
var _accum := 0.0
var _announced_code := false
var _seen_gen := -1
# Live moderation console (background stdin reader -> command queue).
var _console: Thread
var _cmd_mutex := Mutex.new()
var _cmd_queue: Array = []
# Replay-based adjudication: record every match to disk as evidence (#4).
var _record := false
var _record_dir := "user://replays"
var _record_gen := -1
# --banfile doubles as the persistent ban store: loaded at boot, rewritten on
# every console ban/unban so runtime moderation survives a restart ("" = none).
var _banfile := ""

func _initialize() -> void:
	var a := {}
	var bans: Array[String] = []
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i].begins_with("--"):
			var key := args[i].substr(2)
			var val: String = args[i + 1] if i + 1 < args.size() else "1"
			if key == "ban":
				bans.append(val)   # repeatable; comma-lists split later
			else:
				a[key] = val

	session.score_limit = int(a.get("score", "10"))
	session.time_limit = float(a.get("time", "0")) * 60.0
	session.lives = int(a.get("lives", "0"))
	session.hazard = clampf(float(a.get("hazard", "30")) / 100.0, 0.0, 1.0)
	session.star_scale = clampf(float(a.get("star", "25")) / 25.0, 0.2, 4.0)
	session.planet_count = int(a.get("planets", "2"))
	session.map_size = clampf(float(a.get("map", "40000")), 2601.0, 40000.0)
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
		var addr := NetProtocol.parse_addr(String(a["relay"]), RelayProtocol.DEFAULT_PORT)
		err = host.open_relay(String(addr.get("ip", "")), int(addr.get("port", RelayProtocol.DEFAULT_PORT)), server_name)
		if err == OK:
			print("dedicated: hosting via relay %s:%d" % [String(addr.get("ip", "")),
				int(addr.get("port", RelayProtocol.DEFAULT_PORT))])
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
	# Replay-based adjudication: record every match as bit-exact evidence (#4).
	_record = a.has("record")
	if _record:
		var rd := String(a.get("record", ""))
		if rd != "" and rd != "1" and not rd.begins_with("--"):
			_record_dir = rd
		DirAccess.make_dir_recursive_absolute(_record_dir)
		print("dedicated: recording matches to %s (cheating-adjudication evidence)" % _record_dir)
		_maybe_start_recording()
	# Moderation: seed the ban list, then open the live stdin console.
	_banfile = String(a.get("banfile", ""))
	_seed_bans(bans, _banfile)
	_start_console()
	_last_usec = Time.get_ticks_usec()
	process_frame.connect(_tick)

func _tick() -> void:
	var now := Time.get_ticks_usec()
	var wall := clampf(float(now - _last_usec) / 1_000_000.0, 0.0, 0.25)
	_last_usec = now
	# Fixed-step accumulator: the deterministic sim integrates ONLY whole
	# fixed_dt steps — exactly like the GUI host's _physics_process — so
	# client prediction reconciles against identical integration.
	_accum = minf(_accum + wall, 0.25)
	var fixed: float = session.world.config.fixed_dt
	while _accum >= fixed:
		host.update(fixed, {})
		_accum -= fixed
	# Auto-restarts: the session.dedicated flag keeps rebuilds all-bot, so
	# this is just bookkeeping/logging now.
	_drain_commands()
	# Rotate replay evidence across auto-restarts (mirror of the GUI host).
	if _record and (session.finished_recorder != null \
			or (session.recorder != null and session.generation != _record_gen)):
		_finalize_recording()
		_maybe_start_recording()
	if session.generation != _seen_gen:
		_seen_gen = session.generation
		print("dedicated: new match (gen %d)" % session.generation)
	if not _announced_code and host.room_code() != "":
		_announced_code = true
		print("dedicated: ROOM CODE %s — share this with players" % host.room_code())
	_status_accum += wall
	if _status_accum >= 30.0:
		_status_accum = 0.0
		print("dedicated: players %d  tick %d  gen %d  room %s" % [host.player_count(),
			session.world.tick, session.generation,
			host.room_code() if host.room_code() != "" else "-"])
		var ps := host.connected_players()
		if not ps.is_empty():
			var names: Array[String] = []
			for p in ps:
				names.append("%s[%d]" % [String(p["name"]), int(p["sid"])])
			print("dedicated: connected — %s" % ", ".join(names))
	OS.delay_msec(4)  # service loop; the accumulator owns sim timing

# --------------------------------------------------------------------------
# Moderation console + ban seeding + replay evidence
# --------------------------------------------------------------------------

## Seed the host ban list from --ban (comma-lists ok) and an optional --banfile
## (one callsign per line, # comments allowed).
func _seed_bans(bans: Array, banfile: String) -> void:
	var n := 0
	for entry in bans:
		for nm in String(entry).split(",", false):
			if String(nm).strip_edges() != "":
				host.ban_name(String(nm)); n += 1
	if banfile != "":
		var f := FileAccess.open(banfile, FileAccess.READ)
		if f == null:
			printerr("dedicated: cannot read banfile %s" % banfile)
		else:
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line != "" and not line.begins_with("#"):
					host.ban_name(line); n += 1
	if n > 0:
		print("dedicated: %d ban(s) seeded — %s" % [n, str(host.ban_list())])

## Rewrite the banfile with the current ban list so console ban/unban survive a
## restart. No-op unless --banfile was given — that file IS the persistence
## store (read at boot by _seed_bans, written here on change). Address bans are
## transport-ephemeral by nature and intentionally not persisted; callsign bans
## are the portable identity.
func _persist_bans() -> void:
	if _banfile == "":
		return
	var f := FileAccess.open(_banfile, FileAccess.WRITE)
	if f == null:
		printerr("dedicated: cannot write banfile %s (runtime bans won't persist)" % _banfile)
		return
	f.store_line("# XSpaceWar-AI ban list — one callsign per line, rewritten on change.")
	for nm in host.ban_list():
		f.store_line(String(nm))
	f.close()

## Start the background stdin reader. It blocks on input; lines land on a
## queue drained by _tick. EOF (piped/no-tty input) just ends the thread.
func _start_console() -> void:
	_console = Thread.new()
	_console.start(_console_loop)
	print("dedicated: console — kick <name> | ban <name> | unban <name> | players | watch | bans | help")

func _console_loop() -> void:
	while true:
		var line := OS.read_string_from_stdin(1024)
		if line == "":
			break  # EOF: no interactive terminal, so no console
		line = line.strip_edges()
		if line == "":
			continue
		_cmd_mutex.lock()
		_cmd_queue.append(line)
		_cmd_mutex.unlock()

func _drain_commands() -> void:
	_cmd_mutex.lock()
	var cmds := _cmd_queue.duplicate()
	_cmd_queue.clear()
	_cmd_mutex.unlock()
	for line in cmds:
		_run_command(String(line))

func _run_command(line: String) -> void:
	if line.begins_with("/"):
		line = line.substr(1)
	var parts := line.split(" ", false, 1)
	var cmd := String(parts[0]).to_lower()
	var arg: String = String(parts[1]).strip_edges() if parts.size() > 1 else ""
	match cmd:
		"kick":
			if arg == "":
				print("usage: kick <name>"); return
			print("dedicated: kicked %d player(s) matching '%s'" % [host.kick_name(arg, false), arg])
		"ban":
			if arg == "":
				print("usage: ban <name>"); return
			print("dedicated: banned '%s' (removed %d connected)" % [arg, host.kick_name(arg, true)])
			_persist_bans()
		"unban":
			if arg == "":
				print("usage: unban <name>"); return
			print("dedicated: unban '%s' — %s" % [arg, "removed" if host.unban_name(arg) else "not in list"])
			_persist_bans()
		"players":
			var ps := host.connected_players()
			print("dedicated: %d player(s) connected" % ps.size())
			for p in ps:
				var flag := "  ⚠ FLAGGED" if host.is_aim_flagged(int(p["sid"])) else ""
				print("  [%d] %s%s" % [int(p["sid"]), String(p["name"]), flag])
		"watch":
			var flagged := host.aim_report().filter(func(r): return bool(r["flagged"]))
			if flagged.is_empty():
				print("dedicated: no aim anomalies flagged (warnings only — never auto-banned)")
			for r in flagged:
				var nm := ""
				for p in host.connected_players():
					if int(p["sid"]) == int(r["sid"]):
						nm = String(p["name"])
				print("  ⚠ [%d] %s — %s" % [int(r["sid"]), nm, ", ".join(r["reasons"])])
		"bans":
			print("dedicated: bans — %s" % str(host.ban_list()))
		"help":
			print("commands: kick <name> | ban <name> | unban <name> | players | watch | bans | help")
		_:
			print("dedicated: unknown command '%s' (try: help)" % cmd)

func _maybe_start_recording() -> void:
	if _record and not session.movie_mode and session.world != null:
		session.recorder = Replay.begin(session)
		_record_gen = session.generation

func _finalize_recording() -> void:
	var r := session.finished_recorder
	session.finished_recorder = null
	if r == null:
		r = session.recorder
		session.recorder = null
	if r == null or r.final_tick < 300:
		return  # < 5s of match — not worth keeping as evidence
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/dedicated-%s.xsr" % [_record_dir, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(r.to_bytes())
		f.close()
		print("dedicated: match recorded — %s (%.0fs)" % [path.get_file(),
			r.duration_sec(1.0 / 60.0)])

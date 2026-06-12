extends SceneTree
## GRAPHICAL PLAYTEST HARNESS — boots the real game, flies the player ship
## through a scripted sortie, captures rendered frames for visual review,
## and prints a verdict report. Run on a machine with a display (or Xvfb):
##
##   godot --path . --script res://tests/playtest_probe.gd -- --shots /tmp/xsw-shots
##
## In-engine input injection (no OS-level synthetic events needed), so it
## works identically on Linux/X11, macOS console sessions, and Xvfb.

const DURATION_FRAMES := 3000        ## ~50s at 60fps
const SHOT_EVERY := 240              ## a frame capture every ~4s

var _frames := 0
var _shots_dir := "/tmp/xsw-shots"
var _shots_saved := 0
var _kills_seen := 0
var _deaths_seen := 0
var _fps_samples: Array[float] = []
var _phase := "boot"
var _failures: Array[String] = []
var _win_mode := false
var _pilot: BotController = null     ## --win: my combat AI flies the ship
var _won := false

func _initialize() -> void:
	for i in range(OS.get_cmdline_user_args().size() - 1):
		if OS.get_cmdline_user_args()[i] == "--shots":
			_shots_dir = OS.get_cmdline_user_args()[i + 1]
	_win_mode = "--win" in OS.get_cmdline_user_args()
	if "--fast" in OS.get_cmdline_user_args():
		Engine.time_scale = 5.0  # dry runs only: the pilot decides per frame
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	print("=== XSpaceWar-AI — graphical playtest ===")
	print("  shots -> %s" % _shots_dir)
	var packed: PackedScene = load("res://src/ui/main.tscn")
	root.add_child(packed.instantiate())
	process_frame.connect(_on_frame)

func _main() -> Node:
	return root.get_node_or_null("Main")

func _on_frame() -> void:
	_frames += 1
	var main := _main()
	if main == null:
		return

	# --- boot: skip cinema, configure a lively skirmish, launch ---
	if _frames == 30:
		main._end_credits()
		main._dismiss_splash()
		main._ships_slider.value = 5 if _win_mode else 8
		main._lives_slider.value = 0
		main._limit_slider.value = 3 if _win_mode else 0
		main._time_slider.value = 0
		main._hazard_slider.value = 30
		main._map_slider.value = 8000 if _win_mode else 40000
		main._diff_slider.value = BotController.Difficulty.ROOKIE if _win_mode \
			else BotController.Difficulty.VETERAN  # Aaron's mercy rule: I kinda suck
		main._edge_check.button_pressed = false
		main._on_play_pressed()
		if _win_mode:
			var s: GameSession = main.session
			_pilot = BotController.new(s.world, s.human_ship_id,
				BotController.Difficulty.INSANE, BotController.Personality.BRAWLER, 35, 100)
			# Register into the session so the SIM drives my decisions every
			# tick (frame-rate updates degrade reflexes under time_scale).
			s.bots[s.human_ship_id] = _pilot
			print("  [t+%02ds] FIRST TO 3 — my AI has the stick" % (_frames / 60))
		else:
			print("  [t+%02ds] match started" % (_frames / 60))
		_phase = "fly"
		return
	if _frames < 40:
		return

	var session: GameSession = main.session
	if session.world == null:
		return
	var human := session.human_ship()

	# --- win mode: hand the stick to my combat AI; declare on match end ---
	if _win_mode:
		# Re-arm my pilot across auto-restarts (rebuilds clear session.bots).
		if _pilot != null and session.bots.get(session.human_ship_id) != _pilot \
				and not session.match_over:
			_pilot = BotController.new(session.world, session.human_ship_id,
				BotController.Difficulty.INSANE, BotController.Personality.BRAWLER, 35, 100)
			session.bots[session.human_ship_id] = _pilot
		if session.match_over and not _won:
			_won = true
			var i_won: bool = session.winner_ship == session.human_ship_id
			var img := root.get_viewport().get_texture().get_image()
			if img != null and not img.is_empty():
				img.save_png("%s/victory.png" % _shots_dir)
				_shots_saved += 1
			print("  [t+%02ds] MATCH OVER — winner: %s" % [_frames / 60,
				session.display_name(session.winner_ship)])
			if not i_won:
				_failures.append("lost the round (winner: %s)"
					% session.display_name(session.winner_ship))
			_report(main)
			return
		if _frames % 1200 == 0 and human != null:
			print("  [t+%02ds] score: me %d | best rival %d  (%d/%d alive)" % [
				_frames / 60, human.score,
				_best_rival_score(session), _alive(session), session.world.ships.size()])
		if _frames >= 24000:
			_failures.append("no decision after %d sim ticks" % session.world.tick)
			_report(main)
			return
	# --- scripted sortie: fly, fight, hyperspace, die-and-watch ---
	if not _win_mode and human != null and human.alive:
		var t := _frames
		human.in_thrust = (t / 240) % 2 == 0          # burn 4s, coast 4s
		human.in_turn = 1.0 if (t / 150) % 3 == 0 else (-1.0 if (t / 150) % 3 == 1 else 0.0)
		human.in_fire = (t % 30) == 0                  # steady trigger pace
		if t % 600 == 599:
			human.in_mine = true
		if t == 1500:
			human.in_hyper = true
			print("  [t+%02ds] hyperspace!" % (t / 60))

	# --- observers ---
	for ev in session.world.events:
		var tk := int(ev.get("tk", -1))
		if tk != session.world.tick - 1:
			continue  # count each once, freshest tick only
		match String(ev.get("type", "")):
			"kill":
				_kills_seen += 1
			"explosion":
				_deaths_seen += 1
	if _frames % 60 == 0:
		_fps_samples.append(Engine.get_frames_per_second())

	# --- frame captures for visual review ---
	if _frames % SHOT_EVERY == 0:
		var img := root.get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			var path := "%s/frame_%04d.png" % [_shots_dir, _frames]
			img.save_png(path)
			_shots_saved += 1

	# --- verdicts along the way ---
	if _frames == 2000 and main.hud._feed.is_empty() and _deaths_seen > 0:
		_failures.append("deaths happened but the kill feed stayed empty")

	if not _win_mode and _frames >= DURATION_FRAMES:
		_report(main)

func _best_rival_score(s: GameSession) -> int:
	var best := -99
	for ship in s.world.ships:
		if ship.id != s.human_ship_id:
			best = maxi(best, ship.score)
	return best

func _alive(s: GameSession) -> int:
	var n := 0
	for ship in s.world.ships:
		if ship.alive:
			n += 1
	return n

func _report(main: Node) -> void:
	var fps_avg := 0.0
	for f in _fps_samples:
		fps_avg += f
	fps_avg /= maxf(1.0, float(_fps_samples.size()))
	var alive := 0
	for s in main.session.world.ships:
		if s.alive:
			alive += 1
	print("=== PLAYTEST REPORT ===")
	print("  duration: %d frames, sim tick %d, avg fps %.0f" % [_frames,
		main.session.world.tick, fps_avg])
	print("  combat: %d kills, %d explosions observed; %d/%d pilots alive" % [
		_kills_seen, _deaths_seen, alive, main.session.world.ships.size()])
	print("  hud: feed entries=%d  scoreboard chars=%d  banner='%s'" % [
		main.hud._feed.size(), main.hud._score.text.length(), main.hud._banner.text])
	print("  shots saved: %d -> %s" % [_shots_saved, _shots_dir])
	if fps_avg < 20.0 and _shots_saved > 0:
		_failures.append("average fps %.0f — unplayably slow on this machine" % fps_avg)
	if _shots_saved == 0:
		_failures.append("no frames captured (headless/dummy renderer?)")
	if _failures.is_empty():
		print("  [PASS] playtest completed clean")
		quit(0)
	else:
		for f in _failures:
			print("  [FAIL] " + f)
		quit(1)

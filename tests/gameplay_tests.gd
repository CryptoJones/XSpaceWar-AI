extends SceneTree
## Headless tests for the GameSession / match layer: match flow and win
## conditions, lives, lethal edges, team spawns, solo practice, scoreboard
## colours, hull generation, the action-camera duel picker, match stats, and
## bit-exact replay record/playback. Split out of run_tests.gd.
##
## Run with:
##   godot --headless --path . --script res://tests/gameplay_tests.gd
##
## Exits 0 on success, 1 on any failure (CI-friendly).

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — gameplay tests ===")
	_test_match_flow()
	_test_difficulty_spread()
	_test_classic_ffa_is_a_ladder()
	_test_rookie_can_actually_hit()
	_test_ship_colors()
	_test_lives()
	_test_lethal_edges()
	_test_mine_lifetime_clamp()
	_test_manual_respawn()
	_test_match_presets()
	_test_team_spawns()
	_test_review_gameplay_fixes()
	_test_solo_practice()
	_test_hull_generation()
	_test_pick_duel()
	_test_pov_zoom_multiplier()
	_test_enemy_ship_visual_scale()
	_test_radar_zoom()
	_test_match_stats()
	_test_corrupt_replay_rejected()
	_test_replay()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

func _make_world(seed: int) -> SimWorld:
	var cfg := SimConfig.from_seed(seed)
	var w := SimWorld.new(cfg)
	ArenaGen.populate(w, {"asteroid_density": 20})
	return w

# --------------------------------------------------------------------------

func _test_difficulty_spread() -> void:
	# Eight identical VETERANs gave a newcomer no pecking order. A ladder gives
	# them something to beat and something to fear; uniform tuning cannot.
	var s := GameSession.new()
	s.difficulty_spread = [
		BotController.Difficulty.ROOKIE,
		BotController.Difficulty.VETERAN,
		BotController.Difficulty.ACE,
	]
	s.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.VETERAN)
	var tiers: Array[int] = []
	for id in s.bots:
		tiers.append(int(s.bots[id].difficulty))
	_check("spread: bots do not all share one tier",
		tiers.size() >= 3 and tiers.min() != tiers.max(),
		"tiers=%s" % [tiers])
	_check("spread: every tier comes from the ladder",
		tiers.all(func(t): return s.difficulty_spread.has(t)),
		"tiers=%s" % [tiers])

	# Dealt in order and wrapped, never rolled: a random draw could produce a
	# roster of aces and recreate the wall this exists to remove.
	var a := GameSession.new()
	a.difficulty_spread = [BotController.Difficulty.ROOKIE, BotController.Difficulty.ACE]
	a.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.VETERAN)
	var b := GameSession.new()
	b.difficulty_spread = [BotController.Difficulty.ROOKIE, BotController.Difficulty.ACE]
	b.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.VETERAN)
	var first: Array[int] = []
	var second: Array[int] = []
	for id in a.bots:
		first.append(int(a.bots[id].difficulty))
	for id in b.bots:
		second.append(int(b.bots[id].difficulty))
	first.sort()
	second.sort()
	_check("spread: deterministic across builds", first == second,
		"%s vs %s" % [first, second])

	# Empty spread must leave every existing caller untouched.
	var u := GameSession.new()
	u.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var uniform := true
	for id in u.bots:
		if int(u.bots[id].difficulty) != BotController.Difficulty.ROOKIE:
			uniform = false
	_check("spread: empty means uniform, as before", uniform)


func _test_classic_ffa_is_a_ladder() -> void:
	# Classic FFA is what a first-time player picks. It must not be a wall.
	var s := GameSession.new()
	MatchPresets.apply(s, MatchPresets.CLASSIC_FFA)
	_check("classic: carries a mixed roster", not s.difficulty_spread.is_empty())
	_check("classic: includes something beatable",
		s.difficulty_spread.has(BotController.Difficulty.ROOKIE))
	_check("classic: still includes something to fear",
		s.difficulty_spread.has(BotController.Difficulty.ACE))
	_check("classic: no INSANE pilots in the newcomer preset",
		not s.difficulty_spread.has(BotController.Difficulty.INSANE))


func _test_rookie_can_actually_hit() -> void:
	# A trainer that never lands a shot reads as a shooting gallery pointed the
	# wrong way; the player never learns they are in a fight.
	var rookie: Dictionary = BotController.PRESETS[BotController.Difficulty.ROOKIE]
	var ace: Dictionary = BotController.PRESETS[BotController.Difficulty.ACE]
	_check("rookie: aim error tightened to 0.20",
		is_equal_approx(float(rookie["aim_error"]), 0.20))
	_check("rookie: still clearly the worst shot",
		float(rookie["aim_error"]) > float(ace["aim_error"]) * 2.0)


func _test_match_flow() -> void:
	var s := GameSession.new()
	s.score_limit = 3
	s.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var gen0 := s.generation
	var human := s.human_ship()
	human.score = 3
	s.update(1.0 / 60.0)
	_check("match: reaching the score limit ends the match",
		s.match_over and s.winner_ship == human.id)
	for _i in range(520):  # ride out the 8s win screen
		s.update(1.0 / 60.0)
	_check("match: restarts with a fresh arena after the win screen",
		not s.match_over and s.generation == gen0 + 1)
	_check("match: scores reset on restart",
		s.human_ship() != null and s.human_ship().score == 0)

	var t := GameSession.new()
	t.score_limit = 2
	t.start_skirmish(4, GameSession.Mode.TEAM, BotController.Difficulty.ROOKIE)
	t.world.ships[0].score = 1
	t.world.ships[2].score = 1  # ships 0 and 2 share team 0 (i % 2)
	t.update(1.0 / 60.0)
	_check("match: team totals trigger a team win",
		t.match_over and t.winner_team == 0)

	# Time limit: the clock expiring crowns the current leader.
	var u := GameSession.new()
	u.score_limit = 0
	u.time_limit = 2.0
	u.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var leader := u.human_ship()
	leader.score = 5
	for _i in range(130):  # ~2.16s
		u.update(1.0 / 60.0)
	_check("match: clock expiry crowns the leader",
		u.match_over and u.winner_ship == leader.id)

func _test_ship_colors() -> void:
	var s := GameSession.new()
	s.start_skirmish(16, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var seen := {}
	for ship in s.world.ships:
		seen[WorldView.ship_color(ship)] = true
	_check("colors: 16 FFA ships get 16 distinct colors", seen.size() == 16,
		"distinct=%d" % seen.size())

func _test_lives() -> void:
	# World level: a pilot out of lives never respawns.
	var s := GameSession.new()
	s.lives = 2
	s.score_limit = 0
	s.start_skirmish(3, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var human := s.human_ship()
	human.deaths = 2
	human.alive = false
	human.respawn_timer = 0.5
	for _i in range(240):
		s.update(1.0 / 60.0)
	_check("lives: out of lives means no respawn",
		not human.alive and s.is_eliminated(human))

	# Session level: last one standing takes the match.
	var s2 := GameSession.new()
	s2.lives = 1
	s2.score_limit = 0
	s2.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var loser := s2.human_ship()
	loser.deaths = 1
	loser.alive = false
	s2.update(1.0 / 60.0)
	var survivor_id := -1
	for ship in s2.world.ships:
		if ship.id != loser.id:
			survivor_id = ship.id
	_check("lives: last pilot standing wins",
		s2.match_over and s2.winner_ship == survivor_id)

func _test_lethal_edges() -> void:
	var s := GameSession.new()
	s.lethal_edges = true
	s.score_limit = 0
	s.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	_check("edges: lethal mode disables wrap",
		s.world.config.lethal_edges and not s.world.config.wrap_edges)
	var human := s.human_ship()
	human.pos = Vector2(s.world.config.arena_size * 0.5 - 10.0, 0.0)
	human.vel = Vector2(900, 0)
	human.spawn_grace = 0.0
	for _i in range(10):
		s.update(1.0 / 60.0)
		if not human.alive:
			break
	_check("edges: crossing the border destroys the ship", not human.alive)

	var s2 := GameSession.new()
	s2.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	_check("edges: toroidal wrap remains the default", s2.world.config.wrap_edges)

	# Wrap-mode slingshot: crossing the seam doubles your speed.
	var h2 := s2.human_ship()
	h2.pos = Vector2(s2.world.config.arena_size * 0.5 - 5.0, 0.0)
	h2.vel = Vector2(600, 0)
	h2.spawn_grace = 0.0
	var v_before := h2.vel.length()
	s2.update(1.0 / 60.0)
	_check("edges: toroidal wrap preserves velocity (no free-energy boost)",
		h2.alive and absf(h2.vel.length() - v_before) < 5.0 and h2.pos.x < 0.0,
		"v %.0f -> %.0f x=%.0f" % [v_before, h2.vel.length(), h2.pos.x])

func _test_mine_lifetime_clamp() -> void:
	# Arm time clamps to its 3..30s slider range, and a finite mine lifetime is
	# never allowed to undercut the arm time (else the mine fizzles before it
	# ever goes hot). Unlimited (0) lifetime is left untouched.
	var s := GameSession.new()
	s.mine_arm_seconds = 50.0   # over-range -> clamps to 30
	s.mine_lifetime = 10.0      # shorter than arm -> bumped up to the arm time
	s.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	_check("mine: arm time clamps to the 3..30s range",
		is_equal_approx(s.world.config.mine_arm_time, 30.0),
		"arm=%.1f" % s.world.config.mine_arm_time)
	_check("mine: finite lifetime is raised to at least the arm time",
		is_equal_approx(s.world.config.mine_life, 30.0),
		"life=%.1f arm=%.1f" % [s.world.config.mine_life, s.world.config.mine_arm_time])

	var u := GameSession.new()
	u.mine_arm_seconds = 12.0
	u.mine_lifetime = 0.0       # unlimited -> stays unlimited regardless of arm
	u.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	_check("mine: unlimited lifetime is preserved under the clamp",
		u.world.config.mine_life == 0.0 and is_equal_approx(u.world.config.mine_arm_time, 12.0),
		"life=%.1f arm=%.1f" % [u.world.config.mine_life, u.world.config.mine_arm_time])

func _test_manual_respawn() -> void:
	# New rule: once the timer elapses, a human ship stays dead until its fire
	# input arrives, while bots come back on their own.
	var s := GameSession.new()
	s.score_limit = 0
	s.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	_check("respawn: new matches enable manual respawn", s.world.config.manual_respawn)

	var human := s.human_ship()
	CollisionSystem.destroy_ship(s.world, human, -1, "test")
	human.respawn_timer = 0.01            # fast-forward to "ready to respawn"
	for _i in range(10):                  # no fire pressed -> must stay dead
		s.update(1.0 / 60.0)
	_check("respawn: human waits for a fire press (no auto-respawn)", not human.alive)

	human.in_fire = true                  # press fire -> back next step
	s.update(1.0 / 60.0)
	var saw_respawn := false
	for ev in s.world.events:
		if String(ev.get("type", "")) == "respawn" and int(ev.get("ship", -1)) == human.id:
			saw_respawn = true
	_check("respawn: human respawns once fire is pressed", human.alive)
	_check("respawn: non-initial spawn emits a warp-in event", saw_respawn)

	# A bot holds fire while dead, so it auto-respawns with no external input.
	var bot_ship: SimShip = null
	for sh in s.world.ships:
		if sh.id != s.human_ship_id:
			bot_ship = sh
			break
	CollisionSystem.destroy_ship(s.world, bot_ship, -1, "test")
	bot_ship.respawn_timer = 0.01
	for _i in range(10):
		s.update(1.0 / 60.0)
	_check("respawn: bots still auto-respawn", bot_ship.alive)

func _test_match_presets() -> void:
	var expected := {
		MatchPresets.CLASSIC_FFA: [8, GameSession.Mode.FFA, BotController.Difficulty.VETERAN, 10, 40000.0, 0.30, 2, false, 0, 4.0, 75.0],
		MatchPresets.QUICK_SKIRMISH: [4, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE, 5, 12000.0, 0.10, 0, false, 0, 3.0, 90.0],
		MatchPresets.TEAM_BATTLE: [8, GameSession.Mode.TEAM, BotController.Difficulty.VETERAN, 15, 40000.0, 0.30, 2, false, 0, 4.0, 75.0],
		MatchPresets.SURVIVAL: [8, GameSession.Mode.FFA, BotController.Difficulty.VETERAN, 0, 40000.0, 0.60, 2, true, 3, 4.0, 60.0],
	}
	var all_match := true
	for id in expected:
		var s := GameSession.new()
		MatchPresets.apply(s, id)
		var e: Array = expected[id]
		all_match = all_match and s.preset == id and s.num_ships == e[0] \
			and s.mode == e[1] and s.difficulty == e[2] and s.score_limit == e[3] \
			and is_equal_approx(s.map_size, e[4]) and is_equal_approx(s.hazard, e[5]) \
			and s.planet_count == e[6] and s.lethal_edges == e[7] \
			and s.lives == e[8] and is_equal_approx(s.respawn_seconds, e[9]) \
			and is_equal_approx(s.flight_pace, e[10]) \
			and is_zero_approx(s.time_limit) and is_zero_approx(s.torpedo_lifetime) \
			and is_equal_approx(s.mine_arm_seconds, 3.0) \
			and is_equal_approx(s.mine_lifetime, 25.0) and is_equal_approx(s.star_scale, 1.0)
	_check("presets: recipes apply exact match settings", all_match)

func _test_team_spawns() -> void:
	var s := GameSession.new()
	s._rng.seed = 1  # fixed seed — team spawn clustering must not depend on luck
	s.start_skirmish(8, GameSession.Mode.TEAM, BotController.Difficulty.ROOKIE)
	var primary := s.world.primary_body()
	var mean0 := Vector2.ZERO
	var mean1 := Vector2.ZERO
	for ship in s.world.ships:
		var dir := (ship.pos - primary.pos).normalized()
		if ship.team == 0:
			mean0 += dir
		else:
			mean1 += dir
	_check("teams: each team spawns clustered in its own sector",
		mean0.length() > 2.0 and mean1.length() > 2.0,
		"m0=%.2f m1=%.2f" % [mean0.length(), mean1.length()])
	_check("teams: the two sectors are apart",
		mean0.normalized().angle_to(mean1.normalized()) > 0.8
		or mean0.normalized().angle_to(mean1.normalized()) < -0.8,
		"angle=%.2f" % mean0.normalized().angle_to(mean1.normalized()))

func _test_review_gameplay_fixes() -> void:
	# Team mutual annihilation ends the match (score decides).
	var s := GameSession.new()
	s.lives = 1
	s.score_limit = 0
	s.start_skirmish(2, GameSession.Mode.TEAM, BotController.Difficulty.ROOKIE)
	for ship in s.world.ships:
		ship.deaths = 1
		ship.alive = false
	s.world.ships[0].score = 3
	s.update(1.0 / 60.0)
	_check("elim: team mutual annihilation still ends the match",
		s.match_over and s.winner_team == s.world.ships[0].team)

	# Lives + solo practice: no instant victory loop.
	var s2 := GameSession.new()
	s2.lives = 3
	s2.score_limit = 0
	s2.hazard = 0.0
	s2.start_skirmish(1, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	for _i in range(120):
		s2.update(1.0 / 60.0)
	_check("elim: lives + solo practice does not insta-end", not s2.match_over)

	# Hyperspace keeps your ammo and grants no shield.
	var w := SimWorld.new(SimConfig.from_seed(777))
	var ship := w.add_ship()
	ship.pos = Vector2(5000, 0)
	ship.ammo = 2
	ship.fuel = 10.0
	ship.spawn_grace = 0.0
	w._hyperspace(ship)
	if ship.alive:  # (passed the self-destruct roll)
		_check("hyper: jump preserves resources, no grace",
			ship.ammo == 2 and is_equal_approx(ship.fuel, 10.0)
			and ship.spawn_grace == 0.0,
			"ammo=%d fuel=%.1f grace=%.2f" % [ship.ammo, ship.fuel, ship.spawn_grace])

	# Spawn clearance: hazard 1.0, many respawns, nobody dies on arrival.
	var s3 := GameSession.new()
	s3.hazard = 1.0
	s3.score_limit = 0
	s3.start_skirmish(8, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var spawn_deaths := 0
	for _i in range(40):
		for ship3 in s3.world.ships:
			s3.world.place_in_orbit(ship3)
		var deaths_before := 0
		for ship3 in s3.world.ships:
			deaths_before += ship3.deaths
		s3.world.step(1.0 / 60.0)
		var deaths_after := 0
		for ship3 in s3.world.ships:
			deaths_after += ship3.deaths
		spawn_deaths += deaths_after - deaths_before
	_check("spawn: clearance + grace stop arrival deaths at hazard 100",
		spawn_deaths == 0, "deaths=%d" % spawn_deaths)

	# Recorder is parked at restart, not captured into the new world.
	var s4 := GameSession.new()
	s4.score_limit = 1
	s4.hazard = 0.0
	s4.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	s4.recorder = Replay.begin(s4)
	for _i in range(60):
		s4.update(1.0 / 60.0)
	var tick_at_win := s4.world.tick
	s4.human_ship().score = 1
	s4.update(1.0 / 60.0)
	_check("recorder: match flow reached match_over", s4.match_over)
	for _i in range(int(GameSession.RESTART_DELAY * 60.0) + 10):
		s4.update(1.0 / 60.0)
	_check("recorder: finished tape parked with its final tick intact",
		s4.finished_recorder != null and s4.recorder == null
		and s4.finished_recorder.final_tick >= tick_at_win,
		"final_tick=%d" % (s4.finished_recorder.final_tick if s4.finished_recorder != null else -1))

func _test_solo_practice() -> void:
	var s := GameSession.new()
	s.score_limit = 0
	s.hazard = 0.0  # clean space: the session seed varies per run, and a
	                # drifting lone ship occasionally clipped a random rock
	s.start_skirmish(1, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	for _i in range(120):
		s.update(1.0 / 60.0)
	_check("solo: one-ship practice flight runs (no bots, pilot alive)",
		s.world.ships.size() == 1 and s.bots.is_empty()
		and s.human_ship() != null and s.human_ship().alive)

func _test_hull_generation() -> void:
	var a: Dictionary = WorldView.hull_polygon(1234)
	var b: Dictionary = WorldView.hull_polygon(1234)
	var c: Dictionary = WorldView.hull_polygon(987654)
	_check("hull: deterministic for a seed", a["poly"] == b["poly"] and a["tail"] == b["tail"])
	_check("hull: enough points for a silhouette",
		(a["poly"] as PackedVector2Array).size() >= 5)
	_check("hull: different seeds give different ships", a["poly"] != c["poly"])

func _test_pick_duel() -> void:
	var w := _make_world(7777)
	var a := w.add_ship(0)
	var b := w.add_ship(0)   # a's teammate
	var c := w.add_ship(1)
	var d := w.add_ship(1)
	a.pos = Vector2(0, 0)
	b.pos = Vector2(60, 0)        # closest pair overall (60u), but same team
	c.pos = Vector2(-100, 0)      # closest ENEMY: 100u from a, 160u from b
	d.pos = Vector2(2000, 2000)
	var duel := WorldView.pick_duel(w)
	_check("camera: duel picks the closest hostile pair",
		duel.size() == 2 and a.id in duel and c.id in duel, str(duel))
	a.alive = false
	b.alive = false
	d.alive = false
	duel = WorldView.pick_duel(w)
	_check("camera: lone survivor is followed solo", duel == [c.id], str(duel))

func _test_pov_zoom_multiplier() -> void:
	var normal := CameraController.apply_pov_zoom(1.0, 1.0)
	var zoomed := CameraController.apply_pov_zoom(1.0, 1.35)
	var clamped := CameraController.apply_pov_zoom(1.5, 10.0)
	_check("camera: POV zoom multiplier increases main camera zoom", zoomed > normal,
		"normal=%.3f zoomed=%.3f" % [normal, zoomed])
	_check("camera: POV zoom multiplier is clamped", is_equal_approx(clamped, 1.85),
		"clamped=%.3f" % clamped)

func _test_enemy_ship_visual_scale() -> void:
	var rookie := WorldView.enemy_ship_visual_scale(BotController.Difficulty.ROOKIE)
	var veteran := WorldView.enemy_ship_visual_scale(BotController.Difficulty.VETERAN)
	var ace := WorldView.enemy_ship_visual_scale(BotController.Difficulty.ACE)
	var insane := WorldView.enemy_ship_visual_scale(BotController.Difficulty.INSANE)
	_check("enemy scale: easier bots draw larger than hard bots",
		rookie > veteran and veteran > ace and ace > insane,
		"%.2f %.2f %.2f %.2f" % [rookie, veteran, ace, insane])
	var s := GameSession.new()
	s.start_skirmish(4, GameSession.Mode.TEAM, BotController.Difficulty.ROOKIE)
	var view := WorldView.new()
	view.session = s
	var teammate := s.world.ships[2]  # same team as human ship 0
	var enemy := s.world.ships[1]
	_check("enemy scale: teammate remains baseline",
		is_equal_approx(view._ship_difficulty_visual_scale(teammate), 1.0),
		"scale=%.2f" % view._ship_difficulty_visual_scale(teammate))
	_check("enemy scale: opposing bot uses difficulty scale",
		view._ship_difficulty_visual_scale(enemy) > 1.0,
		"scale=%.2f" % view._ship_difficulty_visual_scale(enemy))
	view.free()

func _test_radar_zoom() -> void:
	# The minimap auto-zoom span must scale with the (user-configurable) map
	# size so it behaves identically on every map: most zoomed-in at the star
	# (arena/8), the whole arena at any edge, monotonic between.
	for arena: float in [4000.0, 40000.0, 80000.0, 160000.0]:
		var half := arena * 0.5
		var at_star := Hud.radar_target_span(Vector2.ZERO, arena)
		_check("radar: at the star shows arena/8 (map %d)" % int(arena),
			is_equal_approx(at_star, arena / 8.0), "span=%.1f" % at_star)
		var edge_x := Hud.radar_target_span(Vector2(half, 0.0), arena)
		var edge_y := Hud.radar_target_span(Vector2(0.0, half), arena)
		_check("radar: any edge shows the whole map (map %d)" % int(arena),
			is_equal_approx(edge_x, arena) and is_equal_approx(edge_y, arena),
			"x=%.1f y=%.1f" % [edge_x, edge_y])
		var mid := Hud.radar_target_span(Vector2(half * 0.5, 0.0), arena)
		_check("radar: span grows monotonically star->edge (map %d)" % int(arena),
			at_star < mid and mid < edge_x, "%.1f < %.1f < %.1f" % [at_star, mid, edge_x])
		# Chebyshev distance: a corner well past the edge still clamps to whole-map.
		_check("radar: span clamps to the whole map past the edge (map %d)" % int(arena),
			is_equal_approx(Hud.radar_target_span(Vector2(arena, arena), arena), arena))

func _test_match_stats() -> void:
	var s := GameSession.new()
	s.score_limit = 1
	s.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	s.human_ship().score = 1
	s.update(1.0 / 60.0)
	var entry := MatchStats.entry_from_session(s, "2026-06-11 19:55")
	_check("stats: finished match snapshots correctly",
		entry["mode"] == "FFA" and bool(entry["won"])
		and (entry["players"] as Array).size() == 2
		and String(entry["winner"]).ends_with("(you)"))

	var path := "user://test_stats.jsonl"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	MatchStats.append_entry(entry, path)
	MatchStats.append_entry(entry, path)
	var recent := MatchStats.load_recent(10, path)
	var career := MatchStats.career(path)
	_check("stats: append + load round-trips",
		recent.size() == 2 and String(recent[0]["mode"]) == "FFA")
	_check("stats: career aggregates",
		career["matches"] == 2 and career["wins"] == 2)
	DirAccess.remove_absolute(path)

func _test_corrupt_replay_rejected() -> void:
	var bogus := var_to_bytes({"h": {"v": 1, "ros": []}, "f": [1, 2, 3], "end": 100})
	_check("replay: corrupt frame shapes are refused at load",
		Replay.from_bytes(bogus) == null)

func _test_replay() -> void:
	# Record a real match (ACE bots + scripted human), then play the tape into
	# a fresh world and demand a bit-exact final state.
	var s := GameSession.new()
	s.score_limit = 0
	s.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.ACE)
	s.recorder = Replay.begin(s)
	for i in range(900):  # 15 simulated seconds
		var human := s.human_ship()
		if human != null and human.alive:
			human.in_turn = 1.0 if (i / 40) % 2 == 0 else -1.0
			human.in_thrust = i % 3 == 0
			human.in_fire = i % 23 == 0
			human.in_mine = i == 400
		s.update(1.0 / 60.0)
	var rec := s.recorder
	s.recorder = null

	var loaded := Replay.from_bytes(rec.to_bytes())
	_check("replay: round-trips through bytes",
		loaded != null and loaded.frames.size() == rec.frames.size()
		and loaded.final_tick == rec.final_tick)
	_check("replay: change-encoding stays compact",
		rec.to_bytes().size() < 200_000, "%d bytes" % rec.to_bytes().size())

	var rp := ReplayPlayer.new()
	_check("replay: loads and rebuilds the arena", rp.load_replay(loaded))
	var guard := 0
	while not rp.finished and guard < 2000:
		rp.update(1.0 / 60.0)
		guard += 1
	_check("replay: playback reaches the end", rp.finished, "guard=%d" % guard)

	var exact := rp.session.world.ships.size() == s.world.ships.size()
	if exact:
		for i in range(s.world.ships.size()):
			var a := s.world.ships[i]
			var b := rp.session.world.ships[i]
			if a.pos != b.pos or a.score != b.score or a.kills != b.kills or a.alive != b.alive:
				exact = false
				break
	_check("replay: playback is bit-exact (positions, scores, kills, alive)", exact)

	# Scrubbing: rewind to an exact tick, then back to the end — still exact.
	rp.seek(60)
	_check("replay: backward seek lands on the exact tick",
		rp.session.world.tick == 60 and not rp.finished)
	rp.seek(loaded.final_tick)
	rp.update(1.0 / 60.0)  # the final step
	var exact2 := true
	for i in range(s.world.ships.size()):
		var a2 := s.world.ships[i]
		var b2 := rp.session.world.ships[i]
		if a2.pos != b2.pos or a2.score != b2.score:
			exact2 = false
			break
	_check("replay: state after scrubbing is still bit-exact", exact2)

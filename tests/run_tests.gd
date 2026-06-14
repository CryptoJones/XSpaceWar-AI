extends SceneTree
## Headless test runner for the deterministic simulation.
##
## Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits with code 0 on success, 1 on any failure (CI-friendly).

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — sim tests ===")
	_test_determinism()
	_test_arena_determinism()
	_test_gravity_pull()
	_test_orbit_stability()
	_test_fire_and_kill()
	_test_hyperspace_relocates()
	_test_ai_combat()
	_test_match_flow()
	_test_hazard_slider()
	_test_ship_colors()
	_test_star_scale()
	_test_gravity_escapable()
	_test_min_map_giant_star_playable()
	_test_giant_star_spawns()
	_test_map_size()
	_test_lives()
	_test_swept_and_events()
	_test_review_gameplay_fixes()
	_test_eternal_torpedoes()
	_test_solo_practice()
	_test_lethal_edges()
	_test_team_spawns()
	_test_sim_performance()
	_test_hull_generation()
	_test_pick_duel()
	_test_bot_character()
	_test_ai_temperament()
	_test_no_backwards_fire()
	_test_timid_mining()
	_test_mines()
	_test_pickups()
	_test_match_stats()
	_test_corrupt_replay_rejected()
	_test_replay()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

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

func _drive(s: SimShip, turn: float, thrust: bool, fire: bool) -> void:
	s.in_turn = turn
	s.in_thrust = thrust
	s.in_fire = fire

# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

func _test_determinism() -> void:
	var a := _make_world(12345)
	var b := _make_world(12345)
	var sa := a.add_ship()
	var sb := b.add_ship()
	# Identical scripted input stream into both worlds.
	for i in range(600):
		var turn := 1.0 if (i / 30) % 2 == 0 else -1.0
		var thrust := (i % 5) == 0
		var fire := (i % 17) == 0
		_drive(sa, turn, thrust, fire)
		_drive(sb, turn, thrust, fire)
		a.step()
		b.step()
	var dpos := sa.pos.distance_to(sb.pos)
	_check("determinism: identical seed+inputs converge", dpos == 0.0, "pos delta=%f" % dpos)
	_check("determinism: torpedo counts match", a.torpedoes.size() == b.torpedoes.size())

func _test_arena_determinism() -> void:
	var a := SimWorld.new(SimConfig.from_seed(999))
	var b := SimWorld.new(SimConfig.from_seed(999))
	ArenaGen.populate(a)
	ArenaGen.populate(b)
	var same := a.bodies.size() == b.bodies.size()
	if same:
		for i in range(a.bodies.size()):
			if a.bodies[i].pos.distance_to(b.bodies[i].pos) > 0.0 or a.bodies[i].radius != b.bodies[i].radius:
				same = false
				break
	_check("arena: same seed -> identical bodies", same, "counts %d/%d" % [a.bodies.size(), b.bodies.size()])

func _test_gravity_pull() -> void:
	var cfg := SimConfig.from_seed(1)
	cfg.wrap_edges = false
	var w := SimWorld.new(cfg)
	var star := SimBody.new()
	star.kind = SimBody.Kind.STAR
	star.pos = Vector2.ZERO
	star.mass = 1000.0
	star.radius = 80.0
	w.add_body(star)
	var s := SimShip.new()
	s.id = w.alloc_id()
	s.radius = cfg.ship_radius
	s.pos = Vector2(800, 0)
	s.vel = Vector2.ZERO
	s.fuel = cfg.max_fuel
	s.ammo = cfg.max_ammo
	w.ships.append(s)
	var d0 := s.pos.distance_to(star.pos)
	for i in range(30):
		w.step()
	var d1 := s.pos.distance_to(star.pos)
	_check("gravity: stationary ship falls toward star", d1 < d0, "d0=%f d1=%f" % [d0, d1])
	_check("gravity: pull is leftward (toward star)", s.vel.x < 0.0, "vx=%f" % s.vel.x)

func _test_orbit_stability() -> void:
	var w := _make_world(42)
	var s := w.add_ship()
	var primary := w.primary_body()
	var r0 := s.pos.distance_to(primary.pos)
	var min_r := r0
	var max_r := r0
	for i in range(1800):  # ~30 simulated seconds, no input
		s.clear_inputs()
		w.step()
		if s.alive:
			var r := s.pos.distance_to(primary.pos)
			min_r = minf(min_r, r)
			max_r = maxf(max_r, r)
	# A near-circular orbit should neither crash into the star nor escape far.
	var bounded := s.alive and min_r > primary.radius and max_r < r0 * 2.5
	_check("orbit: ship stays in a bounded orbit for 30s", bounded,
		"r0=%.0f min=%.0f max=%.0f alive=%s" % [r0, min_r, max_r, str(s.alive)])

func _test_fire_and_kill() -> void:
	var cfg := SimConfig.from_seed(7)
	cfg.wrap_edges = false
	var w := SimWorld.new(cfg)
	# No bodies: isolate weapon mechanics from gravity.
	var attacker := SimShip.new()
	attacker.id = w.alloc_id(); attacker.radius = cfg.ship_radius
	attacker.pos = Vector2(0, 0); attacker.angle = 0.0
	attacker.fuel = cfg.max_fuel; attacker.ammo = cfg.max_ammo
	attacker.spawn_grace = 0.0
	w.ships.append(attacker)
	var target := SimShip.new()
	target.id = w.alloc_id(); target.radius = cfg.ship_radius
	target.pos = Vector2(300, 0); target.vel = Vector2.ZERO
	target.fuel = cfg.max_fuel; target.ammo = cfg.max_ammo
	target.spawn_grace = 0.0
	w.ships.append(target)

	var ammo_before := attacker.ammo
	_drive(attacker, 0.0, false, true)
	w.step()
	_check("weapon: firing creates a torpedo", w.torpedoes.size() == 1)
	_check("weapon: firing consumes ammo", attacker.ammo == ammo_before - 1)

	# Let the torpedo fly into the stationary target.
	for i in range(120):
		attacker.clear_inputs()
		target.clear_inputs()
		w.step()
		if not target.alive:
			break
	_check("weapon: torpedo kills the target", not target.alive)
	_check("weapon: killer is credited", attacker.kills == 1 and attacker.score >= 1,
		"kills=%d score=%d" % [attacker.kills, attacker.score])

func _test_hyperspace_relocates() -> void:
	var cfg := SimConfig.from_seed(3)
	cfg.hyperspace_base_risk = 0.0      # disable self-destruct for a clean relocation test
	cfg.hyperspace_risk_per_use = 0.0
	var w := SimWorld.new(cfg)
	ArenaGen.populate(w, {"asteroid_density": 0})
	var s := w.add_ship()
	var before := s.pos
	s.in_hyper = true
	w.step()
	_check("hyperspace: ship relocates", s.pos.distance_to(before) > 1.0 and s.alive)

func _test_ai_combat() -> void:
	# Two ACE bots in a free-for-all should land hits on each other and not
	# simply fly into the star and die out.
	var w := _make_world(2024)
	var a := w.add_ship()
	var b := w.add_ship()
	# Pin personality AND temperament so the assertion tests combat, not the
	# luck of the rolls (timid or far-roaming pilots can avoid each other).
	var ba := BotController.new(w, a.id, BotController.Difficulty.ACE,
		BotController.Personality.BRAWLER, 30, 95)
	var bb := BotController.new(w, b.id, BotController.Difficulty.ACE,
		BotController.Personality.BRAWLER, 30, 95)
	var dt := w.config.fixed_dt
	var torpedoes_fired := 0
	for i in range(5400):  # ~90 simulated seconds
		ba.update(dt)
		bb.update(dt)
		torpedoes_fired = maxi(torpedoes_fired, w.torpedoes.size())
		w.step()
	var total_kills := a.kills + b.kills
	_check("ai: bots fire torpedoes", torpedoes_fired > 0)
	_check("ai: bots score kills against each other", total_kills > 0,
		"kills a=%d b=%d" % [a.kills, b.kills])
	_check("ai: bots are not wiped out permanently (respawn works)",
		a.alive or b.alive or a.respawn_timer > 0.0 or b.respawn_timer > 0.0)

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

func _test_hazard_slider() -> void:
	var w0 := SimWorld.new(SimConfig.from_seed(31))
	ArenaGen.populate(w0, {"hazard": 0.0})
	var rocks0 := 0
	for b in w0.bodies:
		if b.kind == SimBody.Kind.ASTEROID:
			rocks0 += 1
	_check("hazard: 0 means clean space", rocks0 == 0)

	var w1 := SimWorld.new(SimConfig.from_seed(31))
	ArenaGen.populate(w1, {"hazard": 1.0})
	var rocks1 := 0
	for b in w1.bodies:
		if b.kind == SimBody.Kind.ASTEROID:
			rocks1 += 1
	_check("hazard: 100 packs the zone (~every 3rd cell)", rocks1 > 70,
		"rocks=%d" % rocks1)

	var w2 := SimWorld.new(SimConfig.from_seed(31))
	ArenaGen.populate(w2, {"hazard": 1.0})
	var rocks2 := 0
	for b in w2.bodies:
		if b.kind == SimBody.Kind.ASTEROID:
			rocks2 += 1
	_check("hazard: deterministic per seed", rocks2 == rocks1)

func _test_ship_colors() -> void:
	var s := GameSession.new()
	s.start_skirmish(16, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var seen := {}
	for ship in s.world.ships:
		seen[WorldView.ship_color(ship)] = true
	_check("colors: 16 FFA ships get 16 distinct colors", seen.size() == 16,
		"distinct=%d" % seen.size())

func _test_star_scale() -> void:
	# Planets pull too — generate star-only worlds so the ratio is pure.
	var w1 := SimWorld.new(SimConfig.from_seed(61))
	ArenaGen.populate(w1, {"hazard": 0.0, "planets": 0, "satellites": 0, "star_scale": 1.0})
	var w4 := SimWorld.new(SimConfig.from_seed(61))
	ArenaGen.populate(w4, {"hazard": 0.0, "planets": 0, "satellites": 0, "star_scale": 4.0})
	var p1 := w1.primary_body()
	var p4 := w4.primary_body()
	_check("star: scale multiplies mass (gravity) and size",
		is_equal_approx(p4.mass, p1.mass * 4.0) and p4.radius > p1.radius,
		"m %0.f/%0.f r %.0f/%.0f" % [p1.mass, p4.mass, p1.radius, p4.radius])
	var probe := Vector2(1500, 0)
	var g1 := w1.gravity_accel(probe).length()
	var g4 := w4.gravity_accel(probe).length()
	_check("star: bigger star pulls 4x harder (pure inverse-square)",
		is_equal_approx(g4, g1 * 4.0), "g %.2f vs %.2f" % [g1, g4])

func _test_eternal_torpedoes() -> void:
	var w := SimWorld.new(SimConfig.from_seed(99))
	var s := w.add_ship()
	s.pos = Vector2(8000, 8000)  # far from anything it could hit
	s.angle = 0.0
	s.in_fire = true
	w.step(1.0 / 60.0)
	_check("torps: one in flight", w.torpedoes.size() == 1)
	for _i in range(900):  # 15 sim-seconds, triple the old 5s fuse
		w.step(1.0 / 60.0)
	_check("torps: fly forever until they hit something (no fuse)",
		w.torpedoes.size() == 1, "left=%d" % w.torpedoes.size())

func _test_swept_and_events() -> void:
	# Swept collision: a slingshot-speed torpedo cannot tunnel a ship.
	var cfg := SimConfig.from_seed(11)
	cfg.wrap_edges = false
	var w := SimWorld.new(cfg)
	var victim := w.add_ship()
	var shooter := w.add_ship()
	victim.pos = Vector2(8000, 0)
	victim.vel = Vector2.ZERO
	victim.spawn_grace = 0.0
	shooter.pos = Vector2(12000, 4000)  # parked far away, irrelevant
	var t := SimTorpedo.new()
	t.id = 9001
	t.owner_id = shooter.id
	t.team = -1
	t.radius = cfg.torpedo_radius
	t.pos = Vector2(8000.0 - 120.0, 0.0)  # 120u out, moving 8000 u/s
	t.vel = Vector2(8000, 0)              # crosses 133u this tick: pure tunnel before
	t.age = 1.0
	w.torpedoes.append(t)
	w.step(1.0 / 60.0)
	_check("swept: slingshot torpedo connects instead of tunneling",
		not victim.alive)

	# Event accumulation: nothing is lost across multi-step batches.
	var w2 := SimWorld.new(SimConfig.from_seed(12))
	var s2 := w2.add_ship()
	s2.pos = Vector2(5000, 0)
	s2.in_fire = true
	w2.step(1.0 / 60.0)   # fire event at tick 0
	s2.in_fire = false
	w2.step(1.0 / 60.0)   # second step would previously WIPE it
	var fire_evs := 0
	for ev in w2.events:
		if String(ev.get("type", "")) == "fire":
			fire_evs += 1
	_check("events: survive multi-step batches with tick stamps",
		fire_evs == 1 and int(w2.events[0].get("tk", -1)) >= 0,
		"fire_evs=%d size=%d" % [fire_evs, w2.events.size()])

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

func _test_gravity_escapable() -> void:
	# The well must never out-pull thrust — even at the steep core of a small
	# map, a pilot burning straight out makes headway (Aaron\'s rule).
	# Pure Newtonian, star mass sized to the arena: across the whole slider
	# (5..100) x map extremes, a still pilot orbits a STABLE Keplerian ellipse
	# and never decays into the star; and the DEFAULT-size star (scale 1.0,
	# slider 25) is traversable — gravity at the spawn ring is under thrust on
	# every map. (Giant-star extremes are deliberately hard: player's choice.)
	var still_survives_all := true
	var default_traversable := true
	for star_slider in [5, 25, 50, 100]:
		for map_sz in [2601.0, 8000.0, 40000.0]:
			var cfg := SimConfig.from_seed(909 + star_slider)
			cfg.arena_size = clampf(map_sz, 2601.0, 40000.0)
			cfg.spawn_orbit_radius = clampf(cfg.arena_size * 0.035, 550.0, 1400.0)
			var base_mass: float = (cfg.thrust_accel * 0.35) \
				* cfg.spawn_orbit_radius * cfg.spawn_orbit_radius / cfg.gravity_constant
			var ww := SimWorld.new(cfg)
			# Star ONLY — isolate gravity from satellites/asteroids.
			ArenaGen.populate(ww, {"star_count": 1, "star_mass": base_mass,
				"star_scale": float(star_slider) / 25.0, "planets": 0,
				"satellites": 0, "hazard": 0.0})
			if star_slider == 25:
				var gspawn := ww.gravity_accel(ww.primary_body().pos
					+ Vector2(ww.config.spawn_orbit_radius, 0)).length()
				if gspawn > ww.config.thrust_accel:
					default_traversable = false
			var pilot := ww.add_ship()
			pilot.spawn_grace = 0.0
			for _i in range(1200):
				pilot.in_thrust = false; pilot.in_turn = 0.0; pilot.in_fire = false
				ww.step(1.0 / 60.0)
				if not pilot.alive:
					still_survives_all = false
					break
	_check("gravity: still pilot orbits a stable ellipse at every star size",
		still_survives_all)
	_check("gravity: the default star is traversable (spawn gravity < thrust)",
		default_traversable)

func _test_min_map_giant_star_playable() -> void:
	# Below 2601u a maxed star swallows the arena, so 2601 is the floor.
	# At the floor with a full 4x star, the arena must still have an
	# escapable shell (gravity < thrust somewhere inside it).
	var s := GameSession.new()
	s.map_size = 1000.0  # below the floor — must clamp up to 2601
	s.star_scale = 4.0
	s.hazard = 0.0
	s.planet_count = 0
	s.score_limit = 0
	s.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var w := s.world
	_check("corner: map size clamps to the 2601 floor",
		w.config.arena_size >= 2601.0 and w.config.arena_size <= 2602.0,
		"arena=%.0f" % w.config.arena_size)
	var star := w.primary_body()
	var half := w.config.arena_size * 0.5
	var escapable_shell := false
	var rr := w.config.spawn_orbit_radius
	while rr < half:
		if w.gravity_accel(star.pos + Vector2(rr, 0)).length() < w.config.thrust_accel:
			escapable_shell = true
			break
		rr += 50.0
	_check("corner: floor map + full 4x star still has an escapable shell",
		escapable_shell)

func _test_giant_star_spawns() -> void:
	# Max star size: nobody spawns inside (or hugging) the well.
	var s := GameSession.new()
	s.star_scale = 4.0
	s.score_limit = 0
	s.start_skirmish(16, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var star := s.world.primary_body()
	var worst := INF
	for ship in s.world.ships:
		worst = minf(worst, ship.pos.distance_to(star.pos))
	_check("spawn: giant star pushes the spawn ring out",
		worst >= star.radius * 2.0,
		"star r=%.0f closest spawn=%.0f" % [star.radius, worst])

func _test_map_size() -> void:
	var s := GameSession.new()
	s.map_size = 2601.0   # the minimum allowed map size
	s.score_limit = 0
	s.start_skirmish(8, GameSession.Mode.FFA, BotController.Difficulty.VETERAN)
	var half := s.world.config.arena_size * 0.5
	_check("map: smallest arena applies with scaled spawn ring",
		is_equal_approx(s.world.config.arena_size, 2601.0)
		and s.world.config.spawn_orbit_radius <= half * 0.85,
		"orbit=%.0f half=%.0f" % [s.world.config.spawn_orbit_radius, half])
	var inside := true
	for ship in s.world.ships:
		if absf(ship.pos.x) > half or absf(ship.pos.y) > half:
			inside = false
	_check("map: all ships spawn inside a tiny map", inside)
	for _i in range(300):
		s.update(1.0 / 60.0)
	_check("map: tiny arena sim runs clean", s.world.tick >= 300)

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

func _test_sim_performance() -> void:
	# Worst case the menu allows: 16 ACE bots, hazard 1.0 (dense rocks),
	# everything firing and mining. 60 sim seconds must run far faster than
	# real time headless — guard against sim-cost regressions.
	var s := GameSession.new()
	s.score_limit = 0
	s.hazard = 1.0
	s.movie_mode = true  # all bots
	s.num_ships = 16
	s.difficulty = BotController.Difficulty.ACE
	s.mode = GameSession.Mode.FFA
	s._build(424242)
	var t0 := Time.get_ticks_usec()
	for _i in range(3600):
		s.update(1.0 / 60.0)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var per_step := ms / 3600.0
	_check("perf: worst-case step budget (<4ms/step, 60Hz budget is 16.6)",
		per_step < 4.0, "%.3f ms/step (%.0f ms total)" % [per_step, ms])

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

func _test_bot_character() -> void:
	_check("callsign: deterministic and plausible",
		BotController.callsign(42) == BotController.callsign(42)
		and BotController.callsign(42).length() >= 5
		and BotController.callsign(42) != BotController.callsign(43))
	_check("personality: deterministic from seed",
		BotController.personality_for(42) == BotController.personality_for(42))
	var seen := {}
	for i in range(60):
		seen[BotController.personality_for(i * 7919)] = true
	_check("personality: all four kinds occur",
		seen.size() == BotController.Personality.size(), "saw %d kinds" % seen.size())

	# Bots get callsigns on the scoreboard.
	var s := GameSession.new()
	s.start_skirmish(4, GameSession.Mode.FFA, BotController.Difficulty.VETERAN)
	var named := 0
	for sid in s.bots:
		if String(s.ship_names.get(sid, "")).length() >= 5:
			named += 1
	_check("callsign: every bot is named in the session", named == s.bots.size(),
		"%d/%d" % [named, s.bots.size()])

	# Predictive avoidance: a ship coasting straight at a planet sees it.
	var cfg := SimConfig.from_seed(5)
	var w := SimWorld.new(cfg)
	var planet := SimBody.new()
	planet.kind = SimBody.Kind.PLANET
	planet.pos = Vector2(400, 0)
	planet.radius = 50.0
	planet.mass = 0.0
	planet.gravity = false
	planet.lethal = true
	w.add_body(planet)
	var ship := w.add_ship()
	ship.pos = Vector2.ZERO
	ship.vel = Vector2(420, 0)
	var bot := BotController.new(w, ship.id, BotController.Difficulty.ACE)
	var hz := bot._imminent_hazard(ship)
	_check("avoidance: collision course is detected", hz == planet)
	ship.vel = Vector2(-420, 0)
	_check("avoidance: diverging course is clear", bot._imminent_hazard(ship) == null)

func _test_ai_temperament() -> void:
	# Rolls are deterministic per match seed + ship.
	var w := _make_world(909)
	var a := w.add_ship()
	var b1 := BotController.new(w, a.id, BotController.Difficulty.ACE)
	var b2 := BotController.new(w, a.id, BotController.Difficulty.ACE)
	_check("ai: temperament rolls are deterministic",
		b1.roam == b2.roam and b1.aggression == b2.aggression,
		"roam %d/%d aggr %d/%d" % [b1.roam, b2.roam, b1.aggression, b2.aggression])

	# Roam: a lone far-roamer (100) prowls way out; a star-hugger (1) stays
	# near the well. 30 simulated seconds each, no enemies.
	var dt := 1.0 / 60.0
	var w1 := SimWorld.new(SimConfig.from_seed(5151))
	ArenaGen.populate(w1, {"hazard": 0.0})
	var s1 := w1.add_ship()
	var far := BotController.new(w1, s1.id, BotController.Difficulty.ACE,
		BotController.Personality.OPPORTUNIST, 100, 80)
	for _i in range(1800):
		far.update(dt)
		w1.step()
	var d_far := s1.pos.distance_to(w1.primary_body().pos)

	var w2 := SimWorld.new(SimConfig.from_seed(5151))
	ArenaGen.populate(w2, {"hazard": 0.0})
	var s2 := w2.add_ship()
	var hugger := BotController.new(w2, s2.id, BotController.Difficulty.ACE,
		BotController.Personality.OPPORTUNIST, 1, 80)
	for _i in range(1800):
		hugger.update(dt)
		w2.step()
	var d_close := s2.pos.distance_to(w2.primary_body().pos)
	_check("ai: roam spreads pilots (100 roams far, 1 stays closer)",
		d_far > w1.config.spawn_orbit_radius * 2.0 and d_close < d_far * 0.8,
		"far=%.0f close=%.0f" % [d_far, d_close])

	# Aggression 1 = flee: with an enemy 600 away, the desired heading points
	# AWAY from it.
	var cfg := SimConfig.from_seed(7)
	cfg.wrap_edges = false
	var w3 := SimWorld.new(cfg)
	var sa := w3.add_ship()
	var sb := w3.add_ship()
	# Keep well away from the origin: with no star, the escape-the-star check
	# treats (0,0) as the well and would override the flee heading.
	sa.pos = Vector2(5000, 0)
	sb.pos = Vector2(5600, 0)
	var timid := BotController.new(w3, sa.id, BotController.Difficulty.ACE,
		BotController.Personality.BRAWLER, 50, 1)
	timid._acquire_target(sa)
	timid._decide(sa)
	var away := (sa.pos - sb.pos).normalized()
	var want := Vector2(cos(timid._want_angle), sin(timid._want_angle))
	_check("ai: aggression 1 flees from nearby ships", want.dot(away) > 0.4,
		"dot=%.2f" % want.dot(away))

func _test_no_backwards_fire() -> void:
	# A fleeing pilot whose nose points away from the enemy must not fire.
	var cfg := SimConfig.from_seed(404)
	cfg.wrap_edges = false
	var w := SimWorld.new(cfg)
	var runner := w.add_ship()
	var chaser := w.add_ship()
	runner.pos = Vector2(6000, 0)
	runner.angle = 0.0          # nose +x, fleeing direction
	runner.spawn_grace = 0.0
	chaser.spawn_grace = 0.0
	var bot := BotController.new(w, runner.id, BotController.Difficulty.ACE,
		BotController.Personality.BRAWLER, 50, 1)
	var dt := 1.0 / 60.0
	for _i in range(120):
		chaser.pos = runner.pos - Vector2(500, 0)  # always directly behind
		chaser.vel = runner.vel
		bot.update(dt)
		w.step(dt)
	_check("ai: no firing away from the target while fleeing",
		w.torpedoes.is_empty(), "torps=%d" % w.torpedoes.size())

func _test_timid_mining() -> void:
	# A timid pilot (aggression 1) of a personality OUTSIDE the old
	# brawler/opportunist gate mines its escape route when chased.
	var w := SimWorld.new(SimConfig.from_seed(31337))
	var runner := w.add_ship()
	var chaser := w.add_ship()
	runner.pos = Vector2(4000, 0)
	runner.mines = 3
	runner.spawn_grace = 0.0
	chaser.spawn_grace = 0.0
	var bot := BotController.new(w, runner.id, BotController.Difficulty.ACE,
		BotController.Personality.SNIPER, 50, 1)
	var dt := 1.0 / 60.0
	for _i in range(600):
		chaser.pos = runner.pos - runner.facing() * 200.0  # glued to the tail
		chaser.vel = runner.vel
		bot.update(dt)
		w.step(dt)
		if not w.mines.is_empty():
			break
	_check("ai: timid pilots mine their escape route", not w.mines.is_empty(),
		"mines=%d after chase" % w.mines.size())

func _test_mines() -> void:
	var cfg := SimConfig.from_seed(11)
	cfg.wrap_edges = false
	var w := SimWorld.new(cfg)  # empty space: isolate mine mechanics

	var owner := SimShip.new()
	owner.id = w.alloc_id()
	owner.radius = cfg.ship_radius
	owner.fuel = cfg.max_fuel
	owner.ammo = cfg.max_ammo
	owner.mines = cfg.max_mines
	owner.spawn_grace = 0.0
	w.ships.append(owner)

	owner.in_mine = true
	w.step()
	_check("mine: drop creates a mine and consumes supply",
		w.mines.size() == 1 and owner.mines == cfg.max_mines - 1)
	owner.pos = Vector2(600, 0)  # owner clears the area

	var victim := SimShip.new()
	victim.id = w.alloc_id()
	victim.radius = cfg.ship_radius
	victim.fuel = cfg.max_fuel
	victim.spawn_grace = 0.0
	victim.pos = w.mines[0].pos + Vector2(30, 0)  # inside the trigger radius
	w.ships.append(victim)
	w.step()
	_check("mine: unarmed mine does not trigger",
		victim.alive and w.mines.size() == 1)

	for _i in range(int(cfg.mine_arm_time / cfg.fixed_dt) + 3):
		w.step()
	_check("mine: armed proximity kill credits the owner",
		not victim.alive and owner.kills == 1 and w.mines.is_empty(),
		"alive=%s kills=%d mines=%d" % [victim.alive, owner.kills, w.mines.size()])

	# Torpedo counterplay: shooting a mine detonates it.
	owner.mines = 1
	owner.mine_cooldown = 0.0  # still ticking from the first drop
	owner.pos = Vector2.ZERO
	owner.angle = 0.0
	owner.in_mine = true
	w.step()
	_check("mine: second drop works once the cooldown clears", w.mines.size() == 1)
	owner.pos = Vector2(800, 0)
	var torp := SimTorpedo.new()
	torp.id = w.alloc_id()
	torp.owner_id = owner.id
	torp.radius = cfg.torpedo_radius
	torp.pos = w.mines[0].pos + Vector2(120, 0)
	torp.vel = Vector2(-400, 0)
	torp.life = 5.0
	torp.age = 1.0
	w.torpedoes.append(torp)
	for _i in range(40):
		w.step()
		if w.mines.is_empty():
			break
	_check("mine: torpedo detonates it (counterplay)",
		w.mines.is_empty() and w.torpedoes.is_empty())

func _test_pickups() -> void:
	var cfg := SimConfig.from_seed(21)
	cfg.wrap_edges = false
	cfg.pickup_chance = 1.0  # force the drop for determinism
	var w := SimWorld.new(cfg)
	var rock := SimBody.new()
	rock.kind = SimBody.Kind.ASTEROID
	rock.pos = Vector2(300, 0)
	rock.mass = 0.0
	rock.gravity = false
	rock.lethal = true
	rock.radius = 12.0
	w.add_body(rock)
	var ship := SimShip.new()
	ship.id = w.alloc_id()
	ship.radius = cfg.ship_radius
	ship.fuel = cfg.max_fuel
	ship.ammo = cfg.max_ammo
	ship.spawn_grace = 0.0
	w.ships.append(ship)

	ship.in_fire = true
	w.step()
	for _i in range(90):
		w.step()
		if w.bodies.is_empty():
			break
	_check("pickup: torpedo shatters the asteroid",
		w.bodies.is_empty() and w.removed_body_ids.has(rock.id))
	_check("pickup: shattered rock dropped cargo (chance forced)",
		w.pickups.size() == 1, "pickups=%d" % w.pickups.size())
	if w.pickups.is_empty():
		return

	var p := w.pickups[0]
	ship.fuel = 10.0
	ship.ammo = 0
	ship.mines = 0
	ship.pos = p.pos
	ship.vel = p.vel
	w.step()
	var granted := false
	match p.kind:
		SimPickup.Kind.FUEL:
			granted = ship.fuel > 10.0
		SimPickup.Kind.AMMO:
			granted = ship.ammo > 0
		SimPickup.Kind.MINES:
			granted = ship.mines > 0
	_check("pickup: touching it grants the cargo and consumes it",
		granted and w.pickups.is_empty())

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

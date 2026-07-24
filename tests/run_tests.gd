extends SceneTree
## Headless test runner for the core deterministic simulation: determinism,
## arena generation, gravity/orbits, star+map scaling, event accumulation, and
## the sim performance budget. The rest of the old monolith now lives in
## sibling suites for failure locality:
##   combat_tests.gd    weapons / hyperspace / mines / pickups
##   bot_tests.gd       BotController AI behaviour
##   gameplay_tests.gd  match flow / lives / teams / stats / replay
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
	_test_gravity_escapable()
	_test_min_map_giant_star_playable()
	_test_giant_star_spawns()
	_test_map_size()
	_test_star_scale()
	_test_hazard_slider()
	_test_swept_and_events()
	_test_eternal_torpedoes()
	_test_sim_performance()
	_test_flight_pace_and_torus()
	_test_sim_config_roundtrip()
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
	# Pure GRAVITY test: a clean arena (just the star, no satellites/rocks to
	# collide with) so we measure whether the well keeps a coasting ship in a
	# bounded orbit — not whether it happens to dodge a hazard.
	var w := SimWorld.new(SimConfig.from_seed(42))
	ArenaGen.populate(w, {"planets": 0, "satellites": 0, "asteroid_belts": 0, "asteroid_density": 0})
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
		for map_sz in [4000.0, 8000.0, 40000.0, 80000.0, 160000.0]:
			var cfg := SimConfig.from_seed(909 + star_slider)
			cfg.arena_size = clampf(map_sz, 4000.0, 160000.0)
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
	# Below 4000u a maxed star swallows the arena, so 4000 is the floor.
	# At the floor with a full 4x star, the arena must still have an
	# escapable shell (gravity < thrust somewhere inside it).
	var s := GameSession.new()
	s.map_size = 1000.0  # below the floor — must clamp up to 4000
	s.star_scale = 4.0
	s.hazard = 0.0
	s.planet_count = 0
	s.score_limit = 0
	s.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.ROOKIE)
	var w := s.world
	_check("corner: map size clamps to the 4000 floor",
		w.config.arena_size >= 4000.0 and w.config.arena_size <= 4001.0,
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
	s.map_size = 4000.0   # the minimum allowed map size
	s.score_limit = 0
	s.start_skirmish(8, GameSession.Mode.FFA, BotController.Difficulty.VETERAN)
	var half := s.world.config.arena_size * 0.5
	_check("map: smallest arena applies with scaled spawn ring",
		is_equal_approx(s.world.config.arena_size, 4000.0)
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

func _test_flight_pace_and_torus() -> void:
	var slow := SimConfig.from_seed(1)
	var standard := SimConfig.from_seed(1)
	var fast := SimConfig.from_seed(1)
	slow.set_flight_pace(60.0)
	standard.set_flight_pace(75.0)
	fast.set_flight_pace(100.0)
	_check("pace: acceleration, projectile speed, and envelope are monotonic",
		slow.thrust_accel < standard.thrust_accel
		and standard.thrust_accel < fast.thrust_accel
		and slow.torpedo_speed < standard.torpedo_speed
		and standard.torpedo_speed < fast.torpedo_speed
		and slow.max_ship_speed < standard.max_ship_speed
		and standard.max_ship_speed < fast.max_ship_speed)
	var distances := [_pace_distance(slow), _pace_distance(standard), _pace_distance(fast)]
	_check("pace: sustained thrust changes movement monotonically",
		distances[0] < distances[1] and distances[1] < distances[2])
	var capped := SimWorld.new(standard)
	var pilot := capped.add_ship()
	pilot.pos = Vector2.ZERO
	pilot.vel = Vector2.ZERO
	pilot.angle = 0.0
	pilot.spawn_grace = 0.0
	for _i in range(600):
		pilot.in_thrust = true
		capped.step()
	_check("pace: ship velocity respects the synchronized envelope",
		pilot.vel.length() <= standard.max_ship_speed + 0.001,
		"speed=%.2f max=%.2f" % [pilot.vel.length(), standard.max_ship_speed])
	var seam := TorusMath.shortest_delta(Vector2(499, 0), Vector2(-499, 0), 1000.0)
	_check("torus: shortest delta crosses the seam", is_equal_approx(seam.x, 2.0))
	_check("torus: swept seam crossing hits a nearby circle",
		TorusMath.swept_hits_circle(Vector2(499, 0), Vector2(-499, 0),
			Vector2(-500, 0), 5.0, 1000.0))

func _pace_distance(cfg: SimConfig) -> float:
	cfg.gravity_constant = 0.0
	cfg.wrap_edges = false
	var w := SimWorld.new(cfg)
	var s := w.add_ship()
	s.pos = Vector2.ZERO
	s.vel = Vector2.ZERO
	s.angle = 0.0
	s.spawn_grace = 0.0
	for _i in range(300):
		s.in_thrust = true
		w.step()
	return s.pos.x

func _test_sim_config_roundtrip() -> void:
	# Guards the network/replay wire contract for SimConfig (see closed issue
	# #15): to_wire() -> from_wire() -> to_wire() must be bit-identical, and
	# every host-selectable option must survive the trip. Cheap insurance — if
	# a wire-excluded field ever becomes host-tunable and the to_wire/from_wire
	# pair isn't kept in sync, this fails loudly in CI.
	var ok := true
	var detail := ""
	for sd in [0, 1, 42, 1337, 999983]:
		var cfg := SimConfig.from_seed(sd)
		# Push host-selectable options off their defaults so the test exercises
		# real serialization, not just default values.
		cfg.respawn_time = 3.5
		cfg.lethal_edges = (sd % 2 == 0)
		cfg.wrap_edges = not cfg.lethal_edges
		cfg.arena_size = 2048.0 + float(sd % 7) * 100.0
		cfg.spawn_orbit_radius = 480.0 + float(sd % 5) * 25.0
		cfg.lives = 5 + (sd % 4)
		cfg.torpedo_life = float(sd % 6) * 30.0  # 0 (unlimited) .. 150s
		cfg.mine_life = 25.0 + float(sd % 4) * 60.0
		cfg.mine_arm_time = 3.0 + float(sd % 5) * 5.0  # 3 .. 23s

		var w1 := cfg.to_wire()
		var rebuilt := SimConfig.from_wire(w1)
		var w2 := rebuilt.to_wire()

		# 1. Round-trip must be bit-identical, key by key.
		if w1.size() != w2.size():
			ok = false
			detail = "key count differs @seed %d" % sd
			break
		for k in w1:
			if not w2.has(k) or w1[k] != w2[k]:
				ok = false
				detail = "wire mismatch @seed %d key '%s'" % [sd, str(k)]
				break
		if not ok:
			break

		# 2. Every host-selectable option must survive intact.
		if rebuilt.seed != cfg.seed \
				or not is_equal_approx(rebuilt.respawn_time, cfg.respawn_time) \
				or rebuilt.lethal_edges != cfg.lethal_edges \
				or not is_equal_approx(rebuilt.arena_size, cfg.arena_size) \
				or not is_equal_approx(rebuilt.spawn_orbit_radius, cfg.spawn_orbit_radius) \
				or rebuilt.lives != cfg.lives \
				or not is_equal_approx(rebuilt.torpedo_life, cfg.torpedo_life) \
				or not is_equal_approx(rebuilt.mine_life, cfg.mine_life) \
				or not is_equal_approx(rebuilt.mine_arm_time, cfg.mine_arm_time):
			ok = false
			detail = "option lost @seed %d" % sd
			break

		# 3. from_wire() must keep wrap_edges as the inverse of lethal_edges.
		if rebuilt.wrap_edges == rebuilt.lethal_edges:
			ok = false
			detail = "wrap_edges not inverse of lethal_edges @seed %d" % sd
			break
	_check("sim_config: wire round-trip is bit-exact and lossless", ok, detail)

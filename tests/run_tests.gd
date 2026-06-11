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
	_test_hull_generation()
	_test_pick_duel()
	_test_bot_character()
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
	var ba := BotController.new(w, a.id, BotController.Difficulty.ACE)
	var bb := BotController.new(w, b.id, BotController.Difficulty.ACE)
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

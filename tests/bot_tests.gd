extends SceneTree
## Headless tests for the BotController AI: combat effectiveness, deterministic
## character/temperament rolls, and the steering behaviours (flee-no-fire,
## defensive mining, roam spread). Split out of run_tests.gd. Distinct from
## aim_tests.gd, which exercises the host-side aim-anomaly heuristics.
##
## Run with:
##   godot --headless --path . --script res://tests/bot_tests.gd
##
## Exits 0 on success, 1 on any failure (CI-friendly).

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — bot AI tests ===")
	_test_ai_combat()
	_test_bot_character()
	_test_ai_temperament()
	_test_no_backwards_fire()
	_test_timid_mining()
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

func _test_ai_combat() -> void:
	# Two ACE bots in a CLEAN arena (just a star — no planets/rocks to hide
	# behind, die to, or be funneled by) must land hits on each other: this
	# tests core combat AI, not the luck of a particular procedural layout.
	var w := SimWorld.new(SimConfig.from_seed(2024))
	ArenaGen.populate(w, {"planets": 0, "satellites": 0, "asteroid_belts": 0, "asteroid_density": 0})
	var a := w.add_ship()
	var b := w.add_ship()
	# Start them close together in open space so the brawl actually happens
	# within the window — otherwise two pilots can circle a big empty arena on
	# opposite sides and never converge (a procedural layout that funnels them
	# together is luck, not what this asserts).
	a.pos = Vector2(6000, 0); a.vel = Vector2.ZERO; a.spawn_grace = 0.0
	b.pos = Vector2(6800, 0); b.vel = Vector2.ZERO; b.spawn_grace = 0.0
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

	# Roam spreads pilots: a far-roamer (100) ends farther from the star than a
	# star-hugger (1). A single 30s flight is too chaotic to assert on (orbiting
	# planets carry gravity that perturbs the trajectory), so aggregate the
	# roamer-vs-hugger comparison over several seeds.
	var dt := 1.0 / 60.0
	var seeds := [5151, 31, 777, 2024, 909]
	var sum_far := 0.0
	var sum_close := 0.0
	var roamer_farther := 0
	for sd in seeds:
		var d_far := _roam_distance(sd, 100, dt)
		var d_close := _roam_distance(sd, 1, dt)
		sum_far += d_far
		sum_close += d_close
		if d_far > d_close:
			roamer_farther += 1
	_check("ai: roam spreads pilots (100 ends farther than 1, over %d seeds)" % seeds.size(),
		sum_far > sum_close * 1.15 and roamer_farther >= 3,
		"sum_far=%.0f sum_close=%.0f roamer_farther=%d/%d" % [sum_far, sum_close, roamer_farther, seeds.size()])

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

## Final distance from the star after a lone OPPORTUNIST bot of the given roam
## temperament prowls a fresh, enemy-free arena for 30 simulated seconds.
func _roam_distance(seed: int, roam: int, dt: float) -> float:
	var w := SimWorld.new(SimConfig.from_seed(seed))
	ArenaGen.populate(w, {"hazard": 0.0})
	var s := w.add_ship()
	var bot := BotController.new(w, s.id, BotController.Difficulty.ACE,
		BotController.Personality.OPPORTUNIST, roam, 80)
	for _i in range(1800):
		bot.update(dt)
		w.step()
	return s.pos.distance_to(w.primary_body().pos)

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

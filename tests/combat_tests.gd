extends SceneTree
## Headless tests for weapon, hyperspace, mine, and pickup mechanics — the
## per-ship combat layer of the deterministic sim. Split out of run_tests.gd so
## a combat regression surfaces on its own line instead of inside one monolith.
##
## Run with:
##   godot --headless --path . --script res://tests/combat_tests.gd
##
## Exits 0 on success, 1 on any failure (CI-friendly).

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — combat tests ===")
	_test_fire_and_kill()
	_test_hyperspace_relocates()
	_test_hyperspace_chord_edges()
	_test_mines()
	_test_pickups()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

func _drive(s: SimShip, turn: float, thrust: bool, fire: bool) -> void:
	s.in_turn = turn
	s.in_thrust = thrust
	s.in_fire = fire

# --------------------------------------------------------------------------

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
	cfg.gravity_constant = 0.0
	cfg.wrap_edges = false
	cfg.hyperspace_base_risk = 0.0      # disable self-destruct for a clean relocation test
	cfg.hyperspace_risk_per_use = 0.0
	var w := SimWorld.new(cfg)
	ArenaGen.populate(w, {"asteroid_density": 0})
	var s := w.add_ship()
	var before := s.pos
	s.in_hyper = true
	s.in_fire = true
	w.step()
	_check("hyperspace: ship relocates", s.pos.distance_to(before) > 1.0 and s.alive)

func _test_hyperspace_chord_edges() -> void:
	var cfg := SimConfig.from_seed(31)
	cfg.gravity_constant = 0.0
	cfg.wrap_edges = false
	cfg.hyperspace_base_risk = 0.0
	cfg.hyperspace_risk_per_use = 0.0
	var w := SimWorld.new(cfg)
	var s := SimShip.new()
	s.id = w.alloc_id()
	s.radius = cfg.ship_radius
	s.pos = Vector2(100, 0)
	s.fuel = cfg.max_fuel
	s.ammo = cfg.max_ammo
	s.spawn_grace = 0.0
	w.ships.append(s)
	# Either half of the chord alone is harmless.
	s.in_hyper = true
	w.step()
	var hyper_events := 0
	for ev in w.events:
		if ev.get("type", "") == "hyperspace":
			hyper_events += 1
	_check("hyperspace: Hyper alone does not jump", hyper_events == 0)
	s.clear_inputs()
	s.in_fire = true
	w.step()
	_check("hyperspace: Fire alone does not jump", _count_event(w, "hyperspace") == 0)
	# Pressing both triggers once, and holding both across cooldown does not
	# create another rising edge.
	s.clear_inputs()
	s.in_hyper = true
	s.in_fire = true
	w.step()
	var first := _count_event(w, "hyperspace")
	for _i in range(300):
		s.in_hyper = true
		s.in_fire = true
		w.step()
	_check("hyperspace: held chord cannot retrigger", _count_event(w, "hyperspace") == first)
	s.clear_inputs()
	w.step()
	s.in_hyper = true
	s.in_fire = true
	w.step()
	_check("hyperspace: release and repress creates a new edge",
		_count_event(w, "hyperspace") == first + 1)

func _count_event(w: SimWorld, kind: String) -> int:
	var n := 0
	for ev in w.events:
		if String(ev.get("type", "")) == kind:
			n += 1
	return n

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

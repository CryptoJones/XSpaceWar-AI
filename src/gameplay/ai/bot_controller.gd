class_name BotController
extends RefCounted
## Procedural AI pilot. Reads a SimWorld and writes control inputs onto one
## SimShip each step — flying the exact same simulation as human players.
##
## Behaviour: pick the nearest valid enemy, lead-aim torpedoes accounting for
## relative velocity, steer/thrust to hold a fighting orbit, flee the star when
## too close, and panic-hyperspace away from incoming fire. Difficulty tiers
## scale reaction time, aim error, firing discipline, and aggression.

enum Difficulty { ROOKIE, VETERAN, ACE, INSANE }

const PRESETS := {
	Difficulty.ROOKIE:  {"reaction": 0.45, "aim_error": 0.30, "fire_cone": 0.18, "aggression": 0.50, "panic": 70.0, "hyper": false},
	Difficulty.VETERAN: {"reaction": 0.26, "aim_error": 0.15, "fire_cone": 0.12, "aggression": 0.72, "panic": 110.0, "hyper": true},
	Difficulty.ACE:     {"reaction": 0.15, "aim_error": 0.07, "fire_cone": 0.085, "aggression": 0.88, "panic": 150.0, "hyper": true},
	Difficulty.INSANE:  {"reaction": 0.07, "aim_error": 0.02, "fire_cone": 0.05, "aggression": 1.00, "panic": 190.0, "hyper": true},
}

var world: SimWorld
var ship_id: int
var difficulty: int = Difficulty.VETERAN
var _p: Dictionary

var _rng := RandomNumberGenerator.new()
var _decide_timer: float = 0.0
var _target_id: int = -1
var _retarget_timer: float = 0.0

# Cached decisions (refreshed each reaction tick, applied every step).
var _want_angle: float = 0.0
var _want_thrust: bool = false
var _aim_noise: float = 0.0

func _init(p_world: SimWorld, p_ship_id: int, p_difficulty: int = Difficulty.VETERAN) -> void:
	world = p_world
	ship_id = p_ship_id
	difficulty = p_difficulty
	_p = PRESETS[difficulty]
	_rng.seed = world.config.seed ^ (p_ship_id * 0x9E3779B1)

static func difficulty_from_name(n: String) -> int:
	match n.to_lower():
		"rookie": return Difficulty.ROOKIE
		"veteran": return Difficulty.VETERAN
		"ace": return Difficulty.ACE
		"insane": return Difficulty.INSANE
	return Difficulty.VETERAN

## Set this bot's control inputs for the upcoming world.step().
func update(dt: float) -> void:
	var ship := world.ship_by_id(ship_id)
	if ship == null or not ship.alive:
		return

	_retarget_timer -= dt
	if _target_id < 0 or _retarget_timer <= 0.0 or not _target_alive():
		_acquire_target(ship)
		_retarget_timer = 1.0

	_decide_timer -= dt
	if _decide_timer <= 0.0:
		_decide(ship)
		_decide_timer = float(_p["reaction"])

	_apply(ship, dt)

func _target_alive() -> bool:
	var t := world.ship_by_id(_target_id)
	return t != null and t.alive

func _acquire_target(ship: SimShip) -> void:
	var best := -1
	var best_d := INF
	for other in world.ships:
		if other.id == ship.id or not other.alive:
			continue
		if other.team == ship.team and ship.team != -1:
			continue
		var d := ship.pos.distance_squared_to(other.pos)
		if d < best_d:
			best_d = d
			best = other.id
	_target_id = best

func _decide(ship: SimShip) -> void:
	var primary := world.primary_body()
	var star_pos := primary.pos if primary != null else Vector2.ZERO
	var star_r := primary.radius if primary != null else 0.0
	var dist_star := ship.pos.distance_to(star_pos)

	# Refresh aim jitter for this decision window.
	_aim_noise = _rng.randf_range(-1.0, 1.0) * float(_p["aim_error"])

	# 1) Survival: too close to the star -> burn directly away from it.
	var danger := star_r + 260.0
	if dist_star < danger:
		_want_angle = (ship.pos - star_pos).angle()
		_want_thrust = true
		return

	var target := world.ship_by_id(_target_id)
	if target == null:
		# No enemy: hold a gentle prograde orbit (thrust along velocity).
		_want_angle = ship.vel.angle()
		_want_thrust = ship.vel.length() < 120.0
		return

	# 2) Lead-aim: predict intercept accounting for relative velocity.
	var muzzle := world.config.torpedo_speed
	var rel := target.pos - ship.pos
	var t_hit := rel.length() / maxf(muzzle, 1.0)
	for _i in range(2):  # refine the intercept time twice
		var predicted := rel + (target.vel - ship.vel) * t_hit
		t_hit = predicted.length() / maxf(muzzle, 1.0)
	var aim := rel + (target.vel - ship.vel) * t_hit
	_want_angle = aim.angle() + _aim_noise

	# 3) Range management: close in if far, ease off if very close.
	var dist := rel.length()
	var preferred := 520.0
	_want_thrust = dist > preferred and _rng.randf() < float(_p["aggression"])

func _apply(ship: SimShip, dt: float) -> void:
	# Steer toward the desired heading.
	var delta := wrapf(_want_angle - ship.angle, -PI, PI)
	if absf(delta) > 0.03:
		ship.in_turn = signf(delta)
	else:
		ship.in_turn = 0.0
	ship.in_thrust = _want_thrust

	# Fire when lined up, in range, and armed.
	var target := world.ship_by_id(_target_id)
	if target != null and ship.ammo > 0 and absf(delta) < float(_p["fire_cone"]):
		var dist := ship.pos.distance_to(target.pos)
		if dist < 1400.0:
			ship.in_fire = true

	# Panic-hyperspace from a near, fast incoming torpedo.
	if bool(_p["hyper"]) and ship.hyperspace_cooldown <= 0.0 and ship.spawn_grace <= 0.0:
		var panic := float(_p["panic"])
		for torp in world.torpedoes:
			if torp.owner_id == ship.id:
				continue
			if ship.pos.distance_to(torp.pos) < panic:
				# Only dodge torpedoes actually closing on us.
				var closing := (torp.pos - ship.pos).normalized().dot((ship.vel - torp.vel).normalized())
				if closing < -0.2:
					ship.in_hyper = true
					break

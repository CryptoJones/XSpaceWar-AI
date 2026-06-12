class_name BotController
extends RefCounted
## Procedural AI pilot. Reads a SimWorld and writes control inputs onto one
## SimShip each step — flying the exact same simulation as human players.
##
## Difficulty tiers scale reaction time, aim error, firing discipline, and
## aggression. On top of that every bot gets a seeded PERSONALITY (from its
## hull seed) that shapes how it fights: preferred range, target selection,
## fire discipline, and whether it swings past the star for slingshot runs.
## Veteran+ bots also predictively dodge lethal bodies along their velocity;
## rookies still fly into rocks, which is half their charm.

enum Difficulty { ROOKIE, VETERAN, ACE, INSANE }
enum Personality { BRAWLER, SNIPER, SLINGSHOT, OPPORTUNIST }

const PRESETS := {
	Difficulty.ROOKIE:  {"reaction": 0.45, "aim_error": 0.30, "fire_cone": 0.18, "aggression": 0.50, "panic": 70.0, "hyper": false},
	Difficulty.VETERAN: {"reaction": 0.26, "aim_error": 0.15, "fire_cone": 0.12, "aggression": 0.72, "panic": 110.0, "hyper": true},
	Difficulty.ACE:     {"reaction": 0.15, "aim_error": 0.07, "fire_cone": 0.085, "aggression": 0.88, "panic": 150.0, "hyper": true},
	Difficulty.INSANE:  {"reaction": 0.07, "aim_error": 0.02, "fire_cone": 0.05, "aggression": 1.00, "panic": 190.0, "hyper": true},
}

## Personality modifiers applied over the difficulty preset.
const PERSONALITIES := {
	Personality.BRAWLER:     {"range": 300.0, "fire_range": 750.0,  "aggr": 1.25, "cone": 1.4, "panic": 0.7, "sling": 0.0},
	Personality.SNIPER:      {"range": 820.0, "fire_range": 1800.0, "aggr": 0.60, "cone": 0.6, "panic": 1.3, "sling": 0.0},
	Personality.SLINGSHOT:   {"range": 520.0, "fire_range": 1300.0, "aggr": 1.00, "cone": 1.0, "panic": 1.0, "sling": 0.45},
	Personality.OPPORTUNIST: {"range": 540.0, "fire_range": 1400.0, "aggr": 0.85, "cone": 1.0, "panic": 1.1, "sling": 0.0},
}

const CALL_A := ["VEC", "NOVA", "RAD", "JINX", "MOL", "TOR", "ZERO", "KILO",
	"REX", "LUX", "PYRO", "HEX", "DUKE", "GRIM", "WOLF", "ECHO"]
const CALL_B := ["TOR", "RAY", "BACK", "SHOT", "STAR", "BURN", "WIND", "FANG",
	"BOLT", "ZONE", "JET", "HAWK", "DUST", "NULL", "FIRE", "DRIFT"]

var world: SimWorld
var ship_id: int
var difficulty: int = Difficulty.VETERAN
var personality: int = Personality.BRAWLER
## 1..100: where this pilot prefers to hunt — 1 hugs the star, 100 prowls
## the far edges. Every bot rolls its own, so the fleet spreads out instead
## of swarming the gravity well.
var roam := 50
## 1..100: 1 flees from other ships, 100 hunts them relentlessly.
var aggression := 70
var _p: Dictionary
var _preferred_range := 520.0
var _fire_range := 1400.0
var _sling := 0.0

var _rng := RandomNumberGenerator.new()
var _decide_timer: float = 0.0
var _target_id: int = -1
var _retarget_timer: float = 0.0

# Cached decisions (refreshed each reaction tick, applied every step).
var _want_angle: float = 0.0
var _want_thrust: bool = false
var _aim_noise: float = 0.0

func _init(p_world: SimWorld, p_ship_id: int, p_difficulty: int = Difficulty.VETERAN,
		p_personality := -1, p_roam := -1, p_aggression := -1) -> void:
	world = p_world
	ship_id = p_ship_id
	difficulty = p_difficulty
	_rng.seed = world.config.seed ^ (p_ship_id * 0x9E3779B1)

	var ship := world.ship_by_id(ship_id)
	var pseed := ship.hull_seed if ship != null else p_ship_id
	personality = personality_for(pseed) if p_personality < 0 else p_personality
	var pp: Dictionary = PERSONALITIES[personality]
	_p = (PRESETS[difficulty] as Dictionary).duplicate()
	_p["fire_cone"] = float(_p["fire_cone"]) * float(pp["cone"])
	_p["panic"] = float(_p["panic"]) * float(pp["panic"])
	_preferred_range = float(pp["range"])
	_fire_range = float(pp["fire_range"])
	_sling = float(pp["sling"])

	# Per-pilot temperament rolls (deterministic from the match seed) —
	# personality tilts the aggression roll rather than overriding it.
	roam = _rng.randi_range(1, 100) if p_roam < 0 else clampi(p_roam, 1, 100)
	aggression = _rng.randi_range(1, 100) if p_aggression < 0 else clampi(p_aggression, 1, 100)
	if p_aggression < 0:
		# Personality tilts the roll; difficulty scales it (rookies hunt
		# gently, insane pilots relentlessly).
		aggression = clampi(int(float(aggression) * float(pp["aggr"])
			* float(_p["aggression"])), 1, 100)

static func difficulty_from_name(n: String) -> int:
	match n.to_lower():
		"rookie": return Difficulty.ROOKIE
		"veteran": return Difficulty.VETERAN
		"ace": return Difficulty.ACE
		"insane": return Difficulty.INSANE
	return Difficulty.VETERAN

## Deterministic personality from a hull seed.
static func personality_for(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0xBADC0DE
	return rng.randi() % Personality.size()

## Deterministic pilot callsign from a hull seed (shown on the leaderboard).
static func callsign(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0xCA11516
	return CALL_A[rng.randi() % CALL_A.size()] + CALL_B[rng.randi() % CALL_B.size()]

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
	var best_metric := INF
	for other in world.ships:
		if other.id == ship.id or not other.alive:
			continue
		if other.team == ship.team and ship.team != -1:
			continue
		var metric: float
		match personality:
			Personality.OPPORTUNIST:
				# Hunt whoever is weakest, distance as the tiebreaker.
				metric = float(other.score) * 1.0e9 + ship.pos.distance_squared_to(other.pos)
			Personality.SLINGSHOT:
				# Spite: hunt the leader, distance as the tiebreaker.
				metric = -float(other.score) * 1.0e9 + ship.pos.distance_squared_to(other.pos)
			_:
				metric = ship.pos.distance_squared_to(other.pos)
		if metric < best_metric:
			best_metric = metric
			best = other.id
	_target_id = best

## The lethal body we are on course to hit within ~1.5s, or null. Bodies'
## own motion is extrapolated; gravity curvature is ignored (the margin and
## the next reaction tick absorb the error).
func _imminent_hazard(ship: SimShip) -> SimBody:
	var t_max := 1.0 + 0.2 * float(difficulty)
	for b in world.bodies:
		if not b.lethal:
			continue
		var margin := b.radius + ship.radius + (60.0 if b.gravity else 26.0)
		for k in range(1, 5):
			var t := t_max * float(k) * 0.25
			if (ship.pos + ship.vel * t).distance_to(b.pos + b.vel * t) < margin:
				return b
	return null

## An armed hostile mine we're drifting toward, or null.
func _imminent_mine(ship: SimShip) -> SimMine:
	var t_max := 1.0 + 0.2 * float(difficulty)
	for m in world.mines:
		if m.owner_id == ship_id or m.age < world.config.mine_arm_time:
			continue
		if m.team == ship.team and ship.team != -1:
			continue
		var margin := world.config.mine_trigger_radius + ship.radius + 30.0
		for k in range(1, 5):
			var t := t_max * float(k) * 0.25
			if (ship.pos + ship.vel * t).distance_to(m.pos + m.vel * t) < margin:
				return m
	return null

## The lead-aim firing solution angle for hitting `target` from `ship`
## (iterative intercept against relative velocity) — shared by the attack
## steering and the fire gate so bots only shoot when the shot can land.
func _lead_angle(ship: SimShip, target: SimShip) -> float:
	var muzzle := world.config.torpedo_speed
	var rel := target.pos - ship.pos
	var t_hit := rel.length() / maxf(muzzle, 1.0)
	for _i in range(2):
		var predicted := rel + (target.vel - ship.vel) * t_hit
		t_hit = predicted.length() / maxf(muzzle, 1.0)
	return (rel + (target.vel - ship.vel) * t_hit).angle()

## This pilot's preferred hunting ring radius around the star.
func _roam_radius(star_r: float) -> float:
	var r_min := star_r + 500.0
	# Far edge of the hunting grounds: 6x the spawn ring, but always inside
	# the map (small arenas pull everyone's ring inward).
	var r_max := minf(world.config.spawn_orbit_radius * 6.0,
		world.config.arena_size * 0.5 * 0.85)
	return lerpf(r_min, maxf(r_min, r_max), float(roam - 1) / 99.0)

## A nearby pickup worth detouring for (only when actually short on it).
func _wanted_pickup(ship: SimShip) -> SimPickup:
	var best: SimPickup = null
	var best_d := 900.0 * 900.0
	for p in world.pickups:
		var useful := false
		match p.kind:
			SimPickup.Kind.FUEL:
				useful = ship.fuel < world.config.max_fuel * 0.35
			SimPickup.Kind.AMMO:
				useful = ship.ammo <= 3
			SimPickup.Kind.MINES:
				useful = ship.mines == 0 and personality != Personality.SNIPER
		if not useful:
			continue
		var d := ship.pos.distance_squared_to(p.pos)
		if d < best_d:
			best_d = d
			best = p
	return best

func _decide(ship: SimShip) -> void:
	var primary := world.primary_body()
	var star_pos := primary.pos if primary != null else Vector2.ZERO
	var star_r := primary.radius if primary != null else 0.0
	var dist_star := ship.pos.distance_to(star_pos)

	# Refresh aim jitter for this decision window.
	_aim_noise = _rng.randf_range(-1.0, 1.0) * float(_p["aim_error"])

	# 0.5) Lethal boundary: never fly off the map. Burn back toward the well
	# the moment our heading would carry us into the wall.
	if world.config.lethal_edges:
		var half := world.config.arena_size * 0.5
		var ahead := ship.pos + ship.vel * 1.5
		if absf(ahead.x) > half - 300.0 or absf(ahead.y) > half - 300.0:
			_want_angle = (star_pos - ship.pos).angle()
			_want_thrust = true
			return

	# 1) Survival. Veteran+ pilots dodge whatever they're about to hit by
	# burning perpendicular to the collision course (bodies and armed enemy
	# mines alike); everyone burns away from the star's kill zone.
	if difficulty >= Difficulty.VETERAN:
		var hz_pos := Vector2.INF
		var hazard := _imminent_hazard(ship)
		if hazard != null:
			hz_pos = hazard.pos
		else:
			var mz := _imminent_mine(ship)
			if mz != null:
				hz_pos = mz.pos
		if hz_pos.is_finite():
			var lateral := Vector2(-ship.vel.y, ship.vel.x).normalized()
			if lateral.dot(hz_pos - ship.pos) > 0.0:
				lateral = -lateral
			_want_angle = lateral.angle()
			_want_thrust = true
			return
	if dist_star < star_r + 260.0:
		_want_angle = (ship.pos - star_pos).angle()
		_want_thrust = true
		return

	var aggr := float(aggression - 1) / 99.0
	var target := world.ship_by_id(_target_id)

	# 1.6) Fear: timid pilots run FROM ships. The less aggressive, the larger
	# the radius at which they break and flee (still snapping off shots when
	# their nose happens to cross someone — see _apply).
	if target != null:
		var dist_t := ship.pos.distance_to(target.pos)
		var flee_r := lerpf(1500.0, 0.0, aggr)
		if dist_t < flee_r:
			_want_angle = (ship.pos - target.pos).angle() + _aim_noise
			_want_thrust = true
			return

	# 1.7) Logistics: detour to a nearby supply drop when we're short — but
	# never abandon an enemy already inside firing range. Fighting > shopping.
	if target == null or ship.pos.distance_to(target.pos) > _fire_range:
		var want_pickup := _wanted_pickup(ship)
		if want_pickup != null:
			var lead := want_pickup.pos + want_pickup.vel * 0.4 - ship.pos
			_want_angle = lead.angle()
			_want_thrust = true
			return

	# 1.8) Hunter-killer patrol: every pilot has a preferred ring around the
	# star (roam 1 = hug it, 100 = prowl the far edges). With no target —
	# or no appetite to chase — correct back to the ring instead of letting
	# gravity swarm everyone into the well.
	var chase := target != null and _rng.randf() < maxf(0.12, aggr)
	if target == null or not chase:
		var want_r := _roam_radius(star_r)
		var dist_now := maxf(1.0, dist_star)
		if absf(dist_now - want_r) > 280.0:
			# Aim at a point on our ring, a little ahead of us angularly.
			var dir := (ship.pos - star_pos) / dist_now
			var ring_point := star_pos + dir.rotated(0.55) * want_r
			_want_angle = (ring_point - ship.pos).angle()
			_want_thrust = true
		else:
			_want_angle = ship.vel.angle()
			_want_thrust = ship.vel.length() < 120.0
		return

	# 2) Lead-aim: predict intercept accounting for relative velocity.
	var rel := target.pos - ship.pos
	var aim := Vector2.from_angle(_lead_angle(ship, target))
	_want_angle = aim.angle() + _aim_noise

	# 3) Range management per personality; slingshotters bias their approach
	# toward the star to pick up a gravity assist on the way in.
	var dist := rel.length()
	if _sling > 0.0 and dist > _preferred_range * 1.7 and primary != null:
		var blended := aim.normalized().lerp((star_pos - ship.pos).normalized(), _sling)
		_want_angle = blended.angle() + _aim_noise
	_want_thrust = dist > _preferred_range and _rng.randf() < maxf(0.15, aggr)

func _apply(ship: SimShip, dt: float) -> void:
	# Steer toward the desired heading.
	var delta := wrapf(_want_angle - ship.angle, -PI, PI)
	if absf(delta) > 0.03:
		ship.in_turn = signf(delta)
	else:
		ship.in_turn = 0.0
	ship.in_thrust = _want_thrust

	# Fire when the NOSE crosses the firing solution, in range, and armed —
	# delta only measures error to the nav heading, which in flee/patrol
	# modes points away from the enemy entirely.
	var target := world.ship_by_id(_target_id)
	if target != null and ship.ammo > 0:
		var sol_err := absf(wrapf(_lead_angle(ship, target) - ship.angle, -PI, PI))
		if sol_err < float(_p["fire_cone"]) \
				and ship.pos.distance_to(target.pos) < _fire_range:
			ship.in_fire = true

	# Defensive mining: brawlers and opportunists drop one when an enemy is
	# hot on their tail — and timid pilots (low aggression) mine their escape
	# route eagerly: chasing a coward through their breadcrumbs should hurt.
	var timid := aggression <= 35
	if ship.mines > 0 and ship.mine_cooldown <= 0.0 \
			and (timid or personality == Personality.BRAWLER
				or personality == Personality.OPPORTUNIST):
		for other in world.ships:
			if other.id == ship.id or not other.alive:
				continue
			if other.team == ship.team and ship.team != -1:
				continue
			var rel := other.pos - ship.pos
			if rel.length() < 380.0 and rel.dot(ship.facing()) < -0.3 * rel.length():
				if _rng.randf() < (0.09 if timid else 0.04):
					ship.in_mine = true
				break

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

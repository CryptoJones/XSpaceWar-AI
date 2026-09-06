class_name SimWorld
extends RefCounted
## The authoritative, deterministic, render-free game simulation.
##
## Fixed-timestep Newtonian physics: ships and torpedoes coast, are pulled by
## the inverse-square gravity of every massive body, and are destroyed on
## contact with bodies, torpedoes, or each other. Hyperspace teleports a ship
## to a fresh orbit at the risk of self-destruction.
##
## Determinism: integration order is fixed, and all randomness goes through a
## single seeded RNG, so the same config + same input stream reproduces the
## same end state bit-for-bit on a given platform. This one class backs the
## host's authoritative sim, client-side prediction, AI, and replays.
##
## The per-phase logic lives in the stateless systems under src/sim/systems/
## (GravitySystem, SpawnSystem, MineSystem, PickupSystem, CollisionSystem,
## WrapSystem) — extracted from this god-class in issue #18. SimWorld owns the
## state and drives the fixed-order step() pipeline across those systems; a few
## methods are kept here as thin forwarders for external callers.

var config: SimConfig
var rng := RandomNumberGenerator.new()

var bodies: Array[SimBody] = []
var ships: Array[SimShip] = []
var torpedoes: Array[SimTorpedo] = []
var mines: Array[SimMine] = []
var pickups: Array[SimPickup] = []
## Ids of bodies destroyed mid-match (shot asteroids) — replicated to net
## clients so their locally-generated arenas lose the same rocks.
var removed_body_ids: Array[int] = []

var time: float = 0.0
var tick: int = 0
var _next_id: int = 1

## Transient list of things that happened this step, for the renderer/audio
## layer to consume (explosions, fires, hyperspace warps, kills). Cleared at
## the start of every step.
var events: Array[Dictionary] = []

func _init(cfg: SimConfig = null) -> void:
	config = cfg if cfg != null else SimConfig.new()
	rng.seed = config.seed

func alloc_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func add_body(b: SimBody) -> SimBody:
	if b.id < 0:
		b.id = alloc_id()
	bodies.append(b)
	return b

func add_ship(team: int = -1) -> SimShip:
	var s := SimShip.new()
	s.id = alloc_id()
	s.team = team
	s.radius = config.ship_radius
	s.hull_seed = rng.randi()
	s.palette_idx = ships.size()
	place_in_orbit(s)
	ships.append(s)
	return s

func body_by_id(bid: int) -> SimBody:
	for b in bodies:
		if b.id == bid:
			return b
	return null

func ship_by_id(sid: int) -> SimShip:
	for s in ships:
		if s.id == sid:
			return s
	return null

## The most massive gravitating body — the "sun" everything orbits.
func primary_body() -> SimBody:
	var best: SimBody = null
	for b in bodies:
		if b.gravity and (best == null or b.mass > best.mass):
			best = b
	return best

# --------------------------------------------------------------------------
# Stepping — the fixed-order pipeline across the systems. The call order here
# is determinism-critical (it fixes the RNG-consumption order); do not reorder.
# --------------------------------------------------------------------------

func step(dt: float = -1.0) -> void:
	if dt < 0.0:
		dt = config.fixed_dt
	# Events ACCUMULATE (tick-stamped) instead of clearing per step: when a
	# driver runs several steps per consumer pass (fast replay, sub-60fps
	# frames) nothing is lost. Consumers track the last tick they processed;
	# the cap below bounds memory for consumer-less worlds (dedicated).

	GravitySystem.advance_bodies(self, dt)

	for s in ships:
		SpawnSystem.step_ship(self, s, dt)

	GravitySystem.integrate_ships(self, dt)
	_step_torpedoes(dt)
	MineSystem.step_mines(self, dt)
	PickupSystem.step_pickups(self, dt)
	CollisionSystem.resolve(self, dt)

	if config.wrap_edges:
		WrapSystem.wrap_positions(self)
	elif config.lethal_edges:
		WrapSystem.enforce_lethal_edges(self)

	if events.size() > 512:
		events = events.slice(events.size() - 256)

	time += dt
	tick += 1

## Torpedo drift/expiry. Kept on SimWorld (issue #18 listed no torpedo system);
## a small projectile-stepping helper that leans on Gravity/Wrap systems.
func _step_torpedoes(dt: float) -> void:
	var survivors: Array[SimTorpedo] = []
	for t in torpedoes:
		t.age += dt
		# A configured fuse still works (and old replays need it), but the
		# default is 0: torpedoes fly FOREVER until they hit something.
		if config.torpedo_life > 0.0:
			t.life -= dt
			if t.life <= 0.0:
				continue
		if config.torpedo_gravity:
			t.vel += GravitySystem.accel(self, t.pos) * dt
		t.pos += t.vel * dt
		if config.wrap_edges:
			var wb_t := WrapSystem.wrap_with_boost(self, t.pos, t.vel)
			if not wb_t.is_empty():
				t.pos = wb_t[0]
				t.vel = wb_t[1]
		survivors.append(t)
	torpedoes = survivors

## Advance one ship's pilot kinematics (turn / thrust+fuel / gravity /
## position / wrap) exactly as a full step would, without weapons, timers, or
## collisions. Used by net clients to predict the local ship: the order
## matches SpawnSystem.step_ship -> GravitySystem.integrate_ships for one ship.
func step_ship_kinematics(s: SimShip, turn: float, thrust: bool, dt: float, brake: bool = false) -> void:
	s.angle = wrapf(s.angle + clampf(turn, -1.0, 1.0) * config.turn_rate * dt, -PI, PI)
	if thrust and s.fuel > 0.0:
		s.vel += s.facing() * config.thrust_accel * dt
		s.fuel = maxf(0.0, s.fuel - config.thrust_fuel_per_sec * dt)
	elif brake and s.vel.length_squared() > 1.0 and s.fuel > 0.0:
		var speed := s.vel.length()
		var dv := minf(speed, config.thrust_accel * 0.95 * dt)
		s.vel -= s.vel.normalized() * dv
		s.fuel = maxf(0.0, s.fuel - config.thrust_fuel_per_sec * dt)
	else:
		s.fuel = minf(config.max_fuel, s.fuel + config.fuel_regen_per_sec * dt)
	s.vel += GravitySystem.accel(self, s.pos) * dt
	clamp_ship_velocity(s)
	s.pos += s.vel * dt
	if config.wrap_edges:
		var wb := WrapSystem.wrap_with_boost(self, s.pos, s.vel)
		if not wb.is_empty():
			s.pos = wb[0]
			s.vel = wb[1]

# --------------------------------------------------------------------------
# Thin forwarders kept for external callers (net_client, tests, scene_smoke)
# so the extraction in issue #18 preserves the public API.
# --------------------------------------------------------------------------

func gravity_accel(p: Vector2) -> Vector2:
	return GravitySystem.accel(self, p)

func clamp_ship_velocity(s: SimShip) -> void:
	if config.max_ship_speed > 0.0 \
			and s.vel.length_squared() > config.max_ship_speed * config.max_ship_speed:
		s.vel = s.vel.limit_length(config.max_ship_speed)

func _advance_bodies(dt: float) -> void:
	GravitySystem.advance_bodies(self, dt)

func place_in_orbit(s: SimShip) -> void:
	SpawnSystem.place_in_orbit(self, s)

func _hyperspace(s: SimShip) -> void:
	SpawnSystem.hyperspace(self, s)

func _destroy_ship(s: SimShip, killer_id: int, cause: String) -> void:
	CollisionSystem.destroy_ship(self, s, killer_id, cause)

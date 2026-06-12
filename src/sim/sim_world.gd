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

const SELF_HIT_GRACE := 0.30            ## a torpedo can't hit its own ship before this age

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
# Spawning
# --------------------------------------------------------------------------

func place_in_orbit(s: SimShip) -> void:
	var center := Vector2.ZERO
	var m := 0.0
	var primary := primary_body()
	if primary != null:
		center = primary.pos
		m = primary.mass
	# Teams spawn (and respawn) together in their own sector of the ring —
	# golden-angle spacing keeps any team count spread apart. FFA ships use
	# the whole circle.
	var ang: float
	if s.team >= 0:
		ang = wrapf(float(s.team) * 2.399963 + rng.randf_range(-0.6, 0.6), 0.0, TAU)
	else:
		ang = rng.randf() * TAU
	# The ring respects the ACTUAL star: a maxed star-size slider must not
	# leave pilots spawning inside the well (and never at the map's wall).
	var r := config.spawn_orbit_radius
	if primary != null:
		r = maxf(r, primary.radius * 2.2 + 120.0)
	r = minf(r, config.arena_size * 0.5 * 0.85)
	s.pos = center + Vector2(cos(ang), sin(ang)) * r
	# Circular-orbit speed, perpendicular to the radius, random direction.
	var speed := 0.0
	if m > 0.0:
		speed = sqrt(config.gravity_constant * m / r)
	var dir := Vector2(-sin(ang), cos(ang))
	if rng.randf() < 0.5:
		dir = -dir
	s.vel = dir * speed
	s.angle = dir.angle()
	s.fuel = config.max_fuel
	s.ammo = config.max_ammo
	s.ammo_timer = 0.0
	s.mines = config.max_mines
	s.mine_timer = 0.0
	s.mine_cooldown = 0.0
	s.alive = true
	s.respawn_timer = 0.0
	s.fire_cooldown = 0.0
	s.spawn_grace = config.spawn_grace

# --------------------------------------------------------------------------
# Stepping
# --------------------------------------------------------------------------

func step(dt: float = -1.0) -> void:
	if dt < 0.0:
		dt = config.fixed_dt
	events.clear()

	_advance_bodies(dt)

	for s in ships:
		_step_ship(s, dt)

	_integrate_ships(dt)
	_step_torpedoes(dt)
	_step_mines(dt)
	_step_pickups(dt)
	_resolve_collisions()

	if config.wrap_edges:
		_wrap_positions()
	elif config.lethal_edges:
		_enforce_lethal_edges()

	time += dt
	tick += 1

func _advance_bodies(dt: float) -> void:
	for b in bodies:
		if not b.is_orbiting():
			continue
		var parent := body_by_id(b.parent_id)
		if parent == null:
			continue
		var prev := b.pos
		b.orbit_angle = wrapf(b.orbit_angle + b.orbit_speed * dt, 0.0, TAU)
		b.pos = parent.pos + Vector2(cos(b.orbit_angle), sin(b.orbit_angle)) * b.orbit_radius
		b.vel = (b.pos - prev) / dt if dt > 0.0 else Vector2.ZERO

func _step_ship(s: SimShip, dt: float) -> void:
	if not s.alive:
		# Lives mode: out of lives means out of the match — no respawn.
		if config.lives > 0 and s.deaths >= config.lives:
			s.clear_inputs()
			return
		s.respawn_timer -= dt
		if s.respawn_timer <= 0.0:
			place_in_orbit(s)
		s.clear_inputs()
		return

	# Timers / resource regen.
	s.spawn_grace = maxf(0.0, s.spawn_grace - dt)
	s.fire_cooldown = maxf(0.0, s.fire_cooldown - dt)
	s.hyperspace_cooldown = maxf(0.0, s.hyperspace_cooldown - dt)
	s.mine_cooldown = maxf(0.0, s.mine_cooldown - dt)
	if s.ammo < config.max_ammo:
		s.ammo_timer += dt
		while s.ammo_timer >= config.ammo_regen_interval and s.ammo < config.max_ammo:
			s.ammo_timer -= config.ammo_regen_interval
			s.ammo += 1
	if s.mines < config.max_mines:
		s.mine_timer += dt
		while s.mine_timer >= config.mine_regen_interval and s.mines < config.max_mines:
			s.mine_timer -= config.mine_regen_interval
			s.mines += 1

	# Rotation.
	s.angle = wrapf(s.angle + s.in_turn * config.turn_rate * dt, -PI, PI)

	# Thrust (fuel-limited). Integration of velocity happens in _integrate_ships
	# alongside gravity; here we just apply the thrust impulse and burn fuel.
	if s.in_thrust and s.fuel > 0.0:
		s.vel += s.facing() * config.thrust_accel * dt
		s.fuel = maxf(0.0, s.fuel - config.thrust_fuel_per_sec * dt)
		events.append({"type": "thrust", "ship": s.id, "pos": s.pos})
	else:
		s.fuel = minf(config.max_fuel, s.fuel + config.fuel_regen_per_sec * dt)

	# Fire.
	if s.in_fire and s.fire_cooldown <= 0.0 and s.ammo > 0:
		_fire_torpedo(s)

	# Drop a mine behind us.
	if s.in_mine and s.mine_cooldown <= 0.0 and s.mines > 0:
		_drop_mine(s)

	# Hyperspace.
	if s.in_hyper and s.hyperspace_cooldown <= 0.0:
		_hyperspace(s)

	s.clear_inputs()

func _fire_torpedo(s: SimShip) -> void:
	var t := SimTorpedo.new()
	t.id = alloc_id()
	t.owner_id = s.id
	t.team = s.team
	t.radius = config.torpedo_radius
	var fwd := s.facing()
	t.pos = s.pos + fwd * (s.radius + t.radius + 2.0)
	t.vel = s.vel + fwd * config.torpedo_speed
	t.life = config.torpedo_life
	torpedoes.append(t)
	s.ammo -= 1
	s.fire_cooldown = config.fire_cooldown
	events.append({"type": "fire", "ship": s.id, "pos": t.pos})

func _drop_mine(s: SimShip) -> void:
	var m := SimMine.new()
	m.id = alloc_id()
	m.owner_id = s.id
	m.team = s.team
	m.radius = config.mine_radius
	m.pos = s.pos - s.facing() * (s.radius + m.radius + 6.0)
	m.vel = s.vel * 0.85  # sheds a little speed so it falls behind
	m.life = config.mine_life
	mines.append(m)
	s.mines -= 1
	s.mine_cooldown = config.mine_drop_cooldown
	events.append({"type": "mine", "ship": s.id, "pos": m.pos})

func _hyperspace(s: SimShip) -> void:
	s.hyperspace_uses += 1
	s.hyperspace_cooldown = config.hyperspace_cooldown
	events.append({"type": "hyperspace", "ship": s.id, "pos": s.pos})
	var risk := config.hyperspace_base_risk + config.hyperspace_risk_per_use * float(s.hyperspace_uses - 1)
	if rng.randf() < risk:
		_destroy_ship(s, -1, "hyperspace")
		return
	place_in_orbit(s)

func _integrate_ships(dt: float) -> void:
	# Semi-implicit (symplectic) Euler: update velocity from gravity, then
	# position from the new velocity. Stable for orbits.
	for s in ships:
		if not s.alive:
			continue
		s.vel += gravity_accel(s.pos) * dt
		s.pos += s.vel * dt

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
			t.vel += gravity_accel(t.pos) * dt
		t.pos += t.vel * dt
		if config.wrap_edges:
			var wrapped := _wrap_point(t.pos)
			if wrapped != t.pos:
				t.pos = wrapped
				t.vel = (t.vel * WRAP_BOOST).limit_length(WRAP_SPEED_CAP)
		survivors.append(t)
	torpedoes = survivors

func _break_rock(rock: SimBody) -> void:
	bodies.erase(rock)
	removed_body_ids.append(rock.id)
	events.append({"type": "rock_break", "pos": rock.pos})
	if rng.randf() < config.pickup_chance:
		var p := SimPickup.new()
		p.id = alloc_id()
		p.kind = rng.randi() % SimPickup.Kind.size()
		p.pos = rock.pos
		var ang := rng.randf() * TAU
		p.vel = Vector2(cos(ang), sin(ang)) * rng.randf_range(10.0, 50.0)
		p.ttl = config.pickup_ttl
		p.radius = config.pickup_radius
		pickups.append(p)

func _step_pickups(dt: float) -> void:
	var survivors: Array[SimPickup] = []
	for p in pickups:
		p.age += dt
		p.ttl -= dt
		if p.ttl <= 0.0:
			continue
		p.vel += gravity_accel(p.pos) * dt
		p.pos += p.vel * dt
		if config.wrap_edges:
			var wrapped := _wrap_point(p.pos)
			if wrapped != p.pos:
				p.pos = wrapped
				p.vel = (p.vel * WRAP_BOOST).limit_length(WRAP_SPEED_CAP)
		var claimed := false
		for s in ships:
			if not s.alive:
				continue
			if p.pos.distance_to(s.pos) <= p.radius + s.radius:
				_grant_pickup(s, p)
				claimed = true
				break
		if not claimed:
			survivors.append(p)
	pickups = survivors

func _grant_pickup(s: SimShip, p: SimPickup) -> void:
	match p.kind:
		SimPickup.Kind.FUEL:
			s.fuel = minf(config.max_fuel, s.fuel + config.pickup_fuel_amount)
		SimPickup.Kind.AMMO:
			s.ammo = mini(config.max_ammo, s.ammo + config.pickup_ammo_amount)
		SimPickup.Kind.MINES:
			s.mines = mini(config.max_mines, s.mines + config.pickup_mines_amount)
	events.append({"type": "pickup", "ship": s.id, "kind": p.kind, "pos": p.pos})

func _step_mines(dt: float) -> void:
	var survivors: Array[SimMine] = []
	for m in mines:
		m.age += dt
		m.life -= dt
		if m.life <= 0.0:
			continue
		m.vel += gravity_accel(m.pos) * dt
		m.pos += m.vel * dt
		if config.wrap_edges:
			var wrapped := _wrap_point(m.pos)
			if wrapped != m.pos:
				m.pos = wrapped
				m.vel = (m.vel * WRAP_BOOST).limit_length(WRAP_SPEED_CAP)
		survivors.append(m)
	mines = survivors

func gravity_accel(p: Vector2) -> Vector2:
	var a := Vector2.ZERO
	for b in bodies:
		if not b.gravity or b.mass <= 0.0:
			continue
		var d := b.pos - p
		var r2 := d.length_squared()
		# Softening near the core so the acceleration never blows up.
		var soft := b.radius * 0.5
		r2 = maxf(r2, soft * soft)
		var r := sqrt(r2)
		a += d * (config.gravity_constant * b.mass / (r2 * r))
	return a

## Advance one ship's pilot kinematics (turn / thrust+fuel / gravity /
## position / wrap) exactly as a full step would, without weapons, timers, or
## collisions. Used by net clients to predict the local ship: the order
## matches _step_ship -> _integrate_ships for a single ship.
func step_ship_kinematics(s: SimShip, turn: float, thrust: bool, dt: float) -> void:
	s.angle = wrapf(s.angle + clampf(turn, -1.0, 1.0) * config.turn_rate * dt, -PI, PI)
	if thrust and s.fuel > 0.0:
		s.vel += s.facing() * config.thrust_accel * dt
		s.fuel = maxf(0.0, s.fuel - config.thrust_fuel_per_sec * dt)
	else:
		s.fuel = minf(config.max_fuel, s.fuel + config.fuel_regen_per_sec * dt)
	s.vel += gravity_accel(s.pos) * dt
	s.pos += s.vel * dt
	if config.wrap_edges:
		var wrapped := _wrap_point(s.pos)
		if wrapped != s.pos:
			s.pos = wrapped
			s.vel = (s.vel * WRAP_BOOST).limit_length(WRAP_SPEED_CAP)

# --------------------------------------------------------------------------
# Collisions
# --------------------------------------------------------------------------

func _resolve_collisions() -> void:
	# Torpedoes vs bodies. Stars/planets simply eat torpedoes; ASTEROIDS are
	# destructible — the rock shatters and sometimes drops its cargo.
	var torp_survivors: Array[SimTorpedo] = []
	var broken_rocks: Array[SimBody] = []
	for t in torpedoes:
		var hit_body := false
		for b in bodies:
			if not b.lethal:
				continue
			if t.pos.distance_to(b.pos) <= b.radius + t.radius:
				hit_body = true
				if b.kind == SimBody.Kind.ASTEROID and not broken_rocks.has(b):
					broken_rocks.append(b)
				break
		if not hit_body:
			torp_survivors.append(t)
	torpedoes = torp_survivors
	for rock in broken_rocks:
		_break_rock(rock)

	# Torpedoes vs ships.
	var remaining: Array[SimTorpedo] = []
	for t in torpedoes:
		var consumed := false
		for s in ships:
			if not s.alive or s.spawn_grace > 0.0:
				continue
			if s.id == t.owner_id and t.age < SELF_HIT_GRACE:
				continue
			if s.id != t.owner_id and s.team == t.team and s.team != -1 and not config.friendly_fire:
				continue
			if t.pos.distance_to(s.pos) <= s.radius + t.radius:
				var killer := -1 if s.id == t.owner_id else t.owner_id
				_destroy_ship(s, killer, "torpedo")
				consumed = true
				break
		if not consumed:
			remaining.append(t)
	torpedoes = remaining

	_resolve_mines()

	# Ships vs bodies.
	for s in ships:
		if not s.alive:
			continue
		for b in bodies:
			if not b.lethal:
				continue
			if s.pos.distance_to(b.pos) <= b.radius + s.radius:
				_destroy_ship(s, -1, "body")
				break

	# Ships vs ships.
	for i in range(ships.size()):
		var a := ships[i]
		if not a.alive or a.spawn_grace > 0.0:
			continue
		for j in range(i + 1, ships.size()):
			var b := ships[j]
			if not b.alive or b.spawn_grace > 0.0:
				continue
			if a.pos.distance_to(b.pos) > a.radius + b.radius:
				continue
			if a.team == b.team and a.team != -1 and not config.friendly_fire:
				continue
			if config.ship_collision_lethal:
				_destroy_ship(a, -1, "ram")
				_destroy_ship(b, -1, "ram")
			else:
				_bounce(a, b)

func _resolve_mines() -> void:
	var survivors: Array[SimMine] = []
	for m in mines:
		var exploded := false
		# Consumed (detonated) by lethal bodies.
		for b in bodies:
			if b.lethal and m.pos.distance_to(b.pos) <= b.radius + m.radius:
				exploded = true
				break
		# Shot by a torpedo — detonates even unarmed. This is the counterplay.
		if not exploded:
			var remaining: Array[SimTorpedo] = []
			for t in torpedoes:
				if not exploded and m.pos.distance_to(t.pos) <= m.radius + t.radius + 4.0:
					exploded = true
					continue  # the torpedo is consumed by the blast
				remaining.append(t)
			torpedoes = remaining
		# Proximity fuse once armed. The owner never trips the fuse (but is
		# not safe from the blast itself).
		if not exploded and m.age >= config.mine_arm_time:
			for s in ships:
				if not s.alive or s.spawn_grace > 0.0 or s.id == m.owner_id:
					continue
				if s.team == m.team and s.team != -1 and not config.friendly_fire:
					continue
				if m.pos.distance_to(s.pos) <= config.mine_trigger_radius + s.radius:
					exploded = true
					break
		if exploded:
			_explode_mine(m)
		else:
			survivors.append(m)
	mines = survivors

func _explode_mine(m: SimMine) -> void:
	events.append({"type": "mine_explode", "pos": m.pos})
	for s in ships:
		if not s.alive or s.spawn_grace > 0.0:
			continue
		if s.team == m.team and s.team != -1 and not config.friendly_fire and s.id != m.owner_id:
			continue
		if m.pos.distance_to(s.pos) <= config.mine_blast_radius + s.radius:
			_destroy_ship(s, m.owner_id if s.id != m.owner_id else -1, "mine")

func _bounce(a: SimShip, b: SimShip) -> void:
	# Equal-mass elastic bounce along the contact normal.
	var n := (b.pos - a.pos)
	if n.length() < 0.0001:
		return
	n = n.normalized()
	var va := a.vel.dot(n)
	var vb := b.vel.dot(n)
	a.vel += n * (vb - va)
	b.vel += n * (va - vb)
	# Separate so they don't stick.
	var overlap := (a.radius + b.radius) - a.pos.distance_to(b.pos)
	if overlap > 0.0:
		a.pos -= n * overlap * 0.5
		b.pos += n * overlap * 0.5

func _destroy_ship(s: SimShip, killer_id: int, cause: String) -> void:
	if not s.alive:
		return
	s.alive = false
	s.deaths += 1
	s.respawn_timer = config.respawn_time
	events.append({"type": "explosion", "ship": s.id, "pos": s.pos, "vel": s.vel, "cause": cause})
	if killer_id >= 0 and killer_id != s.id:
		var killer := ship_by_id(killer_id)
		if killer != null:
			killer.kills += 1
			killer.score += 1
			events.append({"type": "kill", "killer": killer_id, "victim": s.id})
	elif cause == "torpedo" or cause == "hyperspace" or cause == "mine":
		s.score -= 1  # suicide / self-destruct penalty

# --------------------------------------------------------------------------
# Arena wrapping
# --------------------------------------------------------------------------

## Wrap-mode bonus (Aaron's rule): crossing the map edge DOUBLES your speed —
## the toroidal seam is a slingshot. Capped well above gameplay speeds so the
## math can't run away into absurdity.
const WRAP_BOOST := 2.0
const WRAP_SPEED_CAP := 20000.0

func _wrap_positions() -> void:
	for s in ships:
		var wrapped := _wrap_point(s.pos)
		if wrapped != s.pos:
			s.pos = wrapped
			s.vel = (s.vel * WRAP_BOOST).limit_length(WRAP_SPEED_CAP)
			events.append({"type": "wrap", "ship": s.id, "pos": s.pos})

## Lethal-edge mode: the border is a wall of death. Ships crossing it are
## destroyed (environmental, no score penalty — like flying into a rock);
## loose ordnance and cargo simply leave the field.
func _enforce_lethal_edges() -> void:
	var half := config.arena_size * 0.5
	for s in ships:
		if s.alive and (absf(s.pos.x) > half or absf(s.pos.y) > half):
			_destroy_ship(s, -1, "edge")
	var t_keep: Array[SimTorpedo] = []
	for t in torpedoes:
		if absf(t.pos.x) <= half and absf(t.pos.y) <= half:
			t_keep.append(t)
	torpedoes = t_keep
	var m_keep: Array[SimMine] = []
	for m in mines:
		if absf(m.pos.x) <= half and absf(m.pos.y) <= half:
			m_keep.append(m)
	mines = m_keep
	var p_keep: Array[SimPickup] = []
	for p in pickups:
		if absf(p.pos.x) <= half and absf(p.pos.y) <= half:
			p_keep.append(p)
	pickups = p_keep

func _wrap_point(p: Vector2) -> Vector2:
	var half := config.arena_size * 0.5
	if p.x > half:
		p.x -= config.arena_size
	elif p.x < -half:
		p.x += config.arena_size
	if p.y > half:
		p.y -= config.arena_size
	elif p.y < -half:
		p.y += config.arena_size
	return p

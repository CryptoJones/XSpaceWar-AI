class_name CollisionSystem
## Swept collision detection and resolution for the deterministic sim:
## torpedoes vs bodies/ships, mines (delegated), ships vs bodies/ships, plus
## the rock-shatter, ship-destroy, and elastic-bounce helpers.
##
## Stateless: operates on a passed-in SimWorld. Extracted from SimWorld (issue
## #18). Scan order and the RNG draws in break_rock are unchanged.

const SELF_HIT_GRACE := 0.30  ## a torpedo can't hit its own ship before this age

## True if the swept path p0->p1 passes within r of c. Degenerates to a
## point test for tiny displacement; callers must teleport-guard wraps.
static func segment_hits_circle(p0: Vector2, p1: Vector2, c: Vector2, r: float) -> bool:
	var d := p1 - p0
	var len_sq := d.length_squared()
	if len_sq < 0.000001:
		return p0.distance_to(c) <= r
	var t := clampf((c - p0).dot(d) / len_sq, 0.0, 1.0)
	return (p0 + d * t).distance_to(c) <= r

static func resolve(world: SimWorld, dt: float) -> void:
	var config := world.config
	# Torpedoes vs bodies. Stars/planets simply eat torpedoes; ASTEROIDS are
	# destructible — the rock shatters and sometimes drops its cargo.
	var torp_survivors: Array[SimTorpedo] = []
	var broken_rocks: Array[SimBody] = []
	for t in world.torpedoes:
		var hit_body := false
		var t_prev := t.pos - t.vel * dt
		for b in world.bodies:
			if not b.lethal:
				continue
			if TorusMath.swept_hits_circle(t_prev, t.pos, b.pos,
					b.radius + t.radius, config.arena_size):
				hit_body = true
				if b.kind == SimBody.Kind.ASTEROID and not broken_rocks.has(b):
					broken_rocks.append(b)
				break
		if not hit_body:
			torp_survivors.append(t)
	world.torpedoes = torp_survivors
	for rock in broken_rocks:
		break_rock(world, rock)

	# Torpedoes vs ships.
	var remaining: Array[SimTorpedo] = []
	for t in world.torpedoes:
		var consumed := false
		for s in world.ships:
			if not s.alive or s.spawn_grace > 0.0:
				continue
			if s.id == t.owner_id and (t.age < SELF_HIT_GRACE or not config.friendly_fire):
				continue
			if s.id != t.owner_id and s.team == t.team and s.team != -1 and not config.friendly_fire:
				continue
			var t_prev := t.pos - t.vel * dt
			var s_prev := s.pos - s.vel * dt
			if TorusMath.swept_hits_moving_circle(t_prev, t.pos, s_prev, s.pos,
					s.radius + t.radius, config.arena_size):
				var killer := -1 if s.id == t.owner_id else t.owner_id
				damage_ship(world, s, killer, "torpedo", 1, t.vel)
				consumed = true
				break
		if not consumed:
			remaining.append(t)
	world.torpedoes = remaining

	MineSystem.resolve_mines(world)

	# Ships vs bodies.
	for s in world.ships:
		if not s.alive or s.spawn_grace > 0.0:
			continue
		var s_prev := s.pos - s.vel * dt
		for b in world.bodies:
			if not b.lethal:
				continue
			if TorusMath.swept_hits_circle(s_prev, s.pos, b.pos,
					b.radius + s.radius, config.arena_size):
				if b.kind == SimBody.Kind.ASTEROID and config.shield_max > 0 and s.shields > 0:
					damage_ship(world, s, -1, "asteroid", 1, s.vel * -0.5)
					break_rock(world, b)
				else:
					destroy_ship(world, s, -1, "body")
				break

	# Ships vs ships.
	for i in range(world.ships.size()):
		var a := world.ships[i]
		if not a.alive or a.spawn_grace > 0.0:
			continue
		for j in range(i + 1, world.ships.size()):
			var b := world.ships[j]
			if not b.alive or b.spawn_grace > 0.0:
				continue
			var ship_clearance := a.radius + b.radius
			if TorusMath.distance_squared(a.pos, b.pos, config.arena_size) > ship_clearance * ship_clearance:
				continue
			if a.team == b.team and a.team != -1 and not config.friendly_fire:
				continue
			if config.ship_collision_lethal:
				destroy_ship(world, a, -1, "ram")
				destroy_ship(world, b, -1, "ram")
			else:
				bounce(a, b, config.arena_size)

static func break_rock(world: SimWorld, rock: SimBody) -> void:
	var config := world.config
	var rng := world.rng
	world.bodies.erase(rock)
	world.removed_body_ids.append(rock.id)
	world.events.append({"tk": world.tick, "type": "rock_break", "pos": rock.pos})
	if rng.randf() < config.pickup_chance:
		var p := SimPickup.new()
		p.id = world.alloc_id()
		p.kind = rng.randi() % SimPickup.Kind.size()
		p.pos = rock.pos
		var ang := rng.randf() * TAU
		p.vel = Vector2(cos(ang), sin(ang)) * rng.randf_range(10.0, 50.0)
		p.ttl = config.pickup_ttl
		p.radius = config.pickup_radius
		world.pickups.append(p)

static func bounce(a: SimShip, b: SimShip, arena_size: float) -> void:
	# Equal-mass elastic bounce along the contact normal.
	var n := TorusMath.shortest_delta(a.pos, b.pos, arena_size)
	if n.length() < 0.0001:
		return
	n = n.normalized()
	var va := a.vel.dot(n)
	var vb := b.vel.dot(n)
	a.vel += n * (vb - va)
	b.vel += n * (va - vb)
	# Separate so they don't stick.
	var overlap := (a.radius + b.radius) - TorusMath.distance(a.pos, b.pos, arena_size)
	if overlap > 0.0:
		a.pos -= n * overlap * 0.5
		b.pos += n * overlap * 0.5

static func damage_ship(world: SimWorld, s: SimShip, killer_id: int, cause: String, damage: int = 1, impulse_vel: Vector2 = Vector2.ZERO) -> void:
	if not s.alive or s.spawn_grace > 0.0:
		return
	if s.frozen or s.invulnerable:
		return
	if world.config.shield_max > 0 and s.shields > 0:
		s.shields = maxi(0, s.shields - damage)
		s.shield_timer = 0.0
		if impulse_vel.length_squared() > 1.0:
			s.vel += impulse_vel.normalized() * 120.0
		world.events.append({
			"tk": world.tick,
			"type": "shield_hit",
			"ship": s.id,
			"pos": s.pos,
			"killer": killer_id,
			"remaining": s.shields,
			"cause": cause
		})
		return
	destroy_ship(world, s, killer_id, cause)

static func destroy_ship(world: SimWorld, s: SimShip, killer_id: int, cause: String) -> void:
	if not s.alive:
		return
	if s.frozen or s.invulnerable:
		return  # DEBUG: frozen (parked) or immortal — can't be killed
	s.alive = false
	s.deaths += 1
	s.respawn_timer = world.config.respawn_time
	world.events.append({"tk": world.tick, "type": "explosion", "ship": s.id, "pos": s.pos, "vel": s.vel, "cause": cause, "killer": killer_id})
	if killer_id >= 0 and killer_id != s.id:
		var killer := world.ship_by_id(killer_id)
		if killer != null:
			killer.kills += 1
			killer.score += 1
			world.events.append({"tk": world.tick, "type": "kill", "killer": killer_id, "victim": s.id})
			# Salvage drop from destroyed enemy ship
			if world.config.pickup_chance > 0.0 and world.rng.randf() < 0.60:
				var p := SimPickup.new()
				p.id = world.alloc_id()
				p.kind = world.rng.randi() % SimPickup.Kind.size()
				p.pos = s.pos
				var ang := world.rng.randf() * TAU
				p.vel = s.vel * 0.3 + Vector2(cos(ang), sin(ang)) * world.rng.randf_range(15.0, 45.0)
				p.ttl = world.config.pickup_ttl * 1.5
				p.radius = world.config.pickup_radius * 1.1
				world.pickups.append(p)
	elif cause == "torpedo" or cause == "hyperspace" or cause == "mine":
		s.score -= 1  # suicide / self-destruct penalty

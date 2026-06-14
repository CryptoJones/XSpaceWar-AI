class_name SpawnSystem
## Ship spawning/respawn, per-ship pilot input, firing, and hyperspace for the
## deterministic sim.
##
## Stateless: operates on a passed-in SimWorld. Extracted from SimWorld (issue
## #18); RNG draw order (spawn angle jitter, clearance re-rolls, orbit
## direction, hyperspace risk) is unchanged so the sim stays deterministic.

static func place_in_orbit(world: SimWorld, s: SimShip) -> void:
	var config := world.config
	var rng := world.rng
	var center := Vector2.ZERO
	var m := 0.0
	var primary := world.primary_body()
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
		r = maxf(r, primary.radius * 3.0 + 200.0)
	r = minf(r, config.arena_size * 0.5 * 0.85)
	# Clearance: never materialize inside (or kissing) a rock/satellite —
	# re-roll the ring angle a few times; deterministic via the world rng.
	for _attempt in range(10):
		var probe := center + Vector2(cos(ang), sin(ang)) * r
		var blocked := false
		for b in world.bodies:
			if b.lethal and probe.distance_to(b.pos) < b.radius + s.radius + 60.0:
				blocked = true
				break
		if not blocked:
			break
		ang = rng.randf() * TAU
	s.pos = center + Vector2(cos(ang), sin(ang)) * r
	# Circular-orbit speed, perpendicular to the radius, random direction.
	var speed := 0.0
	if m > 0.0:
		# True circular-orbit speed (Keplerian, pure 1/r^2): a still pilot
		# orbits a stable closed ellipse forever.
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

static func step_ship(world: SimWorld, s: SimShip, dt: float) -> void:
	var config := world.config
	if not s.alive:
		# Lives mode: out of lives means out of the match — no respawn.
		if config.lives > 0 and s.deaths >= config.lives:
			s.clear_inputs()
			return
		s.respawn_timer -= dt
		if s.respawn_timer <= 0.0:
			place_in_orbit(world, s)
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

	# Thrust (fuel-limited). Integration of velocity happens in
	# GravitySystem.integrate_ships alongside gravity; here we just apply the
	# thrust impulse and burn fuel.
	if s.in_thrust and s.fuel > 0.0:
		s.vel += s.facing() * config.thrust_accel * dt
		s.fuel = maxf(0.0, s.fuel - config.thrust_fuel_per_sec * dt)
		world.events.append({"tk": world.tick, "type": "thrust", "ship": s.id, "pos": s.pos})
	else:
		s.fuel = minf(config.max_fuel, s.fuel + config.fuel_regen_per_sec * dt)

	# Fire.
	if s.in_fire and s.fire_cooldown <= 0.0 and s.ammo > 0:
		fire_torpedo(world, s)

	# Drop a mine behind us.
	if s.in_mine and s.mine_cooldown <= 0.0 and s.mines > 0:
		MineSystem.drop_mine(world, s)

	# Hyperspace.
	if s.in_hyper and s.hyperspace_cooldown <= 0.0:
		hyperspace(world, s)

	s.clear_inputs()

static func fire_torpedo(world: SimWorld, s: SimShip) -> void:
	var config := world.config
	var t := SimTorpedo.new()
	t.id = world.alloc_id()
	t.owner_id = s.id
	t.team = s.team
	t.radius = config.torpedo_radius
	var fwd := s.facing()
	t.pos = s.pos + fwd * (s.radius + t.radius + 2.0)
	t.vel = s.vel + fwd * config.torpedo_speed
	t.life = config.torpedo_life
	world.torpedoes.append(t)
	s.ammo -= 1
	s.fire_cooldown = config.fire_cooldown
	world.events.append({"tk": world.tick, "type": "fire", "ship": s.id, "pos": t.pos})

static func hyperspace(world: SimWorld, s: SimShip) -> void:
	var config := world.config
	s.hyperspace_uses += 1
	s.hyperspace_cooldown = config.hyperspace_cooldown
	world.events.append({"tk": world.tick, "type": "hyperspace", "ship": s.id, "pos": s.pos})
	var risk := config.hyperspace_base_risk + config.hyperspace_risk_per_use * float(s.hyperspace_uses - 1)
	if world.rng.randf() < risk:
		CollisionSystem.destroy_ship(world, s, -1, "hyperspace")
		return
	# place_in_orbit is a SPAWN helper (full resupply + grace); a jump is
	# just a relocation — keep the pilot's resources and grant no shield.
	var keep := [s.fuel, s.ammo, s.ammo_timer, s.mines, s.mine_timer,
		s.mine_cooldown, s.fire_cooldown]
	place_in_orbit(world, s)
	s.fuel = keep[0]
	s.ammo = keep[1]
	s.ammo_timer = keep[2]
	s.mines = keep[3]
	s.mine_timer = keep[4]
	s.mine_cooldown = keep[5]
	s.fire_cooldown = keep[6]
	s.spawn_grace = 0.0

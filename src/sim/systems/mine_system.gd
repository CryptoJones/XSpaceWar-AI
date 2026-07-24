class_name MineSystem
## Mine lifecycle, dropping, detonation, and proximity fusing for the
## deterministic sim.
##
## Stateless: operates on a passed-in SimWorld. Extracted from SimWorld (issue
## #18). Detonation order and the torpedo/ship scans are unchanged.

static func step_mines(world: SimWorld, dt: float) -> void:
	var config := world.config
	var survivors: Array[SimMine] = []
	for m in world.mines:
		m.age += dt
		# A configured lifetime fizzles the mine; the default 25s still applies,
		# but mine_life == 0 means it lingers forever (matches torpedo_life).
		if config.mine_life > 0.0:
			m.life -= dt
			if m.life <= 0.0:
				continue
		m.vel += GravitySystem.accel(world, m.pos) * dt
		m.pos += m.vel * dt
		if config.wrap_edges:
			var wb_m := WrapSystem.wrap_with_boost(world, m.pos, m.vel)
			if not wb_m.is_empty():
				m.pos = wb_m[0]
				m.vel = wb_m[1]
		survivors.append(m)
	world.mines = survivors

static func drop_mine(world: SimWorld, s: SimShip) -> void:
	var config := world.config
	var m := SimMine.new()
	m.id = world.alloc_id()
	m.owner_id = s.id
	m.team = s.team
	m.radius = config.mine_radius
	m.pos = s.pos - s.facing() * (s.radius + m.radius + 6.0)
	m.vel = s.vel * 0.85  # sheds a little speed so it falls behind
	m.life = config.mine_life
	world.mines.append(m)
	s.mines -= 1
	s.mine_cooldown = config.mine_drop_cooldown
	world.events.append({"tk": world.tick, "type": "mine", "ship": s.id, "pos": m.pos})

static func resolve_mines(world: SimWorld) -> void:
	var config := world.config
	var survivors: Array[SimMine] = []
	for m in world.mines:
		var exploded := false
		# Consumed (detonated) by lethal bodies.
		for b in world.bodies:
			var body_clearance := b.radius + m.radius
			if b.lethal and TorusMath.distance_squared(m.pos, b.pos, config.arena_size) <= body_clearance * body_clearance:
				exploded = true
				break
		# Shot by a torpedo — detonates even unarmed. This is the counterplay.
		if not exploded:
			var remaining: Array[SimTorpedo] = []
			for t in world.torpedoes:
				var torp_clearance := m.radius + t.radius + 4.0
				if not exploded and TorusMath.distance_squared(m.pos, t.pos, config.arena_size) <= torp_clearance * torp_clearance:
					exploded = true
					continue  # the torpedo is consumed by the blast
				remaining.append(t)
			world.torpedoes = remaining
		# Proximity fuse once armed. The owner never trips the fuse (but is
		# not safe from the blast itself).
		if not exploded and m.age >= config.mine_arm_time:
			for s in world.ships:
				if not s.alive or s.spawn_grace > 0.0 or s.id == m.owner_id:
					continue
				if s.team == m.team and s.team != -1 and not config.friendly_fire:
					continue
				var trigger_clearance := config.mine_trigger_radius + s.radius
				if TorusMath.distance_squared(m.pos, s.pos, config.arena_size) <= trigger_clearance * trigger_clearance:
					exploded = true
					break
		if exploded:
			explode_mine(world, m)
		else:
			survivors.append(m)
	world.mines = survivors

static func explode_mine(world: SimWorld, m: SimMine) -> void:
	var config := world.config
	world.events.append({"tk": world.tick, "type": "mine_explode", "pos": m.pos})
	for s in world.ships:
		if not s.alive or s.spawn_grace > 0.0:
			continue
		# When friendly fire is off, the blast spares the owner AND teammates;
		# the owner is not safe from their own mine once FF is on.
		if not config.friendly_fire and (s.id == m.owner_id or (s.team == m.team and s.team != -1)):
			continue
		var blast_clearance := config.mine_blast_radius + s.radius
		if TorusMath.distance_squared(m.pos, s.pos, config.arena_size) <= blast_clearance * blast_clearance:
			CollisionSystem.destroy_ship(world, s, m.owner_id if s.id != m.owner_id else -1, "mine")

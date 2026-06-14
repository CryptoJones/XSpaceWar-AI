class_name PickupSystem
## Pickup drift, expiry, collection, and granting for the deterministic sim.
##
## Stateless: operates on a passed-in SimWorld. Extracted from SimWorld (issue
## #18). Pickups are created by CollisionSystem.break_rock; this system steps
## and grants them.

static func step_pickups(world: SimWorld, dt: float) -> void:
	var config := world.config
	var survivors: Array[SimPickup] = []
	for p in world.pickups:
		p.age += dt
		p.ttl -= dt
		if p.ttl <= 0.0:
			continue
		p.vel += GravitySystem.accel(world, p.pos) * dt
		p.pos += p.vel * dt
		if config.wrap_edges:
			var wb_p := WrapSystem.wrap_with_boost(world, p.pos, p.vel)
			if not wb_p.is_empty():
				p.pos = wb_p[0]
				p.vel = wb_p[1]
		var claimed := false
		for s in world.ships:
			if not s.alive:
				continue
			if p.pos.distance_to(s.pos) <= p.radius + s.radius:
				grant_pickup(world, s, p)
				claimed = true
				break
		if not claimed:
			survivors.append(p)
	world.pickups = survivors

static func grant_pickup(world: SimWorld, s: SimShip, p: SimPickup) -> void:
	var config := world.config
	match p.kind:
		SimPickup.Kind.FUEL:
			s.fuel = minf(config.max_fuel, s.fuel + config.pickup_fuel_amount)
		SimPickup.Kind.AMMO:
			s.ammo = mini(config.max_ammo, s.ammo + config.pickup_ammo_amount)
		SimPickup.Kind.MINES:
			s.mines = mini(config.max_mines, s.mines + config.pickup_mines_amount)
	world.events.append({"tk": world.tick, "type": "pickup", "ship": s.id, "kind": p.kind, "pos": p.pos})

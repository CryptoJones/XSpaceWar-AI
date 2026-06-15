class_name GravitySystem
## Inverse-square gravity and symplectic integration for the deterministic sim.
##
## Stateless: every method operates on a passed-in SimWorld. Extracted from the
## SimWorld god-class (issue #18); call order and math are unchanged so the sim
## stays bit-for-bit deterministic.

## Newtonian inverse-square acceleration at point p from every massive body.
static func accel(world: SimWorld, p: Vector2) -> Vector2:
	var config := world.config
	var a := Vector2.ZERO
	for b in world.bodies:
		if not b.gravity or b.mass <= 0.0:
			continue
		var d := b.pos - p
		var r2 := d.length_squared()
		# Softening near the core so the acceleration never blows up.
		var soft := b.radius * 0.5
		r2 = maxf(r2, soft * soft)
		var r := sqrt(r2)
		a += d * (config.gravity_constant * b.mass / (r2 * r))
	return a  # pure Newtonian inverse-square — no caps (star mass is sized
	          # to the arena instead; see GameSession._build / README Physics)

## Advance orbiting bodies along their parent orbit.
static func advance_bodies(world: SimWorld, dt: float) -> void:
	for b in world.bodies:
		if not b.is_orbiting():
			continue
		var parent := world.body_by_id(b.parent_id)
		if parent == null:
			continue
		var prev := b.pos
		b.orbit_angle = wrapf(b.orbit_angle + b.orbit_speed * dt, 0.0, TAU)
		b.pos = parent.pos + Vector2(cos(b.orbit_angle), sin(b.orbit_angle)) * b.orbit_radius
		b.vel = (b.pos - prev) / dt if dt > 0.0 else Vector2.ZERO

## Semi-implicit (symplectic) Euler: velocity from gravity, then position from
## the new velocity. Stable for orbits.
static func integrate_ships(world: SimWorld, dt: float) -> void:
	for s in world.ships:
		if not s.alive:
			continue
		if s.frozen:
			s.vel = Vector2.ZERO   # DEBUG freeze: park in place, ignore gravity
			continue
		s.vel += accel(world, s.pos) * dt
		s.pos += s.vel * dt

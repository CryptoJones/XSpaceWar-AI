class_name WrapSystem
## Toroidal edge wrapping and lethal-edge enforcement for the deterministic sim.
##
## Stateless: operates on a passed-in SimWorld. Extracted from SimWorld (issue
## #18). Wrap math and edge culling are unchanged.

## Wrap-mode bonus (Aaron's rule): crossing the map edge DOUBLES your speed —
## the toroidal seam is a slingshot. Capped well above gameplay speeds so the
## math can't run away into absurdity.
const WRAP_BOOST := 2.0
const WRAP_SPEED_CAP := 20000.0

## Toroidal wrap: position teleports across the seam, velocity is PRESERVED
## (space is a torus — no free energy). Returns [wrapped_pos, vel] or empty.
static func wrap_with_boost(world: SimWorld, pos: Vector2, vel: Vector2) -> Array:
	var wrapped := wrap_point(world, pos)
	if wrapped == pos:
		return []
	return [wrapped, vel]

static func wrap_positions(world: SimWorld) -> void:
	for s in world.ships:
		var wb := wrap_with_boost(world, s.pos, s.vel)
		if not wb.is_empty():
			s.pos = wb[0]
			s.vel = wb[1]
			world.events.append({"tk": world.tick, "type": "wrap", "ship": s.id, "pos": s.pos})

## Lethal-edge mode: the border is a wall of death. Ships crossing it are
## destroyed (environmental, no score penalty — like flying into a rock);
## loose ordnance and cargo simply leave the field.
static func enforce_lethal_edges(world: SimWorld) -> void:
	var config := world.config
	var half := config.arena_size * 0.5
	for s in world.ships:
		if s.alive and (absf(s.pos.x) > half or absf(s.pos.y) > half):
			CollisionSystem.destroy_ship(world, s, -1, "edge")
	var t_keep: Array[SimTorpedo] = []
	for t in world.torpedoes:
		if absf(t.pos.x) <= half and absf(t.pos.y) <= half:
			t_keep.append(t)
	world.torpedoes = t_keep
	var m_keep: Array[SimMine] = []
	for m in world.mines:
		if absf(m.pos.x) <= half and absf(m.pos.y) <= half:
			m_keep.append(m)
	world.mines = m_keep
	var p_keep: Array[SimPickup] = []
	for p in world.pickups:
		if absf(p.pos.x) <= half and absf(p.pos.y) <= half:
			p_keep.append(p)
	world.pickups = p_keep

static func wrap_point(world: SimWorld, p: Vector2) -> Vector2:
	var size := world.config.arena_size
	var half := size * 0.5
	if p.x > half:
		p.x -= size
	elif p.x < -half:
		p.x += size
	if p.y > half:
		p.y -= size
	elif p.y < -half:
		p.y += size
	return p

class_name TorusMath
extends RefCounted
## Shared shortest-path math for the square toroidal arena.

static func shortest_delta(from: Vector2, to: Vector2, size: float) -> Vector2:
	var d := to - from
	if size <= 0.0:
		return d
	var half := size * 0.5
	if d.x > half:
		d.x -= size
	elif d.x < -half:
		d.x += size
	if d.y > half:
		d.y -= size
	elif d.y < -half:
		d.y += size
	return d

static func distance_squared(a: Vector2, b: Vector2, size: float) -> float:
	return shortest_delta(a, b, size).length_squared()

static func distance(a: Vector2, b: Vector2, size: float) -> float:
	return sqrt(distance_squared(a, b, size))

static func wrap_point(p: Vector2, size: float) -> Vector2:
	if size <= 0.0:
		return p
	var half := size * 0.5
	return Vector2(fposmod(p.x + half, size) - half,
		fposmod(p.y + half, size) - half)

## Test a moving point against a circle while respecting seam crossings.
static func swept_hits_circle(p0: Vector2, p1: Vector2, center: Vector2,
		radius: float, size: float) -> bool:
	var local0 := shortest_delta(center, p0, size)
	var local1 := local0 + shortest_delta(p0, p1, size)
	var d := local1 - local0
	var len_sq := d.length_squared()
	if len_sq < 0.000001:
		return local0.length_squared() <= radius * radius
	var t := clampf(-local0.dot(d) / len_sq, 0.0, 1.0)
	return (local0 + d * t).length_squared() <= radius * radius

static func swept_hits_moving_circle(p0: Vector2, p1: Vector2, c0: Vector2,
		c1: Vector2, radius: float, size: float) -> bool:
	var local0 := shortest_delta(c0, p0, size)
	var d := shortest_delta(p0, p1, size) - shortest_delta(c0, c1, size)
	var len_sq := d.length_squared()
	if len_sq < 0.000001:
		return local0.length_squared() <= radius * radius
	var t := clampf(-local0.dot(d) / len_sq, 0.0, 1.0)
	return (local0 + d * t).length_squared() <= radius * radius

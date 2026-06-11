class_name SimPickup
extends RefCounted
## A supply drop knocked loose from a destroyed asteroid. Drifts under
## gravity, expires if unclaimed, and grants its cargo to the first ship
## that touches it.

enum Kind { FUEL, AMMO, MINES }

var id: int = -1
var kind: int = Kind.FUEL
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var age: float = 0.0
var ttl: float = 20.0
var radius: float = 10.0

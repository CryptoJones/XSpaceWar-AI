class_name SimTorpedo
extends RefCounted
## A torpedo (missile) in flight. Subject to gravity like ships (modern
## accuracy), deactivates after a fixed lifetime, and is destroyed on impact.

var id: int = -1
var owner_id: int = -1
var team: int = -1
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var life: float = 0.0                   ## seconds remaining
var age: float = 0.0                    ## seconds alive (used for self-hit grace)
var radius: float = 4.0

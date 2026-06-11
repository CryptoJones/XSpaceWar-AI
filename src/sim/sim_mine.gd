class_name SimMine
extends RefCounted
## A proximity mine. Dropped behind a ship with most of its velocity, it
## coasts under gravity (orbiting minefields are a feature, not a bug), arms
## after a short delay, and detonates when a ship strays into its trigger
## radius — or instantly when shot by a torpedo, which is the counterplay.
## The owner never trips the fuse but is NOT safe from the blast.

var id: int = -1
var owner_id: int = -1
var team: int = -1
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var age: float = 0.0                    ## seconds since drop (arms past arm_time)
var life: float = 0.0                   ## seconds remaining before fizzle
var radius: float = 6.0                 ## physical size (torpedo/body contact)

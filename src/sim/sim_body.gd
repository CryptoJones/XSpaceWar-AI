class_name SimBody
extends RefCounted
## A celestial body: star, planet, moon/satellite, or asteroid.
##
## Bodies are gravity sources and/or collision hazards. Orbiting bodies move
## kinematically on fixed circular paths (deterministic and fair) rather than
## via full N-body integration, while still exerting gravity on ships and
## torpedoes.

enum Kind { STAR, PLANET, MOON, ASTEROID, SATELLITE }

var id: int = -1
var kind: int = Kind.STAR
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO         ## derived from orbit each step (for lead-aiming/AI)
var mass: float = 0.0
var radius: float = 64.0
var gravity: bool = true                ## contributes gravitational pull
var lethal: bool = true                 ## contact destroys ships
var seed: int = 0                       ## per-body seed for procedural rendering

# --- Orbit (kinematic). parent_id < 0 means a fixed body. ---
var parent_id: int = -1
var orbit_radius: float = 0.0
var orbit_angle: float = 0.0            ## current angle (radians)
var orbit_speed: float = 0.0            ## radians / second (sign = direction)

func is_orbiting() -> bool:
	return parent_id >= 0 and orbit_radius > 0.0

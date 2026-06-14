class_name BotBehaviors
## Priority-ordered steering behaviors for BotController, extracted from the
## _decide() priority chain (issue #21).
##
## Evaluated in order with EARLY-EXIT — deliberately NOT utility scoring. The
## chain's RNG draws are CONDITIONAL (the chase roll fires only when a target
## exists; the approach-thrust roll only when out of range), so scoring every
## behavior each tick would change RNG consumption and break determinism.
##
## Each behavior's decide(bot, ship, ctx) returns true to CLAIM the decision
## (setting bot._want_angle / bot._want_thrust) or false to defer to the next.
## ctx carries the per-tick reads {primary, star_pos, star_r, dist_star, aggr,
## target} so behaviors don't recompute them. (bot/ship are left untyped to
## avoid a cyclic class dependency with BotController.)

## 0.5) Lethal boundary: never fly off the map — burn back toward the well.
class Boundary extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		if not bot.world.config.lethal_edges:
			return false
		var half: float = bot.world.config.arena_size * 0.5
		var ahead: Vector2 = ship.pos + ship.vel * 1.5
		if absf(ahead.x) > half - 300.0 or absf(ahead.y) > half - 300.0:
			bot._want_angle = (ctx["star_pos"] - ship.pos).angle()
			bot._want_thrust = true
			return true
		return false

## 1) Survival: Veteran+ pilots dodge an imminent body or armed mine.
class HazardDodge extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		if bot.difficulty < BotController.Difficulty.VETERAN:
			return false
		var hz_pos := Vector2.INF
		var hazard = bot._imminent_hazard(ship)
		if hazard != null:
			hz_pos = hazard.pos
		else:
			var mz = bot._imminent_mine(ship)
			if mz != null:
				hz_pos = mz.pos
		if hz_pos.is_finite():
			var lateral := Vector2(-ship.vel.y, ship.vel.x).normalized()
			if lateral.dot(hz_pos - ship.pos) > 0.0:
				lateral = -lateral
			bot._want_angle = lateral.angle()
			bot._want_thrust = true
			return true
		return false

## 1) Survival: everyone burns away from the star's kill zone.
class StarEscape extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		if float(ctx["dist_star"]) < float(ctx["star_r"]) + 260.0:
			bot._want_angle = (ship.pos - ctx["star_pos"]).angle()
			bot._want_thrust = true
			return true
		return false

## 1.6) Fear: timid pilots flee nearby ships (snapping shots via _apply).
class Fear extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		if target != null:
			var dist_t: float = ship.pos.distance_to(target.pos)
			var flee_r := lerpf(1500.0, 0.0, float(ctx["aggr"]))
			if dist_t < flee_r:
				bot._want_angle = (ship.pos - target.pos).angle() + bot._aim_noise
				bot._want_thrust = true
				return true
		return false

## 1.7) Logistics: detour to a nearby supply drop when not already engaged.
class Logistics extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		if target == null or ship.pos.distance_to(target.pos) > bot._fire_range:
			var want_pickup = bot._wanted_pickup(ship)
			if want_pickup != null:
				var lead: Vector2 = want_pickup.pos + want_pickup.vel * 0.4 - ship.pos
				bot._want_angle = lead.angle()
				bot._want_thrust = true
				return true
		return false

## 1.8) Patrol the preferred ring unless we roll to chase. The chase roll
## consumes RNG ONLY when a target exists (short-circuit preserved exactly).
class Patrol extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		var chase: bool = target != null and bot._rng.randf() < maxf(0.12, float(ctx["aggr"]))
		if target == null or not chase:
			var want_r: float = bot._roam_radius(float(ctx["star_r"]))
			var dist_now := maxf(1.0, float(ctx["dist_star"]))
			if absf(dist_now - want_r) > 280.0:
				var dir: Vector2 = (ship.pos - ctx["star_pos"]) / dist_now
				var ring_point: Vector2 = ctx["star_pos"] + dir.rotated(0.55) * want_r
				bot._want_angle = (ring_point - ship.pos).angle()
				bot._want_thrust = true
			else:
				bot._want_angle = ship.vel.angle()
				bot._want_thrust = ship.vel.length() < 120.0
			return true
		return false  # chasing — RNG already drawn; defer to LeadAimRange

## 2-3) Terminal: lead-aim the target with range/slingshot management. Only
## reached when Patrol deferred (target != null and chase succeeded).
class LeadAimRange extends RefCounted:
	func decide(bot, ship, ctx) -> bool:
		var target = ctx["target"]
		var rel: Vector2 = target.pos - ship.pos
		var aim := Vector2.from_angle(bot._lead_angle(ship, target))
		bot._want_angle = aim.angle() + bot._aim_noise
		var dist := rel.length()
		if bot._sling > 0.0 and dist > bot._preferred_range * 1.7 and ctx["primary"] != null:
			var blended := aim.normalized().lerp((ctx["star_pos"] - ship.pos).normalized(), bot._sling)
			bot._want_angle = blended.angle() + bot._aim_noise
		# Approach-thrust roll consumes RNG ONLY when out of range (short-circuit).
		bot._want_thrust = dist > bot._preferred_range and bot._rng.randf() < maxf(0.15, float(ctx["aggr"]))
		return true

## Build the cascade in priority order (one instance set per bot).
static func make_cascade() -> Array:
	return [Boundary.new(), HazardDodge.new(), StarEscape.new(), Fear.new(),
		Logistics.new(), Patrol.new(), LeadAimRange.new()]

extends SceneTree
## Tests for the host-side aim-anomaly heuristics (AimAnalyzer, issue #4).
## Drives a tiny two-ship world by hand and feeds the analyzer fire events,
## asserting that an inhuman shooter trips a flag, a sloppy human does not, and
## aim that follows a target through the wrap seam is caught.
##
## Run with:
##   godot --headless --path . --script res://tests/aim_tests.gd

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — aim-anomaly tests ===")
	_test_aimbot_flagged()
	_test_human_not_flagged()
	_test_seam_tracking_flagged()
	_test_forget_and_reset()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

## A minimal FFA world with two opposing ships at fixed spots.
func _two_ship_world(wrap := true) -> SimWorld:
	var cfg := SimConfig.from_seed(1)
	cfg.arena_size = 40000.0
	cfg.wrap_edges = wrap
	var w := SimWorld.new(cfg)
	w.ships.clear()
	var a := SimShip.new()
	a.id = 1; a.team = -1; a.alive = true; a.radius = 10.0; a.pos = Vector2(100, 100)
	var b := SimShip.new()
	b.id = 2; b.team = -1; b.alive = true; b.radius = 10.0; b.pos = Vector2(600, 100)
	w.ships.append(a)
	w.ships.append(b)
	w.tick = 0
	return w

func _bearing(from: Vector2, to: Vector2, size: float, wrap: bool) -> float:
	var d := to - from
	if wrap:
		if absf(d.x) > size * 0.5: d.x -= signf(d.x) * size
		if absf(d.y) > size * 0.5: d.y -= signf(d.y) * size
	return d.angle()

func _has_reason(report: Array, sid: int, needle: String) -> bool:
	for r in report:
		if int(r["sid"]) == sid:
			for why in r["reasons"]:
				if needle in String(why):
					return true
	return false

## A locked-on shooter: aim exactly at the enemy every tick, fire every tick.
func _test_aimbot_flagged() -> void:
	var w := _two_ship_world()
	var a := w.ship_by_id(1)
	var b := w.ship_by_id(2)
	var az := AimAnalyzer.new()
	for i in range(40):
		w.tick += 1
		b.pos += Vector2(3, 1)                       # the target maneuvers
		a.angle = _bearing(a.pos, b.pos, w.config.arena_size, w.config.wrap_edges)
		w.events.append({"tk": w.tick - 1, "type": "fire", "ship": a.id, "pos": a.pos})
		az.observe(w, [a.id])
	var rep := az.report()
	_check("aimbot: shooter is flagged", az.is_flagged(1),
		"reasons=%s" % str(az.reasons_for(1)))
	_check("aimbot: flagged for inhuman aim", _has_reason(rep, 1, "inhuman aim"))
	var entry := {}
	for r in rep:
		if int(r["sid"]) == 1: entry = r
	_check("aimbot: counted the shots", int(entry.get("shots", 0)) >= 20,
		"shots=%d" % int(entry.get("shots", 0)))
	_check("aimbot: aim mean is tiny", float(entry.get("aim_mean_deg", 99.0)) < 1.0,
		"mean=%.2f deg" % float(entry.get("aim_mean_deg", 99.0)))

## A sloppy-but-steady human: ~8 degrees off (in the cone, not tight), and only
## firing well after acquiring — no heuristic should trip.
func _test_human_not_flagged() -> void:
	var w := _two_ship_world()
	var a := w.ship_by_id(1)
	var b := w.ship_by_id(2)
	var az := AimAnalyzer.new()
	for i in range(60):
		w.tick += 1
		b.pos += Vector2(2, 0)
		var aim := _bearing(a.pos, b.pos, w.config.arena_size, w.config.wrap_edges)
		a.angle = aim + deg_to_rad(8.0)              # steady human offset
		if i >= 30:                                  # fire only after warmup
			w.events.append({"tk": w.tick - 1, "type": "fire", "ship": a.id, "pos": a.pos})
		az.observe(w, [a.id])
	_check("human: steady 8-degree shooter is NOT flagged", not az.is_flagged(1),
		"reasons=%s" % str(az.reasons_for(1)))
	# Sanity: it DID record shots — the absence of a flag isn't because we saw nothing.
	var saw := false
	for r in az.report():
		if int(r["sid"]) == 1 and int(r["shots"]) > 0: saw = true
	_check("human: shots were observed (flag absence is real)", saw)

## Aim that stays glued to a target as it teleports across the wrap edge.
func _test_seam_tracking_flagged() -> void:
	var w := _two_ship_world(true)
	var a := w.ship_by_id(1)
	var b := w.ship_by_id(2)
	var size := w.config.arena_size
	var az := AimAnalyzer.new()
	# Bounce B across the seam each tick; A re-locks to the wrapped bearing.
	var near := Vector2(600, 100)
	var far := Vector2(size - 400.0, 100)
	for i in range(8):
		w.tick += 1
		b.pos = far if i % 2 == 0 else near          # jumps across the seam
		a.angle = _bearing(a.pos, b.pos, size, w.config.wrap_edges)
		az.observe(w, [a.id])
	_check("seam: cross-seam aim lock is flagged", az.is_flagged(1),
		"reasons=%s" % str(az.reasons_for(1)))
	_check("seam: flagged for wrap-seam tracking", _has_reason(az.report(), 1, "wrap seam"))

func _test_forget_and_reset() -> void:
	var w := _two_ship_world()
	var a := w.ship_by_id(1)
	var b := w.ship_by_id(2)
	var az := AimAnalyzer.new()
	for i in range(40):
		w.tick += 1
		a.angle = _bearing(a.pos, b.pos, w.config.arena_size, w.config.wrap_edges)
		w.events.append({"tk": w.tick - 1, "type": "fire", "ship": a.id, "pos": a.pos})
		az.observe(w, [a.id])
	_check("lifecycle: flagged before forget", az.is_flagged(1))
	az.forget(1)
	_check("lifecycle: forget clears the player", not az.is_flagged(1) and az.report().is_empty())
	# Rebuild stats then wipe with reset().
	for i in range(40):
		w.tick += 1
		a.angle = _bearing(a.pos, b.pos, w.config.arena_size, w.config.wrap_edges)
		w.events.append({"tk": w.tick - 1, "type": "fire", "ship": a.id, "pos": a.pos})
		az.observe(w, [a.id])
	az.reset()
	_check("lifecycle: reset wipes everything", az.report().is_empty())

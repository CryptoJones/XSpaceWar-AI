extends SceneTree
## Headless smoke test: boot the real main scene (menu over Movie Mode attract)
## and run it for a few hundred frames to prove the renderer, HUD, and session
## wiring load and tick without script errors.
##
## Run with:
##   godot --headless --path . --script res://tests/scene_smoke.gd

const FRAMES := 300

var _frames := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — scene smoke test ===")
	var packed: PackedScene = load("res://src/ui/main.tscn")
	if packed == null:
		print("  [FAIL] res://src/ui/main.tscn failed to load")
		quit(1)
		return
	var node := packed.instantiate()
	if node == null:
		print("  [FAIL] main.tscn failed to instantiate")
		quit(1)
		return
	root.add_child(node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	if _frames == FRAMES:
		var main := root.get_node_or_null("Main")
		var ok: bool = main != null and main.session != null and main.session.world != null \
			and main.session.world.tick > 0
		if ok:
			print("  [PASS] main scene ran %d frames headless (sim tick=%d, ships=%d)"
				% [_frames, main.session.world.tick, main.session.world.ships.size()])
			quit(0)
		else:
			print("  [FAIL] scene ran but the simulation did not advance")
			quit(1)

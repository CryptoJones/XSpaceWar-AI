extends SceneTree
## Camera-follow regression probe: boot the real game, start a skirmish, and
## hammer it with hyperspace jumps, menu toggles, deaths, and a match restart
## while asserting the camera never loses the player's ship for more than a
## brief pan (4s of sustained separation = failure).
##
## Run with:
##   godot --headless --path . --script res://tests/camera_probe.gd

const FRAMES := 4200
const MAX_LOST_FRAMES := 240   # 4s of camera >3000u from the live ship

var _frames := 0
var _lost := 0
var _worst_lost := 0
var _failed := false

func _initialize() -> void:
	print("=== XSpaceWar-AI — camera follow probe ===")
	var packed: PackedScene = load("res://src/ui/main.tscn")
	root.add_child(packed.instantiate())
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	var main := root.get_node_or_null("Main")
	if main == null:
		return
	if _frames == 5:
		main._end_credits()
		main._dismiss_splash()
		main._limit_spin.value = 3  # force a mid-probe match restart
		main._on_play_pressed()
		return
	if _frames < 10:
		return

	var session: GameSession = main.session
	var view: WorldView = main.view
	if session.world == null:
		return
	# Menu toggles (pause/unpause churn).
	if _frames % 700 == 0:
		main.set_menu_visible(true)
	elif _frames % 700 == 60:
		main.set_menu_visible(false)
	var human := session.human_ship()
	if human != null and human.alive:
		# Scripted chaos: thrust hard, spam hyperspace periodically.
		human.in_thrust = (_frames % 4) != 0
		human.in_turn = 1.0 if (_frames / 90) % 2 == 0 else -1.0
		if _frames % 600 == 300:
			human.in_hyper = true
	if human != null:
		var d := view._camera.position.distance_to(human.pos)
		if d > 3000.0:
			_lost += 1
			_worst_lost = maxi(_worst_lost, _lost)
			if _lost > MAX_LOST_FRAMES:
				_failed = true
				print("  [FAIL] camera lost the ship for >4s (d=%.0f ship=%s cam=%s gen=%d)"
					% [d, human.pos, view._camera.position, session.generation])
				quit(1)
				return
		else:
			_lost = 0

	if _frames >= FRAMES:
		print("  [PASS] camera stayed on the ship across %d frames (worst pan: %d frames)"
			% [_frames, _worst_lost])
		quit(0)

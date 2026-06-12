extends SceneTree
## Camera-follow regression probe: boot the real game, start a skirmish, and
## hammer it with hyperspace jumps, menu toggles, deaths, and a match restart
## while asserting the camera never loses the player's ship for more than a
## brief pan (4s of sustained separation = failure).
##
## Run with:
##   godot --headless --path . --script res://tests/camera_probe.gd

const FRAMES := 4200
const MAX_LOST_FRAMES := 20    # ship off the visible screen for ⅓s = failure

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
		main._limit_slider.value = 3  # force a mid-probe match restart
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
		# Alternate sustained straight burns (the camera-outrunning case that
		# bit Aaron) with turning chaos and hyperspace spam.
		var burning := (_frames / 600) % 2 == 0
		human.in_thrust = true if burning else (_frames % 4) != 0
		human.in_turn = 0.0 if burning else (1.0 if (_frames / 90) % 2 == 0 else -1.0)
		if _frames % 1100 == 550:
			human.in_hyper = true
	if human != null and human.alive:
		# THE invariant: a LIVING ship must stay INSIDE the visible screen.
		# (While dead the camera intentionally leaves the wreck — killcam
		# rides the killer, or holds position until the respawn snaps back.)
		var half_view: Vector2 = main.view.get_viewport_rect().size * 0.5 / main.view._cam_zoom
		var d := (human.pos - view._camera.position).abs()
		if d.x > half_view.x * 1.02 or d.y > half_view.y * 1.02:
			_lost += 1
			_worst_lost = maxi(_worst_lost, _lost)
			if _lost > MAX_LOST_FRAMES:
				_failed = true
				print("  [FAIL] ship left the screen for >%d frames (d=%s half_view=%s v=%.0f)"
					% [MAX_LOST_FRAMES, d, half_view, human.vel.length()])
				quit(1)
				return
		else:
			_lost = 0
	elif human != null:
		_lost = 0  # death resets the streak; respawn must re-acquire instantly

	if _frames >= FRAMES:
		print("  [PASS] camera stayed on the ship across %d frames (worst pan: %d frames)"
			% [_frames, _worst_lost])
		quit(0)

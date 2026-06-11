extends SceneTree
## Capture documentation screenshots into docs/ (requires a real display —
## run this on a machine with a desktop, NOT --headless):
##
##   godot --path . --script res://tests/screenshot.gd
##
## Writes: docs/screenshot-menu.png (tabbed menu over the attract),
##         docs/screenshot-gameplay.png (Movie Mode action),
##         docs/screenshot-splash.png (controls splash).

var _frames := 0

func _initialize() -> void:
	var packed: PackedScene = load("res://src/ui/main.tscn")
	root.add_child(packed.instantiate())
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	var main := root.get_node_or_null("Main")
	if main == null:
		return
	if _frames == 30:
		main._end_credits()  # skip the boot roll for the captures
	elif _frames == 150:
		_capture("docs/screenshot-splash.png")
		main._dismiss_splash()
	elif _frames == 240:
		_capture("docs/screenshot-menu.png")
		main.set_menu_visible(false)
	elif _frames == 700:
		_capture("docs/screenshot-gameplay.png")
		quit(0)

func _capture(rel_path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var abs := ProjectSettings.globalize_path("res://" + rel_path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	img.save_png(abs)
	print("saved %s (%dx%d)" % [rel_path, img.get_width(), img.get_height()])

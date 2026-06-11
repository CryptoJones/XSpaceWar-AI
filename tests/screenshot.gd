extends SceneTree
## Visual verification: boot the main scene with a real renderer, capture the
## menu over the Movie Mode attract, then hide the menu and capture pure
## gameplay. Writes PNGs to /tmp.
##
## Run with (needs a working display, NOT --headless):
##   godot --path . --script res://tests/screenshot.gd

var _frames := 0

func _initialize() -> void:
	var packed: PackedScene = load("res://src/ui/main.tscn")
	root.add_child(packed.instantiate())
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	if _frames == 120:
		_capture("/tmp/xspacewar_menu.png")
		var main := root.get_node_or_null("Main")
		if main != null:
			main.set_menu_visible(false)
	elif _frames == 420:
		_capture("/tmp/xspacewar_movie.png")
		quit(0)

func _capture(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " (", img.get_width(), "x", img.get_height(), ")")

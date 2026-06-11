extends SceneTree
var _frames := 0
func _initialize() -> void:
	var packed: PackedScene = load("res://src/ui/main.tscn")
	root.add_child(packed.instantiate())
	process_frame.connect(_on_frame)
func _on_frame() -> void:
	_frames += 1
	if _frames < 10:
		return
	var main := root.get_node_or_null("Main")
	print("UIPROBE hazard_slider=%s value=%s" % [main._hazard_slider != null,
		main._hazard_slider.value if main._hazard_slider != null else -1])
	print("UIPROBE time_spin=%s" % (main._time_spin != null))
	print("UIPROBE radar_visible=%s pos=%s" % [main.hud.radar_visible(),
		main.hud._radar.position])
	quit(0)

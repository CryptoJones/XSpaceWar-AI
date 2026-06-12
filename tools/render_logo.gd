extends SceneTree
## Transparent Steam library logo (issue #1): the Orbitron wordmark only.
## macOS ignores viewport transparent_bg without per-pixel window
## transparency, so this renders the wordmark on near-black, then key it:
##   python3 -c "from PIL import Image; im=Image.open(p).convert(0);
##   ... px[x,y]=(r,g,b,max(r,g,b))"  (alpha = luminance).
var _f := 0
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1840, 560))
	root.transparent_bg = true
	var cl = CanvasLayer.new(); root.add_child(cl)
	var lbl = Label.new()
	lbl.text = "XSpaceWar-AI"
	var fv = FontVariation.new()
	fv.base_font = load("res://assets/fonts/Orbitron.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	lbl.add_theme_font_override("font", fv)
	lbl.add_theme_font_size_override("font_size", 212)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0.06, 0.22, 0.42, 1.0))
	lbl.add_theme_constant_override("outline_size", 18)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.add_child(lbl)
	process_frame.connect(_on_frame)
func _on_frame() -> void:
	_f += 1
	if _f == 10:
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/steam/logo.png"))
		print("saved logo")
		quit(0)

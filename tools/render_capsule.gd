extends SceneTree
## Procedural Steam capsule art (issue #1). Renders the whole set off ONE posed
## scene — two procedural hulls dueling around the glowing star, nebula backdrop,
## Orbitron wordmark — at exact Steam dimensions into docs/steam/.
##
## MUST run on a real GPU: HDR glow (the star bloom + the >1.0 nebula tints) is
## disabled on weak/software GPUs. The dev laptop's NVIDIA card isn't reachable
## as a Vulkan device, so we render on the Mac mini's M2 Pro (Metal):
##   scp tools/render_capsule.gd makemake:<proj>/ ; \
##   sudo launchctl asuser <uid> Godot.app/Contents/MacOS/Godot --path <proj> --script res://tools/render_capsule.gd
## then scp docs/steam/*.png back. Seed 2 is the locked hero backdrop.
var _f := 0
var _main
var _view
var _c := Vector2.ZERO
var _lbl: Label
var _torps := []
# name, render_w, render_h, out_w, out_h, zoom, ship_dx, ship_dy, wm_font(0=none)
const PHASES := [
	["capsule_460x215", 1840, 860, 460, 215, 2.6, 255, 55, 158],
	["library_hero_3840x1240", 3840, 1240, 3840, 1240, 3.0, 370, 65, 0],
	["page_background_1438x810", 2876, 1620, 1438, 810, 2.5, 330, 95, 0],
	["library_capsule_600x900", 1200, 1800, 600, 900, 2.05, 120, 320, 145],
	["small_capsule_231x87", 924, 348, 231, 87, 2.55, 235, 48, 104],
]
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1840, 860))
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)
func _reframe(p: Array) -> void:
	DisplayServer.window_set_size(Vector2i(int(p[1]), int(p[2])))
	var s = _main.session
	var sh = s.world.ships
	var dx = float(p[6]); var dy = float(p[7])
	sh[0].pos = _c + Vector2(-dx, -dy); sh[0].vel = Vector2.ZERO; sh[0].spawn_grace = 0.0
	sh[1].pos = _c + Vector2(dx, dy); sh[1].vel = Vector2.ZERO; sh[1].spawn_grace = 0.0
	sh[0].angle = (sh[1].pos - sh[0].pos).angle()
	sh[1].angle = (sh[0].pos - sh[1].pos).angle()
	for i in range(_torps.size()):
		var a = sh[i]; var b = sh[1 - i]
		_torps[i].pos = a.pos.lerp(b.pos, 0.38)
		_torps[i].vel = (b.pos - a.pos).normalized() * 1100.0
		_torps[i].age = 0.25
	var z = float(p[5])
	_view._cam_pos = _c; _view._cam_pos_prev = _c
	_view._cam_zoom = z; _view._cam_zoom_prev = z
	_view._camera.position = _c; _view._camera.zoom = Vector2(z, z)
	_view._ship_vis_scale = 3.6
	_view._bg_mat.set_shader_parameter("cam", _c)
	_lbl.add_theme_font_size_override("font_size", int(p[8]))
	_lbl.visible = int(p[8]) > 0
	_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lbl.position.y -= int(float(p[2]) * 0.05)
	_view.queue_redraw()
func _capture(p: Array) -> void:
	var img = root.get_viewport().get_texture().get_image()
	if img.get_width() != int(p[3]):
		img.resize(int(p[3]), int(p[4]), Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path("res://docs/steam/%s.png" % p[0]))
	print("saved ", p[0], " ", img.get_width(), "x", img.get_height())
func _on_frame() -> void:
	_f += 1
	if _main == null: return
	if _f == 6:
		_main._end_credits(); _main._dismiss_splash(); _main.set_menu_visible(false)
		_main.hud.visible = false
		_view = _main.view
		var s = _main.session
		s.hazard = 0.0; s.planet_count = 0; s.star_scale = 0.7; s.map_size = 40000.0
		_view.set_background_prefs(1.0, 1.1, true)
		var bg = _view._bg_mat
		bg.set_shader_parameter("tint_a", Vector3(0.35, 0.65, 1.8))
		bg.set_shader_parameter("tint_b", Vector3(1.6, 0.45, 1.15))
		bg.set_shader_parameter("seed", 2.0)
		s.start_skirmish(2, GameSession.Mode.FFA, BotController.Difficulty.VETERAN)
		s.human_ship_id = -1
		_c = s.world.primary_body().pos
		var cfg = s.world.config
		for i in range(2):
			var t = SimTorpedo.new()
			t.id = 9000 + i; t.team = -1; t.life = cfg.torpedo_life; t.radius = cfg.torpedo_radius
			t.owner_id = s.world.ships[i].id
			s.world.torpedoes.append(t); _torps.append(t)
		var cl = CanvasLayer.new(); cl.layer = 60; root.add_child(cl)
		_lbl = Label.new()
		_lbl.text = "XSpaceWar-AI"
		_lbl.add_theme_font_override("font", _main._get_title_font())
		_lbl.add_theme_color_override("font_color", Color(0.78, 0.95, 1.0))
		_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.09, 0.18, 0.95))
		_lbl.add_theme_constant_override("outline_size", 16)
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.add_child(_lbl)
		_view.set_physics_process(false)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/steam"))
	# Phase scheduling: reframe at 8+i*16, capture 12 frames later.
	if _f >= 8:
		var i = (_f - 8) / 16
		var k = (_f - 8) % 16
		if i < PHASES.size():
			if k == 0: _reframe(PHASES[i])
			elif k == 12: _capture(PHASES[i])
		else:
			quit(0)

extends SceneTree
## Procedural 1920x1080 gameplay screenshots (issue #1). Poses a frozen
## combat tableau around the star (camera locked, HUD on via a live human
## ship) and captures several framings into docs/steam/screenshot-N.png.
## Run on a real GPU (Mac mini M2 Pro) for HDR glow — see render_capsule.gd.
var _f := 0
var _main
var _view
var _c := Vector2.ZERO
# cluster_scale, zoom  — tight dogfight / balanced / wide gravity well / medium
const SCENES := [[0.75, 1.25], [1.0, 1.0], [1.7, 0.6], [1.15, 0.85], [0.6, 1.55]]
const OFFS := [Vector2(70,-30), Vector2(-360,150), Vector2(320,250), Vector2(-220,-300),
	Vector2(470,-120), Vector2(-500,-40), Vector2(170,400), Vector2(-130,300)]
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)
func _pose(scn: Array) -> void:
	var s = _main.session
	var sh = s.world.ships
	var scale = float(scn[0])
	for i in range(min(sh.size(), OFFS.size())):
		sh[i].pos = _c + OFFS[i] * scale
		sh[i].vel = Vector2.ZERO
		sh[i].spawn_grace = 0.0
		sh[i].alive = true
	for i in range(sh.size()):
		var nearest = _c
		var bd = 1e20
		for j in range(sh.size()):
			if i == j: continue
			var d = sh[i].pos.distance_squared_to(sh[j].pos)
			if d < bd: bd = d; nearest = sh[j].pos
		sh[i].angle = (nearest - sh[i].pos).angle()
	s.world.torpedoes.clear()
	var cfg = s.world.config
	var tid = 5000
	for i in range(sh.size()):
		var t = SimTorpedo.new()
		t.id = tid; tid += 1; t.owner_id = sh[i].id; t.team = -1
		t.pos = sh[i].pos + Vector2(cfg.ship_radius * 2.2, 0).rotated(sh[i].angle)
		t.vel = Vector2(900, 0).rotated(sh[i].angle)
		t.age = 0.4; t.life = cfg.torpedo_life; t.radius = cfg.torpedo_radius
		s.world.torpedoes.append(t)
	var z = float(scn[1])
	_view._cam_pos = _c; _view._cam_pos_prev = _c
	_view._cam_zoom = z; _view._cam_zoom_prev = z
	_view._camera.position = _c; _view._camera.zoom = Vector2(z, z)
	_view._ship_vis_scale = clampf(1.6 * maxf(1.0, 0.55 / z), 1.6, 3.2)
	_view._bg_mat.set_shader_parameter("cam", _c)
	_view.queue_redraw()
func _on_frame() -> void:
	_f += 1
	if _main == null: return
	if _f == 6:
		_main._end_credits(); _main._dismiss_splash(); _main.set_menu_visible(false)
		var s = _main.session
		s.score_limit = 0; s.time_limit = 0.0; s.hazard = 0.25; s.star_scale = 1.2
		s.planet_count = 0; s.map_size = 12000.0
		_view = _main.view
		_view.set_background_prefs(0.65, 0.9, true)
		_view._bg_mat.set_shader_parameter("seed", 2.0)
		_view._bg_mat.set_shader_parameter("tint_a", Vector3(0.25, 0.45, 1.3))
		_view._bg_mat.set_shader_parameter("tint_b", Vector3(1.2, 0.35, 0.8))
		s.start_skirmish(8, GameSession.Mode.FFA, BotController.Difficulty.ACE)
		# keep the human ship -> HUD bars; give it some score for the board
		_c = s.world.primary_body().pos
		for sh in s.world.ships:
			sh.score = randi() % 7; sh.kills = randi() % 5
		_view.set_physics_process(false)   # freeze the pose
	if _f >= 10:
		var i = (_f - 10) / 14
		var k = (_f - 10) % 14
		if i < SCENES.size():
			if k == 0: _pose(SCENES[i])
			elif k == 2: _view.queue_redraw()
			elif k == 10:
				_main.hud._banner.visible = false
				root.get_viewport().get_texture().get_image().save_png(
					ProjectSettings.globalize_path("res://docs/steam/screenshot-%d.png" % (i + 1)))
				print("saved screenshot-%d" % (i + 1))
		else:
			quit(0)
	if _f > 6:
		_main.hud._banner.visible = false

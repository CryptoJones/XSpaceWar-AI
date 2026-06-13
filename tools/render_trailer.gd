extends SceneTree
## Cinematic Steam trailer (issue #1): 20 INSANE ships brawling around the
## star, camera locked on the star with a slow push-in, nebula maxed /
## stars ~5%, no HUD. Render on a real GPU (Mac mini M2 Pro) with Movie
## Maker, then transcode + mux an original score:
##   Godot --write-movie trailer.avi --quit-after 1620 --path . --script res://tools/render_trailer.gd
##   ffmpeg -ss .15 -i trailer.avi -i score.m4a -c:v libx264 -crf 19 -c:a aac -shortest out.mp4
## Score: original ElevenLabs Music track (cinematic sci-fi war), NOT the
## copyrighted Expanse soundtrack — just the vibe.
var _main
var _view
var _c := Vector2.ZERO
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)
func _on_frame() -> void:
	_f += 1
	if _main == null: return
	if _f == 3:
		_main._end_credits(); _main._dismiss_splash(); _main.set_menu_visible(false)
		_main.hud.visible = false
		var s = _main.session
		s.score_limit = 0; s.time_limit = 0.0; s.lives = 0; s.respawn_seconds = 1.5
		s.hazard = 0.3; s.star_scale = 1.0; s.planet_count = 0; s.map_size = 4200.0
		_view = _main.view
		_view.set_background_prefs(1.0, 0.08, true)        # nebula MAX, stars ~5%
		_view._bg_mat.set_shader_parameter("seed", 2.0)
		_view._bg_mat.set_shader_parameter("tint_a", Vector3(0.32, 0.58, 1.7))
		_view._bg_mat.set_shader_parameter("tint_b", Vector3(1.6, 0.42, 1.05))
		s.start_skirmish(20, GameSession.Mode.FFA, BotController.Difficulty.INSANE)
		s.human_ship_id = -1
		_c = s.world.primary_body().pos
	if _f >= 4 and _view != null:
		var prog = clampf(float(_f - 6) / 1600.0, 0.0, 1.0)
		var z = lerpf(0.98, 0.78, prog)                    # slow push-in
		_view._cam_pos = _c; _view._cam_pos_prev = _c
		_view._cam_zoom = z; _view._cam_zoom_prev = z
		_view._camera.position = _c; _view._camera.zoom = Vector2(z, z)
		_view._bg_mat.set_shader_parameter("cam", _c)
		if _main.hud.visible: _main.hud.visible = false

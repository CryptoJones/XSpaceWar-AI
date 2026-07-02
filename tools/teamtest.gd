extends SceneTree
## Repro: start a TEAM-mode match and exercise the HUD to surface the
## scoreboard/minimap bug. Run headless; watch stderr for SCRIPT ERROR.
func _initialize() -> void:
	var main = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.has_method("_dismiss_splash"): main._dismiss_splash()
	if main.has_method("set_menu_visible"): main.set_menu_visible(false)
	if main.has_method("_end_credits"): main._end_credits()
	main.session.start_skirmish(6, GameSession.Mode.TEAM, BotController.Difficulty.ACE)
	main.session.human_ship_id = main.session.world.ships[0].id
	main._splash.visible = false
	main.hud.set_radar_visible(true)
	main.hud.set_score_visible(true)
	main.hud.set_feed_visible(true)
	for _i in range(40):
		await process_frame
	print("=== TEAMTEST mode=", main.session.mode, " radar_vis=", main.hud.radar_visible(),
		" score_vis=", main.hud.score_visible(), " feed_vis=", main.hud.feed_visible(),
		" human=", main.session.human_ship_id, " hud_visible=", main.hud.visible, " ===")
	var sc = main.hud._score
	print("SCORE vis=", sc.visible, " bbcode=", sc.bbcode_enabled, " size=", sc.size, " gpos=", sc.global_position)
	print("SCORE_RAW>>>", sc.text)
	print("SCORE_PARSED>>>[", sc.get_parsed_text(), "]")
	var rd = main.hud._radar
	print("RADAR vis=", rd.visible, " size=", rd.size, " gpos=", rd.global_position, " modulate_a=", rd.modulate.a)
	print("VIEWPORT size=", root.get_viewport().get_visible_rect().size, " hud_root_vis=", main.hud.visible, " hud_gpos=", main.hud.global_position)
	await RenderingServer.frame_post_draw
	var img = root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/teamhud.png")
	print("saved /tmp/teamhud.png")
	quit()

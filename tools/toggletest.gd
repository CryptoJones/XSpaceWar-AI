extends SceneTree
## Tests the minimap/scoreboard/feed toggle keybinds by feeding synthetic key
## events straight into main._unhandled_input and checking HUD visibility flips.
func _initialize() -> void:
	var main = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.has_method("_end_credits"): main._end_credits()
	if main.has_method("_dismiss_splash"): main._dismiss_splash()
	if main.has_method("set_menu_visible"): main.set_menu_visible(false)
	main._splash.visible = false
	main.session.start_skirmish(4, GameSession.Mode.TEAM, BotController.Difficulty.ACE)
	main.session.human_ship_id = main.session.world.ships[0].id
	await process_frame
	print("splash_vis=", main._splash.visible, " menu_vis=", main._menu.visible,
		" credits_vis=", main._credits.visible)
	for pair in [["toggle_map", "minimap"], ["toggle_score", "scoreboard"], ["toggle_feed", "feed"]]:
		var action: String = pair[0]
		var bound: int = int(main.view.key_binds[action])
		var before := _vis(main, pair[1])
		var e := InputEventKey.new()
		e.physical_keycode = bound
		e.pressed = true
		main._unhandled_input(e)
		var after := _vis(main, pair[1])
		print("%s (key %d): %s -> %s  %s" % [pair[1], bound, before, after,
			"TOGGLED" if before != after else "NO-CHANGE !!"])
	quit()

func _vis(main, which: String) -> bool:
	if which == "minimap": return main.hud.radar_visible()
	if which == "scoreboard": return main.hud.score_visible()
	return main.hud.feed_visible()

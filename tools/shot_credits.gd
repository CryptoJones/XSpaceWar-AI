extends SceneTree
## One-shot: freeze the credits roll on the PLAY TESTERS block and save a PNG.
## Run (needs a display): godot --path . --resolution 1920x1080 --script res://tools/shot_credits.gd

func _initialize() -> void:
	var main = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.has_method("_dismiss_splash"):
		main._dismiss_splash()
	if main.has_method("set_menu_visible"):
		main.set_menu_visible(false)
	main._end_credits()
	main._start_credits(false)
	if main._credits.get_child_count() > 0 and main._credits.get_child(0) is ColorRect:
		(main._credits.get_child(0) as ColorRect).color = Color(0, 0, 0, 1)  # opaque backdrop for a clean shot
	for _i in range(8):
		await process_frame
	var box = main._credits_box
	var vp = root.get_viewport().get_visible_rect().size
	var header_y := -1.0
	for c in box.get_children():
		if c is Label and (c as Label).text.begins_with("PLAY TESTERS"):
			header_y = (c as Control).position.y
			break
	main.set_process(false)            # freeze the roll
	if header_y < 0.0:
		header_y = box.size.y * 0.5
	main._credits_y = vp.y * 0.24 - header_y
	box.position = Vector2((vp.x - box.size.x) * 0.5, main._credits_y)
	for _j in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img = root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/credits_shot.png")
	print("DONE header_y=%s credits_y=%s vp=%s" % [header_y, main._credits_y, vp])
	quit()

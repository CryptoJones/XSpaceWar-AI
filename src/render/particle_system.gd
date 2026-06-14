class_name ParticleSystem
## One-shot particle bursts and floating kill/pickup popups for WorldView,
## extracted from the renderer god-class (#26).
##
## Stateless: operates on the passed-in WorldView. The _popups array stays on
## WorldView; burst nodes are parented to it and self-free after 2s.

static func spawn_burst(view: WorldView, pos: Vector2, color: Color, amount: int, speed: float) -> void:
	var m := ParticleProcessMaterial.new()
	m.gravity = Vector3.ZERO
	m.spread = 180.0
	m.initial_velocity_min = speed * 0.25
	m.initial_velocity_max = speed
	m.damping_min = 80.0
	m.damping_max = 200.0
	m.scale_min = 1.5
	m.scale_max = 4.0
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r * 0.3, color.g * 0.2, color.b * 0.2, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	var p := GPUParticles2D.new()
	p.process_material = m
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = pos
	p.emitting = true
	view.add_child(p)
	view.get_tree().create_timer(2.0).timeout.connect(p.queue_free)

static func add_kill_popup(view: WorldView, killer_id: int, victim_id: int) -> void:
	var victim := view.session.world.ship_by_id(victim_id)
	var killer := view.session.world.ship_by_id(killer_id)
	if victim == null or killer == null:
		return
	var kname := view.session.display_name(killer_id)
	view._popups.append({"pos": victim.pos, "vel": Vector2(0, -46), "ttl": 1.7,
		"text": "+1  %s" % kname, "color": WorldView.ship_color(killer)})

static func add_text_popup(view: WorldView, pos: Vector2, text: String, color: Color) -> void:
	view._popups.append({"pos": pos, "vel": Vector2(0, -40), "ttl": 1.4,
		"text": text, "color": color})

static func step_popups(view: WorldView, dt: float) -> void:
	for p in view._popups:
		p["ttl"] = float(p["ttl"]) - dt
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * dt
	while not view._popups.is_empty() and float(view._popups[0]["ttl"]) <= 0.0:
		view._popups.pop_front()

## Called from WorldView._draw (so view's immediate-mode draw context is live).
static func draw_popups(view: WorldView) -> void:
	for p in view._popups:
		var c: Color = p["color"]
		c.a = clampf(float(p["ttl"]) / 0.6, 0.0, 1.0)
		var sz := int(18.0 * clampf(view._ship_vis_scale * 0.7, 1.0, 2.0))
		view.draw_string(ThemeDB.fallback_font, (p["pos"] as Vector2) + Vector2(-60, 0),
			String(p["text"]), HORIZONTAL_ALIGNMENT_CENTER, 120, sz, c)

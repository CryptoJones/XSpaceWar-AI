class_name SkyController
## Nebula/star backdrop settings for WorldView, extracted from the renderer
## god-class (#26).
##
## Stateless: operates on the passed-in WorldView. The _bg_mat ShaderMaterial is
## built in WorldView._ready (UI node wiring); this owns the per-arena reseed and
## the player's display preferences.

## Re-seed the starfield per arena (distinct sky each match) and pick per-arena
## nebula tints (only visible when the player enables nebula).
static func reseed(view: WorldView, seed_value: int) -> void:
	view._bg_mat.set_shader_parameter("seed", float(absi(seed_value) % 100000) * 0.001)
	var h1 := float(absi(seed_value) % 997) / 997.0
	var h2 := wrapf(h1 + 0.35, 0.0, 1.0)
	view._bg_mat.set_shader_parameter("tint_a", Color.from_hsv(h1, 0.65, 0.35))
	view._bg_mat.set_shader_parameter("tint_b", Color.from_hsv(h2, 0.55, 0.30))

## Player display preferences (Settings menu): nebula 0..1, stars 0..1.5, far
## star layer on/off. Defaults match the shader's (black + near stars).
static func apply_prefs(view: WorldView, nebula: float, stars: float, far: bool) -> void:
	view._bg_mat.set_shader_parameter("nebula_intensity", clampf(nebula, 0.0, 1.0))
	view._bg_mat.set_shader_parameter("star_brightness", clampf(stars, 0.0, 1.5))
	view._bg_mat.set_shader_parameter("far_stars", far)

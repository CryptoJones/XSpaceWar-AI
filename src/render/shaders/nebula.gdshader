shader_type canvas_item;
// Deep-space backdrop: pure black with two parallax layers of small, round,
// jittered, gently twinkling stars. Fully procedural (UV + seed), no assets.
//
// Star math runs in ISOTROPIC uv space (x scaled by the viewport aspect) —
// in raw UV a "round" star renders as a 16:9 horizontal dash.

uniform vec2 cam = vec2(0.0);
uniform float seed = 0.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p + seed) * 43758.5453);
}

// One layer of stars: sparse cells, random sub-cell offset (kills the grid),
// random size, gentle twinkle.
float star_layer(vec2 uv, float density, float bright, float t) {
	vec2 g = floor(uv * density);
	vec2 rnd = hash2(g);
	if (rnd.x < 0.965) {
		return 0.0;
	}
	vec2 c = (g + 0.5 + 0.7 * (hash2(g + 31.7) - 0.5)) / density;
	float d = length(uv - c) * density;
	float size = 0.18 + 0.5 * rnd.y;
	float s = smoothstep(size, 0.0, d);
	float tw = 0.75 + 0.25 * sin(t * (2.0 + 4.0 * rnd.y) + rnd.x * 40.0);
	return s * bright * tw;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = vec2(UV.x * aspect, UV.y);
	float t = TIME;

	// Black space, two parallax star layers, nothing else.
	float st = star_layer(uv + cam * 0.000115, 70.0, 0.5, t)
		+ star_layer(uv * 1.9 + cam * 0.00008 + 7.0, 130.0, 0.28, t);
	COLOR = vec4(vec3(0.85, 0.92, 1.0) * st, 1.0);
}

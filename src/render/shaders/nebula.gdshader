shader_type canvas_item;
// Procedural deep-space backdrop: domain-warped fractal nebula + three
// parallax layers of round, jittered, twinkling stars. Fully generated from
// UV + a seed uniform — no texture assets. Drawn on a full-screen ColorRect
// behind the world; the camera position arrives via `cam` for parallax.
//
// All star/nebula math runs in ISOTROPIC uv space (x scaled by the viewport
// aspect) — in raw UV a "round" star is a 16:9 horizontal dash.

uniform vec2 cam = vec2(0.0);
uniform float seed = 0.0;
uniform vec3 tint_a : source_color = vec3(0.10, 0.16, 0.42);
uniform vec3 tint_b : source_color = vec3(0.45, 0.10, 0.38);

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p + seed) * 43758.5453);
}

float hash1(vec2 p) {
	return hash2(p).x;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));  // de-axis the octaves
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = rot * p * 2.03;
		amp *= 0.5;
	}
	return v;
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

	// Nebula: two domain-warped fbm layers, gated by a broad patchiness mask
	// so the sky has empty stretches instead of uniform cloud.
	vec2 p = uv * 2.6 + cam * 0.00006 + vec2(seed * 3.1, seed * 1.7);
	vec2 warp = vec2(fbm(p * 1.6), fbm(p * 1.6 + vec2(5.2, 1.3)));
	float n1 = fbm(p * 1.2 + 1.4 * (warp - 0.5));
	float n2 = fbm(p * 2.5 - 1.1 * (warp - 0.5) + cam * 0.00003);
	float patch = fbm(p * 0.35 + 2.0);
	float neb = pow(clamp(n1 * 1.35 - 0.32, 0.0, 1.0), 1.7) * smoothstep(0.25, 0.75, patch);
	float wisps = pow(clamp(n2 * 1.25 - 0.42, 0.0, 1.0), 2.1) * smoothstep(0.2, 0.7, patch);

	// The deepest layer is PURE BLACK — empty space. Everything visible
	// sits in front of it: faint nebula wisps, then two near star layers.
	vec3 col = vec3(0.0);
	col += tint_a * neb * 0.32;
	col += tint_b * wisps * 0.26;

	// Two parallax star layers (small, dim; the slow far layer of big soft
	// dots is gone — it read as floating rocks, not stars).
	float st = star_layer(uv + cam * 0.000115, 70.0, 0.5, t)
		+ star_layer(uv * 1.9 + cam * 0.00008 + 7.0, 130.0, 0.28, t);
	col += vec3(0.85, 0.92, 1.0) * st;

	COLOR = vec4(col, 1.0);
}

shader_type canvas_item;
// Procedural deep-space backdrop, player-configurable from Settings:
//   nebula_intensity  0 = pure black space (default) … 1 = full color wisps
//   star_brightness   overall gain for the two near star layers
//   far_stars         optional third layer of big, slow, distant stars
// Fully procedural (UV + seed), no assets. Star math runs in ISOTROPIC uv
// (x scaled by viewport aspect) — in raw UV a round star is a 16:9 dash.

uniform vec2 cam = vec2(0.0);
uniform float seed = 0.0;
uniform float nebula_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float star_brightness : hint_range(0.0, 1.5) = 0.5;
uniform bool far_stars = false;
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
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = rot * p * 2.03;
		amp *= 0.5;
	}
	return v;
}

// One layer of stars: sparse cells, random sub-cell offset (kills the grid),
// random size, gentle twinkle. Each pixel samples its 3x3 cell neighborhood
// so a star whose jitter pushes it against a cell edge still renders whole
// instead of being sliced into quarter circles at the tile boundary.
float star_layer(vec2 uv, float density, float bright, float t) {
	vec2 gv = uv * density;
	vec2 g0 = floor(gv);
	float acc = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = g0 + vec2(float(x), float(y));
			vec2 rnd = hash2(g);
			if (rnd.x < 0.965) {
				continue;
			}
			vec2 c = g + 0.5 + 0.7 * (hash2(g + 31.7) - 0.5);
			float d = length(gv - c);  // distance in cell units
			float size = 0.18 + 0.5 * rnd.y;
			float s = smoothstep(size, 0.0, d);
			float tw = 0.75 + 0.25 * sin(t * (2.0 + 4.0 * rnd.y) + rnd.x * 40.0);
			acc += s * tw;
		}
	}
	return acc * bright;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = vec2(UV.x * aspect, UV.y);
	float t = TIME;

	vec3 col = vec3(0.0);  // the deepest layer is always pure black

	// Optional nebula: domain-warped fbm wisps gated by a patchiness mask.
	if (nebula_intensity > 0.001) {
		vec2 p = uv * 2.6 + cam * 0.00006 + vec2(seed * 3.1, seed * 1.7);
		vec2 warp = vec2(fbm(p * 1.6), fbm(p * 1.6 + vec2(5.2, 1.3)));
		float n1 = fbm(p * 1.2 + 1.4 * (warp - 0.5));
		float n2 = fbm(p * 2.5 - 1.1 * (warp - 0.5) + cam * 0.00003);
		float patch = fbm(p * 0.35 + 2.0);
		float neb = pow(clamp(n1 * 1.35 - 0.32, 0.0, 1.0), 1.7) * smoothstep(0.25, 0.75, patch);
		float wisps = pow(clamp(n2 * 1.25 - 0.42, 0.0, 1.0), 2.1) * smoothstep(0.2, 0.7, patch);
		col += tint_a * neb * 0.6 * nebula_intensity;
		col += tint_b * wisps * 0.5 * nebula_intensity;
	}

	// Star layers: two near (parallax) + an optional far layer of big slow ones.
	float st = star_layer(uv + cam * 0.000115, 70.0, 1.0, t)
		+ star_layer(uv * 1.9 + cam * 0.00008 + 7.0, 130.0, 0.55, t);
	if (far_stars) {
		st += star_layer(uv * 0.7 + cam * 0.000045 - 3.0, 38.0, 1.6, t);
	}
	col += vec3(0.85, 0.92, 1.0) * st * star_brightness;

	COLOR = vec4(col, 1.0);
}

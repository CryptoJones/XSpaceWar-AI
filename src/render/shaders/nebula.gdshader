shader_type canvas_item;
// Procedural deep-space backdrop: layered fractal-noise nebula + star field.
// Fully generated from UV + a seed uniform — no texture assets. Designed to be
// drawn on a full-screen ColorRect behind the world, with the camera offset
// fed in via `cam` for cheap parallax.

uniform vec2 cam = vec2(0.0);
uniform float seed = 0.0;
uniform vec3 tint_a : source_color = vec3(0.10, 0.16, 0.42);
uniform vec3 tint_b : source_color = vec3(0.45, 0.10, 0.38);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * noise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return v;
}

// Sharp, sparse stars with twinkle.
float stars(vec2 uv, float density, float bright) {
	vec2 g = floor(uv * density);
	float h = hash(g * 1.7);
	if (h < 0.985) return 0.0;
	vec2 c = (g + 0.5) / density;
	float d = length(uv - c) * density;
	float s = smoothstep(0.5, 0.0, d);
	return s * bright * (0.6 + 0.4 * h);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * 3.0 + cam * 0.00006;

	// Two nebula layers at different scales/parallax.
	float n1 = fbm(p * 1.3 + vec2(seed));
	float n2 = fbm(p * 2.7 - vec2(seed * 0.5) + cam * 0.00003);
	float neb = pow(clamp(n1 * 1.2 - 0.25, 0.0, 1.0), 1.8);
	float wisps = pow(clamp(n2 * 1.1 - 0.30, 0.0, 1.0), 2.2);

	vec3 col = vec3(0.012, 0.014, 0.03);                 // deep space base
	col += tint_a * neb * 0.55;
	col += tint_b * wisps * 0.45;

	// Parallax star layers.
	vec2 suv = uv + cam * 0.00010;
	float st = stars(suv, 90.0, 1.0) + stars(suv * 1.7 + 7.0, 160.0, 0.6)
		+ stars(suv * 0.6 - 3.0, 50.0, 1.3);
	col += vec3(0.9, 0.95, 1.0) * st;

	COLOR = vec4(col, 1.0);
}

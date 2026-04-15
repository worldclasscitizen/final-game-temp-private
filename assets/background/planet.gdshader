shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float size : hint_range(1.0, 100.0) = 5.365;
uniform int OCTAVES : hint_range(0, 20, 1) = 3;
uniform float seed : hint_range(1.0, 10.0) = 4.875;
uniform float pixels : hint_range(10.0, 2000.0) = 500.0;
uniform sampler2D colorscheme;
uniform vec2 light_origin = vec2(0.39, 0.39);

float rand(vec2 coord) {
	return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 15.5453 * seed);
}

float noise(vec2 coord) {
	vec2 i = floor(coord);
	vec2 f = fract(coord);
	float a = rand(i);
	float b = rand(i + vec2(1.0, 0.0));
	float c = rand(i + vec2(0.0, 1.0));
	float d = rand(i + vec2(1.0, 1.0));
	vec2 cubic = f * f * (3.0 - 2.0 * f);
	return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

float fbm(vec2 coord) {
	float value = 0.0;
	float scale = 0.5;
	for (int i = 0; i < OCTAVES; i++) {
		value += noise(coord) * scale;
		coord *= 2.0;
		scale *= 0.5;
	}
	return value;
}

bool dither(vec2 uv1, vec2 uv2) {
	return mod(uv1.y + uv2.x, 2.0 / pixels) <= 1.0 / pixels;
}

vec2 spherify(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	float z = sqrt(1.0 - dot(centered.xy, centered.xy));
	vec2 sphere = centered / (z + 1.0);
	return sphere * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = floor(UV * pixels) / pixels;
	bool dith = dither(UV, uv);

	float d_to_center = distance(uv, vec2(0.5));
	uv = spherify(uv);

	float d_to_light = distance(uv, light_origin);
	d_to_light += pow(d_to_center * 3.0, 4.0) * 0.05;

	float n = fbm(uv * size);
	float n2 = fbm(uv * size + n * 3.0);
	float mixed = n2 * d_to_light;

	if (dith) {
		mixed *= 0.95;
	}

	float col_val = floor(mixed * 15.0) / 7.0;
	vec3 col = texture(colorscheme, vec2(col_val, 0.0)).rgb;

	float a = step(d_to_center, 0.5);
	COLOR = vec4(col, a);
}

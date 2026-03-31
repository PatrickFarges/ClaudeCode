shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_softness : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.8;
uniform vec2 wind_direction = vec2(1.0, 0.3);
uniform float wind_speed : hint_range(0.0, 0.1) = 0.01;
uniform float cloud_scale : hint_range(0.0001, 0.01) = 0.002;
uniform float edge_fade_start : hint_range(0.3, 0.9) = 0.6;

varying vec3 world_pos;
varying vec2 local_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_uv = UV * 2.0 - 1.0;
}

// Hash-based noise (no texture needed)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Smoothstep interpolation
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		value += amplitude * value_noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	// Edge fade — smooth circle falloff
	float dist = length(local_uv);
	float edge_fade = 1.0 - smoothstep(edge_fade_start, 1.0, dist);

	// Cloud noise in world space
	vec2 uv = world_pos.xz * cloud_scale;
	vec2 wind_offset = wind_direction * wind_speed * TIME;
	float n = fbm(uv + wind_offset);

	// Second layer for detail (slower, smaller scale)
	float detail = fbm(uv * 2.5 + wind_offset * 0.7 + vec2(50.0, 80.0));
	n = mix(n, detail, 0.3);

	// Coverage threshold with soft edges
	float cloud = smoothstep(cloud_coverage, cloud_coverage + cloud_softness, n);

	ALBEDO = cloud_color;
	ALPHA = cloud * cloud_opacity * edge_fade;
}

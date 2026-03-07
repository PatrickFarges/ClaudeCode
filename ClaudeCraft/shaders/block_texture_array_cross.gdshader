shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray block_textures : source_color, filter_nearest, repeat_enable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;

varying flat float tex_layer;
varying vec3 tint_rgb;

void vertex() {
	// Layer index encode dans l'alpha du vertex color (contourne bug CUSTOM0 flora mesh)
	tex_layer = round(COLOR.a * 255.0);
	// Extraire le tint RGB (sans l'alpha qui porte le layer)
	tint_rgb = COLOR.rgb;
}

void fragment() {
	vec4 tex_sample = texture(block_textures, vec3(UV, tex_layer));
	ALBEDO = tex_sample.rgb * tint_rgb;
	ALPHA = tex_sample.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	// Emission legere pour contrer le SSAO/SSIL sur la vegetation fine
	EMISSION = ALBEDO * 0.15;
}

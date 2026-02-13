shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray block_textures : source_color, filter_nearest, repeat_enable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;

varying flat float tex_layer;

void vertex() {
	// CUSTOM0.x contient l'index de layer dans le Texture2DArray
	tex_layer = CUSTOM0.x;
}

void fragment() {
	// UV tile naturellement sur les quads fusionnés (greedy meshing)
	vec4 tex_sample = texture(block_textures, vec3(UV, tex_layer));
	// COLOR (vertex color) sert de tint multiplicatif (AO, direction, teinte)
	ALBEDO = tex_sample.rgb * COLOR.rgb;
	ALPHA = tex_sample.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}

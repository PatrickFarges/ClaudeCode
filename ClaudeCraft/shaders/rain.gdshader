shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_always;

uniform vec4 rain_color : source_color = vec4(0.7, 0.75, 0.85, 0.35);
uniform float drop_length : hint_range(0.1, 2.0) = 0.6;
uniform float drop_width : hint_range(0.001, 0.02) = 0.005;

void vertex() {
	// Stretch vertices along Y to make elongated drops
	VERTEX.y *= drop_length;
	VERTEX.x *= drop_width;
	VERTEX.z *= drop_width;
}

void fragment() {
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a;
}

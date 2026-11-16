shader_type spatial;
render_mode cull_disabled, diffuse_burley;

varying vec3 col;

void vertex() {
	col = COLOR.rgb;
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.86;
	SPECULAR = 0.04;
}

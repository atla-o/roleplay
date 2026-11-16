shader_type spatial;
render_mode cull_disabled, diffuse_burley, depth_prepass_alpha;

uniform sampler2D crown : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sway = 0.35;

varying float v_h;

void vertex() {
	v_h = UV.y;
	float bend = sin(TIME * 1.15 + VERTEX.x * 0.07 + VERTEX.z * 0.05) * sway * UV.y * UV.y;
	VERTEX.x += bend;
}

void fragment() {
	vec4 tex = texture(crown, UV);
	// Drop the card that is edge-on so the cross does not draw a bright line.
	if (tex.a < 0.28 || abs(NORMAL.z) < 0.28) {
		discard;
	}
	ALBEDO = tex.rgb;
	ROUGHNESS = 0.88;
	SPECULAR = 0.04;
}

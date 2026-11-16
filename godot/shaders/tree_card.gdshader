shader_type spatial;
render_mode cull_disabled, diffuse_burley, depth_prepass_alpha;

uniform sampler2D crown : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sway = 0.35;

varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	float bend = sin(TIME * 1.15 + VERTEX.x * 0.07 + VERTEX.z * 0.05) * sway * UV.y * UV.y;
	VERTEX.x += bend;
}

void fragment() {
	vec4 tex = texture(crown, UV);
	// Drop the card that is edge-on so the cross does not draw a bright line.
	// Alpha scissor lets the visibility-range crossfade dither instead of pop.
	if (tex.a < 0.28 || abs(NORMAL.z) < 0.28) {
		discard;
	}
	vec3 ink = tint;
	if (dot(ink, vec3(1.0)) < 0.05) {
		ink = vec3(0.15, 0.28, 0.12);
	}
	float ink_l = max(dot(ink, vec3(0.25, 0.5, 0.25)), 0.02);
	ALBEDO = tex.rgb * (ink / ink_l) * 0.9;
	ROUGHNESS = 0.88;
	SPECULAR = 0.04;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.28;
}

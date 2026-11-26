shader_type spatial;
render_mode cull_disabled, diffuse_burley;

varying vec3 tint;
varying float height_k;

void vertex() {
	tint = COLOR.rgb;
	height_k = UV.y;
	float bend = sin(TIME * 1.05 + VERTEX.x * 0.15) * 0.06 * UV.y * UV.y;
	VERTEX.x += bend;
}

void fragment() {
	vec3 ink = tint;
	if (dot(ink, vec3(1.0)) < 0.05) {
		ink = vec3(0.15, 0.28, 0.12);
	}
	vec3 bark = vec3(0.24, 0.15, 0.08);
	float crown = smoothstep(0.06, 0.18, height_k);
	ALBEDO = mix(bark, ink, crown);
	ROUGHNESS = mix(0.92, 0.74, crown);
	SPECULAR = 0.04;
}

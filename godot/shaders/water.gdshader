shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float water_y = 0.0;
uniform vec2 tile_m = vec2(4000.0, 4000.0);
uniform vec2 tile_origin = vec2(0.0, 0.0);

varying vec3 world_pos;

float decode_h(vec2 uv) {
	vec3 e = texture(height_map, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	float t = (e.r * 255.0 * 256.0 + e.g * 255.0) / 65535.0;
	return mix(height_range.x, height_range.y, t);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2((world_pos.x - tile_origin.x) / tile_m.x, 1.0 - (world_pos.z - tile_origin.y) / tile_m.y);
	float terrain = decode_h(uv);
	float depth = water_y - terrain;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	if (uv.y < 0.0) {
		depth = 12.0;
	}
	if (depth < -0.15) {
		discard;
	}
	float shore = smoothstep(0.0, 1.4, depth);
	vec3 shallow = vec3(0.45, 0.42, 0.28);
	vec3 deep = vec3(0.02, 0.08, 0.12);
	ALBEDO = mix(shallow, deep, shore);
	ROUGHNESS = mix(0.18, 0.06, shore);
	SPECULAR = 0.55;
	METALLIC = 0.0;
}

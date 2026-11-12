shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D disturb_map : filter_linear, repeat_disable;
uniform sampler2D grain_map : filter_linear_mipmap, repeat_enable;
uniform vec2 height_range = vec2(0.0, 1.0);
uniform vec2 tile_m = vec2(3998.0, 3998.0);
uniform float spacing = 2.0;

varying vec3 world_normal;

float decode_h(vec2 uv) {
	vec3 e = texture(height_map, uv).rgb;
	float t = (e.r * 255.0 * 256.0 + e.g * 255.0) / 65535.0;
	return mix(height_range.x, height_range.y, t);
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Mesh UV.y is the north fraction. Both maps are stored north-up.
	vec2 uv = clamp(vec2(UV.x, 1.0 - UV.y), vec2(0.001), vec2(0.999));
	vec3 alb = texture(albedo_map, uv).rgb;
	alb = alb / (vec3(1.0) + alb * 0.35);
	float cut = texture(disturb_map, uv).r;
	vec3 soil = vec3(0.22, 0.11, 0.045);
	alb = mix(alb, soil, smoothstep(0.08, 0.55, cut) * 0.92);
	ALBEDO = alb;
	ROUGHNESS = mix(0.94, 0.55, cut);
	SPECULAR = mix(0.03, 0.22, cut);

	vec3 grain = texture(grain_map, UV * 90.0).rgb * 2.0 - 1.0;
	vec3 n = normalize(world_normal + vec3(grain.x, 0.0, grain.y) * 0.12);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

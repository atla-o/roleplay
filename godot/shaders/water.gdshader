shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D wave_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
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
	float depth = 18.0;
	bool in_tile = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	if (in_tile) {
		depth = water_y - decode_h(uv);
		if (depth < -0.25) {
			discard;
		}
	}
	float shore = smoothstep(0.0, 4.5, depth);
	vec2 w1 = world_pos.xz * 0.18 + vec2(TIME * 0.04, TIME * 0.015);
	vec2 w2 = world_pos.xz * 0.31 + vec2(-TIME * 0.02, TIME * 0.03);
	vec3 wn = texture(wave_nrm, w1).rgb * 2.0 - 1.0;
	wn += texture(wave_nrm, w2).rgb * 2.0 - 1.0;
	wn = normalize(vec3(wn.x, 1.4, wn.y));
	vec3 shallow = vec3(0.55, 0.66, 0.48);
	vec3 deep = vec3(0.04, 0.12, 0.16);
	vec3 water = mix(shallow, deep, smoothstep(0.2, 0.85, shore));
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), up_view), 0.0, 1.0), 3.0);
	vec2 ref_uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + wn.xz * 0.025;
	vec3 mirror = texture(screen_tex, clamp(ref_uv, vec2(0.001), vec2(0.999))).rgb;
	vec3 sky = vec3(0.55, 0.64, 0.72);
	vec3 refl = mix(sky, mirror, 0.55);
	ALBEDO = mix(water, refl, fres * 0.72);
	float foam = (1.0 - smoothstep(0.0, 0.55, depth)) * (0.55 + 0.45 * sin(world_pos.x * 1.7 + world_pos.z * 1.3 + TIME * 1.4));
	ALBEDO = mix(ALBEDO, vec3(0.82, 0.86, 0.82), clamp(foam, 0.0, 1.0) * 0.85);
	ROUGHNESS = mix(0.08, 0.28, 1.0 - fres);
	SPECULAR = 0.7;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

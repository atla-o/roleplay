shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sentinel : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D gravel_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D disturb_map : filter_linear, repeat_disable;
uniform sampler2D fine_cut : filter_linear, repeat_disable;
uniform vec2 height_range = vec2(0.0, 1.0);
uniform vec2 tile_m = vec2(3998.0, 3998.0);
uniform float forest = 0.0;
uniform float water_y = -1000.0;
uniform vec2 patch_origin = vec2(0.0, 0.0);
uniform float patch_size = 64.0;
uniform float patch_live = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

vec3 triplanar_color(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= max(b.x + b.y + b.z, 0.0001);
	vec3 x = texture(tex, p.zy * scale).rgb;
	vec3 y = texture(tex, p.xz * scale).rgb;
	vec3 z = texture(tex, p.xy * scale).rgb;
	return x * b.x + y * b.y + z * b.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv_raw = vec2(UV.x, 1.0 - UV.y);
	bool in_photo = uv_raw.x > 0.0 && uv_raw.x < 1.0 && uv_raw.y > 0.0 && uv_raw.y < 1.0;
	vec2 uv = clamp(uv_raw, vec2(0.001), vec2(0.999));
	vec3 sat = in_photo ? texture(sentinel, uv).rgb : vec3(0.15, 0.22, 0.11);
	float sat_l = dot(sat, vec3(0.25, 0.5, 0.25));
	vec3 nrm = normalize(world_normal);
	float slope = clamp(1.0 - nrm.y, 0.0, 1.0);
	// Macro blotches, tens of metres across. Not the fine ripple that was an alias.
	float macro = texture(gravel_alb, world_pos.xz * 0.018).g;

	vec3 gravel = triplanar_color(gravel_alb, world_pos, nrm, 0.22);
	vec3 rock = triplanar_color(rock_alb, world_pos, nrm, 0.16);
	vec3 floor_t = triplanar_color(forest_alb, world_pos, nrm, 0.2);
	vec3 leaves = triplanar_color(leaves_alb, world_pos, nrm, 0.24);
	vec3 shore = triplanar_color(shore_alb, world_pos, nrm, 0.28);

	vec3 detail = mix(gravel, rock, clamp(slope * 1.6 + (1.0 - sat_l) * 0.35, 0.0, 1.0));
	vec3 alb = sat * (0.55 + 0.8 * detail);
	if (forest > 0.5) {
		float canopy = clamp((sat.g - max(sat.r, sat.b)) * 4.0, 0.0, 1.0);
		detail = mix(floor_t, leaves, clamp(macro, 0.0, 1.0));
		detail = mix(detail, rock, smoothstep(0.18, 0.55, slope));
		float shore_w = 0.0;
		if (water_y > -100.0) {
			shore_w = 1.0 - smoothstep(0.05, 1.6, world_pos.y - water_y);
		}
		detail = mix(detail, shore, shore_w * (1.0 - slope));
		// Duff and moss under the canopy. The Sentinel green only tints it,
		// so the island is not a single turf colour.
		alb = mix(detail, sat, 0.22 + canopy * 0.28);
		alb *= 0.72 + sat_l * 0.55;
	}
	float wet = 0.0;
	if (water_y > -100.0) {
		wet = 1.0 - smoothstep(0.0, 0.7, world_pos.y - water_y);
		alb = mix(alb, alb * vec3(0.55, 0.62, 0.58), wet * 0.65);
	}

	float cut = texture(disturb_map, uv).r;
	vec2 fuv = (world_pos.xz - patch_origin) / max(patch_size, 0.001);
	if (patch_live > 0.5 && fuv.x >= 0.0 && fuv.y >= 0.0 && fuv.x <= 1.0 && fuv.y <= 1.0) {
		cut = max(cut, texture(fine_cut, vec2(fuv.x, 1.0 - fuv.y)).r);
	}
	vec3 mud = triplanar_color(mud_alb, world_pos, nrm, 0.55);
	alb = mix(alb, mud, smoothstep(0.08, 0.55, cut) * 0.82);
	ALBEDO = alb;
	ROUGHNESS = mix(0.92, 0.62, cut);
	SPECULAR = 0.02;
	METALLIC = 0.0;

	vec3 gn = texture(gravel_nrm, world_pos.xz * 0.22).rgb * 2.0 - 1.0;
	vec3 rn = texture(rock_nrm, world_pos.xz * 0.16).rgb * 2.0 - 1.0;
	vec3 dn = mix(gn, rn, clamp(slope * 1.4, 0.0, 1.0));
	vec3 n = normalize(nrm + vec3(dn.x, 0.0, dn.y) * mix(0.55, 0.25, slope));
	if (cut > 0.2) {
		n = normalize(nrm + vec3(dn.x, 0.0, dn.y) * 0.12);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

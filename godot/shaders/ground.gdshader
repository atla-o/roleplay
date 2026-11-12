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
uniform float is_fine = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Four crops of a tile, blended so the repeat is not a grid and has no shared direction.
vec3 stochastic(sampler2D tex, vec2 uv) {
	vec2 iuv = floor(uv);
	vec2 fuv = fract(uv);
	vec2 sm = fuv * fuv * (3.0 - 2.0 * fuv);
	// Offsets are shared by the cells that meet at a corner, and the sample uses
	// the absolute uv, so the blend has no seam.
	vec2 o00 = vec2(hash12(iuv), hash12(iuv + vec2(17.0, 3.0))) * 2.0;
	vec2 o10 = vec2(hash12(iuv + vec2(1.0, 0.0)), hash12(iuv + vec2(19.0, 5.0))) * 2.0;
	vec2 o01 = vec2(hash12(iuv + vec2(0.0, 1.0)), hash12(iuv + vec2(13.0, 9.0))) * 2.0;
	vec2 o11 = vec2(hash12(iuv + vec2(1.0, 1.0)), hash12(iuv + vec2(23.0, 11.0))) * 2.0;
	vec2 base = uv * 0.37;
	vec3 c00 = texture(tex, base + o00).rgb;
	vec3 c10 = texture(tex, base + o10).rgb;
	vec3 c01 = texture(tex, base + o01).rgb;
	vec3 c11 = texture(tex, base + o11).rgb;
	return mix(mix(c00, c10, sm.x), mix(c01, c11, sm.x), sm.y);
}

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
	if (is_fine < 0.5 && patch_live > 0.5) {
		vec2 puv = (world_pos.xz - patch_origin) / max(patch_size, 0.001);
		if (puv.x > -0.002 && puv.y > -0.002 && puv.x < 1.002 && puv.y < 1.002) {
			vec4 edited = texture(fine_cut, clamp(vec2(puv.x, 1.0 - puv.y), vec2(0.001), vec2(0.999)));
			if (edited.r > 0.2 || edited.g > 0.2) {
				discard;
			}
		}
	}
	vec2 uv_raw = vec2(UV.x, 1.0 - UV.y);
	bool in_photo = uv_raw.x > 0.0 && uv_raw.x < 1.0 && uv_raw.y > 0.0 && uv_raw.y < 1.0;
	vec2 uv = clamp(uv_raw, vec2(0.001), vec2(0.999));
	vec3 sat = in_photo ? texture(sentinel, uv).rgb : vec3(0.15, 0.22, 0.11);
	float sat_l = dot(sat, vec3(0.25, 0.5, 0.25));
	vec3 nrm = normalize(world_normal);
	float slope = clamp(1.0 - nrm.y, 0.0, 1.0);
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	// High-frequency detail aliases into streaks past a few dozen metres.
	float detail_fade = 1.0 - smoothstep(28.0, 150.0, dist);
	float macro = stochastic(gravel_alb, world_pos.xz * 0.018).g;
	vec3 gravel_near = stochastic(gravel_alb, world_pos.xz * 0.11);
	vec3 gravel_far = texture(gravel_alb, world_pos.xz * 0.006).rgb;
	vec3 gravel = mix(gravel_far, gravel_near, detail_fade);
	vec3 rock = stochastic(rock_alb, world_pos.xz * 0.07);
	vec3 floor_t = mix(stochastic(forest_alb, world_pos.xz * 0.09), stochastic(leaves_alb, world_pos.xz * 0.13), macro);
	vec3 shore = stochastic(shore_alb, world_pos.xz * 0.1);

	vec3 detail = mix(gravel, rock, smoothstep(0.22, 0.55, slope) * detail_fade);
	// Cool the orange sand so the plain reads as gravel, not a dune.
	detail = mix(detail, detail * vec3(0.78, 0.84, 0.88), 0.45);
	vec3 alb = mix(detail, sat, mix(0.08, 0.22, detail_fade));
	alb = alb / (1.0 + max(alb - vec3(0.7), vec3(0.0)) * 1.2);
	if (forest > 0.5) {
		float canopy = clamp((sat.g - max(sat.r, sat.b)) * 4.0, 0.0, 1.0);
		detail = mix(floor_t, rock, smoothstep(0.22, 0.55, slope));
		float shore_w = 0.0;
		if (water_y > -100.0) {
			shore_w = 1.0 - smoothstep(0.05, 3.2, world_pos.y - water_y);
		}
		detail = mix(detail, shore, shore_w * (1.0 - slope));
		alb = mix(detail, sat, 0.12 + canopy * 0.16);
		alb *= 1.15 + sat_l * 0.2;
		vec3 moss = vec3(0.13, 0.24, 0.12);
		float moss_w = canopy * (1.0 - smoothstep(0.08, 0.4, slope));
		alb = mix(alb, moss, moss_w * 0.62);
	}
	float wet = 0.0;
	if (water_y > -100.0) {
		float above = world_pos.y - water_y;
		wet = (1.0 - smoothstep(-0.15, 3.6, above)) * (1.0 - smoothstep(0.02, 0.5, slope));
		vec3 wet_soil = alb * vec3(0.42, 0.4, 0.34);
		wet_soil = mix(wet_soil, vec3(0.18, 0.22, 0.2), clamp(1.0 - above, 0.0, 1.0) * 0.55);
		alb = mix(alb, wet_soil, wet * 0.94);
	}

	float cut = texture(disturb_map, uv).r;
	float tracks = 0.0;
	vec2 fuv = (world_pos.xz - patch_origin) / max(patch_size, 0.001);
	if (patch_live > 0.5 && fuv.x >= 0.0 && fuv.y >= 0.0 && fuv.x <= 1.0 && fuv.y <= 1.0) {
		vec4 fine = texture(fine_cut, vec2(fuv.x, 1.0 - fuv.y));
		cut = max(cut, fine.r);
		tracks = fine.g;
	}
	// Fresh spoil is lighter and rougher than the crust it came out of.
	vec3 spoil = texture(mud_alb, world_pos.xz * 0.12).rgb;
	spoil = mix(spoil, vec3(0.8, 0.68, 0.5), 0.78);
	alb = mix(alb, spoil, smoothstep(0.25, 0.9, cut) * 0.72);
	alb = mix(alb, alb * vec3(0.62, 0.58, 0.5), tracks * 0.7);
	ALBEDO = alb;
	ROUGHNESS = mix(mix(0.94, 1.0, max(cut, tracks)), 0.32, wet);
	SPECULAR = mix(0.02, 0.18, wet);
	METALLIC = 0.0;

	vec3 n = nrm;
	float crumb = hash12(floor(world_pos.xz * 8.0)) - 0.5;
	float crumb2 = hash12(floor(world_pos.xz * 8.0 + vec2(4.0, 1.0))) - 0.5;
	n += vec3(crumb, 0.0, crumb2) * cut * 0.07;
	// A groove across each track so the print catches the light.
	float groove = sin(dot(world_pos.xz, normalize(vec2(nrm.z, -nrm.x) + vec2(0.001))) * 14.0);
	n += vec3(groove, 0.0, 0.0) * tracks * 0.2;
	n.y = max(n.y, 0.35);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);
}

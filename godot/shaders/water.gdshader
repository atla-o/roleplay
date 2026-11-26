shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float water_y = 0.0;
uniform vec2 tile_m = vec2(4000.0, 4000.0);
uniform vec2 tile_origin = vec2(0.0, 0.0);
uniform float use_ssr = 0.0;
uniform vec3 sun_dir = vec3(0.45, 0.42, 0.78);
uniform sampler2D shore_field : filter_linear, repeat_disable;
uniform float has_shore = 0.0;
uniform float shore_scale = 96.0;

varying vec3 world_pos;

float decode_h(vec2 uv) {
	vec3 e = texture(height_map, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	float t = (e.r * 255.0 * 256.0 + e.g * 255.0) / 65535.0;
	return mix(height_range.x, height_range.y, t);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Blur the bed, but ignore samples that climb the bank so the shore stays put.
float take_bed(vec2 uv, float center, float acc, inout float w) {
	float h = min(decode_h(uv), center + 2.4);
	w += 1.0;
	return acc + h;
}

float bed_near(vec2 uv, float center) {
	float w = 2.0;
	float acc = center * 2.0;
	vec2 s = vec2(0.006);
	acc = take_bed(uv + vec2(s.x, 0.0), center, acc, w);
	acc = take_bed(uv - vec2(s.x, 0.0), center, acc, w);
	acc = take_bed(uv + vec2(0.0, s.y), center, acc, w);
	acc = take_bed(uv - vec2(0.0, s.y), center, acc, w);
	acc = take_bed(uv + s, center, acc, w);
	acc = take_bed(uv - s, center, acc, w);
	acc = take_bed(uv + vec2(s.x, -s.y), center, acc, w);
	acc = take_bed(uv + vec2(-s.x, s.y), center, acc, w);
	return acc / w;
}

void vertex() {
	vec3 p = VERTEX;
	float swell = sin(p.x * 0.02 + TIME * 0.45) * 0.22 + sin(p.z * 0.013 - TIME * 0.3) * 0.16;
	float local = 1.0 - smoothstep(2200.0, 5200.0, length(p.xz));
	p.y += swell * local;
	VERTEX = p;
	world_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2((world_pos.x - tile_origin.x) / tile_m.x, 1.0 - (world_pos.z - tile_origin.y) / tile_m.y);
	bool in_tile = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	float raw = in_tile ? decode_h(uv) : water_y - 6.0;
	float bed = in_tile ? bed_near(uv, raw) : raw;
	// Feather across the bank so the 2 m grid does not draw a stair or flecks.
	float cover = 1.0 - smoothstep(water_y - 0.55, water_y + 0.08, bed);
	if (cover < 0.04) {
		discard;
	}
	float depth = max(water_y - bed, 0.0);
	float shore_m = 48.0;
	if (has_shore > 0.5) {
		shore_m = texture(shore_field, uv).r * shore_scale;
	} else {
		vec2 texel = vec2(18.0 / tile_m.x, 18.0 / tile_m.y);
		for (int i = 0; i < 8; i++) {
			float ang = 0.785398 * float(i);
			vec2 off = vec2(cos(ang), sin(ang)) * texel;
			float bed_i = in_tile ? decode_h(uv + off) : water_y - 6.0;
			if (bed_i > water_y - 0.15) {
				shore_m = min(shore_m, 18.0);
			}
		}
	}
	float rise = 0.0;
	if (in_tile) {
		rise = max(abs(decode_h(uv + vec2(0.004, 0.0)) - raw), abs(decode_h(uv + vec2(0.0, 0.004)) - raw));
	}
	// The stored reservoir is a flat sheet on the waterline, so that reads as deep water.
	float sheet = (1.0 - smoothstep(0.25, 2.8, rise)) * (1.0 - smoothstep(0.15, 2.2, abs(water_y - raw)));
	float shown = mix(depth, 6.0, sheet);
	// The jump-flood distance stands in for depth where the stored reservoir is a flat sheet.
	float field_depth = shore_m * 0.55;
	shown = max(shown, mix(depth, field_depth, sheet));

	float w1 = sin(world_pos.x * 0.05 + world_pos.z * 0.02 + TIME * 0.35);
	float w2 = sin(world_pos.z * 0.04 - TIME * 0.22);
	float w3 = sin((world_pos.x + world_pos.z) * 0.015 + TIME * 0.15);
	vec3 wn = normalize(vec3(-w1 * 0.035 - w3 * 0.02, 1.0, -w2 * 0.03));

	vec3 shallow = vec3(0.30, 0.42, 0.34);
	vec3 mid = vec3(0.10, 0.24, 0.26);
	vec3 deep = vec3(0.02, 0.05, 0.09);
	float depth_k = smoothstep(0.2, 8.0, shown);
	float far_k = smoothstep(6.0, 42.0, max(shown, shore_m * 0.65));
	vec3 water = mix(mix(shallow, mid, depth_k), deep, far_k);

	vec3 view_w = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 refl = reflect(-view_w, wn);
	float sky_h = clamp(refl.y * 1.05, 0.0, 1.0);
	vec3 sky = mix(vec3(0.62, 0.68, 0.72), vec3(0.28, 0.38, 0.46), sky_h);
	float fres = pow(1.0 - clamp(dot(view_w, wn), 0.0, 1.0), 3.2);
	vec3 color = mix(water, sky, fres * 0.55 + 0.04);
	if (use_ssr > 0.5) {
		vec3 mirror = texture(screen_tex, SCREEN_UV + wn.xz * 0.015).rgb;
		color = mix(color, mirror, fres * 0.28);
	}

	float foam = (1.0 - smoothstep(0.4, 28.0, shore_m)) * (1.0 - smoothstep(0.05, 1.4, sheet));
	float lip = smoothstep(0.0, 0.25, depth) * (1.0 - smoothstep(0.25, 1.6, depth));
	float broken = step(0.42, hash21(floor(world_pos.xz * 0.35)));
	color = mix(color, vec3(0.55, 0.62, 0.6), foam * 0.35 * broken);
	color = mix(color, vec3(0.78, 0.82, 0.8), lip * 0.65);

	float ndot = clamp(dot(refl, normalize(sun_dir)), 0.0, 1.0);
	float spark = step(0.96, hash21(floor(world_pos.xz * 2.5)));
	float glint = pow(ndot, 800.0) * spark;

	ALBEDO = color;
	EMISSION = vec3(1.0, 0.98, 0.92) * glint * 0.25;
	ROUGHNESS = mix(0.18, 0.55, foam);
	SPECULAR = 0.0;
	METALLIC = 0.0;
	ALPHA = cover;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

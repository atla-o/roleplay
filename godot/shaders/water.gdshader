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

varying vec3 world_pos;

float decode_h(vec2 uv) {
	vec3 e = texture(height_map, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	float t = (e.r * 255.0 * 256.0 + e.g * 255.0) / 65535.0;
	return mix(height_range.x, height_range.y, t);
}

float bed_at(vec2 uv) {
	// A wide filter so the 2 m height samples do not become stair-steps.
	float h = decode_h(uv) * 4.0;
	h += decode_h(uv + vec2(0.0024, 0.0));
	h += decode_h(uv - vec2(0.0024, 0.0));
	h += decode_h(uv + vec2(0.0, 0.0024));
	h += decode_h(uv - vec2(0.0, 0.0024));
	h += decode_h(uv + vec2(0.0017, 0.0017));
	h += decode_h(uv + vec2(-0.0017, 0.0017));
	h += decode_h(uv + vec2(0.0017, -0.0017));
	h += decode_h(uv + vec2(-0.0017, -0.0017));
	return h / 12.0;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
	float dist = length(to_cam);
	if (dist > 0.001) {
		vec3 toward = to_cam / dist;
		VERTEX += toward * 0.18;
		world_pos += toward * 0.18;
	}
}

void fragment() {
	vec2 uv = vec2((world_pos.x - tile_origin.x) / tile_m.x, 1.0 - (world_pos.z - tile_origin.y) / tile_m.y);
	float depth = 16.0;
	bool in_tile = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	float open_water = 0.0;
	if (in_tile) {
		float bed = bed_at(uv);
		depth = water_y - bed;
		if (depth < -0.85) {
			discard;
		}
		// The reservoir is stored as a flat sheet on the waterline, so a
		// near-zero depth on flat ground is open lake, not a puddle.
		float rise = max(abs(bed_at(uv + vec2(0.006, 0.0)) - bed), abs(bed_at(uv + vec2(0.0, 0.006)) - bed));
		float flatness = 1.0 - smoothstep(0.12, 2.4, rise);
		float near_line = 1.0 - smoothstep(0.05, 3.8, abs(depth));
		open_water = smoothstep(0.2, 0.82, flatness * near_line);
	}
	float shown = mix(max(depth, 0.02), 7.0, open_water);

	float w1 = sin(world_pos.x * 0.09 + world_pos.z * 0.04 + TIME * 0.45);
	float w2 = sin(world_pos.x * -0.05 + world_pos.z * 0.08 + TIME * 0.3);
	float w3 = sin((world_pos.x + world_pos.z) * 0.03 - TIME * 0.2);
	vec3 wn = normalize(vec3(-(w1 * 0.6 + w3) * 0.02, 1.0, -(w2 * 0.6 - w3) * 0.02));

	vec3 shallow = vec3(0.28, 0.62, 0.66);
	vec3 deep = vec3(0.08, 0.28, 0.48);
	vec3 water = mix(shallow, deep, smoothstep(0.2, 4.0, shown));

	vec3 view_w = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 refl = reflect(-view_w, wn);
	float sky_h = clamp(refl.y * 1.15 + 0.05, 0.0, 1.0);
	vec3 sky = mix(vec3(0.62, 0.72, 0.78), vec3(0.18, 0.42, 0.72), sky_h);
	vec3 sun = normalize(sun_dir);
	float ndot = clamp(dot(refl, sun), 0.0, 1.0);
	float core = pow(ndot, 280.0);
	float spark = hash21(floor(world_pos.xz * 1.6 + vec2(TIME * 0.35, 0.0)));
	float glint = core * step(0.55, spark);
	if (use_ssr > 0.5) {
		vec2 ref_uv = SCREEN_UV + wn.xz * 0.04;
		float toward_sky = step(SCREEN_UV.y, ref_uv.y);
		vec3 mirror = texture(screen_tex, clamp(ref_uv, vec2(0.002), vec2(0.998))).rgb;
		sky = mix(sky, mirror, 0.25 * toward_sky);
	}
	float fres = pow(1.0 - clamp(dot(view_w, wn), 0.0, 1.0), 3.2);
	vec3 color = mix(water, sky, fres * 0.62 + 0.14);
	color += vec3(1.0, 0.98, 0.92) * glint * 0.42;

	float shore = smoothstep(-0.05, 0.28, depth) * (1.0 - smoothstep(0.2, 1.8, shown));
	shore *= 1.0 - open_water;
	float lap = 0.5 + 0.5 * sin(world_pos.x * 0.18 + world_pos.z * 0.13 + TIME * 0.7);
	color = mix(color, vec3(0.82, 0.9, 0.88), shore * (0.28 + 0.45 * lap));

	ALBEDO = color * 0.5;
	EMISSION = color * 0.55;
	ROUGHNESS = mix(0.04, 0.22, 1.0 - fres);
	SPECULAR = 0.85;
	METALLIC = 0.0;
	ALPHA = mix(smoothstep(-0.35, 0.7, depth), 1.0, open_water);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

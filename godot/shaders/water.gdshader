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

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2((world_pos.x - tile_origin.x) / tile_m.x, 1.0 - (world_pos.z - tile_origin.y) / tile_m.y);
	bool in_tile = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	// A few metres of blur, enough to hide the 2 m height steps and not the bank.
	vec2 blur = vec2(0.0014, 0.0014);
	float raw = in_tile ? decode_h(uv) : water_y - 4.0;
	float bed = raw;
	if (in_tile) {
		bed = raw * 0.4;
		bed += decode_h(uv + vec2(blur.x, 0.0)) * 0.15;
		bed += decode_h(uv - vec2(blur.x, 0.0)) * 0.15;
		bed += decode_h(uv + vec2(0.0, blur.y)) * 0.15;
		bed += decode_h(uv - vec2(0.0, blur.y)) * 0.15;
		// The bank is above the water. The flat reservoir sheet is the lake.
		if (raw > water_y + 0.4) {
			discard;
		}
	}
	float depth = max(water_y - bed, 0.0);
	float rise = 0.0;
	if (in_tile) {
		rise = max(abs(decode_h(uv + vec2(0.0022, 0.0)) - raw), abs(decode_h(uv + vec2(0.0, 0.0022)) - raw));
	}
	float sheet = (1.0 - smoothstep(0.12, 1.4, rise)) * (1.0 - smoothstep(0.05, 1.1, abs(water_y - raw)));
	float shown = mix(depth, 5.0, sheet);

	float w1 = sin(world_pos.x * 0.045 + world_pos.z * 0.02 + TIME * 0.3);
	float w2 = sin(world_pos.z * 0.04 - TIME * 0.22);
	vec3 wn = normalize(vec3(-w1 * 0.01, 1.0, -w2 * 0.01));

	vec3 shallow = vec3(0.16, 0.45, 0.52);
	vec3 deep = vec3(0.04, 0.2, 0.4);
	vec3 water = mix(shallow, deep, smoothstep(0.05, 2.8, shown));

	vec3 view_w = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 refl = reflect(-view_w, wn);
	float sky_h = clamp(refl.y * 1.1 + 0.04, 0.0, 1.0);
	vec3 sky = mix(vec3(0.55, 0.68, 0.76), vec3(0.16, 0.38, 0.66), sky_h);
	float fres = pow(1.0 - clamp(dot(view_w, wn), 0.0, 1.0), 2.6);
	vec3 color = mix(water, sky, fres * 0.35 + 0.05);

	float foam = smoothstep(0.0, 0.12, depth) * (1.0 - smoothstep(0.12, 0.7, depth));
	foam *= 1.0 - sheet;
	float lap = 0.7 + 0.3 * sin(world_pos.x * 0.07 + world_pos.z * 0.05 + TIME * 0.5);
	color = mix(color, vec3(0.78, 0.86, 0.84), foam * lap * 0.65);

	float ndot = clamp(dot(refl, normalize(sun_dir)), 0.0, 1.0);
	float spark = step(0.94, hash21(floor(world_pos.xz * 3.0)));
	float glint = pow(ndot, 500.0) * spark;

	ALBEDO = color;
	EMISSION = vec3(1.0, 0.98, 0.92) * glint * 0.4;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	ALPHA = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

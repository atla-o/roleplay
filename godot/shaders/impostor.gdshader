shader_type spatial;
render_mode cull_disabled, unshaded, depth_prepass_alpha, shadows_disabled;

// Hemi-octahedral atlas. Eight yaw columns, four elevation rows.
// UV (0,0) of a cell is the lower left of that view.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 grid = vec2(8.0, 4.0);

varying vec3 tint;
varying vec2 frame_uv;
varying vec3 view_dir;

vec2 hemi_oct(vec3 n) {
	float m = abs(n.x) + abs(n.y) + abs(n.z);
	vec2 p = n.xz / max(m, 0.0001);
	return p * 0.5 + 0.5;
}

void vertex() {
	tint = COLOR.rgb;
	frame_uv = UV;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	view_dir = normalize(to_cam);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = cross(up, view_dir);
	if (dot(right, right) < 0.0001) {
		right = vec3(1.0, 0.0, 0.0);
	}
	right = normalize(right);
	up = normalize(cross(view_dir, right));
	vec3 world = origin + right * VERTEX.x * sx + up * VERTEX.y * sy;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	NORMAL = to_cam;
}

void fragment() {
	vec2 oct = clamp(hemi_oct(view_dir), vec2(0.001), vec2(0.999));
	vec2 cell = clamp(floor(oct * grid), vec2(0.0), grid - vec2(1.0));
	vec2 local_uv = mix(vec2(0.06), vec2(0.94), frame_uv);
	vec2 uv = (cell + local_uv) / grid;
	vec4 tex = texture(atlas, uv);
	if (tex.a < 0.35) {
		discard;
	}
	vec3 ink = tint;
	if (dot(ink, vec3(1.0)) < 0.05) {
		ink = vec3(0.45, 0.55, 0.4);
	}
	float ink_l = max(dot(ink, vec3(0.25, 0.5, 0.25)), 0.08);
	ALBEDO = tex.rgb * clamp(ink / ink_l, vec3(0.35), vec3(1.15));
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}

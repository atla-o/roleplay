shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D imagery : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float fade = 1.0;
uniform float has_photo = 1.0;

varying vec3 world_normal;

float bayer4(vec2 p) {
	vec2 q = floor(mod(p, 4.0));
	float x = q.x;
	float y = q.y;
	// 4x4 Bayer, written with steps so the compatibility renderer does not need integer bitwise ops.
	float v = 0.0;
	v += (1.0 - step(1.0, x)) * (1.0 - step(1.0, y)) * 0.0;
	v += step(1.0, x) * (1.0 - step(2.0, x)) * (1.0 - step(1.0, y)) * 8.0;
	v += step(2.0, x) * (1.0 - step(3.0, x)) * (1.0 - step(1.0, y)) * 2.0;
	v += step(3.0, x) * (1.0 - step(1.0, y)) * 10.0;
	v += (1.0 - step(1.0, x)) * step(1.0, y) * (1.0 - step(2.0, y)) * 12.0;
	v += step(1.0, x) * (1.0 - step(2.0, x)) * step(1.0, y) * (1.0 - step(2.0, y)) * 4.0;
	v += step(2.0, x) * (1.0 - step(3.0, x)) * step(1.0, y) * (1.0 - step(2.0, y)) * 14.0;
	v += step(3.0, x) * step(1.0, y) * (1.0 - step(2.0, y)) * 6.0;
	v += (1.0 - step(1.0, x)) * step(2.0, y) * (1.0 - step(3.0, y)) * 3.0;
	v += step(1.0, x) * (1.0 - step(2.0, x)) * step(2.0, y) * (1.0 - step(3.0, y)) * 11.0;
	v += step(2.0, x) * (1.0 - step(3.0, x)) * step(2.0, y) * (1.0 - step(3.0, y)) * 1.0;
	v += step(3.0, x) * step(2.0, y) * (1.0 - step(3.0, y)) * 9.0;
	v += (1.0 - step(1.0, x)) * step(3.0, y) * 15.0;
	v += step(1.0, x) * (1.0 - step(2.0, x)) * step(3.0, y) * 7.0;
	v += step(2.0, x) * (1.0 - step(3.0, x)) * step(3.0, y) * 13.0;
	v += step(3.0, x) * step(3.0, y) * 5.0;
	return v / 16.0;
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Parent and child use complementary fades, so the 4x4 pattern partitions
	// the pixels instead of blending two LODs into a blur.
	if (fade < 0.999 && bayer4(FRAGCOORD.xy) >= fade) {
		discard;
	}
	vec3 photo = texture(imagery, UV).rgb;
	vec3 bare = vec3(0.34, 0.38, 0.3);
	float slope = clamp(1.0 - world_normal.y, 0.0, 1.0);
	bare = mix(bare, vec3(0.42, 0.4, 0.36), slope);
	vec3 color = mix(bare, photo, has_photo);
	ALBEDO = color;
	ROUGHNESS = mix(0.92, 0.78, has_photo);
	SPECULAR = 0.04;
}

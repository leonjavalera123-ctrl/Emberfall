// Faction pennant — cloth wave grows toward the free end (UV.x 0 = pole).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 col : source_color = vec3(0.7, 0.2, 0.15);

void vertex() {
	float w = UV.x;
	VERTEX.z += sin(TIME * 3.2 + w * 4.5) * 0.14 * w;
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

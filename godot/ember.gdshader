// Emberstone crystal shards — each MultiMesh instance carries its own pulse
// phase in INSTANCE_CUSTOM.x, so the fields shimmer out of sync.
shader_type spatial;

uniform vec3 base_col : source_color = vec3(0.30, 0.10, 0.05);
uniform vec3 glow_col : source_color = vec3(1.0, 0.52, 0.16);

varying float phase;

void vertex() {
	phase = INSTANCE_CUSTOM.x;
}

void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * 2.4 + phase * 6.2831);
	ALBEDO = base_col;
	EMISSION = glow_col * (0.7 + 2.4 * pulse);
	ROUGHNESS = 0.35;
}

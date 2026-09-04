// EMBERFALL: 1940 — scrolling tank treads.
//
// The baked vehicle mesh keeps its track surfaces on this material. Tread
// bands are cut from the LOCAL Z coordinate (the hull's long axis) and slide
// by `track_scroll`, which unit.gd advances by distance travelled — so the
// treads move exactly as fast as the ground passes under them, and stop dead
// when the vehicle does. One shared material for every tracked vehicle; the
// per-unit position rides the per-instance uniform.
shader_type spatial;
render_mode cull_back;

instance uniform float track_scroll = 0.0;

varying float vz;

void vertex() {
	vz = VERTEX.z;
}

void fragment() {
	// alternating tread plates, ~5 links per metre
	float band = step(0.42, fract(vz * 5.0 - track_scroll * 5.0));
	ALBEDO = mix(vec3(0.085, 0.082, 0.080), vec3(0.145, 0.140, 0.135), band);
	ROUGHNESS = 0.92;
	METALLIC = 0.25;
	// a faint lengthwise seam so the run reads as linked plates, not stripes
	float seam = smoothstep(0.0, 0.06, abs(fract(vz * 5.0 - track_scroll * 5.0) - 0.21));
	ALBEDO *= 0.85 + 0.15 * seam;
	// pipeline models bake ambient occlusion into COLOR — honour it here too,
	// or the running gear stays flat while the hull above it gains depth
	ALBEDO *= COLOR.rgb;
}

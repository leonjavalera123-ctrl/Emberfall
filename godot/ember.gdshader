// Emberstone crystal shards — each MultiMesh instance carries its own pulse
// phase in INSTANCE_CUSTOM.x, so the fields shimmer out of sync.
//
// The heat lives in the TIP: emission climbs the shard's height, so crystals
// read as molten cores burning up through dark stone rather than uniformly
// lit plastic. A fresnel rim catches the edges so every shard silhouettes
// against the ground even mid-pulse.
shader_type spatial;

uniform vec3 base_col : source_color = vec3(0.30, 0.10, 0.05);
uniform vec3 glow_col : source_color = vec3(1.0, 0.52, 0.16);

varying float phase;
varying float tip;

void vertex() {
	phase = INSTANCE_CUSTOM.x;
	// PrismMesh spans y -0.5..+0.5 locally; 0 at the base, 1 at the point
	tip = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}

void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * 2.4 + phase * 6.2831);
	ALBEDO = base_col * (0.7 + 0.5 * tip);
	// the point burns, the base stays stone — and the totals stay BELOW the
	// old flat emission: with screen-blend glow these values stack with the
	// under-glow decal, and the first pass of this shader washed the whole
	// field into one blinding rectangle
	float heat = 0.18 + 0.62 * tip * tip;
	EMISSION = glow_col * (0.6 + 1.6 * pulse) * heat;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += glow_col * rim * (0.25 + 0.3 * pulse);
	ROUGHNESS = 0.35;
}

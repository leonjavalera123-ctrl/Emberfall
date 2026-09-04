// Flooded-trench water: murky, slow-moving interference ripples, faint sheen.
shader_type spatial;
render_mode blend_mix, cull_back;

uniform vec3 deep_col : source_color = vec3(0.045, 0.09, 0.10);
uniform vec3 shallow_col : source_color = vec3(0.12, 0.21, 0.22);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// A PRODUCT of two axis-aligned sines is literally a checkerboard — which
	// is exactly what the old sin(x)*sin(z) painted across every trench, in
	// giant teal squares once the fog sun-scatter lit the surface. Real water
	// interference is a SUM of waves travelling at unrelated angles.
	// ...but a SUM is not enough on its own. The previous set still read as a
	// teal grid across every channel, because two of its four directions —
	// (0.93,0.36) and (-0.41,0.91) — are within three degrees of PERPENDICULAR,
	// and two perpendicular waves at similar frequencies are a checkerboard
	// whether you add them or multiply them. These five are spaced 35 degrees
	// apart so no pair is anywhere near 90, on frequencies with no small
	// integer ratio between them, so the pattern never closes up and repeats.
	vec2 q = wpos.xz;
	// domain warp: bending the sample point with a slow wave destroys what is
	// left of the regularity far more cheaply than piling on more octaves
	q += 0.35 * vec2(sin(q.y * 0.41 + TIME * 0.21), cos(q.x * 0.37 - TIME * 0.17));
	float ripple =
		  0.46 * sin(dot(q, vec2(1.000, 0.000)) * 1.31 + TIME * 0.61)
		+ 0.30 * sin(dot(q, vec2(0.814, 0.581)) * 2.17 - TIME * 0.43)
		+ 0.20 * sin(dot(q, vec2(0.325, 0.946)) * 3.41 + TIME * 0.86)
		+ 0.13 * sin(dot(q, vec2(-0.284, 0.959)) * 5.23 - TIME * 1.07)
		+ 0.08 * sin(dot(q, vec2(-0.790, 0.613)) * 8.09 + TIME * 1.43);
	float f = 0.5 + 0.28 * ripple;
	ALBEDO = mix(deep_col, shallow_col, f);
	// murky ash-water, not a mirror: the old 0.12 roughness caught the fog's
	// sun scatter as one huge white hotspot
	ROUGHNESS = 0.34;
	METALLIC = 0.05;
	SPECULAR = 0.45;
	EMISSION = vec3(0.02, 0.05, 0.05) * f;
	ALPHA = 0.94;
}

// Faction ensign — cloth wave grows toward the free end (UV.x 0 = pole).
shader_type spatial;
render_mode cull_disabled;

// The flag used to be one flat colour: the same three numbers already shown by
// the minimap blip, the health bar and the selection ring, so it carried no
// information the player did not already have. It now flies the banner's real
// ensign — field, hoist band and roundel — from textures/flag_f<N>.png.
uniform sampler2D banner : source_color, filter_linear_mipmap;
uniform bool use_tex = false;      // false keeps the old flat-colour behaviour
uniform vec3 col : source_color = vec3(0.7, 0.2, 0.15);

varying float lit;

void vertex() {
	float w = UV.x;
	float ph = TIME * 3.2 + w * 4.5;
	VERTEX.z += sin(ph) * 0.14 * w;
	// The DERIVATIVE of the same wave is the surface slope, so it doubles as
	// shading for free: the cloth darkens exactly where it turns away. Without
	// this the flag waves but stays perfectly evenly lit, which is what made
	// the old one read as a painted card rather than fabric.
	lit = cos(ph) * w;
}

void fragment() {
	vec3 c = col;
	if (use_tex) {
		vec4 t = texture(banner, UV);
		// frayed fly edge is authored as alpha; discard keeps the flag in the
		// opaque pass so it never sorts against smoke or the ground shadow
		if (t.a < 0.5) {
			discard;
		}
		c = t.rgb;
	}
	ALBEDO = c * (0.86 + 0.14 * lit);
	ROUGHNESS = 1.0;
}

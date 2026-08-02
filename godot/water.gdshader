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
	float ripple = sin(wpos.x * 1.1 + TIME * 0.7) * sin(wpos.z * 1.6 - TIME * 0.5)
			+ 0.5 * sin(wpos.x * 2.3 - TIME * 0.9);
	float f = 0.5 + 0.33 * ripple;
	ALBEDO = mix(deep_col, shallow_col, f);
	ROUGHNESS = 0.12;
	METALLIC = 0.1;
	SPECULAR = 0.6;
	EMISSION = vec3(0.02, 0.05, 0.05) * f;
	ALPHA = 0.94;
}

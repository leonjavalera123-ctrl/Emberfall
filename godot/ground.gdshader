// EMBERFALL: 1940 — the ground itself.
//
// Replaces the StandardMaterial3D world-triplanar setup on the terrain slabs.
// Two wins over triplanar:
//   * COST — triplanar samples every texture three times and blends; the
//     ground is overwhelmingly horizontal, so one planar XZ sample does the
//     same job at a third of the fetches.
//   * THE REPEAT — the same albedo is sampled again at 1/7th frequency and
//     multiplied in. That macro layer is what kills the visible tiling: the
//     eye locks onto the low-frequency mottling instead of the tile grid.
// Steep faces (trench walls, slab sides) fall back toward a plain darkened
// dirt so the planar projection never smears down them.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.1;
uniform float macro_amount : hint_range(0.0, 1.0) = 0.45;
uniform float normal_amount = 0.6;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz * uv_scale;
	vec3 alb = texture(albedo_tex, uv).rgb;
	// the anti-tiling layer: same texture, 1/7.3 the frequency, multiplied in.
	// 7.3 is deliberately irrational-ish so the two repeats never phase-lock.
	vec3 macro = texture(albedo_tex, uv * 0.137).rgb;
	alb *= mix(vec3(1.0), macro * 1.9, macro_amount);

	float topness = smoothstep(0.35, 0.7, clamp(wnorm.y, 0.0, 1.0));
	alb = mix(tint.rgb * 0.16, alb * tint.rgb, max(topness, 0.25));
	ALBEDO = alb;
	ROUGHNESS = texture(rough_tex, uv).r;

	// planar-XZ normal mapping, hand-built: for horizontal ground the tangent
	// frame is simply world +X / +Z, so the perturbation needs no mesh
	// tangents (whose UVs would disagree with this projection anyway)
	vec3 nrm = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 n_ws = normalize(wnorm
		+ vec3(1.0, 0.0, 0.0) * nrm.x * normal_amount * topness
		+ vec3(0.0, 0.0, 1.0) * nrm.y * normal_amount * topness);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_ws, 0.0)).xyz);
}

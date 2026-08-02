// EMBERFALL: 1940 — the sky over the Ashfall.
//
// An overcast, ash-choked sky: two scrolling cloud decks, a sun that never
// quite burns through, and a warm emberstone glow banked along the horizon.
// Self-contained (hash noise, no textures) so nothing needs importing.
//
// The cubemap/radiance pass runs a cheaper version of the clouds — ambient
// light only needs the broad shape, not the detail.

shader_type sky;

group_uniforms colors;
uniform vec3 zenith_color : source_color = vec3(0.155, 0.175, 0.225);
uniform vec3 horizon_color : source_color = vec3(0.60, 0.565, 0.485);
uniform vec3 ground_color : source_color = vec3(0.185, 0.175, 0.160);
uniform vec3 cloud_lit : source_color = vec3(0.78, 0.745, 0.685);
uniform vec3 cloud_dark : source_color = vec3(0.235, 0.235, 0.255);
uniform vec3 ember_color : source_color = vec3(0.95, 0.46, 0.16);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.66);

group_uniforms shape;
uniform float cloud_scale = 1.35;
uniform float cloud_cover = 0.58;      // 0 = clear, 1 = solid overcast
uniform float cloud_softness = 0.34;
uniform float cloud_speed = 0.0055;
uniform float dust_speed = 0.008;      // drift of the dust sea below the horizon
uniform float ember_band = 0.13;       // how far up the horizon glow reaches
uniform float ember_strength = 0.42;
uniform float sun_diffuse = 0.22;      // how much the sun burns through
uniform float haze_strength = 0.85;

// ---------------------------------------------------------------- value noise

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);          // smoothstep interpolation
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += vnoise(p) * amp;
		norm += amp;
		p *= 2.03;
		p += vec2(17.3, 9.1);                  // decorrelate the octaves
		amp *= 0.5;
	}
	return sum / max(norm, 0.0001);
}

// A cloud deck seen from below: project the view direction onto a plane
// overhead. Near the horizon that projection stretches toward infinity, so the
// caller fades the deck out down there instead of letting it alias.
float deck(vec3 dir, float scale, float t, int octaves) {
	float y = max(dir.y, 0.055);
	vec2 uv = dir.xz / y * scale;
	uv += vec2(t, t * 0.35);
	float n = fbm(uv, octaves);
	// a second, slower warp so the deck churns instead of merely sliding
	n = mix(n, fbm(uv * 0.51 - vec2(t * 0.6, 0.0), max(octaves - 1, 1)), 0.35);
	return n;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	bool cheap = AT_CUBEMAP_PASS;
	int oct = cheap ? 2 : 5;

	// ---- base gradient -------------------------------------------------
	float up = smoothstep(-0.04, 0.80, h);
	vec3 col = mix(horizon_color, zenith_color, pow(up, 0.72));

	// Below the horizon is the region the RTS camera actually shows: at a -52
	// degree pitch the whole frame sits under the horizontal, so everything
	// past the map boundary is this. It has to read as a dust sea receding into
	// haze, not as a flat wall.
	if (h < 0.0) {
		float depth = clamp(-h / 0.9, 0.0, 1.0);
		vec2 duv = vec2(dir.x * 2.2 + dir.z * 0.6 + TIME * dust_speed,
				depth * 5.5);
		float dust = fbm(duv, cheap ? 2 : 4);
		float streak = fbm(vec2(duv.x * 0.35, depth * 13.0), cheap ? 1 : 3);
		vec3 low = mix(horizon_color, ground_color, pow(depth, 0.8));
		low *= 0.82 + 0.34 * mix(dust, streak, 0.45);
		low += ember_color * pow(1.0 - depth, 3.0) * ember_strength * 0.45;
		col = low;
	}

	// ---- the sun, mostly smothered -------------------------------------
	vec3 sun_dir = vec3(0.0, 1.0, 0.0);
	float sun_amt = 0.0;
	if (LIGHT0_ENABLED) {
		sun_dir = normalize(-LIGHT0_DIRECTION);
		sun_amt = max(dot(dir, sun_dir), 0.0);
		// no hard disk — an overcast sky gives a broad bright smear
		float disk = pow(sun_amt, 220.0) * 0.55;
		float halo = pow(sun_amt, 7.0) * sun_diffuse;
		float wide = pow(sun_amt, 2.0) * 0.10;
		col += sun_color * (disk + halo + wide) * LIGHT0_ENERGY;
	}

	// ---- cloud decks ---------------------------------------------------
	float t = TIME * cloud_speed;
	float fade = smoothstep(0.008, 0.17, h);            // kill the horizon smear
	if (fade > 0.001) {
		float high = deck(dir, cloud_scale * 0.55, t * 0.6, max(oct - 1, 1));
		float low = deck(dir, cloud_scale * 1.6, t, oct);
		float n = mix(high, low, 0.55);

		// cover pushes the noise through a soft threshold into cloud shapes
		float lo = 1.0 - cloud_cover;
		float dens = smoothstep(lo - cloud_softness * 0.5,
				lo + cloud_softness * 0.5, n);
		dens *= fade;

		// light the clouds from the sun's side and let their undersides stay grim
		float lit = clamp(sun_amt * 0.85 + 0.30, 0.0, 1.0);
		lit *= mix(0.75, 1.0, smoothstep(0.0, 0.6, high));
		vec3 cloud = mix(cloud_dark, cloud_lit, lit);
		cloud += sun_color * pow(sun_amt, 5.0) * 0.30;   // silver lining

		col = mix(col, cloud, dens * 0.92);
	}

	// ---- emberstone glow along the horizon -----------------------------
	// The Cradle burns somewhere out there; the whole rim of the world is warm.
	float band = 1.0 - clamp(abs(h) / max(ember_band, 0.001), 0.0, 1.0);
	band = pow(band, 2.2);
	float toward_sun = 0.55 + 0.45 * clamp(dot(normalize(vec3(dir.x, 0.0, dir.z)),
			normalize(vec3(sun_dir.x, 0.0, sun_dir.z))), -1.0, 1.0);
	col += ember_color * band * ember_strength * toward_sun;

	// ---- haze that ties the sky to the scene fog -----------------------
	float haze = pow(1.0 - clamp(abs(h) / 0.5, 0.0, 1.0), 2.0) * haze_strength;
	col = mix(col, horizon_color, haze * 0.22);

	COLOR = col;
}

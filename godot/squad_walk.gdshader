// EMBERFALL: 1940 — the infantry gait.
//
// Infantry are baked into ONE mesh and drawn as a 6-instance MultiMesh, so
// there are no bones to animate and no per-man nodes to move. The walk is done
// here instead: every vertex carries its limb id and pivot height, and each
// instance carries its own gait phase in INSTANCE_CUSTOM.
//
//   UV.x   limb   0 body · 1 left leg · 2 right leg · 3 left arm · 4 right arm
//   UV.y   1 - pivot height in metres
//
// UV, NOT UV2 — and that one word is why the army marched like statues. The
// prep script names its Blender layer "UV2", but a Hunyuan mesh has no other
// UV layer, so the exporter writes it as the FIRST texcoord (TEXCOORD_0) and
// Godot imports that as UV. The old shader read UV2, a channel these meshes
// do not have: every limb id came back 0 and no vertex ever swung. The pivot
// rides in 1-v because the glTF exporter flips V on the way out.
//
//   INSTANCE_CUSTOM.x  gait phase in radians, advanced by DISTANCE TRAVELLED
//                      (not by TIME — that is what makes feet skate)
//   INSTANCE_CUSTOM.y  gait amount 0..1, eased in and out so a halted man
//                      settles instead of stopping mid-stride
//   INSTANCE_CUSTOM.z  per-man brightness jitter so six men are not stamped
//   INSTANCE_CUSTOM.w  fire kick 0..1: rifle recoil, decays over ~0.3 s

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float rough : hint_range(0.0, 1.0) = 0.85;
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_col : source_color = vec4(0.0);
uniform float emission_energy = 0.0;

uniform float leg_swing = 0.62;     // radians at a full stride
uniform float arm_swing = 0.38;
uniform float bob_amount = 0.016;   // metres — deliberately small

varying float v_jitter;

void vertex() {
	float limb = floor(UV.x + 0.5);
	float pivot = clamp(1.0 - UV.y, 0.0, 2.0);
	float phase = INSTANCE_CUSTOM.x;
	float amt = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	float kick = INSTANCE_CUSTOM.w;
	v_jitter = INSTANCE_CUSTOM.z;

	float ang = 0.0;
	if (limb > 0.5) {
		// limbs 1/3 lead while 2/4 trail, so the man is never mid-air on both feet
		float odd = (limb == 1.0 || limb == 3.0) ? 1.0 : -1.0;
		float swing = (limb < 2.5) ? leg_swing : -arm_swing;  // arms counter-swing
		ang = sin(phase) * odd * swing * amt;
	}
	// the shot: the firing arm snaps up and back, then eases down — it reads
	// as a rifle kick even at 27 px because it breaks the gait rhythm
	if (limb == 4.0) {
		ang -= kick * 0.55;
	}
	if (abs(ang) > 0.0005) {
		vec3 p = VERTEX;
		p.y -= pivot;
		float c = cos(ang);
		float s = sin(ang);
		// swing fore/aft: rotate in the YZ plane about the pivot
		float ny = p.y * c - p.z * s;
		float nz = p.y * s + p.z * c;
		p.y = ny;
		p.z = nz;
		p.y += pivot;
		// legs shorten slightly at the extremes so the feet do not sink
		if (limb < 2.5) {
			p.y += (1.0 - c) * pivot * 0.35;
		}
		VERTEX = p;
	}

	// A body rise of TWICE the stride frequency: the old code hopped the whole
	// man up and down on a single sine, which is what read as a bouncing toy.
	VERTEX.y += amt * bob_amount * (1.0 - cos(phase * 2.0)) * 0.5;
	if (limb < 0.5) {
		VERTEX.y += kick * 0.008;      // the torso rocks back a touch
	}
}

void fragment() {
	float j = 0.92 + v_jitter * 0.16;
	ALBEDO = albedo.rgb * COLOR.rgb * j;   // COLOR carries the baked AO
	ROUGHNESS = rough;
	METALLIC = metal;
	if (emission_energy > 0.0) {
		EMISSION = emission_col.rgb * emission_energy;
	}
}

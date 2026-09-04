r"""EMBERFALL model manifest — every unit's prep parameters, in one place.

WHY THIS FILE EXISTS
--------------------
Re-prepping a model used to mean reconstructing its arguments from memory: the
length it was scaled to, whether its running gear is wheels or tracks, and —
worst — the hand-verified orientation overrides. Four aircraft need an explicit
front_axis or force_yaw because the automatic rules genuinely cannot read them
(a biplane's stacked wings score as "tall" as its fuselage; an aircraft whose
mass sits behind midships defeats the centroid test). Those four were settled by
photographing each one in flight and judging the picture, which is expensive to
redo and easy to lose. Losing them silently reintroduces aircraft that fly
backwards, which is exactly the bug this pipeline already shipped once.

So: parameters live here, not in whatever call was last typed into the bridge.

FIELDS
------
src         concept glb, relative to blender\  (octree 48 = infantry, 64 = rest)
length      metres along the model's long axis; 0 with `height` for tall units
kind        vehicle | aircraft | infantry
wheeled     True for tyres, False for tracks. Controls how much of the lower
            hull is allowed to become tread-black — a wheeled model painted with
            the tracked rule loses 43% of its hull to a colour the art has only
            on the rubber.
track_band  fraction of height the running gear may occupy
front_axis  '+Y' / '-Y' to override the nose test  (verified visually)
force_yaw   True/False to override the fuselage-axis test  (verified visually)
"""

# ---- ORIENTATION OVERRIDES, ROUND 2 (2026-08-14) --------------------------
# A 64-agent panel photographed all 32 models facing a known heading and judged
# each from the picture, with an independent refuter per model. SIX vehicles
# were shipping REVERSED — the two Leon caught (Juggernaut, Hammerfall) plus
# Keelwright, Rat, Stovepipe and Warpig, which nobody had noticed.
#
# WHY THE RULE FAILS: the vehicle nose test assumes "the thin end is the gun
# barrel, therefore the front". That holds for a turreted tank. It inverts on
# anything whose BULK is forward and whose thin end is an exhaust stack, a
# launcher tube or a tapered stern — which is most of this list. The panel's
# reasoning is the durable part: engine stacks + radiator grille + flat riveted
# deck = STERN, and a cab/glacis/barrel = BOW, regardless of which end is thinner.
M = {
    # ---- Karvath Iron Concord ------------------------------------------
    "bastion":       dict(src="hunyuan_64/bastion_concept.glb",    length=3.20, kind="vehicle", wheeled=False),
    "juggernaut":    dict(src="hunyuan/juggernaut_concept.glb", length=5.20, kind="vehicle", wheeled=False, front_axis="-Y"),
    "outrider":      dict(src="hunyuan_64/outrider_concept.glb",   length=2.70, kind="vehicle", wheeled=True,  track_band=0.20),
    # HALF-TRACK: wheels forward, a full track run aft. Neither rule fits it
    # exactly, but the run is the bigger dark mass and the wheeled rule was
    # leaving it painted hull grey, so it takes the tracked treatment.
    "sperrwagen":    dict(src="hunyuan_64/sperrwagen_concept.glb", length=2.70, kind="vehicle", wheeled=False),
    "hammerfall":    dict(src="hunyuan_64/hammerfall_concept.glb", length=3.40, kind="vehicle", wheeled=False, front_axis="-Y"),
    "mule":          dict(src="hunyuan_64/mule_concept.glb",       length=3.00, kind="vehicle", wheeled=True,  track_band=0.20),
    "warpig":        dict(src="hunyuan_64/warpig_concept.glb",     length=3.20, kind="vehicle", wheeled=False, front_axis="-Y"),
    "forge_crawler": dict(src="hunyuan_64/forge_crawler_concept.glb", length=4.40, kind="vehicle", wheeled=False),
    "kondor":        dict(src="hunyuan_64/kondor_concept.glb",     length=4.60, kind="aircraft"),
    # INFANTRY SCALE BY HEIGHT, NEVER LENGTH. A standing figure's long axis is
    # VERTICAL; scaling its horizontal span to 1.75 m let the height balloon to
    # 4-5.6 m, and the uniform re-prep shipped soldiers taller than the tanks.
    "iron_guard":    dict(src="hunyuan_48/iron_guard_concept.glb", height=1.75, kind="infantry", out="unit_soldier_karvath"),

    # ---- Ashfall Compact -----------------------------------------------
    # TRACKED, not wheeled — the concept is a tankette on full-length runs, and
    # the wheeled rule confines the dark band to the tyres, which left the
    # Rat's track runs painted olive hull colour instead of tread black.
    # FACING CONFIRMED independently (the round-2 panel's refuter for this model
    # died on a spend limit, so it was carrying a single unchecked vote): the
    # roof climbs 1.09 -> 2.00 m over the leading third, which is a glacis, and
    # falls away gradually behind, which is an engine deck; the leading band
    # holds 19,843 verts at full width against 3,106 behind it; and the exhaust
    # pipe the concept puts on the rear deck renders on the TRAILING end.
    "rat":           dict(src="hunyuan_64/rat_concept.glb",        length=2.70, kind="vehicle", wheeled=False, front_axis="+Y"),
    "stovepipe":     dict(src="hunyuan_64/stovepipe_concept.glb",  length=2.70, kind="vehicle", wheeled=True,  track_band=0.20, front_axis="-Y"),
    "magpie":        dict(src="hunyuan_64/magpie_concept.glb",     length=3.00, kind="vehicle", wheeled=True,  track_band=0.20),
    "ashworm":       dict(src="hunyuan/ashworm_concept.glb",    length=5.60, kind="vehicle", wheeled=False),
    "scrap_hauler":  dict(src="hunyuan_64/scrap_hauler_concept.glb", length=4.40, kind="vehicle", wheeled=False),
    # BIPLANE: two stacked wings make the span axis score as "tall" as the
    # fuselage (0.61 vs 0.65), so the automatic yaw test picks the wrong axis
    # and the Duster flies sideways. Verified by photographing it in flight.
    "duster":        dict(src="hunyuan_64/duster_concept.glb",     length=4.00, kind="aircraft", force_yaw=False),
    "conscript":     dict(src="hunyuan_48/conscript_concept.glb",  height=1.75, kind="infantry", out="unit_soldier_ashfall"),

    # ---- Aurelian League -----------------------------------------------
    "pavise":        dict(src="hunyuan_64/pavise_concept.glb",     length=3.30, kind="vehicle", wheeled=False),
    "dart":          dict(src="hunyuan_64/dart_concept.glb",       length=2.70, kind="vehicle", wheeled=True,  track_band=0.20),
    "zephyr":        dict(src="hunyuan_64/zephyr_concept.glb",     length=2.70, kind="vehicle", wheeled=True,  track_band=0.20),
    "dray":          dict(src="hunyuan_64/dray_concept.glb",       length=3.00, kind="vehicle", wheeled=True,  track_band=0.20),
    "keelwright":    dict(src="hunyuan_64/keelwright_concept.glb", length=4.40, kind="vehicle", wheeled=False, front_axis="-Y"),
    "sparrowhawk":   dict(src="hunyuan_64/sparrowhawk_concept.glb", length=3.80, kind="aircraft"),
    "wasp":          dict(src="hunyuan_64/wasp_concept.glb",       length=2.80, kind="aircraft"),
    "pelican":       dict(src="hunyuan_64/pelican_concept.glb",    length=5.20, kind="aircraft"),
    # airship: the hull is a fat cigar and the centroid barely leans, so the
    # nose test is inside its own noise. Settled by picture — the finned stern
    # trails, the blunt prow leads.
    "leviathan":     dict(src="hunyuan_96/leviathan_concept.glb",  length=7.50, kind="aircraft", front_axis="+Y"),
    "sky_marine":    dict(src="hunyuan_48/sky_marine_concept.glb", height=1.75, kind="infantry", out="unit_soldier_aurelia"),

    # ---- Luminar Covenant ----------------------------------------------
    "glimmer":       dict(src="hunyuan_64/glimmer_concept.glb",    length=2.70, kind="vehicle", wheeled=True,  track_band=0.20),
    # WALKER with a cannon on EACH FLANK: the side barrels are its longest
    # horizontal span, so the auto yaw rule aligned the BARRELS with travel and
    # the visor faced sideways. force_yaw=False keeps the true body axis on
    # travel. Trap for the next reader: do NOT diagnose this from the raw glb's
    # axis spans — glTF is Y-up, so its y-span is the walker's HEIGHT; the
    # first "fix" here measured that, picked True, and changed nothing.
    "faraday":       dict(src="hunyuan_64/faraday_concept.glb",    length=2.30, kind="vehicle", wheeled=False, force_yaw=False, front_axis="+Y"),
    "ion_carriage":  dict(src="hunyuan_64/ion_carriage_concept.glb", length=2.70, kind="vehicle", wheeled=True, track_band=0.20),
    "dynamo":        dict(src="hunyuan_64/dynamo_concept.glb",     length=2.70, kind="vehicle", wheeled=True,  track_band=0.20),
    "collector":     dict(src="hunyuan_64/collector_concept.glb",  length=3.00, kind="vehicle", wheeled=True,  track_band=0.20),
    "ark_carriage":  dict(src="hunyuan_64/ark_carriage_concept.glb", length=4.40, kind="vehicle", wheeled=False),
    # mass sits behind midships (the thruster pod), which inverts the centroid
    # rule these two would otherwise use. Both verified by picture.
    "seraph":        dict(src="hunyuan_64/seraph_concept.glb",     length=3.80, kind="aircraft", front_axis="+Y"),
    "cathedral":     dict(src="hunyuan_96/cathedral_concept.glb",  length=7.00, kind="aircraft", front_axis="+Y"),
    "arc_templar":   dict(src="hunyuan_48/arc_templar_concept.glb", height=1.75, kind="infantry", out="unit_soldier_luminar"),
    # no sculpt of its own: the Warden shares the Templar body, and is
    # distinguished in game by its weapon and stats rather than its mesh

    # ---- Structures ------------------------------------------------------
    # `length` is the FOOTPRINT in metres: the game places these on a tile grid
    # at 1 tile = 2 m, so a size-2 building must span 4 m and a size-3 must span
    # 6 m or it will not sit on its own pad. Carved at octree 96 rather than 64
    # because a base has a dozen structures, not forty, and the camera lingers
    # on them — and their roofs are the surface it actually sees.
    "bld_boiler":        dict(src="hunyuan_96/bld_boiler_concept.glb",        length=4.0, kind="building"),
    "bld_barracks":      dict(src="hunyuan_96/bld_barracks_concept.glb",      length=4.0, kind="building"),
    "bld_refinery":      dict(src="hunyuan_96/bld_refinery_concept.glb",      length=6.0, kind="building"),
    "bld_vehicle_works": dict(src="hunyuan_96/bld_vehicle_works_concept.glb", length=6.0, kind="building"),
    "bld_airfield":      dict(src="hunyuan_96/bld_airfield_concept.glb",      length=6.0, kind="building"),
    "bld_doomworks":     dict(src="hunyuan_96/bld_doomworks_concept.glb",     length=6.0, kind="building"),
    "bld_gun_turret":    dict(src="hunyuan_64/bld_gun_turret_concept.glb",    length=2.0, kind="building"),
    "bld_aa_turret":     dict(src="hunyuan_64/bld_aa_turret_concept.glb",     length=2.0, kind="building"),
}


def build(names, root=r"C:\Users\leonj\Emberfall", only_existing=True):
    """Prep + export each named unit. Returns [(name, ok, note), ...].

    Runs them all inside ONE bridge call: prep(fresh=False) clears the scene by
    hand rather than via read_homefile, which would break the glTF exporter's
    context for the rest of the call and force a round trip per model.
    """
    import os
    import bpy
    import prep_model
    out = []
    for n in names:
        cfg = dict(M[n])
        src = os.path.join(root, "blender", cfg.pop("src").replace("/", os.sep))
        # structures already carry their bld_ prefix in the key; units do not.
        # `out` overrides the stem entirely — the squad system reads soldiers
        # as unit_soldier_<faction>.glb, not unit_<kind>.glb.
        stem = cfg.pop("out", None)
        if stem is None:
            stem = n if n.startswith("bld_") else "unit_%s" % n
        dst = os.path.join(root, "godot", "models", "%s.glb" % stem)
        if only_existing and not os.path.exists(src):
            out.append((n, False, "no concept glb"))
            continue
        try:
            prep_model.prep(src, dst, fresh=False, **cfg)
            bpy.ops.export_scene.gltf(
                filepath=dst, export_format='GLB', use_selection=True,
                export_vertex_color='MATERIAL', export_all_vertex_colors=True,
                export_active_vertex_color_when_no_material=True)
            out.append((n, True, ""))
        except Exception as exc:                      # keep the batch going
            out.append((n, False, repr(exc)[:120]))
    return out

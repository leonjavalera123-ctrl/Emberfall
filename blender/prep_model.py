r"""EMBERFALL asset prep — the reusable step between Hunyuan3D and Godot.

Run inside Blender (via the MCP bridge or `blender --python`):

    import prep_model
    prep_model.prep(r"...\hunyuan\bastion_concept.glb",
                    r"...\godot\models\unit_bastion.glb",
                    length=3.2, kind="vehicle")

WHY THE AO PASS EXISTS
----------------------
Hunyuan3D returns SHAPE ONLY — no textures, no vertex colours. Emberfall then
paints the hull with one flat faction tint, so from a 52-degree RTS camera all
the rivets, panel seams and vents the concept art carved end up invisible: the
unit reads as a single coloured blob no matter how good the mesh is.

Baking ambient occlusion into VERTEX COLOURS fixes exactly that. Every crevice
Hunyuan carved gets darker, every raised plate stays bright, and because the
game's materials multiply vertex colour into albedo, the detail survives the
faction tint instead of being flattened by it. No UVs required — which matters,
because these meshes have none.

Crownhold learned this the easy way (Rodin returned textured meshes); Emberfall
has to bake it.
"""
import bpy
import math
import numpy as np


# ---------------------------------------------------------------- ambient occlusion

def bake_ao_to_vertex_colours(obj, samples=64, radius=0.75, strength=1.25,
                              floor=0.22, seed=7, gamma=0.85):
    """Ray-cast AO per vertex, written to a 'Col' colour attribute.

    Deliberately hand-rolled rather than using Blender's bake system: bpy.ops
    bake needs a UV map (these meshes have none), a Cycles render context, and
    a viewport — none of which exist over the MCP bridge.
    """
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    no = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    me.vertices.foreach_get("normal", no)
    co = co.reshape(n, 3)
    no = no.reshape(n, 3)

    rng = np.random.default_rng(seed)
    # cosine-weighted hemisphere directions, shared across vertices
    dirs = rng.normal(size=(samples, 3))
    dirs /= np.linalg.norm(dirs, axis=1)[:, None]

    bvh_obj = obj
    occl = np.zeros(n, dtype=np.float64)
    eps = radius * 0.02

    for i in range(n):
        origin = co[i]
        normal = no[i]
        nrm = normal / (np.linalg.norm(normal) + 1e-9)
        # flip any sample pointing into the surface
        d = dirs.copy()
        flip = d @ nrm < 0.0
        d[flip] = -d[flip]
        hits = 0
        start = origin + nrm * eps
        for k in range(samples):
            hit, _, _, _ = bvh_obj.ray_cast(start, d[k], distance=radius)
            if hit:
                hits += 1
        occl[i] = hits / float(samples)

    light = np.clip(1.0 - occl * strength, 0.0, 1.0)
    # gamma < 1 deepens the mid-tones, which is where panel seams live; a
    # straight linear ramp left the whole hull sitting near 0.8 and the detail
    # never showed through the flat faction tint at RTS distance
    light = np.power(light, 1.0 / gamma)
    light = floor + (1.0 - floor) * light          # never fully black
    light = np.clip(light, 0.0, 1.0)

    # write per LOOP (Blender colour attributes are per corner)
    if me.color_attributes:
        for ca in list(me.color_attributes):
            me.color_attributes.remove(ca)
    ca = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    loops = len(me.loops)
    vidx = np.empty(loops, dtype=np.int32)
    me.loops.foreach_get("vertex_index", vidx)
    cols = np.ones((loops, 4), dtype=np.float64)
    cols[:, 0] = light[vidx]
    cols[:, 1] = light[vidx]
    cols[:, 2] = light[vidx]
    ca.data.foreach_set("color", cols.ravel())
    me.update()
    return float(light.mean()), float(light.min())


def dust_lower_hull(obj, band=0.42, strength=0.55, power=1.7,
                    tint=(1.0, 0.90, 0.74)):
    """Warm the vertex colours toward road dust near the ground.

    Every unit was uniformly clean from roof to skirt, which is what made the
    army read as models placed ON a battlefield rather than vehicles driving
    THROUGH one — the hull ended in a hard clean line against the dirt. Real
    kit is filthiest where it is closest to the ground, so this ramps a warm
    earth tint up the lower `band` of the model.

    It rides the same COLOR_0 attribute the AO already uses, so it costs
    nothing at runtime and needs no UVs — the materials multiply vertex colour
    into albedo, which means the dirt survives the faction tint exactly the way
    the baked occlusion does. Multiplying can only ever darken, which is the
    correct direction: dust dulls a hull, it does not brighten it.
    """
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    zmin, zmax = co[:, 2].min(), co[:, 2].max()
    span = max(zmax - zmin, 1e-6)

    # 1 at the very bottom, 0 at the top of the band
    t = np.clip(1.0 - (co[:, 2] - zmin) / (span * band), 0.0, 1.0) ** power
    t *= strength

    ca = me.color_attributes.get("Col")
    if ca is None:
        return 0.0
    loops = len(me.loops)
    vidx = np.empty(loops, dtype=np.int32)
    me.loops.foreach_get("vertex_index", vidx)
    cols = np.empty(loops * 4, dtype=np.float64)
    ca.data.foreach_get("color", cols)
    cols = cols.reshape(loops, 4)

    tl = t[vidx][:, None]
    factor = (1.0 - tl) + tl * np.array(tint)[None, :]
    cols[:, :3] *= factor
    ca.data.foreach_set("color", cols.ravel())
    me.update()
    return float(t.max())


# ---------------------------------------------------------------- orientation

def _sustain(co, ax):
    """How well is HEIGHT sustained along this horizontal axis (0..1).

    A fuselage keeps a tall cross-section from nose to tail, so most bins along
    it are near the model's full height. A wing is a thin sheet everywhere
    except the root, so most bins along the SPAN are a fraction of it. That
    difference is what tells a 3.77 m wingspan apart from a 2.68 m fuselage on
    the same aircraft — which raw extents cannot do, because on a fighter the
    span is simply the longer of the two.
    """
    lo, hi = co[:, ax].min(), co[:, ax].max()
    if hi - lo < 1e-6:
        return 0.0
    hs = []
    for i in range(16):
        a = lo + (hi - lo) * i / 16.0
        b = lo + (hi - lo) * (i + 1) / 16.0
        m = (co[:, ax] >= a) & (co[:, ax] < b)
        if m.sum() > 3:
            sel = co[m][:, 2]
            hs.append(float(sel.max() - sel.min()))
        else:
            hs.append(0.0)
    hs = np.array(hs)
    return float(np.median(hs) / max(hs.max(), 1e-6))


def orient_and_scale(obj, length=3.2, front_axis=None, height=0.0,
                     aircraft=False, force_yaw=None):
    """Face +Y, ground to z=0, centre on x/y, scale to `length` metres.

    front_axis: None = auto-detect, or one of '+Y' / '-Y' to force it.
    aircraft:   use the fuselage/centroid rules instead of the vehicle ones.
                A plane breaks BOTH vehicle assumptions — see below.
    force_yaw:  None = auto, True/False to force the 90-degree yaw. Needed for
                a BIPLANE: two stacked wings make the SPAN axis score nearly as
                "tall" as the fuselage (the Duster measured 0.61 vs 0.65), so
                the sustained-height test cannot separate them and picks wrong.
    """
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)

    # Hunyuan does not guarantee which horizontal axis the vehicle lies along.
    # A model that came out rotated 90 degrees scaled to 6.7 m WIDE and 2.9 m
    # long, because the length budget was applied to the short axis. Put the
    # longest horizontal span on Y before doing anything else.
    xs = co[:, 0].max() - co[:, 0].min()
    ys = co[:, 1].max() - co[:, 1].min()
    if aircraft and max(xs, ys) / max(min(xs, ys), 1e-6) < 2.0:
        # "the longest horizontal span is the length" is TRUE for a tank and
        # FALSE for an aircraft: the Sparrowhawk's wingspan (3.77 m) is longer
        # than its fuselage (2.68 m), so that rule laid the wingspan along Y,
        # scaled the span to the intended LENGTH, and left the aircraft flying
        # sideways with its nose pointing north. When the two spans are within
        # 2x of each other the extents cannot decide it, so ask which axis the
        # height is sustained along. Past 2x the model is unambiguously long
        # and thin (the Wasp is 2.80 x 0.75) and the extents are trustworthy.
        need_yaw = _sustain(co, 0) > _sustain(co, 1)
    else:
        need_yaw = xs > ys
    if force_yaw is not None:
        need_yaw = bool(force_yaw)
    if need_yaw:
        yaw = np.array([[0.0, 1.0, 0.0], [-1.0, 0.0, 0.0], [0.0, 0.0, 1.0]])
        co = co @ yaw.T
        me.vertices.foreach_set("co", co.ravel())
        me.update()

    if front_axis is None:
        ymin, ymax = co[:, 1].min(), co[:, 1].max()
        if aircraft:
            # The vehicle rule (thin end = the gun barrel = the nose) inverts
            # on an aircraft: the THIN end of a plane is its tail. Use mass
            # instead — on a PROPELLER aircraft the engine, cockpit and the fat
            # part of the fuselage are all forward and the tail tapers away
            # behind the wing, so the volume centroid leans toward the NOSE.
            #
            # This holds for the Sparrowhawk, Pelican, Kondor and Wasp, and it
            # FAILS for anything whose mass sits aft: the Seraph's thruster pod,
            # and the Leviathan's and Cathedral's gondolas and belly turrets,
            # all pull the centroid sternward and point the ship backwards.
            # Those four are pinned with an explicit front_axis by their caller
            # rather than by tuning this threshold until it happens to agree —
            # a threshold that flips one of the working four back is worse.
            front_axis = '-Y' if co[:, 1].mean() < (ymin + ymax) * 0.5 else '+Y'
        else:
            band = (ymax - ymin) * 0.08
            lo = co[co[:, 1] < ymin + band]
            hi = co[co[:, 1] > ymax - band]
            lo_area = (lo[:, 0].max() - lo[:, 0].min()) * (lo[:, 2].max() - lo[:, 2].min())
            hi_area = (hi[:, 0].max() - hi[:, 0].min()) * (hi[:, 2].max() - hi[:, 2].min())
            front_axis = '-Y' if lo_area < hi_area else '+Y'

    if front_axis == '-Y':
        rot = np.array([[-1.0, 0.0, 0.0], [0.0, -1.0, 0.0], [0.0, 0.0, 1.0]])
        co = co @ rot.T

    # Scaling by LENGTH alone crushed the Juggernaut: it is a long machine, so
    # matching its length forced its height down and the siege battleship read
    # as a flat platform. `height` scales by stature instead, for anything
    # whose menace comes from being tall rather than long.
    if height > 0.0:
        span = co[:, 2].max() - co[:, 2].min()
        co *= (height / span)
    else:
        span = co[:, 1].max() - co[:, 1].min()
        co *= (length / span)
    co[:, 0] -= (co[:, 0].max() + co[:, 0].min()) / 2.0
    co[:, 1] -= (co[:, 1].max() + co[:, 1].min()) / 2.0
    co[:, 2] -= co[:, 2].min()

    me.vertices.foreach_set("co", co.ravel())
    me.update()
    obj.matrix_world.identity()
    return front_axis, co


# ---------------------------------------------------------------- smoothing

def strip_loose_parts(obj, keep_frac=0.06):
    """Delete connected shells smaller than `keep_frac` of the biggest one.

    Concept art likes to bank loose rubble around a ruin, and Hunyuan carves
    every brick of it as its own little closed shell. That wrecks decimation:
    COLLAPSE works per connected component and cannot take a shell below a
    handful of faces, so a ruin asked to come down to 2,600 triangles stopped
    at 40,746 — the budget was being spent almost entirely on gravel.

    Dropping the crumbs also fixes a second problem. The scatter drops these on
    uneven ground, where individually modelled pebbles float or sink anyway.
    """
    import bmesh
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()

    seen = set()
    parts = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        comp = []
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        parts.append(comp)

    if len(parts) < 2:
        bm.free()
        return 0, 0
    biggest = max(len(c) for c in parts)
    doomed = []
    for comp in parts:
        if len(comp) < biggest * keep_frac:
            doomed.extend(comp)
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()
    return len(parts), len(doomed)


def decimate_to(obj, target_tris):
    """Collapse the mesh down to roughly `target_tris` triangles.

    Units are placed a few dozen at a time and can afford 20-40k each. TERRAIN
    props cannot: a rock is instanced on every rock tile, which is hundreds per
    map, so the hand-made kit sits at 320-1280 tris apiece. A raw Hunyuan carve
    dropped in at 40k would have put tens of millions of triangles on the field.

    The Decimate MODIFIER is used rather than any bmesh call because there is no
    bmesh decimate operator, and it is applied by evaluating the depsgraph
    instead of bpy.ops.object.modifier_apply — ops needs an active object and a
    viewport, neither of which exists over the MCP bridge.
    """
    def _apply():
        dg = bpy.context.evaluated_depsgraph_get()
        baked = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        obj.modifiers.clear()
        old = obj.data
        obj.data = baked
        bpy.data.meshes.remove(old)

    n0 = len(obj.data.polygons)
    if n0 <= target_tris:
        return n0, n0

    # PLANAR DISSOLVE FIRST. Collapse alone stalled badly on the ruins — a
    # 57,576-triangle farmhouse asked for 2,600 stopped at 40,700 — because
    # COLLAPSE will not collapse an edge that would break boundary topology,
    # and a ruin is nothing but boundaries: window openings, doorways, broken
    # wall tops, thin two-sided walls. Architecture is the ideal case for a
    # planar pass instead, since a flat wall of a thousand coplanar triangles
    # is a handful of ngons. Collapse then cleans up whatever is left.
    if n0 > target_tris * 2:
        mod = obj.modifiers.new("ef_planar", 'DECIMATE')
        mod.decimate_type = 'DISSOLVE'
        mod.angle_limit = math.radians(6.0)
        _apply()

    n1 = len(obj.data.polygons)
    if n1 > target_tris:
        mod = obj.modifiers.new("ef_collapse", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = float(target_tris) / float(n1)
        _apply()
    return n0, len(obj.data.polygons)


def smooth_mesh(obj, iterations=2, factor=0.5):
    """Laplacian smoothing, done by hand in numpy.

    Hunyuan carves on a voxel grid, so a large smooth surface — an airship
    hull, a wing, a fuselage — comes back with visible stair-step ridges that
    read as corrugation under a moving light. Higher octree makes the steps
    finer but never removes them, and it costs triangles the RTS camera will
    never resolve. Averaging each vertex toward its neighbours flattens the
    ridges while leaving the silhouette intact, which is the cheaper trade.

    Blender's SMOOTH modifier would do this, but applying a modifier needs a
    viewport context that the MCP bridge does not have.
    """
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)

    # neighbour sums via the edge list: each edge contributes to both ends
    ed = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ed)
    a = ed[0::2]
    b = ed[1::2]
    deg = np.bincount(np.concatenate([a, b]), minlength=n).astype(np.float64)
    deg[deg == 0.0] = 1.0

    for _ in range(iterations):
        acc = np.zeros_like(co)
        np.add.at(acc, a, co[b])
        np.add.at(acc, b, co[a])
        co += factor * (acc / deg[:, None] - co)

    me.vertices.foreach_set("co", co.ravel())
    me.update()
    return co


# ---------------------------------------------------------------- materials

def _mat(name, rgb, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def tag_trim_edges(obj, target=0.022, lo_deg=22.0, hi_deg=75.0, protect=(1,),
                   dilate=1, min_run=28):
    """Paint slot 3 (brass/accent trim) along CONVEX creases.

    The concept art puts its accent metal on thin trim strips outlining panels,
    on hopper rims and on headlamp bezels — never on broad plate. The old rule
    assigned accent by REGION (the whole centreline deck, the whole rear deck),
    which produced gold slabs: roughly 15% of the hull in a few big blobs where
    the art has ~2% in fine lines. Region tests cannot express "the edge of a
    thing", so this uses geometry instead — a face bordering a sharp CONVEX
    crease is, by definition, on the lip of a panel.

    The angle threshold is searched rather than fixed. Hunyuan carves on a voxel
    grid, so mesh sharpness varies hugely between a smooth airship hull and a
    riveted truck: one fixed angle gilds a truck and leaves an airship bare.
    Bisecting to a target FRACTION of faces gives every model the same visual
    weight of trim, which is what actually reads consistent on the field.

    Faces already assigned to `protect` (the tracks) are never overpainted —
    tyres and treads have no brass on them in any concept.
    """
    import bmesh
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()

    # precompute each edge's crease angle once; the search only re-thresholds
    creases = []
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        if not e.is_convex:            # a concave seam is a gap, not a lip
            continue
        creases.append((math.degrees(e.calc_face_angle(0.0)),
                        [f.index for f in e.link_faces]))

    nfaces = len(bm.faces)
    protected = {i for i, p in enumerate(me.polygons) if p.material_index in protect}
    eligible = max(nfaces - len(protected), 1)

    def pick(deg):
        s = set()
        for ang, fids in creases:
            if ang >= deg:
                for fi in fids:
                    if fi not in protected:
                        s.add(fi)
        return s

    lo, hi = lo_deg, hi_deg
    best = pick(hi)
    for _ in range(12):
        mid = (lo + hi) / 2.0
        got = pick(mid)
        if len(got) / eligible > target:
            lo = mid                   # too much trim: demand sharper creases
        else:
            hi = mid
        best = got

    # Thicken the runs. A crease selects exactly the two faces touching it,
    # which is a line ONE face wide — and at the RTS camera's distance a unit is
    # about 60 px tall, so that line lands under a pixel and the brass vanishes
    # completely. Widening by face-adjacency thickens the strips that were
    # already found instead of lowering the angle and scattering trim into new
    # places, which is the difference between a trim strip and a gold rash.
    for _ in range(dilate):
        grow = set()
        for fi in best:
            for e in bm.faces[fi].edges:
                for nf in e.link_faces:
                    if nf.index not in protected:
                        grow.add(nf.index)
        best |= grow

    # Drop speckle. On a smooth domed hull — the Faraday's cupola, an airship
    # envelope — the sharpest creases are voxel stair-stepping rather than panel
    # lips, so the selection came out as scattered islands a few faces across.
    # Painted in a contrasting metal that reads as battle damage or splashed
    # paint, not as trim. Real trim runs: keeping only components above a floor
    # throws the noise away and leaves the genuine edges, which are long.
    if min_run > 1:
        seen, keep = set(), set()
        for fi in best:
            if fi in seen:
                continue
            stack, comp = [fi], []
            seen.add(fi)
            while stack:                       # flood fill over shared edges
                cur = stack.pop()
                comp.append(cur)
                for e in bm.faces[cur].edges:
                    for nf in e.link_faces:
                        if nf.index in best and nf.index not in seen:
                            seen.add(nf.index)
                            stack.append(nf.index)
            if len(comp) >= min_run:
                keep.update(comp)
        best = keep
    bm.free()

    for fi in best:
        me.polygons[fi].material_index = 3
    me.update()
    return len(best), len(best) / max(nfaces, 1), hi


def ensure_slots_nonempty(obj, nslots=4):
    """Give every material slot at least one face.

    The glTF exporter emits ONE primitive PER USED SLOT. Godot's importer can
    drop material names, so unit.gd identifies a surface by its INDEX against a
    fixed role table — which silently breaks the moment a slot is empty and the
    exporter renumbers what is left. An aircraft has no tracks and no gun deck,
    so its trim would have arrived as surface 1 and been painted tread-black.
    One stolen triangle per empty slot is invisible and keeps the contract.
    """
    me = obj.data
    used = set(p.material_index for p in me.polygons)
    donor = [p for p in me.polygons]
    fixed = []
    for si in range(nslots):
        if si in used:
            continue
        for p in donor:
            if sum(1 for q in me.polygons if q.material_index == p.material_index) > 4:
                p.material_index = si
                fixed.append(si)
                break
    me.update()
    return fixed


def split_vehicle_materials(obj, co, track_band=0.42, wheeled=False):
    """Slot 0 = hull (faction tint), 1 = track, 2 = steel, 3 = trim.

    Emberfall's baker reads these BY SLOT INDEX, because Godot's importer can
    drop the material names — so the order here is load-bearing, not cosmetic.
    """
    me = obj.data
    me.materials.clear()
    me.materials.append(_mat("unit_tint", (0.45, 0.42, 0.40), 0.70))
    me.materials.append(_mat("u_track", (0.09, 0.085, 0.08), 0.95))
    me.materials.append(_mat("u_steel", (0.32, 0.32, 0.34), 0.45, 0.70))
    me.materials.append(_mat("u_trim", (0.80, 0.66, 0.34), 0.30, 0.95))

    zmax = co[:, 2].max()
    xspan = max(abs(co[:, 0].max()), abs(co[:, 0].min()))
    ymax = co[:, 1].max()
    ymin = co[:, 1].min()
    counts = [0, 0, 0]

    # Face normals separate a flat deck from a vertical flank, which pure
    # position thresholds cannot: the running gear is the low band whose
    # faces point OUTWARD, while the hull roof above it points up.
    nrm = np.empty(len(me.polygons) * 3, dtype=np.float64)
    me.polygons.foreach_get("normal", nrm)
    nrm = nrm.reshape(len(me.polygons), 3)

    for pi, p in enumerate(me.polygons):
        c = np.zeros(3)
        for vi in p.vertices:
            c += co[vi]
        c /= len(p.vertices)
        nx, nz = abs(nrm[pi][0]), abs(nrm[pi][2])
        sideways = nx > nz                             # flank, not deck

        # TRACKS: the whole lower band, plus anything low that faces outward.
        # The old rule demanded BOTH low AND far out, so the inner track run,
        # the belly and the wheel hubs all stayed hull-red.
        #
        # ...but that generous reading is only right for a TRACKED hull, where
        # the run really is a full-length slab. On a wheeled truck it painted
        # 63% of the Zephyr black, because every flank face below the band
        # qualified via `sideways` — while the concept keeps the hull navy down
        # to the chassis and blacks only the tyres. Wheeled models therefore
        # demand low AND outboard, which is the wheels and nothing else.
        # A tracked hull's run really is a full-length slab, so it keeps the
        # generous lateral threshold. A wheeled one must be confined to the
        # TYRES: at 0.34 the outer two-thirds of the half-width qualified, which
        # on the Zephyr meant the whole lower body — 43% of a six-wheeled truck
        # painted tread-black, against a concept whose hull stays navy down to
        # the chassis and blacks nothing but the rubber.
        lat = 0.45 if wheeled else 0.34
        low = c[2] < zmax * track_band
        if low and (abs(c[0]) > xspan * lat or (sideways and not wheeled)):
            p.material_index = 1
        # STEEL: the GUN, and only the gun. This clause used to take the whole
        # centreline deck and the whole rear deck as well, on the theory it was
        # catching hatches and stacks — but slot 2 now renders as gunmetal and
        # the trim pass below owns the accent, so a broad grab here just drains
        # faction colour out of the hull. The concepts back this up: their decks
        # are painted armour like everything else, and the only large non-hull
        # metal on a vehicle is the barrel.
        elif c[1] > ymax * 0.70 and abs(c[0]) < xspan * 0.26 \
                and c[2] > zmax * 0.45:
            p.material_index = 2
        else:
            p.material_index = 0
        counts[p.material_index] += 1
    me.update()
    return counts


# ---------------------------------------------------------------- infantry

def tag_limbs_uv2(obj, hip=0.45, shoulder=0.78, arm_out=0.55):
    r"""Stamp UV2 with (limb id, pivot height) so the squad walk shader can
    swing legs and arms on a mesh that has no bones and no named parts.

    Emberfall's baker derives limb ids from NODE NAMES (SD_Leg, SD_Arm...),
    which works for the hand-built soldier's 27 separate objects. A pipeline
    mesh is ONE object, so every vertex would tag as body and the section
    would glide along without moving its feet. Tagging by POSITION is the only
    option here, and it is viable because a standing figure's geometry is
    predictable: legs below the hip, arms outboard at shoulder height.

    The greatcoat hem overlaps the legs in Z, so the lower coat swings with
    them — which is what a real greatcoat does, so it reads correctly.

    ids: 0 body · 1 left leg · 2 right leg · 3 left arm · 4 right arm
    """
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    zmax = co[:, 2].max()
    xspan = max(abs(co[:, 0].max()), abs(co[:, 0].min()))
    hip_z = zmax * hip
    sh_z = zmax * shoulder

    uv = me.uv_layers.get("UV2") or me.uv_layers.new(name="UV2")
    loops = len(me.loops)
    vidx = np.empty(loops, dtype=np.int32)
    me.loops.foreach_get("vertex_index", vidx)

    tag = np.zeros(n, dtype=np.float64)
    pivot = np.zeros(n, dtype=np.float64)
    legs = co[:, 2] < hip_z
    tag[legs & (co[:, 0] < 0.0)] = 1.0
    tag[legs & (co[:, 0] >= 0.0)] = 2.0
    pivot[legs] = hip_z
    arms = (~legs) & (np.abs(co[:, 0]) > xspan * arm_out) \
        & (co[:, 2] < sh_z + zmax * 0.06)
    tag[arms & (co[:, 0] < 0.0)] = 3.0
    tag[arms & (co[:, 0] >= 0.0)] = 4.0
    pivot[arms] = sh_z

    data = np.empty(loops * 2, dtype=np.float64)
    data[0::2] = tag[vidx]
    data[1::2] = pivot[vidx]
    uv.data.foreach_set("uv", data)
    me.update()
    counts = [int((tag == k).sum()) for k in range(5)]
    print("limbs: body=%d Lleg=%d Rleg=%d Larm=%d Rarm=%d (hip %.2f shoulder %.2f)"
          % (counts[0], counts[1], counts[2], counts[3], counts[4], hip_z, sh_z))
    return counts


# ---------------------------------------------------------------- driver

def prep(src_glb, out_glb, length=3.2, kind="vehicle", ao_samples=64,
         ao_radius=0.35, front_axis=None, height=0.0, track_band=0.42,
         fresh=True, smooth=0, force_yaw=None, wheeled=False,
         trim_dilate=2, dust=0.55, decimate=0, strip_loose=0.0):
    # read_homefile is what breaks the exporter's context for the REST of the
    # call, forcing prep and export into separate bridge round-trips. Clearing
    # the scene by hand instead keeps the context intact, so a whole faction
    # can be prepped AND exported in one call.
    if fresh:
        bpy.ops.wm.read_homefile(use_empty=True)
    else:
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=src_glb)
    obj = None
    for o in bpy.data.objects:
        if o.type == 'MESH':
            obj = o
            break
    if obj is None:
        raise RuntimeError("no mesh in " + src_glb)

    face, co = orient_and_scale(obj, length=length, front_axis=front_axis,
                                height=height, aircraft=(kind == "aircraft"),
                                force_yaw=force_yaw)
    if strip_loose > 0.0:
        nparts, ndel = strip_loose_parts(obj, keep_frac=strip_loose)
        if ndel:
            print("prep: stripped %d loose shells (%d faces) of %d parts"
                  % (nparts - 1, ndel, nparts))
    dec_from = dec_to = 0
    if decimate > 0:
        # BEFORE the AO bake: AO ray-casts against the final geometry and writes
        # one colour per vertex, so decimating afterwards would throw most of
        # those vertices — and the shading with them — straight back out.
        dec_from, dec_to = decimate_to(obj, decimate)
        co = np.empty(len(obj.data.vertices) * 3, dtype=np.float64)
        obj.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
    if smooth > 0:
        co = smooth_mesh(obj, iterations=smooth)
    counts = [0, 0, 0, 0]
    trim_info = None
    if kind == "vehicle":
        counts = split_vehicle_materials(obj, co, track_band, wheeled)
        # tracks are protected: no concept puts brass on a tyre or a tread
        trim_info = tag_trim_edges(obj, protect=(1,), dilate=trim_dilate)
        ensure_slots_nonempty(obj)
    elif kind == "aircraft":
        # An aircraft has no running gear and no raised deck fittings, so the
        # vehicle split has nothing correct to find: its "steel" rule read the
        # whole wing upper surface and the entire top of the Leviathan's hull
        # as fittings and painted them grey, erasing the faction colour on the
        # one part of the model the RTS camera always sees.
        #
        # But giving it ONE material was the opposite mistake: the Leviathan and
        # the Cathedral came out 100% flat tint, which is why the two showpiece
        # airships read as untextured blocks. They get the same four slots as
        # everything else — the panel-lip trim pass is what carries their
        # detail, since they genuinely have no tracks and no gun deck.
        me = obj.data
        me.materials.clear()
        me.materials.append(_mat("unit_tint", (0.45, 0.42, 0.40), 0.60))
        me.materials.append(_mat("u_track", (0.09, 0.085, 0.08), 0.95))
        me.materials.append(_mat("u_steel", (0.32, 0.32, 0.34), 0.45, 0.70))
        me.materials.append(_mat("u_trim", (0.80, 0.66, 0.34), 0.30, 0.95))
        for p in me.polygons:
            p.material_index = 0
        trim_info = tag_trim_edges(obj, protect=(), dilate=trim_dilate)
        ensure_slots_nonempty(obj)
        for p in me.polygons:
            counts[p.material_index] += 1
    elif kind == "building":
        # A structure has no running gear and no gun deck, so the vehicle split
        # has nothing correct to find — but it DOES have panel lips, roof ribs
        # and door frames, which is exactly what the crease pass reads. Slots
        # stay in the same order so the baker's index convention still holds.
        me = obj.data
        me.materials.clear()
        me.materials.append(_mat("unit_tint", (0.45, 0.42, 0.40), 0.72))
        me.materials.append(_mat("u_track", (0.09, 0.085, 0.08), 0.95))
        me.materials.append(_mat("u_steel", (0.32, 0.32, 0.34), 0.45, 0.70))
        me.materials.append(_mat("u_trim", (0.80, 0.66, 0.34), 0.30, 0.95))
        for p in me.polygons:
            p.material_index = 0
        trim_info = tag_trim_edges(obj, protect=(), dilate=trim_dilate)
        ensure_slots_nonempty(obj)
        for p in me.polygons:
            counts[p.material_index] += 1
    elif kind == "infantry":
        # The vehicles got four material slots; infantry never did, so a
        # soldier rendered as ONE flat hull-coloured statue — helmet, coat and
        # boots identical, which is exactly the toy-army look. The concepts
        # paint a coat with a DISTINCT helmet and dark boots, so split by
        # height band: the helmet is the top of the figure, boots the bottom.
        # Slot order matches CUSTOM_SLOT_ROLE in unit.gd — index is contract.
        me = obj.data
        me.materials.clear()
        me.materials.append(_mat("unit_tint", (0.42, 0.40, 0.38), 0.85))
        me.materials.append(_mat("u_track", (0.10, 0.095, 0.09), 0.9))
        me.materials.append(_mat("u_steel", (0.22, 0.22, 0.23), 0.5, 0.6))
        me.materials.append(_mat("u_trim", (0.60, 0.58, 0.55), 0.5, 0.5))
        zmax = co[:, 2].max()
        for pg in me.polygons:
            c = np.zeros(3)
            for vi in pg.vertices:
                c += co[vi]
            c /= len(pg.vertices)
            if c[2] > zmax * 0.87:
                pg.material_index = 3          # helmet -> faction accent
            elif c[2] < zmax * 0.075:
                pg.material_index = 1          # boots -> dark leather
            else:
                pg.material_index = 0
        ensure_slots_nonempty(obj)
        counts = [0, 0, 0, 0]
        for pg in me.polygons:
            counts[pg.material_index] += 1
        tag_limbs_uv2(obj)
    # AO last: it ray-casts against the final geometry, and radius is in the
    # SCALED units, so baking before the scale would use the wrong radius
    ao_mean, ao_min = bake_ao_to_vertex_colours(
        obj, samples=ao_samples, radius=ao_radius)
    # dust AFTER the AO bake: it multiplies into the same attribute, so baking
    # it first would let the AO pass overwrite it wholesale
    # ground vehicles only: an airship's lower 42% is its gondola, and caking
    # that in road dust reads as damage rather than wear
    if dust > 0.0 and kind != "aircraft":
        # a building is far taller than a tank, so the same 42% band would
        # climb halfway up the walls — keep the grime down at the footings
        dust_lower_hull(obj, strength=dust,
                        band=0.18 if kind == "building" else 0.42)

    # NOTE: the glTF exporter reads bpy.context.active_object, and in a file
    # opened during THIS MCP call the Context object has no such attribute at
    # all — assigning view_layer.objects.active does not create it. So prep()
    # never exports: the caller must export in a SEPARATE bridge call.
    obj.select_set(True)

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dims = (co[:, 0].max() - co[:, 0].min(), co[:, 1].max() - co[:, 1].min(),
            co[:, 2].max() - co[:, 2].min())
    print("prep: %.2f wide x %.2f long x %.2f tall" % dims)
    # 3 decimals, not 2: at %.2f a real change from radius 0.45 to 0.75 printed
    # as "0.78" both times and read as a dead knob
    print("prep: front=%s tris=%d slots hull/track/steel/trim=%s AO mean=%.3f min=%.3f"
          % (face, tris, counts, ao_mean, ao_min))
    if dec_from:
        print("prep: decimated %d -> %d tris" % (dec_from, dec_to))
    if trim_info is not None:
        print("prep: trim %d faces (%.1f%%) at crease >= %.1f deg"
              % (trim_info[0], trim_info[1] * 100.0, trim_info[2]))
    return out_glb

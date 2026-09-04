# EMBERFALL: 1940 — world.gd
# Loads the SAME map text file as the pygame prototype and builds it in 3D:
# merged terrain slabs (row-run merging keeps the node count low), a sunken
# flooded trench with shader water, raised rock and ruins, glowing emberstone
# crystal fields (MultiMesh + pulsing shader), and faction start pads with
# procedural Command Posts — each with a .glb hook so Blender models can
# replace them later, Faction Wars style.

class_name EFWorld
extends Node3D

const T := 2.0   # meters per tile

const TILE_DEFS := {
	".": {"name": "Ashen Ground",     "walk": true,  "build": true},
	",": {"name": "Cratered Rough",   "walk": true,  "build": false},
	"#": {"name": "Rock & Ruin",      "walk": false, "build": false},
	"~": {"name": "Flooded Trench",   "walk": false, "build": false},
	# A river that cannot be crossed cuts a map in half and strands half the
	# pathfinding. Fords are the crossings: the water reads as continuous from
	# above, but the bed is raised and the surface sits shallow, so ground units
	# wade through instead of walking around the world.
	"f": {"name": "Ford",             "walk": true,  "build": false},
	"E": {"name": "Emberstone Field", "walk": true,  "build": false},
	"B": {"name": "Ruined Structure", "walk": false, "build": false},
	"R": {"name": "Refinery",         "walk": false, "build": false},
	"C": {"name": "Structure",        "walk": false, "build": false},
	"W": {"name": "Iron Wall",        "walk": false, "build": false},
}

# THREE colours per banner, because one was doing two incompatible jobs.
#
# "color" is the TEAM colour: minimap blips, health bars, selection rings, the
# flag on a wing. That job wants saturation and separation, so it keeps the
# bright values the UI has always used.
#
# "hull" and "accent" are what the ARMOUR is actually painted. These were
# measured off the Higgsfield concept art with k-means over the subject pixels
# (background and contact shadow masked out), then brightened ~1.4x, because a
# sampled pixel is a SHADED result and albedo has to survive being multiplied
# by sunlight and baked AO on the way back down. Painting the bright team
# colour across a whole hull is what made the army read as flat toys: the
# concepts are dark, desaturated armour carrying one bright metal accent, and
# the accent had nowhere to live because every faction shared Blender's grey.
#
# Measured dominant hull clusters, for anyone re-tuning these:
#   Karvath rgb(85,50,46) · Ashfall rgb(102,87,69)
#   Aurelia rgb(48,54,70) · Luminar rgb(215,212,215) + violet rgb(67,59,80)
# The armour colours are chosen against the TERRAIN, not in isolation. Sampled
# ground albedo is rgb(108,83,57) at L*37 — a warm mid-brown — and the first
# concept-faithful pass put Karvath at deltaE 14.4 and Ashfall at 13.9 from it.
# Both were near-camouflaged: faithful to the art, unreadable in play. A unit
# the player cannot pick off the ground is a worse failure than a unit whose
# paint is a shade off its concept, so these sit at the closest point to the art
# that still clears deltaE 26 from terrain and 30 from every other banner.
#
# Ashfall drifts furthest and does so knowingly. Its art is warm khaki-brown,
# which is precisely the ground's own hue; the olive it wears here is the only
# direction with anywhere to go.
const FACTIONS := {
	1: {"name": "KARVATH", "color": Color(0.72, 0.25, 0.18),
		# deeper and more saturated than the sampled oxide: red holds its
		# identity while pulling away from the brown it used to sink into
		"hull": Color(0.48, 0.18, 0.15),          # terrain ~28
		# dark iron, not bright steel. At deltaE 46 from the hull the old
		# polished trim read as white specks of chipped paint, because the
		# crease pattern it follows is blotchy and high contrast advertises
		# that. Pulling it to ~35 lets it read as fittings on a red hull.
		"accent": Color(0.45, 0.42, 0.38), "acc_metal": 0.80, "acc_rough": 0.45},
	2: {"name": "ASHFALL", "color": Color(0.5, 0.52, 0.3),
		"hull": Color(0.46, 0.50, 0.26),          # terrain 27.8
		"accent": Color(0.46, 0.30, 0.18), "acc_metal": 0.55, "acc_rough": 0.78},
	3: {"name": "AURELIA", "color": Color(0.28, 0.52, 0.73),
		"hull": Color(0.26, 0.31, 0.42),          # terrain 37.8, the signature navy
		"accent": Color(0.80, 0.66, 0.34), "acc_metal": 0.95, "acc_rough": 0.30},
	# Luminar was asked to go darker, and darkening a violet-GREY walks it
	# straight into Aurelia's navy — the two sat only deltaE 13 apart, close
	# enough to confuse mid-battle. Saturating instead of dulling buys the
	# darkness for free: L* drops 57 -> 37 while separation from navy RISES to
	# 42.6. The art's white enamel does not vanish, it swaps roles and becomes
	# the trim, so both concept colours are still on the model.
	4: {"name": "LUMINAR", "color": Color(0.47, 0.31, 0.74),
		"hull": Color(0.42, 0.23, 0.54),          # terrain 62.6, navy 38.1
		# near-white on violet was the worst offender of all: at deltaE 67 the
		# trim read as snow or battle damage rather than enamel. Softened to a
		# pale silver-violet that still catches the light.
		"accent": Color(0.70, 0.66, 0.80), "acc_metal": 0.55, "acc_rough": 0.28},
}


# Units and buildings paint themselves with the armour colour; everything that
# exists to be READ at a glance keeps the saturated team colour.
static func hull_of(fac: int) -> Color:
	var f: Dictionary = FACTIONS.get(fac, FACTIONS[1])
	return f.get("hull", f["color"])

var grid: Array[String] = []      # one String per row; row[x] is the tile char
var starts := {}                  # start number -> Vector2i tile
var w := 0
var h := 0
var ember_tiles: Array[Vector2i] = []
var b_groups: Array = []          # each: Array[Vector2i] — one garrisonable ruin
var start_nodes := {}             # faction id -> its pad/HQ visual root
var show_start_pads := true       # false on a crawler landing: nobody has a base yet
var explored := PackedByteArray() # shroud: 1 = the player has seen this tile
var _shroud_img: Image
var _shroud_tex: ImageTexture
var _shroud_mi: MeshInstance3D
var _shroud_dirty := false
var _vis_now := {}                # tiles the player can SEE this tick
var _vis_prev := {}
const FOG_COL := Color(0.42, 0.42, 0.48, 0.36)   # grey memory of seen ground
# Never-explored ground is FULLY opaque: you discover the map by walking it,
# rather than peering through a thin veil. Once seen, a tile drops to FOG_COL
# and keeps showing whatever was last there.
const DARK_COL := Color(0.0, 0.0, 0.0, 1.0)
signal tiles_revealed(cells: Array)
var slot_faction := {1: 1, 2: 2}  # start slot on the map -> the faction playing it

# The team model. Distinct teams by default, which makes 1v1 AND free-for-all
# work with zero configuration (is_hostile degenerates to "a != b", exactly the
# check every combat system used before teams existed). Only the 2v2 allied
# mode writes shared team ids in here. Hosted on world because every system
# that decides hostility already holds a world reference.
var team_of := {1: 1, 2: 2, 3: 3, 4: 4}   # faction -> team


func is_hostile(a: int, b: int) -> bool:
	return a != b and team_of.get(a, a) != team_of.get(b, b)


func is_ally(a: int, b: int) -> bool:      # allied but not the same faction
	return a != b and not is_hostile(a, b)
var _ember_mm: MultiMesh
var _ember_ids := {}              # Vector2i -> Array[int] crystal instance ids
var _shared_normal: NoiseTexture2D
var _prop_ids := {}               # Vector2i -> [[multimesh, id], ...] for cleanup


static func tile_hash(x: int, y: int, salt: int = 0) -> int:
	var n := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	return n & 0x7FFFFFFF


func tile_char(tx: int, ty: int) -> String:
	return grid[ty][tx]


func is_walkable(tx: int, ty: int) -> bool:
	if tx < 0 or tx >= w or ty < 0 or ty >= h:
		return false
	return TILE_DEFS[grid[ty][tx]]["walk"]


func is_buildable(tx: int, ty: int) -> bool:
	if tx < 0 or tx >= w or ty < 0 or ty >= h:
		return false
	return TILE_DEFS[grid[ty][tx]]["build"]


func walkable_at(wx: float, wz: float) -> bool:
	return is_walkable(int(floor(wx / T)), int(floor(wz / T)))


func clear_at(wx: float, wz: float, r: float) -> bool:
	# a unit occupies a small square — all four corners must be on open ground
	return walkable_at(wx - r, wz - r) and walkable_at(wx + r, wz - r) \
		and walkable_at(wx - r, wz + r) and walkable_at(wx + r, wz + r)


const SIGHT_BLOCKERS := "#BCRW"    # tall things bullets can't pass through

func sight_clear(a: Vector3, b: Vector3, ignore_first := 0.0,
		over_walls := false) -> bool:
	# ignore_first: a shooter inside/atop a structure may see past its OWN
	# footprint (turret bases, garrison walls). over_walls: elevated shooters
	# fire over wall segments entirely.
	var d := Vector2(b.x - a.x, b.z - a.z)
	var dlen := d.length()
	var steps := int(dlen) + 1
	for i in range(1, steps):
		var f := float(i) / steps
		if f * dlen <= ignore_first:
			continue
		var tx := int((a.x + d.x * f) / T)
		var ty := int((a.z + d.y * f) / T)
		if not in_bounds(tx, ty):
			continue
		var ch: String = grid[ty][tx]
		if over_walls and ch == "W":
			continue
		if ch in SIGHT_BLOCKERS:
			return false
	return true


func in_bounds(tx: int, ty: int) -> bool:
	return tx >= 0 and tx < w and ty >= 0 and ty < h


# =============================== BUILD =======================================

func build(map_path: String) -> void:
	_parse(map_path)
	_find_b_groups()
	_build_terrain()
	_build_embers()
	_build_boulders()
	_build_scorch()
	_build_props()
	# Only slots an actual side occupies get a base. A 4-start map used for a
	# 1v1 leaves slots 3 and 4 empty, and building pads for them raised fully
	# dressed phantom command posts — flags, smoke and all — for factions that
	# were not in the match, one of them wearing the player's own colours.
	#
	# On a crawler landing NOBODY has a base yet, so no pads at all: raising them
	# anyway made the landing look like an ordinary start, and then deploying on
	# that tile stacked a second identical post on the first, so the deploy read
	# as doing nothing at all.
	if show_start_pads:
		for num in starts:
			if slot_faction.has(num):
				_build_start_pad(num, starts[num])
	_init_shroud()


func _find_b_groups() -> void:
	# flood-fill contiguous 'B' tiles into structures (a 2x2 farm, a 1-tile
	# bunker, a 3x2 house...) — structures.gd turns each into a garrison
	var left := {}
	for ty in range(h):
		for tx in range(w):
			if grid[ty][tx] == "B":
				left[Vector2i(tx, ty)] = true
	while not left.is_empty():
		var seed_cell: Vector2i = left.keys()[0]
		left.erase(seed_cell)
		var grp: Array[Vector2i] = [seed_cell]
		var q := [seed_cell]
		while not q.is_empty():
			var c: Vector2i = q.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if left.has(n):
					left.erase(n)
					grp.append(n)
					q.append(n)
		b_groups.append(grp)


func set_runtime_tile(cells: Array, ch: String) -> void:
	for c in cells:
		if ch != ".":
			clear_props_at(c)
	# runtime map edits (refinery footprints, depleted fields)
	for c in cells:
		var row := grid[c.y]
		grid[c.y] = row.substr(0, c.x) + ch + row.substr(c.x + 1)


func deplete_ember(tile: Vector2i) -> void:
	set_runtime_tile([tile], ",")
	if _ember_ids.has(tile):
		var gone := Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)),
			Vector3(0, -20, 0))
		for id in _ember_ids[tile]:
			_ember_mm.set_instance_transform(id, gone)
		# ids are KEPT: the field regrows its crystals from the same seed


func regrow_ember(tile: Vector2i) -> void:
	set_runtime_tile([tile], "E")
	if not _ember_ids.has(tile):
		return
	var ids: Array = _ember_ids[tile]
	for s in range(mini(4, ids.size())):
		var hh := tile_hash(tile.x, tile.y, 20 + s)
		var ox := 0.3 + float(hh % 100) / 100.0 * (T - 0.6)
		var oz := 0.3 + float((hh >> 7) % 100) / 100.0 * (T - 0.6)
		var scl := 0.5 + float((hh >> 14) % 90) / 100.0
		var yaw := float(hh % 628) / 100.0
		var tilt := 0.12 + float((hh >> 4) % 25) / 100.0
		var basis := Basis(Vector3.UP, yaw)
		basis = basis * Basis(Vector3.RIGHT, tilt)
		basis = basis.scaled(Vector3(scl, scl * 1.3, scl))
		var pos := Vector3(tile.x * T + ox, 0.28 * scl, tile.y * T + oz)
		_ember_mm.set_instance_transform(ids[s], Transform3D(basis, pos))


func _parse(map_path: String) -> void:
	var f := FileAccess.open(map_path, FileAccess.READ)
	assert(f != null, "Map not found: " + map_path)
	for raw_line in f.get_as_text().split("\n"):
		var line := raw_line.strip_edges(false, true)
		if line.is_empty():
			continue
		var row := ""
		for x in range(line.length()):
			var ch := line[x]
			if ch in "1234":
				starts[int(ch)] = Vector2i(x, grid.size())
				ch = "."
			assert(TILE_DEFS.has(ch), "Unknown tile %s" % ch)
			if ch == "E":
				ember_tiles.append(Vector2i(x, grid.size()))
			row += ch
		grid.append(row)
	h = grid.size()
	w = grid[0].length()


# --- materials -----------------------------------------------------------------

func _noisy_mat(dark: Color, light: Color, scale: float = 0.14) -> StandardMaterial3D:
	# FastNoiseLite albedo = free terrain texture, no image files needed.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.7
	noise.fractal_octaves = 4
	var grad := Gradient.new()
	grad.set_color(0, dark)
	grad.set_color(1, light)
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.color_ramp = grad
	tex.width = 256
	tex.height = 256
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true      # merged slabs of any size texture continuously
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = 1.0
	# bump-mapped ash: light finally catches the grain of the ground
	# (one shared normal texture — they were all identical anyway)
	if _shared_normal == null:
		var nnoise := FastNoiseLite.new()
		nnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		nnoise.frequency = 2.4
		nnoise.fractal_octaves = 3
		_shared_normal = NoiseTexture2D.new()
		_shared_normal.noise = nnoise
		_shared_normal.seamless = true
		_shared_normal.as_normal_map = true
		_shared_normal.bump_strength = 7.0
		_shared_normal.width = 256
		_shared_normal.height = 256
	m.normal_enabled = true
	m.normal_texture = _shared_normal
	m.normal_scale = 0.6
	return m


func _pbr_mat(base: String, tint: Color, scale: float, macro := 0.45) -> Material:
	var diff := "res://textures/%s_Diffuse.jpg" % base
	if not ResourceLoader.exists(diff):
		return null
	# the ground shader: planar XZ at a third of triplanar's fetches, plus the
	# 1/7th-frequency macro layer that breaks the visible tile repeat. `macro`
	# must shrink as the BASE frequency drops: on the mud (uv 0.14) the macro
	# resample lands at a ~50 m period and paints giant blotches instead of
	# breaking tiling — observed as a huge checkerboard across the trench.
	var sh := load("res://ground.gdshader") as Shader
	if sh != null:
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("albedo_tex", load(diff))
		sm.set_shader_parameter("tint", tint)
		sm.set_shader_parameter("uv_scale", scale)
		sm.set_shader_parameter("macro_amount", macro)
		var norp := "res://textures/%s_nor_gl.jpg" % base
		if ResourceLoader.exists(norp):
			sm.set_shader_parameter("normal_tex", load(norp))
		var rgp := "res://textures/%s_Rough.jpg" % base
		if ResourceLoader.exists(rgp):
			sm.set_shader_parameter("rough_tex", load(rgp))
		return sm
	# fallback: the old triplanar StandardMaterial3D, kept for safety
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(diff)
	m.albedo_color = tint
	var norp2 := "res://textures/%s_nor_gl.jpg" % base
	if ResourceLoader.exists(norp2):
		m.normal_enabled = true
		m.normal_texture = load(norp2)
		m.normal_scale = 0.6
	var rgp2 := "res://textures/%s_Rough.jpg" % base
	if ResourceLoader.exists(rgp2):
		m.roughness_texture = load(rgp2)
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _flat_mat(col: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _slab(cx: float, cy: float, cz: float, sx: float, sy: float, sz: float,
		mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(sx, sy, sz)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(cx, cy, cz)
	add_child(mi)
	return mi


# --- terrain: row-run merging INTO MultiMeshes ----------------------------------
# Row-runs merge same-type tile strips into slabs (the Faction Wars trick);
# packing every slab of a type into ONE MultiMesh makes the whole 192x128
# battlefield cost ~8 draw calls instead of thousands of nodes.

func _build_terrain() -> void:
	# Poly Haven photoscanned earth (CC0), tinted to the palette of dead Veyre;
	# graceful fallback to procedural noise if the textures are missing
	var mat_ground: Material = _pbr_mat("burned_ground_01",
		Color(1.0, 0.97, 0.9), 0.085)
	if mat_ground == null:
		mat_ground = _noisy_mat(Color(0.27, 0.25, 0.21), Color(0.5, 0.47, 0.4), 0.18)
	var mat_rough: Material = _pbr_mat("brown_mud_dry",
		Color(0.78, 0.72, 0.62), 0.11)
	if mat_rough == null:
		mat_rough = _noisy_mat(Color(0.18, 0.165, 0.14), Color(0.36, 0.33, 0.27), 0.24)
	var mat_ember_soil: Material = _pbr_mat("brown_mud_dry",
		Color(1.0, 0.52, 0.35), 0.14, 0.3)
	if mat_ember_soil == null:
		mat_ember_soil = _noisy_mat(Color(0.17, 0.1, 0.07), Color(0.37, 0.25, 0.17), 0.28)
	var mat_rock: Material = _pbr_mat("aerial_rocks_02",
		Color(0.82, 0.8, 0.8), 0.1, 0.25)
	if mat_rock == null:
		mat_rock = _noisy_mat(Color(0.12, 0.115, 0.12), Color(0.31, 0.30, 0.31), 0.09)
	var mat_mud: Material = _pbr_mat("brown_mud", Color(0.5, 0.46, 0.42), 0.14, 0.0)
	if mat_mud == null:
		mat_mud = _flat_mat(Color(0.1, 0.09, 0.075), 1.0)
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://water.gdshader")

	var runs := {}
	for ch in TILE_DEFS:
		runs[ch] = []
	for ty in range(h):
		var x := 0
		while x < w:
			var ch := grid[ty][x]
			var run := 1
			while x + run < w and grid[ty][x + run] == ch:
				run += 1
			runs[ch].append(Vector3i(x, ty, run))
			x += run

	# ground-like slabs (structures stand on ordinary ground)
	_mm_slabs(runs["."] + runs["B"], mat_ground, 1.2, -0.6)
	# rock tiles get the rough slab too: with the old stretched box the tile was
	# hidden underneath it, but a real rock mesh leaves gaps, and the bare base
	# plane showed through as a pale strip running the length of every ridge
	_mm_slabs(runs[","] + runs["#"], mat_rough, 1.2, -0.6)
	_mm_slabs(runs["E"], mat_ember_soil, 1.2, -0.6)
	_mm_slabs(runs["~"], mat_mud, 0.3, -1.05)                    # trench bed
	_mm_water(runs["~"], water_mat)
	# Ford: a RAISED bed under the SAME water surface. Dropping the ford's water
	# plane instead put the bed above its own surface, so the crossing rendered
	# as an opaque strip of mud — a dirt road through a river. A river has one
	# water level; a ford is where the bottom comes up to meet it.
	_mm_slabs(runs["f"], mat_mud, 0.3, -0.80)     # bed top -0.65 vs channel -0.90
	_mm_water(runs["f"], water_mat)               # same surface as the channel
	_build_ruins()                 # must precede _mm_rocks: it consumes tiles
	_mm_rocks(runs["#"], mat_rock)
	_mm_shore_stones(mat_rock)


func _mm_slabs(list: Array, mat: Material, height: float, cy: float) -> void:
	if list.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in range(list.size()):
		var r: Vector3i = list[i]
		var basis := Basis.from_scale(Vector3(r.z * T, height, T))
		var pos := Vector3((r.x + r.z * 0.5) * T, cy, (r.y + 0.5) * T)
		mm.set_instance_transform(i, Transform3D(basis, pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _mm_water(list: Array, mat: Material, y := -0.5) -> void:
	if list.is_empty():
		return
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in range(list.size()):
		var r: Vector3i = list[i]
		var basis := Basis.from_scale(Vector3(r.z * T, 1.0, T))
		var pos := Vector3((r.x + r.z * 0.5) * T, y, (r.y + 0.5) * T)
		mm.set_instance_transform(i, Transform3D(basis, pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# name, uniform scale (x tile size), how often it is picked out of 10
# name, uniform scale (x tile size), weight out of 10, CORE-ONLY
#
# The last column splits the kit in two. Scaling a jagged spire up for a
# mountain core just makes a bigger spike — which is precisely how the first
# ranges came out looking like a stone forest. rock_e and rock_f are broad
# geological masses built for that job and are used ONLY deep inside a rock
# body; the fringe keeps the original boulders, which is what a mountain's
# foothills should be made of anyway.
const ROCK_KIT := [
	["rock_d", 1.10, 5, false],   # low broken boulder, 320 tris — the common case
	["rock_a", 0.80, 2, false],   # jagged spire, ~4.3 m
	["rock_b", 1.05, 2, false],   # fractured block, ~3.0 m
	["rock_c", 0.70, 1, false],   # tall mountain horn, ~5.2 m, used sparingly
	["rock_e", 1.55, 6, true],    # broad layered massif, wide and low
	["rock_f", 1.60, 4, true],    # long ridge crag with a sloping spine
]


# Derelict civilian structures scattered through the landscape — the thing that
# makes a map read as a place people used to live rather than an arena.
#
# They are substituted for 2x2 blocks of ROCK, never dropped on open ground, and
# that is deliberate: rock tiles are already impassable, so a ruin costs nothing
# in pathing and cannot break the map connectivity the river and mountain carves
# were checked against. A decorative building standing on walkable ground would
# have units strolling through its walls.
const RUIN_KIT := [
	["ruin_house", 2.1],       # two-storey farmhouse shell, roof gone
	["ruin_silo", 1.7],        # three cracked concrete grain silos
	["ruin_shed", 2.4],        # long factory shed, half the roof collapsed
]

var _ruin_used := {}           # Vector2i -> true: rock tiles a ruin has taken
var _ruin_ring := {}           # tiles touching a ruin: boulders kept small there


func _build_ruins() -> void:
	_ruin_used.clear()
	_ruin_ring.clear()
	var kit := []
	for entry in RUIN_KIT:
		var path := "res://models/%s.glb" % String(entry[0])
		if not ResourceLoader.exists(path):
			continue
		var src: Node3D = (load(path) as PackedScene).instantiate()
		var found := src.find_children("*", "MeshInstance3D", true, false)
		if found.is_empty():
			continue
		kit.append({"mesh": (found[0] as MeshInstance3D).mesh,
			"scale": float(entry[1]), "xf": []})
	if kit.is_empty():
		return

	var depth := rock_depth()
	for ty in range(h - 1):
		for tx in range(w - 1):
			var cells := [Vector2i(tx, ty), Vector2i(tx + 1, ty),
				Vector2i(tx, ty + 1), Vector2i(tx + 1, ty + 1)]
			var ok := true
			for c: Vector2i in cells:
				# all four must be rock, unclaimed, and on the FRINGE — a ruin
				# buried in the middle of a massif would never be seen
				# Depth 2 is the useful limit. Demanding all four tiles at depth
				# EXACTLY 1 sounds tidier but collapses the count from 27 ruins
				# to 3 — depth-1 tiles form a one-tile-wide ring, so a 2x2 block
				# of them barely exists. Visibility is solved by shrinking the
				# surrounding boulders instead (see _ruin_ring below).
				if grid[c.y][c.x] != "#" or _ruin_used.has(c) \
						or depth[c.y * w + c.x] > 2:
					ok = false
					break
			if not ok:
				continue
			var hsh := tile_hash(tx, ty, 71)
			if hsh % 100 >= 14:            # ~14% of eligible blocks
				continue
			var near_start := false
			for s in starts.values():
				if maxi(absi(tx - s.x), absi(ty - s.y)) <= 10:
					near_start = true
					break
			if near_start:
				continue
			for c: Vector2i in cells:
				_ruin_used[c] = true
			# Ring: the tiles touching the footprint keep their boulder — they
			# are impassable rock and clearing them would leave an invisible
			# wall — but the boulder is forced back to FRINGE size so a
			# depth-scaled neighbour cannot tower over the ruin and hide it.
			for ry in range(ty - 1, ty + 3):
				for rx in range(tx - 1, tx + 3):
					var rc := Vector2i(rx, ry)
					if rx >= 0 and ry >= 0 and rx < w and ry < h \
							and not _ruin_used.has(rc):
						_ruin_ring[rc] = true
			var e: Dictionary = kit[hsh % kit.size()]
			var s2: float = float(e["scale"]) * T * (0.88 + float((hsh >> 3) % 26) / 100.0)
			var basis := Basis(Vector3.UP, float(hsh % 360) * PI / 180.0)
			basis = basis.scaled(Vector3(s2, s2, s2))
			(e["xf"] as Array).append(Transform3D(basis,
				Vector3((tx + 1.0) * T, -0.12, (ty + 1.0) * T)))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.37, 0.34)
	mat.roughness = 0.96
	mat.metallic = 0.0
	# the baked occlusion IS the detail on these: no faction paint, no trim
	mat.vertex_color_use_as_albedo = true
	var total := 0
	for e in kit:
		var xf: Array = e["xf"]
		if xf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e["mesh"]
		mm.instance_count = xf.size()
		for i in range(xf.size()):
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)
		total += xf.size()
	if total > 0:
		print("[world] %d background ruins placed" % total)


func rock_depth() -> PackedInt32Array:
	# How many tiles inward from open ground each rock tile sits. Multi-source
	# BFS from every non-rock tile at once, so one pass over the map gives the
	# whole field.
	#
	# This is what turns a blob of '#' into a MOUNTAIN. Every rock tile used to
	# get the same boulder at the same size, so a rock mass read as a gravel
	# field seen from above — flat, repetitive, and exactly the "boxy" look.
	# Scaling by depth instead means the fringe stays low and the core rears up,
	# which is the silhouette a massif actually has.
	var d := PackedInt32Array()
	d.resize(w * h)
	var q: Array[Vector2i] = []
	for ty in range(h):
		for tx in range(w):
			if grid[ty][tx] == "#":
				d[ty * w + tx] = -1
			else:
				d[ty * w + tx] = 0
				q.append(Vector2i(tx, ty))
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		var cd: int = d[c.y * w + c.x]
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = c.x + off.x
			var ny: int = c.y + off.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if d[ny * w + nx] == -1:
				d[ny * w + nx] = cd + 1
				q.append(Vector2i(nx, ny))
	return d


func _mm_rocks(list: Array, mat: Material) -> void:
	# Rock tiles used to be a stretched BoxMesh — literally a cube scaled to the
	# length of the run — which is precisely why every ridge on every map read as
	# masonry. Now each TILE gets a real rock mesh, picked, spun and tilted by
	# its own tile hash, so a run of tiles becomes a broken ridge instead of one
	# long block. Runs are expanded per tile for that reason: a single mesh
	# stretched across five tiles would just be the cube problem with bumps.
	if list.is_empty():
		return
	var kit := []
	var pick := []            # fringe: the boulder kit
	var pick_core := []       # deep inside a massif: the mountain kit
	for entry in ROCK_KIT:
		var path := "res://models/%s.glb" % String(entry[0])
		if not ResourceLoader.exists(path):
			continue
		var src: Node3D = (load(path) as PackedScene).instantiate()
		var found := src.find_children("*", "MeshInstance3D", true, false)
		if found.is_empty():
			continue
		var slot := kit.size()
		kit.append({"mesh": (found[0] as MeshInstance3D).mesh,
			"scale": float(entry[1]), "xf": []})
		var core_only: bool = entry.size() > 3 and bool(entry[3])
		for _n in range(int(entry[2])):
			if core_only:
				pick_core.append(slot)
			else:
				pick.append(slot)
	if pick_core.is_empty():
		pick_core = pick          # massif models missing: fall back to boulders
	if kit.is_empty():
		_mm_rock_boxes(list, mat)       # models missing: keep the old look
		return

	var depth := rock_depth()
	for r in list:
		for step in range(r.z):
			var tx: int = r.x + step
			if _ruin_used.has(Vector2i(tx, r.y)):
				continue          # a ruin stands here; no boulder through it
			var hsh := tile_hash(tx, r.y)
			var dcore: int = depth[r.y * w + tx]
			if _ruin_ring.has(Vector2i(tx, r.y)):
				dcore = 1         # next to a ruin: stay a fringe boulder
			var plist: Array = pick_core if dcore >= 2 else pick
			var e: Dictionary = kit[plist[hsh % plist.size()]]
			# wide spread on purpose: at +-20% every rock in a run came out the
			# same size and the ridge read as a string of beads
			var s: float = float(e["scale"]) * T * (0.72 + float((hsh >> 3) % 60) / 100.0)
			# MASSIF: how far inside the rock body this tile lies. A one-tile
			# ridge stays a ridge (depth 1, unchanged); a thick range rears up
			# toward its core, and the VERTICAL exaggeration is deliberately
			# stronger than the horizontal one — widening a boulder just makes a
			# bigger boulder, height is what reads as a mountain from a 52-degree
			# camera. Capped at 6 so a huge massif does not grow through the sky.
			var dep: float = clampf(float(depth[r.y * w + tx]), 1.0, 6.0) - 1.0
			var lift := 0.0
			var ys := s
			if dep > 0.0:
				# Grow the rock NEARLY UNIFORMLY and lift it. Stretching height
				# faster than width (0.42 vs 0.30 per level) made the cores 2.7x
				# taller than wide, and since the kit meshes are already slabby
				# that came out as a forest of stone spikes rather than a massif.
				# A mountain is big rock stacked high, not tall rock — so scale
				# up evenly, keep a slight vertical bias for the peak, and let
				# the LIFT do the work of raising the core above its foothills.
				s *= 1.0 + 0.40 * dep
				ys = s * (1.0 + 0.14 * dep)
				lift = 0.34 * dep
			var yaw := float(hsh % 360) * PI / 180.0
			# a few degrees of lean: rocks sitting perfectly level read as props
			var tilt := (float((hsh >> 9) % 13) - 6.0) * PI / 180.0
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
			basis = basis.scaled(Vector3(s, ys, s))
			# jitter stays inside the tile so the rock never creeps onto ground
			# a unit is allowed to walk through
			var jx := (float((hsh >> 5) % 21) - 10.0) / 100.0 * T
			var jz := (float((hsh >> 15) % 21) - 10.0) / 100.0 * T
			var pos := Vector3((tx + 0.5) * T + jx, -0.15 + lift,
				(r.y + 0.5) * T + jz)
			(e["xf"] as Array).append(Transform3D(basis, pos))

	for e in kit:
		var xf: Array = e["xf"]
		if xf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e["mesh"]
		mm.instance_count = xf.size()
		for i in range(xf.size()):
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)


func _mm_shore_stones(mat: Material) -> void:
	# Two jobs, one scatter. On a FORD the stones are signage: the crossing is
	# only a slightly shallower band of the same water, which a player scanning
	# for somewhere to cross will never spot — stepping stones say "here". On a
	# BANK they break the shoreline, which is otherwise a hard rectangular cut
	# straight along the tile grid.
	var path := "res://models/rock_d.glb"
	if not ResourceLoader.exists(path):
		return
	var src: Node3D = (load(path) as PackedScene).instantiate()
	var found := src.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		return
	var xf: Array[Transform3D] = []
	for ty in range(h):
		for tx in range(w):
			var ch := grid[ty][tx]
			var on_ford := ch == "f"
			var on_bank := false
			if ch == "," or ch == ".":
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
						Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = tx + d.x
					var ny: int = ty + d.y
					if nx >= 0 and ny >= 0 and nx < w and ny < h \
							and (grid[ny][nx] == "~" or grid[ny][nx] == "f"):
						on_bank = true
						break
			if not (on_ford or on_bank):
				continue
			var hsh := tile_hash(tx, ty, 29)
			# fords are marked densely, banks only sparsely dressed
			if hsh % 100 >= (62 if on_ford else 34):
				continue
			var s: float = T * (0.16 + float((hsh >> 3) % 22) / 100.0)
			var basis := Basis(Vector3.UP, float(hsh % 360) * PI / 180.0)
			basis = basis.scaled(Vector3(s, s * 0.7, s))
			var jx := (float((hsh >> 7) % 51) - 25.0) / 100.0 * T
			var jz := (float((hsh >> 17) % 51) - 25.0) / 100.0 * T
			# ford stones break the surface (-0.5); bank stones sit on the soil
			var y := -0.62 if on_ford else -0.18
			xf.append(Transform3D(basis, Vector3((tx + 0.5) * T + jx, y,
				(ty + 0.5) * T + jz)))
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = (found[0] as MeshInstance3D).mesh
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _mm_rock_boxes(list: Array, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in range(list.size()):
		var r: Vector3i = list[i]
		var hh := 2.0 + (tile_hash(r.x, r.y) % 3) * 0.5          # 2.0 / 2.5 / 3.0
		var basis := Basis.from_scale(Vector3(r.z * T, hh, T))
		var pos := Vector3((r.x + r.z * 0.5) * T, hh * 0.5 - 0.2, (r.y + 0.5) * T)
		mm.set_instance_transform(i, Transform3D(basis, pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# --- emberstone: MultiMesh crystals + pulsing emission shader --------------------

func _build_embers() -> void:
	var shard := PrismMesh.new()
	shard.size = Vector3(0.42, 1.0, 0.42)

	# under-glow decals: every field bleeds warm light into the ash
	var glow_mesh := PlaneMesh.new()
	# EXACTLY one tile: at 2.3 the neighbouring quads overlapped in strips, and
	# with additive-ish alpha those strips doubled up into a glowing grid
	glow_mesh.size = Vector2(2.0, 2.0)
	var gmm := MultiMesh.new()
	gmm.transform_format = MultiMesh.TRANSFORM_3D
	gmm.mesh = glow_mesh
	gmm.instance_count = ember_tiles.size()
	var gi := 0
	for tile in ember_tiles:
		gmm.set_instance_transform(gi, Transform3D(Basis.IDENTITY,
			Vector3((tile.x + 0.5) * T, 0.045, (tile.y + 0.5) * T)))
		gi += 1
	var gmi := MultiMeshInstance3D.new()
	gmi.multimesh = gmm
	var gmat := StandardMaterial3D.new()
	# An UNSHADED material outputs albedo and DROPS emission entirely, so the
	# emission settings that used to be here did nothing and the under-glow
	# never reached the bloom threshold. Values above 1.0 in the albedo of an
	# unshaded material go straight to the HDR buffer, which is what actually
	# makes the fields burn.
	gmat.albedo_color = Color(1.45, 0.72, 0.22, 0.15)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmi.material_override = gmat
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gmi)

	var heroes := 0
	for tile in ember_tiles:
		if tile_hash(tile.x, tile.y, 88) % 4 == 0:
			heroes += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = shard
	mm.instance_count = ember_tiles.size() * 4 + heroes

	_ember_mm = mm
	var i := 0
	for tile in ember_tiles:
		_ember_ids[tile] = []
		for s in range(4):
			var hh := tile_hash(tile.x, tile.y, 20 + s)
			var ox := 0.3 + float(hh % 100) / 100.0 * (T - 0.6)
			var oz := 0.3 + float((hh >> 7) % 100) / 100.0 * (T - 0.6)
			var scl := 0.5 + float((hh >> 14) % 90) / 100.0     # 0.5 .. 1.4
			var yaw := float(hh % 628) / 100.0
			var tilt := 0.12 + float((hh >> 4) % 25) / 100.0
			var basis := Basis(Vector3.UP, yaw)
			basis = basis * Basis(Vector3.RIGHT, tilt)
			basis = basis.scaled(Vector3(scl, scl * 1.3, scl))
			var pos := Vector3(tile.x * T + ox, 0.28 * scl, tile.y * T + oz)
			mm.set_instance_transform(i, Transform3D(basis, pos))
			var phase := float(tile_hash(tile.x, tile.y, 99) % 100) / 100.0
			mm.set_instance_custom_data(i, Color(phase, 0, 0, 0))
			_ember_ids[tile].append(i)
			i += 1
		if tile_hash(tile.x, tile.y, 88) % 4 == 0:
			# a hero crystal: one great spire per lucky tile
			var hh2 := tile_hash(tile.x, tile.y, 89)
			var hb := Basis(Vector3.UP, float(hh2 % 628) / 100.0)
			hb = hb * Basis(Vector3.RIGHT, 0.08)
			hb = hb.scaled(Vector3(1.7, 2.6, 1.7))
			mm.set_instance_transform(i, Transform3D(hb,
				Vector3(tile.x * T + 1.0, 0.75, tile.y * T + 1.0)))
			mm.set_instance_custom_data(i,
				Color(float(tile_hash(tile.x, tile.y, 90) % 100) / 100.0, 0, 0, 0))
			_ember_ids[tile].append(i)
			i += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ember.gdshader")
	mmi.material_override = mat
	add_child(mmi)

	# a few real lights so the fields cast warm glow on the ground (capped for perf)
	var light_spots: Array[Vector2i] = []
	for tile in ember_tiles:
		var ok := true
		for spot in light_spots:
			if (tile - spot).length() < 6.0:
				ok = false
				break
		if ok and light_spots.size() < 8:
			light_spots.append(tile)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.55, 0.22)
			lamp.light_energy = 2.4
			lamp.omni_range = 7.0
			lamp.shadow_enabled = false
			lamp.position = Vector3((tile.x + 0.5) * T, 1.1, (tile.y + 0.5) * T)
			add_child(lamp)

	_build_ember_motes()


func _build_ember_motes() -> void:
	# Sparks rising off the fields: ONE GPUParticles3D for the whole map,
	# emitting from every ember tile at once. The signature resource should
	# look alive, not like painted rocks.
	if ember_tiles.is_empty():
		return
	var pts := Image.create(ember_tiles.size(), 1, false, Image.FORMAT_RGBF)
	for i in range(ember_tiles.size()):
		var t: Vector2i = ember_tiles[i]
		pts.set_pixel(i, 0, Color((t.x + 0.5) * T, 0.25, (t.y + 0.5) * T))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(pts)
	pm.emission_point_count = ember_tiles.size()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.gravity = Vector3(0.15, 0.0, 0.1)      # no fall; a whisper of wind drift
	pm.initial_velocity_min = 0.22
	pm.initial_velocity_max = 0.65
	pm.damping_min = 0.05
	pm.damping_max = 0.12
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.set_color(0, Color(2.2, 1.0, 0.3, 0.0))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	grad.add_point(0.12, Color(2.2, 1.0, 0.3, 0.85))   # HDR: motes bloom
	grad.add_point(0.7, Color(1.4, 0.45, 0.1, 0.4))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var parts := GPUParticles3D.new()
	parts.process_material = pm
	parts.amount = mini(60 + ember_tiles.size() * 2, 220)
	parts.lifetime = 3.4
	parts.preprocess = 2.0                    # fields are already alive on frame 1
	var quad := QuadMesh.new()
	quad.size = Vector2(0.085, 0.085)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = qm
	parts.draw_pass_1 = quad
	parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# emitters spread across the whole map — without this AABB the node culls
	# the moment its origin leaves the frustum and every mote vanishes
	parts.visibility_aabb = AABB(Vector3(0, -1, 0), Vector3(w * T, 12.0, h * T))
	add_child(parts)


# --- scattered debris on rough ground -------------------------------------------

func _build_scorch() -> void:
	# dark scorch rings on cratered ground: one MultiMesh, one draw call, and
	# suddenly the rough tiles read as a battlefield instead of paint
	var spots := []
	for ty in range(h):
		for tx in range(w):
			if grid[ty][tx] != "," or tile_hash(tx, ty, 13) % 3 == 0:
				continue
			# the decal plane is fixed at ground height — next to a trench it
			# would hang in the air over the water, so shorelines stay clean
			var near_water := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = tx + d.x
				var ny: int = ty + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h \
						and (grid[ny][nx] == "~" or grid[ny][nx] == "f"):
					near_water = true
					break
			if not near_water:
				spots.append(Vector2i(tx, ty))
	if spots.is_empty():
		return
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.7, 1.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in range(spots.size()):
		var s: Vector2i = spots[i]
		var hh := tile_hash(s.x, s.y, 41)
		var pos := Vector3(
			s.x * T + 0.5 + float(hh % 100) / 100.0,
			0.042,
			s.y * T + 0.5 + float((hh >> 5) % 100) / 100.0)
		var basis := Basis(Vector3.UP, float(hh % 314) / 50.0)
		var scl := 0.7 + float((hh >> 11) % 45) / 100.0
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(scl, 1.0, scl)), pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.035, 0.03, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_boulders() -> void:
	var spots := []
	for ty in range(h):
		for tx in range(w):
			if grid[ty][tx] == "," and tile_hash(tx, ty, 7) % 4 == 0:
				spots.append(Vector2i(tx, ty))
	if spots.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.34, 0.44)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in range(spots.size()):
		var s: Vector2i = spots[i]
		var hh := tile_hash(s.x, s.y, 31)
		var pos := Vector3(
			s.x * T + 0.4 + float(hh % 100) / 100.0 * 1.2,
			0.12,
			s.y * T + 0.4 + float((hh >> 6) % 100) / 100.0 * 1.2)
		var basis := Basis(Vector3.UP, float(hh % 314) / 100.0)
		var scl := 0.6 + float((hh >> 12) % 80) / 100.0
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(scl, scl, scl)), pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _flat_mat(Color(0.27, 0.26, 0.24), 1.0)
	add_child(mmi)


func _note_prop(tile: Vector2i, mm: MultiMesh, id: int) -> void:
	if not _prop_ids.has(tile):
		_prop_ids[tile] = []
	_prop_ids[tile].append([mm, id])


func clear_props_at(tile: Vector2i) -> void:
	# construction crews clear the ground before they pour a slab
	if not _prop_ids.has(tile):
		return
	var gone := Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)),
		Vector3(0, -30, 0))
	for entry in _prop_ids[tile]:
		(entry[0] as MultiMesh).set_instance_transform(entry[1], gone)
	_prop_ids.erase(tile)


func _build_props() -> void:
	# life and death scattered on the ash: charred stumps, stones, pale reeds
	var stumps := []
	var reeds := []
	var stones := []
	for ty in range(h):
		for tx in range(w):
			if grid[ty][tx] != ".":
				continue
			var near_start := false
			for s in starts.values():
				if maxi(absi(tx - s.x), absi(ty - s.y)) <= 3:
					near_start = true
					break
			if near_start:
				continue
			var hh := tile_hash(tx, ty, 55)
			if hh % 41 == 0:
				stumps.append(Vector2i(tx, ty))
			elif hh % 23 == 0:
				reeds.append(Vector2i(tx, ty))
			elif hh % 17 == 0:
				stones.append(Vector2i(tx, ty))

	if not stumps.is_empty():
		var smesh := CylinderMesh.new()
		smesh.top_radius = 0.06
		smesh.bottom_radius = 0.16
		smesh.height = 0.55
		smesh.radial_segments = 7
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.mesh = smesh
		smm.instance_count = stumps.size()
		for i in range(stumps.size()):
			var s: Vector2i = stumps[i]
			var hh2 := tile_hash(s.x, s.y, 56)
			var pos := Vector3(s.x * T + 0.4 + float(hh2 % 100) / 80.0, 0.24,
				s.y * T + 0.4 + float((hh2 >> 7) % 100) / 80.0)
			var b := Basis(Vector3.UP, float(hh2 % 314) / 50.0)
			b = b * Basis(Vector3.RIGHT, float(hh2 % 20) / 100.0 - 0.1)
			var scl := 0.6 + float((hh2 >> 12) % 70) / 100.0
			smm.set_instance_transform(i, Transform3D(b.scaled(
				Vector3(scl, scl * 1.2, scl)), pos))
			_note_prop(s, smm, i)
		var smi := MultiMeshInstance3D.new()
		smi.multimesh = smm
		smi.material_override = _flat_mat(Color(0.1, 0.09, 0.085), 1.0)
		add_child(smi)

	if not reeds.is_empty():
		var rmesh := CylinderMesh.new()
		rmesh.top_radius = 0.005
		rmesh.bottom_radius = 0.035
		rmesh.height = 0.55
		rmesh.radial_segments = 5
		var rmm := MultiMesh.new()
		rmm.transform_format = MultiMesh.TRANSFORM_3D
		rmm.mesh = rmesh
		rmm.instance_count = reeds.size() * 3
		var ri := 0
		for s in reeds:
			for k in range(3):
				var hh3 := tile_hash(s.x, s.y, 60 + k)
				var pos2 := Vector3(s.x * T + 0.3 + float(hh3 % 100) / 70.0, 0.26,
					s.y * T + 0.3 + float((hh3 >> 6) % 100) / 70.0)
				var b2 := Basis(Vector3.UP, float(hh3 % 314) / 50.0)
				b2 = b2 * Basis(Vector3.RIGHT, float(hh3 % 30) / 100.0 - 0.15)
				var sc2 := 0.6 + float((hh3 >> 11) % 80) / 100.0
				rmm.set_instance_transform(ri, Transform3D(b2.scaled(
					Vector3(sc2, sc2, sc2)), pos2))
				_note_prop(s, rmm, ri)
				ri += 1
		var rmi := MultiMeshInstance3D.new()
		rmi.multimesh = rmm
		rmi.material_override = _flat_mat(Color(0.52, 0.5, 0.4), 1.0)
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rmi)

	if not stones.is_empty():
		var tmesh := SphereMesh.new()
		tmesh.radius = 0.16
		tmesh.height = 0.2
		tmesh.radial_segments = 8
		tmesh.rings = 4
		var tmm := MultiMesh.new()
		tmm.transform_format = MultiMesh.TRANSFORM_3D
		tmm.mesh = tmesh
		tmm.instance_count = stones.size()
		for i in range(stones.size()):
			var s2: Vector2i = stones[i]
			var hh4 := tile_hash(s2.x, s2.y, 70)
			var pos3 := Vector3(s2.x * T + 0.4 + float(hh4 % 100) / 80.0, 0.05,
				s2.y * T + 0.4 + float((hh4 >> 7) % 100) / 80.0)
			var b3 := Basis(Vector3.UP, float(hh4 % 314) / 50.0)
			var sc3 := 0.5 + float((hh4 >> 12) % 100) / 100.0
			tmm.set_instance_transform(i, Transform3D(b3.scaled(
				Vector3(sc3, sc3 * 0.7, sc3)), pos3))
			_note_prop(s2, tmm, i)
		var tmi := MultiMeshInstance3D.new()
		tmi.multimesh = tmm
		tmi.material_override = _flat_mat(Color(0.3, 0.29, 0.27), 0.95)
		add_child(tmi)


# --- start pads & Command Posts ---------------------------------------------------
# Procedural buildings now; drops in models/hq_<faction>.glb automatically the
# moment a Blender-made model exists (same swap pattern as Faction Wars).

func _build_start_pad(num: int, tile: Vector2i) -> void:
	var fac_id: int = slot_faction.get(num, num)
	var root := Node3D.new()
	root.position = Vector3((tile.x + 0.5) * T, 0.0, (tile.y + 0.5) * T)
	add_child(root)
	start_nodes[fac_id] = root
	hq_visual(root, fac_id)


# The command-post visual, built into any parent. Shared so a Command Post
# DEPLOYED mid-match from a crawler looks exactly like a starting one —
# buildings._build_mesh had no command_post case at all, so a deployed base
# would otherwise have been an invisible empty node.
func hq_visual(root: Node3D, fac_id: int) -> void:
	var fac: Dictionary = FACTIONS.get(fac_id, FACTIONS[1])

	# landing pad + glowing faction trim
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(6.6, 0.3, 6.6)
	pad.mesh = pad_mesh
	pad.material_override = _flat_mat(Color(0.16, 0.17, 0.19), 0.6, 0.4)
	pad.position = Vector3(0, 0.15, 0)
	root.add_child(pad)

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = fac["color"]
	trim_mat.emission_enabled = true
	trim_mat.emission = fac["color"]
	trim_mat.emission_energy_multiplier = 0.7
	for side in range(4):
		var tmesh := BoxMesh.new()
		tmesh.size = Vector3(6.6, 0.12, 0.22) if side < 2 else Vector3(0.22, 0.12, 6.6)
		var trim := MeshInstance3D.new()
		trim.mesh = tmesh
		trim.material_override = trim_mat
		trim.position = Vector3(0, 0.32, [3.2, -3.2, 0, 0][side]) \
			if side < 2 else Vector3([0.0, 0.0, 3.2, -3.2][side], 0.32, 0)
		root.add_child(trim)

	# Blender hook: use the real model if it exists
	var glb_path := "res://models/hq_%s.glb" % fac["name"].to_lower()
	if ResourceLoader.exists(glb_path):
		var scene: PackedScene = load(glb_path)
		var inst: Node3D = scene.instantiate()
		inst.rotation_degrees = Vector3(0, 22.0 if fac_id == 1 else -18.0, 0)
		root.add_child(inst)
		# the Blender file carries a "SmokeAnchor" empty at the stack mouth
		var anchor := inst.find_child("SmokeAnchor", true, false)
		if anchor is Node3D:
			_smoke(root, inst.transform * (anchor as Node3D).position)
	else:
		match fac_id:
			2:
				_hq_ashfall(root)
			3:
				_hq_aurelia(root)
			4:
				_hq_luminar(root)
			_:
				_hq_karvath(root, fac)

	_flag(root, fac["color"], fac_id)


func _hq_karvath(root: Node3D, _fac: Dictionary) -> void:
	# Angled so the default camera sees two faces, not one dark roof.
	var bld := Node3D.new()
	bld.rotation_degrees = Vector3(0, 22, 0)
	root.add_child(bld)

	var iron := _flat_mat(Color(0.36, 0.27, 0.24), 0.6, 0.45)
	var roof_iron := _flat_mat(Color(0.28, 0.2, 0.18), 0.7, 0.35)
	var dark := _flat_mat(Color(0.17, 0.16, 0.17), 0.65, 0.4)

	var hall := MeshInstance3D.new()
	var hmesh := BoxMesh.new()
	hmesh.size = Vector3(3.4, 2.2, 2.6)
	hall.mesh = hmesh
	hall.material_override = iron
	hall.position = Vector3(-0.8, 1.1, -0.4)
	bld.add_child(hall)

	var roof := MeshInstance3D.new()
	var rmesh := PrismMesh.new()
	rmesh.size = Vector3(3.7, 0.8, 2.9)
	roof.mesh = rmesh
	roof.material_override = roof_iron
	roof.position = Vector3(-0.8, 2.6, -0.4)
	bld.add_child(roof)

	# lit windows on the south face — someone is home
	var win_mat := StandardMaterial3D.new()
	win_mat.albedo_color = Color(1.0, 0.75, 0.35)
	win_mat.emission_enabled = true
	win_mat.emission = Color(1.0, 0.65, 0.25)
	win_mat.emission_energy_multiplier = 1.6
	for i in range(2):
		var win := MeshInstance3D.new()
		var wmesh := QuadMesh.new()
		wmesh.size = Vector2(0.5, 0.4)
		win.mesh = wmesh
		win.material_override = win_mat
		win.position = Vector3(-1.5 + i * 1.3, 1.15, 0.91)
		bld.add_child(win)

	var stack := MeshInstance3D.new()
	var smesh := CylinderMesh.new()
	smesh.top_radius = 0.3
	smesh.bottom_radius = 0.44
	smesh.height = 4.0
	stack.mesh = smesh
	stack.material_override = dark
	stack.position = Vector3(1.7, 2.0, -1.6)
	bld.add_child(stack)

	var ring := MeshInstance3D.new()
	var rgmesh := CylinderMesh.new()
	rgmesh.top_radius = 0.34
	rgmesh.bottom_radius = 0.34
	rgmesh.height = 0.18
	ring.mesh = rgmesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.5, 0.2)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.45, 0.15)
	ring_mat.emission_energy_multiplier = 2.0
	ring.material_override = ring_mat
	ring.position = Vector3(1.7, 3.95, -1.6)
	bld.add_child(ring)

	_smoke(bld, Vector3(1.7, 4.15, -1.6))


func _init_shroud() -> void:
	explored.resize(w * h)
	_shroud_img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	_shroud_img.fill(DARK_COL)
	_shroud_tex = ImageTexture.create_from_image(_shroud_img)
	var quad := QuadMesh.new()
	quad.size = Vector2(w * T, h * T)
	_shroud_mi = MeshInstance3D.new()
	_shroud_mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_texture = _shroud_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_shroud_mi.material_override = m
	_shroud_mi.rotation_degrees = Vector3(-90, 0, 0)
	_shroud_mi.position = Vector3(w * T * 0.5, 12.0, h * T * 0.5)
	_shroud_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shroud_mi)


func is_explored(tx: int, ty: int) -> bool:
	if not in_bounds(tx, ty):
		return false
	return explored[ty * w + tx] == 1


func explored_percent() -> float:
	var n := 0
	for v in explored:
		if v == 1:
			n += 1
	return 100.0 * n / maxf(1.0, float(explored.size()))


func reveal(center: Vector2i, r: int) -> void:
	var fresh := []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var tx := center.x + dx
			var ty := center.y + dy
			if not in_bounds(tx, ty) or explored[ty * w + tx] == 1:
				continue
			explored[ty * w + tx] = 1
			_shroud_img.set_pixel(tx, ty, FOG_COL)
			fresh.append(Vector2i(tx, ty))
	if not fresh.is_empty():
		_shroud_dirty = true
		tiles_revealed.emit(fresh)


func begin_vision() -> void:
	_vis_prev = _vis_now
	_vis_now = {}


func mark_visible(center: Vector2i, r: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var tx := center.x + dx
			var ty := center.y + dy
			if in_bounds(tx, ty):
				_vis_now[Vector2i(tx, ty)] = true
	reveal(center, r)


func end_vision() -> void:
	# fresh eyes clear the veil; lost ground fades to grey memory
	for c in _vis_now:
		if not _vis_prev.has(c):
			_shroud_img.set_pixel(c.x, c.y, Color(0, 0, 0, 0))
			_shroud_dirty = true
	for c in _vis_prev:
		if not _vis_now.has(c):
			_shroud_img.set_pixel(c.x, c.y, FOG_COL)
			_shroud_dirty = true
	shroud_flush()


func repaint_explored() -> void:
	# after a load: repaint the whole veil from the explored bitmap
	var cells := []
	for ty in range(h):
		for tx in range(w):
			if explored[ty * w + tx] == 1:
				_shroud_img.set_pixel(tx, ty, FOG_COL)
				cells.append(Vector2i(tx, ty))
	_shroud_dirty = true
	shroud_flush()
	if not cells.is_empty():
		tiles_revealed.emit(cells)


func tile_visible(tx: int, ty: int) -> bool:
	return _vis_now.has(Vector2i(tx, ty))


func shroud_flush() -> void:
	if _shroud_dirty and _shroud_tex:
		_shroud_dirty = false
		_shroud_tex.update(_shroud_img)


func faction_start(fac: int) -> Vector2i:
	for slot in slot_faction:
		if slot_faction[slot] == fac and starts.has(slot):
			return starts[slot]
	return starts[starts.keys()[0]]


func _hq_aurelia(root: Node3D) -> void:
	# a sky-harbor in miniature: brass watchtower + mooring mast
	var bld := Node3D.new()
	bld.rotation_degrees = Vector3(0, 15, 0)
	root.add_child(bld)

	var brass := _flat_mat(Color(0.55, 0.42, 0.22), 0.45, 0.7)
	var pale := _flat_mat(Color(0.42, 0.46, 0.5), 0.6, 0.4)
	var dark := _flat_mat(Color(0.15, 0.15, 0.16), 0.65, 0.4)

	var tower := MeshInstance3D.new()
	var tmesh := CylinderMesh.new()
	tmesh.top_radius = 0.95
	tmesh.bottom_radius = 1.2
	tmesh.height = 2.6
	tower.mesh = tmesh
	tower.material_override = pale
	tower.position = Vector3(-0.7, 1.3, -0.4)
	bld.add_child(tower)

	var band := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 1.02
	bmesh.bottom_radius = 1.02
	bmesh.height = 0.18
	band.mesh = bmesh
	band.material_override = brass
	band.position = Vector3(-0.7, 2.0, -0.4)
	bld.add_child(band)

	var cone := MeshInstance3D.new()
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 0.05
	cmesh.bottom_radius = 1.05
	cmesh.height = 1.1
	cone.mesh = cmesh
	cone.material_override = brass
	cone.position = Vector3(-0.7, 3.15, -0.4)
	bld.add_child(cone)

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.8, 0.4)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.7, 0.3)
	glow_mat.emission_energy_multiplier = 1.6
	for i in range(3):
		var w := MeshInstance3D.new()
		var wmesh := BoxMesh.new()
		wmesh.size = Vector3(0.3, 0.42, 0.1)
		w.mesh = wmesh
		w.material_override = glow_mat
		var ang := -0.5 + i * 0.55
		w.position = Vector3(-0.7 + sin(ang) * 1.1, 1.5, -0.4 + cos(ang) * 1.1)
		w.rotation_degrees = Vector3(0, rad_to_deg(ang), 0)
		bld.add_child(w)

	var mast := MeshInstance3D.new()
	var mmesh := CylinderMesh.new()
	mmesh.top_radius = 0.06
	mmesh.bottom_radius = 0.1
	mmesh.height = 5.2
	mast.mesh = mmesh
	mast.material_override = dark
	mast.position = Vector3(1.8, 2.6, 1.3)
	bld.add_child(mast)
	var arm := MeshInstance3D.new()
	var amesh := BoxMesh.new()
	amesh.size = Vector3(1.5, 0.08, 0.08)
	arm.mesh = amesh
	arm.material_override = brass
	arm.position = Vector3(1.8, 4.9, 1.3)
	bld.add_child(arm)


func _hq_luminar(root: Node3D) -> void:
	# the Glass City in miniature: a white spire between two arc coils
	var bld := Node3D.new()
	bld.rotation_degrees = Vector3(0, 10, 0)
	root.add_child(bld)

	var marble := _flat_mat(Color(0.62, 0.64, 0.68), 0.35, 0.15)
	var glass := _flat_mat(Color(0.55, 0.6, 0.72), 0.2, 0.5)
	var dark := _flat_mat(Color(0.16, 0.16, 0.18), 0.6, 0.4)

	var base := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 1.05
	bmesh.bottom_radius = 1.3
	bmesh.height = 1.8
	base.mesh = bmesh
	base.material_override = marble
	base.position = Vector3(-0.6, 0.9 + 0.3, -0.4)
	bld.add_child(base)

	var spire := MeshInstance3D.new()
	var smesh := CylinderMesh.new()
	smesh.top_radius = 0.12
	smesh.bottom_radius = 0.85
	smesh.height = 2.8
	spire.mesh = smesh
	spire.material_override = glass
	spire.position = Vector3(-0.6, 3.2, -0.4)
	bld.add_child(spire)

	var arc_mat := StandardMaterial3D.new()
	arc_mat.albedo_color = Color(0.66, 0.5, 1.0)
	arc_mat.emission_enabled = true
	arc_mat.emission = Color(0.6, 0.42, 1.0)
	arc_mat.emission_energy_multiplier = 2.6

	var beacon := MeshInstance3D.new()
	var bemesh := SphereMesh.new()
	bemesh.radius = 0.3
	bemesh.height = 0.6
	beacon.mesh = bemesh
	beacon.material_override = arc_mat
	beacon.position = Vector3(-0.6, 4.75, -0.4)
	bld.add_child(beacon)

	for cx in [1.6, -2.6]:
		var rod := MeshInstance3D.new()
		var rmesh := CylinderMesh.new()
		rmesh.top_radius = 0.07
		rmesh.bottom_radius = 0.12
		rmesh.height = 3.0
		rod.mesh = rmesh
		rod.material_override = dark
		rod.position = Vector3(cx, 1.8, 1.2)
		bld.add_child(rod)
		var orb := MeshInstance3D.new()
		var omesh := SphereMesh.new()
		omesh.radius = 0.22
		omesh.height = 0.44
		orb.mesh = omesh
		orb.material_override = arc_mat
		orb.position = Vector3(cx, 3.5, 1.2)
		bld.add_child(orb)


func _hq_ashfall(root: Node3D) -> void:
	var bld := Node3D.new()
	bld.rotation_degrees = Vector3(0, -18, 0)
	root.add_child(bld)
	root = bld

	var scrap := _flat_mat(Color(0.36, 0.34, 0.23), 0.95)
	var rust := _flat_mat(Color(0.38, 0.24, 0.15), 0.9)
	var bag := _flat_mat(Color(0.38, 0.35, 0.27), 1.0)

	var shack := MeshInstance3D.new()
	var smesh := BoxMesh.new()
	smesh.size = Vector3(3.0, 1.7, 2.4)
	shack.mesh = smesh
	shack.material_override = scrap
	shack.position = Vector3(-0.5, 1.0, -0.7)
	root.add_child(shack)

	var roof := MeshInstance3D.new()
	var rmesh := BoxMesh.new()
	rmesh.size = Vector3(3.5, 0.12, 2.9)
	roof.mesh = rmesh
	roof.material_override = rust
	roof.position = Vector3(-0.5, 1.95, -0.7)
	roof.rotation_degrees = Vector3(0, 0, 7)
	root.add_child(roof)

	for i in range(2):
		var barrel := MeshInstance3D.new()
		var bmesh := CylinderMesh.new()
		bmesh.top_radius = 0.26
		bmesh.bottom_radius = 0.26
		bmesh.height = 0.72
		barrel.mesh = bmesh
		barrel.material_override = rust
		barrel.position = Vector3(1.6 + i * 0.6, 0.66, 1.3 - i * 0.4)
		root.add_child(barrel)

	for i in range(10):                       # sandbag arc around the front
		var ang := -0.4 + i * 0.36
		var sb := MeshInstance3D.new()
		var sbm := BoxMesh.new()
		sbm.size = Vector3(0.72, 0.34, 0.4)
		sb.mesh = sbm
		sb.material_override = bag
		sb.position = Vector3(cos(ang) * 2.9, 0.45, sin(ang) * 2.9)
		sb.rotation_degrees = Vector3(0, -rad_to_deg(ang), 0)
		root.add_child(sb)


func _flag(root: Node3D, col: Color, fac_id := 0) -> void:
	var pole := MeshInstance3D.new()
	var pmesh := CylinderMesh.new()
	pmesh.top_radius = 0.05
	pmesh.bottom_radius = 0.05
	pmesh.height = 3.4
	pole.mesh = pmesh
	pole.material_override = _flat_mat(Color(0.55, 0.55, 0.58), 0.4, 0.8)
	pole.position = Vector3(2.6, 1.85, -2.6)
	root.add_child(pole)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.25, 0.55)
	# more segments than the default 1x1: the wave is applied per VERTEX, so a
	# two-triangle quad can only ever tilt as a rigid sheet — the cloth needs
	# spans along its length to actually ripple
	quad.subdivide_width = 14
	quad.subdivide_depth = 2
	quad.center_offset = Vector3(0.625, 0, 0)   # hangs off the pole to +X
	var flag := MeshInstance3D.new()
	flag.mesh = quad
	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://flag.gdshader")
	fmat.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
	var btex := "res://textures/flag_f%d.png" % fac_id
	if fac_id > 0 and ResourceLoader.exists(btex):
		fmat.set_shader_parameter("banner", load(btex))
		fmat.set_shader_parameter("use_tex", true)
	flag.material_override = fmat
	flag.position = Vector3(2.6, 3.25, -2.6)
	root.add_child(flag)


func _smoke(root: Node3D, at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 2.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.12, 0.35, 0.0)      # drifts up and slightly east
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.6, 0.58, 0.4))
	ramp.set_color(1, Color(0.55, 0.55, 0.55, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	p.process_material = pm

	var puff := SphereMesh.new()
	puff.radius = 0.26
	puff.height = 0.52
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	puff.material = pmat
	p.draw_pass_1 = puff
	p.position = at
	root.add_child(p)

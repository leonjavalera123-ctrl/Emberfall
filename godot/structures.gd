# EMBERFALL: 1940 — structures.gd
# GARRISONS: the map's ruined farms / bunkers / watchtowers ('B' tiles).
# Infantry of ANY faction can occupy them for hard cover. Occupied buildings
# glow their holder's color. In Phase 5, garrisoned troops take
# GARRISON_DAMAGE_MULT of incoming damage and shoot from the walls.
# (Constructed base buildings live in buildings.gd.)

class_name EFStructures
extends Node3D

const T := 2.0
const GARRISON_DAMAGE_MULT := 0.5     # cover bonus, applied in Phase 5 combat

var world: EFWorld
var army: EFArmy
var garrisons: Array = []             # dicts, see _make_garrison
var cell_to_garrison := {}            # Vector2i -> garrison index
var selected := -1                    # selected garrison index (UI), -1 = none
var _sel_ring: MeshInstance3D


func setup(w: EFWorld, a: EFArmy) -> void:
	world = w
	army = a
	for grp in world.b_groups:
		_make_garrison(grp)
	_make_selection_ring()


# ============================ GARRISONS ======================================

func _make_garrison(cells: Array[Vector2i]) -> void:
	var minx := 99999
	var maxx := -99999
	var miny := 99999
	var maxy := -99999
	for c in cells:
		minx = mini(minx, c.x)
		maxx = maxi(maxx, c.x)
		miny = mini(miny, c.y)
		maxy = maxi(maxy, c.y)
	var center := Vector3((minx + maxx + 1) * 0.5 * T, 0, (miny + maxy + 1) * 0.5 * T)
	var kind_name := "Bunker" if cells.size() == 1 else \
		("Ruined House" if cells.size() >= 6 else "Ruined Farmhouse")
	var g := {
		"cells": cells, "center": center, "door": _find_door(cells),
		"capacity": clampi(cells.size() * 2, 2, 6), "occupants": [],
		"kind_name": kind_name, "size": Vector2(maxx - minx + 1, maxy - miny + 1),
		"win_mat": null, "banner": null,
	}
	var idx := garrisons.size()
	for c in cells:
		cell_to_garrison[c] = idx
	_build_garrison_mesh(g)
	garrisons.append(g)


func _find_door(cells: Array[Vector2i]) -> Vector2i:
	for c in cells:
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if world.is_walkable(n.x, n.y):
				return n
	return cells[0]


func _build_garrison_mesh(g: Dictionary) -> void:
	var root := Node3D.new()
	root.position = g["center"]
	add_child(root)
	var sx: float = g["size"].x * T
	var sz: float = g["size"].y * T
	var hh := EFWorld.tile_hash(g["cells"][0].x, g["cells"][0].y, 55)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.34, 0.32, 0.29).lerp(Color(0.42, 0.38, 0.32),
		float(hh % 100) / 100.0)
	stone.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.095, 0.09)
	dark.roughness = 0.9

	# occupied-glow window material (dim until someone moves in)
	var win := StandardMaterial3D.new()
	win.albedo_color = Color(0.15, 0.14, 0.13)
	win.emission_enabled = true
	win.emission = Color(0.9, 0.6, 0.3)
	win.emission_energy_multiplier = 0.0
	g["win_mat"] = win

	if g["cells"].size() == 1:
		# bunker: low concrete block with a firing slit
		_box(root, Vector3(sx * 0.82, 1.1, sz * 0.82), Vector3(0, 0.55, 0), stone)
		_box(root, Vector3(sx * 0.9, 0.25, sz * 0.9), Vector3(0, 1.22, 0), dark)
		_box(root, Vector3(sx * 0.6, 0.18, 0.1), Vector3(0, 0.78, sz * 0.42), win)
	else:
		# ruined walls: full-height shell with a broken, uneven parapet
		_box(root, Vector3(sx * 0.86, 1.9, sz * 0.86), Vector3(0, 0.95, 0), stone)
		for i in range(3 + hh % 3):
			var hb := EFWorld.tile_hash(g["cells"][0].x, g["cells"][0].y, 60 + i)
			var bx := (float(hb % 100) / 100.0 - 0.5) * sx * 0.7
			var bz := (float((hb >> 7) % 100) / 100.0 - 0.5) * sz * 0.7
			_box(root, Vector3(0.5 + float(hb % 40) / 100.0, 0.5, 0.4),
				Vector3(bx, 2.15, bz), stone)
		_box(root, Vector3(0.9, 1.3, 0.12), Vector3(0, 0.65, sz * 0.43 - 0.02), dark)
		for wx in [-sx * 0.25, sx * 0.25]:
			_box(root, Vector3(0.55, 0.45, 0.1), Vector3(wx, 1.25, sz * 0.43), win)
			_box(root, Vector3(0.55, 0.45, 0.1), Vector3(wx, 1.25, -sz * 0.43), win)

	# holder banner (hidden until garrisoned)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.04
	pole.height = 1.4
	var pmi := MeshInstance3D.new()
	pmi.mesh = pole
	pmi.material_override = dark
	pmi.position = Vector3(sx * 0.3, 2.6, -sz * 0.3)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.4)
	quad.center_offset = Vector3(0.4, 0, 0)
	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://flag.gdshader")
	var fmi := MeshInstance3D.new()
	fmi.mesh = quad
	fmi.material_override = fmat
	fmi.position = Vector3(sx * 0.3, 3.1, -sz * 0.3)
	var banner := Node3D.new()
	banner.add_child(pmi)
	banner.add_child(fmi)
	banner.visible = false
	root.add_child(banner)
	g["banner"] = banner
	g["banner_mat"] = fmat


func garrison_at(tile: Vector2i) -> int:
	return cell_to_garrison.get(tile, -1)


func enter(u: EFUnit, idx: int) -> bool:
	var g: Dictionary = garrisons[idx]
	if g["occupants"].size() >= g["capacity"]:
		return false
	if not g["occupants"].is_empty() and g["occupants"][0].faction != u.faction:
		return false                      # no sharing with the enemy
	g["occupants"].append(u)
	u.garrisoned_in = idx
	u.selected = false
	u.visible = false
	u.path.clear()
	u.vel = Vector3.ZERO
	u.global_position = g["center"]
	_update_holder_visuals(idx)
	return true


func unload(idx: int, point: Vector3) -> void:
	var g: Dictionary = garrisons[idx]
	var door: Vector2i = g["door"]
	var door_pos := Vector3((door.x + 0.5) * T, 0, (door.y + 0.5) * T)
	var i := 0
	for u: EFUnit in g["occupants"]:
		u.garrisoned_in = -1
		u.visible = true
		u.global_position = door_pos + Vector3(0.3 * (i % 3) - 0.3, 0, 0.3 * (i / 3))
		army.path_single(u, point, i)
		i += 1
	g["occupants"].clear()
	_update_holder_visuals(idx)
	if selected == idx:
		select_garrison(-1)


func _update_holder_visuals(idx: int) -> void:
	var g: Dictionary = garrisons[idx]
	var occupied: bool = not g["occupants"].is_empty()
	var fac_col := Color(1, 1, 1)
	if occupied:
		fac_col = EFWorld.FACTIONS[g["occupants"][0].faction]["color"]
	g["win_mat"].emission = fac_col if occupied else Color(0.9, 0.6, 0.3)
	g["win_mat"].emission_energy_multiplier = 2.2 if occupied else 0.0
	g["banner"].visible = occupied
	if occupied:
		g["banner_mat"].set_shader_parameter("col",
			Vector3(fac_col.r, fac_col.g, fac_col.b))


func select_garrison(idx: int) -> void:
	selected = idx
	_sel_ring.visible = idx >= 0
	if idx >= 0:
		var g: Dictionary = garrisons[idx]
		_sel_ring.position = g["center"] + Vector3(0, 0.1, 0)
		var s: float = maxf(g["size"].x, g["size"].y) * T * 0.75
		_sel_ring.scale = Vector3(s, 1, s)


func damage_garrison(idx: int, wclass: String, dmg: float, army_ref: EFArmy) -> void:
	# Cover in action: hits on an occupied ruin reach the defenders at
	# GARRISON_DAMAGE_MULT strength. The stone shell itself is indestructible.
	var g: Dictionary = garrisons[idx]
	if g["occupants"].is_empty():
		return
	var t: EFUnit = g["occupants"][0]
	t.hp -= dmg * EFArmy.ARMOR_MULT[wclass][t.armor] * GARRISON_DAMAGE_MULT
	if t.hp <= 0.0:
		g["occupants"].erase(t)
		t.garrisoned_in = -1
		army_ref.kill_unit(t, false)
		_update_holder_visuals(idx)


func garrison_summary(idx: int) -> Dictionary:
	var g: Dictionary = garrisons[idx]
	var counts := {}
	for u in g["occupants"]:
		var key: String = u.display_name + " (garrisoned)"
		counts[key] = counts.get(key, 0) + 1
	return counts


func _make_selection_ring() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 1.0, 0.55)
	m.emission_enabled = true
	m.emission = Color(0.35, 1.0, 0.4)
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_ring = MeshInstance3D.new()
	_sel_ring.mesh = ring
	_sel_ring.material_override = m
	_sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sel_ring.visible = false
	add_child(_sel_ring)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

# EMBERFALL: 1940 — army.gd
# Owns every unit on the field: spawning, selection, move orders, and the
# two crowd systems from the design doc —
#   1) A* pathfinding on the tile grid (Godot's AStarGrid2D: octile
#      heuristic, no corner cutting), with greedy string-pulling so units
#      walk smooth lines instead of tile-center zigzags;
#   2) the push-apart pass: units are points with radii that gently shove
#      each other aside, which avoids classic RTS tile-gridlock entirely.

class_name EFArmy
extends Node3D

const T := 2.0

# Stats follow GAME_DESIGN.md §8: baseline roles with faction skews baked in
# (Karvath HP x1.3, Ashfall HP x0.75). Damage = dmg x ARMOR_MULT[class][armor].
const KINDS := {
	"iron_guard": {"name": "Iron Guard", "speed": 3.7, "radius": 0.34, "turn": 12.0, "kind": "inf",
		"hp": 72.0, "armor": "INF",
		"weapon": {"class": "BULLET", "dmg": 8.0, "rof": 1.0, "range": 8.0}},
	"grenadier": {"name": "Grenadier", "speed": 3.4, "radius": 0.36, "turn": 12.0, "kind": "inf",
		"hp": 65.0, "armor": "INF",
		"weapon": {"class": "BLAST", "dmg": 30.0, "rof": 0.5, "range": 11.0}},
	"bastion": {"name": "Bastion Tank", "speed": 4.1, "radius": 0.85, "turn": 4.5, "kind": "tank",
		"hp": 416.0, "armor": "HEAVY",
		"weapon": {"class": "CANNON", "dmg": 45.0, "rof": 0.55, "range": 11.0}},
	"outrider": {"name": "Outrider", "speed": 7.6, "radius": 0.6, "turn": 7.0, "kind": "scout",
		"hp": 143.0, "armor": "LIGHT",
		"weapon": {"class": "BULLET", "dmg": 10.0, "rof": 1.5, "range": 8.0}},
	"mule": {"name": "Mule Harvester", "speed": 3.2, "radius": 0.7, "turn": 5.0, "kind": "harvester",
		"hp": 520.0, "armor": "LIGHT", "weapon": null},
	"conscript": {"name": "Conscript", "speed": 4.4, "radius": 0.3, "turn": 12.0, "kind": "inf",
		"hp": 41.0, "armor": "INF",
		"weapon": {"class": "BULLET", "dmg": 8.0, "rof": 1.0, "range": 8.0}},
	"sapper": {"name": "Cinder Sapper", "speed": 3.8, "radius": 0.32, "turn": 12.0, "kind": "inf",
		"hp": 38.0, "armor": "INF",
		"weapon": {"class": "BLAST", "dmg": 30.0, "rof": 0.5, "range": 11.0}},
	"rat": {"name": "Rat Tankette", "speed": 8.5, "radius": 0.55, "turn": 8.0, "kind": "smalltank",
		"hp": 83.0, "armor": "LIGHT",
		"weapon": {"class": "BULLET", "dmg": 10.0, "rof": 1.5, "range": 8.0}},
	"warpig": {"name": "Warpig Tank", "speed": 3.4, "radius": 0.8, "turn": 4.5, "kind": "tank",
		"hp": 240.0, "armor": "HEAVY",
		"weapon": {"class": "CANNON", "dmg": 45.0, "rof": 0.55, "range": 11.0}},
	"magpie": {"name": "Magpie Harvester", "speed": 3.6, "radius": 0.65, "turn": 5.5, "kind": "harvester",
		"hp": 300.0, "armor": "LIGHT", "weapon": null},
	# --- Aurelian League (faction 3): fast, fragile on the ground, lethal above it ---
	"sky_marine": {"name": "Sky Marine", "speed": 4.4, "radius": 0.32, "turn": 12.0, "kind": "inf",
		"hp": 55.0, "armor": "INF",
		"weapon": {"class": "BULLET", "dmg": 8.0, "rof": 1.0, "range": 8.0}},
	"rocketeer": {"name": "Rocketeer", "speed": 3.8, "radius": 0.34, "turn": 12.0, "kind": "inf",
		"hp": 50.0, "armor": "INF",
		"weapon": {"class": "ROCKET", "dmg": 26.0, "rof": 0.5, "range": 11.0}},
	"dart": {"name": "Dart", "speed": 10.8, "radius": 0.55, "turn": 8.0, "kind": "scout",
		"hp": 88.0, "armor": "LIGHT",
		"weapon": {"class": "BULLET", "dmg": 10.0, "rof": 1.5, "range": 8.0}},
	"pavise": {"name": "Pavise Tank", "speed": 6.4, "radius": 0.75, "turn": 6.0, "kind": "tank",
		"hp": 256.0, "armor": "LIGHT",
		"weapon": {"class": "CANNON", "dmg": 38.0, "rof": 0.6, "range": 11.0}},
	"dray": {"name": "Dray Harvester", "speed": 4.0, "radius": 0.68, "turn": 5.5, "kind": "harvester",
		"hp": 320.0, "armor": "LIGHT", "weapon": null},
	"zephyr": {"name": "Zephyr AA", "speed": 7.6, "radius": 0.6, "turn": 7.0, "kind": "scout",
		"hp": 128.0, "armor": "LIGHT",
		"weapon": {"class": "FLAK", "dmg": 12.0, "rof": 2.2, "range": 12.0}},
	# --- anti-air trucks for the other banners ---
	"sperrwagen": {"name": "Sperrwagen AA", "speed": 5.4, "radius": 0.65, "turn": 6.0, "kind": "scout",
		"hp": 208.0, "armor": "LIGHT",
		"weapon": {"class": "FLAK", "dmg": 12.0, "rof": 2.0, "range": 12.0}},
	"stovepipe": {"name": "Stovepipe Truck", "speed": 6.8, "radius": 0.62, "turn": 7.0, "kind": "scout",
		"hp": 120.0, "armor": "LIGHT",
		"weapon": {"class": "FLAK", "dmg": 12.0, "rof": 2.0, "range": 12.0}},
	# --- the sky (Phase 6): armor class AIR, ignores terrain, never lands ---
	"kondor": {"name": "Kondor Gunship", "speed": 10.0, "radius": 1.0, "turn": 2.2, "kind": "plane",
		"flying": true, "hp": 170.0, "armor": "AIR",
		"weapon": {"class": "CANNON", "dmg": 22.0, "rof": 1.6, "range": 10.0}},
	"sparrowhawk": {"name": "Sparrowhawk", "speed": 15.0, "radius": 0.9, "turn": 3.2, "kind": "plane",
		"flying": true, "hp": 150.0, "armor": "AIR",
		"weapon": {"class": "FLAK", "dmg": 12.0, "rof": 3.0, "range": 9.0}},
	"duster": {"name": "Duster", "speed": 12.0, "radius": 0.9, "turn": 2.8, "kind": "plane",
		"flying": true, "hp": 100.0, "armor": "AIR",
		"weapon": {"class": "ROCKET", "dmg": 24.0, "rof": 0.8, "range": 9.0}},
	"pelican": {"name": "Pelican", "speed": 8.0, "radius": 1.0, "turn": 3.0, "kind": "plane",
		"flying": true, "hp": 200.0, "armor": "AIR", "weapon": null},
	# --- Luminar Covenant (faction 4): few, brilliant, shielded, grid-bound ---
	"arc_templar": {"name": "Arc Templar", "speed": 3.6, "radius": 0.34, "turn": 12.0,
		"kind": "inf", "hp": 55.0, "armor": "INF", "shield": 40.0,
		"weapon": {"class": "ARC", "dmg": 10.0, "rof": 1.0, "range": 8.0}},
	"lance_warden": {"name": "Lance Warden", "speed": 3.4, "radius": 0.36, "turn": 12.0,
		"kind": "inf", "hp": 50.0, "armor": "INF", "shield": 40.0,
		"weapon": {"class": "ARC", "dmg": 39.0, "rof": 0.5, "range": 11.0}},
	"glimmer": {"name": "Glimmer", "speed": 8.4, "radius": 0.55, "turn": 8.0,
		"kind": "scout", "hp": 110.0, "armor": "LIGHT", "shield": 40.0,
		"weapon": {"class": "BULLET", "dmg": 13.0, "rof": 1.5, "range": 8.0}},
	"faraday": {"name": "Faraday Walker", "speed": 3.8, "radius": 0.8, "turn": 5.0,
		"kind": "tank", "hp": 320.0, "armor": "HEAVY", "shield": 40.0,
		"weapon": {"class": "ARC", "dmg": 58.0, "rof": 0.55, "range": 11.0}},
	"ion_carriage": {"name": "Ion Carriage", "speed": 6.8, "radius": 0.62, "turn": 7.0,
		"kind": "scout", "hp": 160.0, "armor": "LIGHT", "shield": 40.0,
		"weapon": {"class": "FLAK", "dmg": 16.0, "rof": 2.2, "range": 12.0}},
	"collector": {"name": "Collector", "speed": 3.4, "radius": 0.68, "turn": 5.5,
		"kind": "harvester", "hp": 400.0, "armor": "LIGHT", "shield": 40.0,
		"weapon": null},
	"seraph": {"name": "Seraph", "speed": 13.0, "radius": 0.9, "turn": 3.0,
		"kind": "plane", "flying": true, "hp": 130.0, "armor": "AIR", "shield": 40.0,
		"weapon": {"class": "ROCKET", "dmg": 31.0, "rof": 0.8, "range": 9.0}},
	# --- Phase 9: signature tech ---
	# --- mobile construction vehicles: one-shot, deploy into a Command Post ---
	"forge_crawler": {"name": "Forge Crawler", "speed": 2.3, "radius": 1.05, "turn": 2.4,
		"kind": "mcv", "hp": 1300.0, "armor": "HEAVY", "weapon": null},
	"scrap_hauler": {"name": "Scrapworks Hauler", "speed": 2.7, "radius": 1.05, "turn": 2.8,
		"kind": "mcv", "hp": 1050.0, "armor": "HEAVY", "weapon": null},
	"keelwright": {"name": "Keelwright Carrier", "speed": 2.9, "radius": 1.05, "turn": 3.0,
		"kind": "mcv", "hp": 1100.0, "armor": "HEAVY", "weapon": null},
	"ark_carriage": {"name": "Ark Carriage", "speed": 2.5, "radius": 1.05, "turn": 2.6,
		"kind": "mcv", "hp": 1150.0, "armor": "HEAVY", "shield": 250.0, "weapon": null},
	"hammerfall": {"name": "Hammerfall Crawler", "speed": 2.6, "radius": 0.9, "turn": 3.5,
		"kind": "tank", "hp": 300.0, "armor": "HEAVY",
		"weapon": {"class": "BLAST", "dmg": 60.0, "rof": 0.35, "range": 16.0}},
	"wasp": {"name": "Wasp Gyrocopter", "speed": 9.0, "radius": 0.8, "turn": 4.0,
		"kind": "plane", "flying": true, "hp": 90.0, "armor": "AIR",
		"weapon": {"class": "BULLET", "dmg": 10.0, "rof": 3.0, "range": 8.0}},
	"vulture": {"name": "Vulture Crew", "speed": 4.0, "radius": 0.34, "turn": 12.0,
		"kind": "inf", "hp": 45.0, "armor": "INF", "weapon": null},
	"dynamo": {"name": "Dynamo Wagon", "speed": 5.0, "radius": 0.66, "turn": 6.0,
		"kind": "scout", "hp": 200.0, "armor": "LIGHT", "shield": 40.0, "weapon": null},
	# --- the superunits ---
	"juggernaut": {"name": "Juggernaut", "speed": 2.4, "radius": 1.5, "turn": 2.0,
		"kind": "tank", "hp": 2200.0, "armor": "HEAVY",
		"weapon": {"class": "CANNON", "dmg": 60.0, "rof": 1.0, "range": 13.0}},
	"ashworm": {"name": "The Ashworm", "speed": 3.2, "radius": 1.4, "turn": 2.4,
		"kind": "tank", "hp": 1500.0, "armor": "HEAVY",
		"weapon": {"class": "BLAST", "dmg": 50.0, "rof": 0.8, "range": 11.0}},
	"leviathan": {"name": "Stratos Leviathan", "speed": 7.0, "radius": 1.8, "turn": 1.6,
		"kind": "plane", "flying": true, "hp": 1300.0, "armor": "AIR",
		"weapon": {"class": "CANNON", "dmg": 40.0, "rof": 1.2, "range": 12.0}},
	"cathedral": {"name": "The Cathedral", "speed": 6.0, "radius": 1.8, "turn": 1.5,
		"kind": "plane", "flying": true, "hp": 1100.0, "armor": "AIR", "shield": 80.0,
		"weapon": {"class": "ARC", "dmg": 70.0, "rof": 0.5, "range": 12.0}},
}

const ARMOR_MULT := {
	"BULLET": {"INF": 1.0, "LIGHT": 0.6, "HEAVY": 0.3, "AIR": 0.4, "BLDG": 0.25},
	"CANNON": {"INF": 0.5, "LIGHT": 1.0, "HEAVY": 1.0, "AIR": 0.0, "BLDG": 0.9},
	"BLAST":  {"INF": 1.2, "LIGHT": 0.8, "HEAVY": 0.6, "AIR": 0.0, "BLDG": 1.5},
	"FLAK":   {"INF": 0.6, "LIGHT": 0.4, "HEAVY": 0.2, "AIR": 1.5, "BLDG": 0.2},
	"ROCKET": {"INF": 0.4, "LIGHT": 0.9, "HEAVY": 1.25, "AIR": 0.9, "BLDG": 1.0},
	"ARC":    {"INF": 1.3, "LIGHT": 1.0, "HEAVY": 0.8, "AIR": 0.5, "BLDG": 0.7},
}

const TURRET_WEAPON := {"class": "CANNON", "dmg": 40.0, "rof": 0.7, "range": 12.0}
const AA_TURRET_WEAPON := {"class": "FLAK", "dmg": 14.0, "rof": 2.5, "range": 14.0}
const AGGRO_RANGE := 24.0     # how far the enemy garrison notices intruders
const WIDE_R := 1.5           # the widest GROUND radius in KINDS (juggernaut)
# 1.25 is derived, not tuned: above it, radius*0.8 exceeds half a tile, so
# clear_at's corner samples land in the DIAGONAL neighbours and the unit's own
# tile is never tested. Those units need the clearance-aware grid.
const WIDE_MIN := 1.25

var world: EFWorld
var audio: EFAudio                    # wired by main after setup
var music: EFMusic                    # wired by main after setup
var economy: EFEconomy                # wired by main after setup
var structures: EFStructures          # wired by main after setup
var buildings: EFBuildings            # wired by main after setup
var astar := AStarGrid2D.new()
# A second grid for units too wide to fit a one-tile gap. The main grid marks a
# tile solid purely from world.is_walkable, which is a single-tile boolean — so
# it happily routed a 1.5 m-radius Juggernaut through 1 m gaps it cannot
# physically enter, and the stuck watchdog then re-issued the same impossible
# route until it gave up and stood down 45 m short.
var astar_wide := AStarGrid2D.new()
var units: Array[EFUnit] = []
var selection: Array[EFUnit] = []
var player_faction := 1
var selection_dirty := true
var _markers: Array = []
var _dust_t := 0.0


func setup(w: EFWorld) -> void:
	world = w
	astar.region = Rect2i(0, 0, world.w, world.h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	astar_wide.region = Rect2i(0, 0, world.w, world.h)
	astar_wide.cell_size = Vector2.ONE
	astar_wide.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_wide.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar_wide.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar_wide.update()
	for ty in range(world.h):
		for tx in range(world.w):
			if not world.is_walkable(tx, ty):
				astar.set_point_solid(Vector2i(tx, ty), true)
			_refresh_wide(Vector2i(tx, ty))


func spawn(kind: String, fac: int, tile: Vector2i) -> EFUnit:
	# a wide unit must not materialise on a tile it cannot legally stand on —
	# the Doomworks door is exactly such a tile for a Juggernaut, and spawning
	# there jammed it before it had moved an inch
	var wide_spawn: bool = float(KINDS[kind].get("radius", 0.5)) > WIDE_MIN
	var cell := tile if KINDS[kind].get("flying", false) \
		else _nearest_open(tile, wide_spawn)
	var u := EFUnit.new()
	u.setup(kind, KINDS[kind], fac, EFWorld.FACTIONS[fac]["color"])
	add_child(u)
	u.global_position = Vector3((cell.x + 0.5) * T, 0, (cell.y + 0.5) * T)
	units.append(u)
	return u


func spawn_start_forces() -> void:
	# each start slot musters whichever faction the menu assigned to it,
	# offsets aimed at the map center so this works on every map size
	for slot in world.slot_faction:
		if not world.starts.has(slot):
			continue
		var f: int = world.slot_faction[slot]
		var s: Vector2i = world.starts[slot]
		var dx := 1 if s.x < world.w / 2 else -1
		var dy := 1 if s.y < world.h / 2 else -1
		match f:
			1:
				for i in range(6):
					spawn("iron_guard", 1, s + Vector2i(dx * (4 + i % 3), dy * (4 + i / 3)))
				spawn("grenadier", 1, s + Vector2i(dx * 7, dy * 4))
				spawn("grenadier", 1, s + Vector2i(dx * 7, dy * 6))
				spawn("bastion", 1, s + Vector2i(dx * 9, dy * 4))
				spawn("bastion", 1, s + Vector2i(dx * 9, dy * 6))
				spawn("outrider", 1, s + Vector2i(dx * 11, dy * 2))
			2:
				for i in range(8):
					spawn("conscript", 2, s + Vector2i(dx * (4 + i % 4), dy * (4 + i / 4)))
				spawn("sapper", 2, s + Vector2i(dx * 7, dy * 6))
				spawn("sapper", 2, s + Vector2i(dx * 9, dy * 6))
				for i in range(3):
					spawn("rat", 2, s + Vector2i(dx * (5 + i), dy * 8))
				spawn("warpig", 2, s + Vector2i(dx * 9, dy * 9))
				spawn("warpig", 2, s + Vector2i(dx * 11, dy * 7))
			3:
				for i in range(6):
					spawn("sky_marine", 3, s + Vector2i(dx * (4 + i % 3), dy * (4 + i / 3)))
				spawn("rocketeer", 3, s + Vector2i(dx * 7, dy * 4))
				spawn("rocketeer", 3, s + Vector2i(dx * 7, dy * 6))
				spawn("pavise", 3, s + Vector2i(dx * 9, dy * 4))
				spawn("zephyr", 3, s + Vector2i(dx * 9, dy * 6))
				spawn("dart", 3, s + Vector2i(dx * 11, dy * 2))
			4:
				# the Covenant was playable from the menu with no army at all:
				# this match had no case 4 and no default, so a Luminar side
				# opened with a command post, a refinery and one harvester
				for i in range(6):
					spawn("arc_templar", 4, s + Vector2i(dx * (4 + i % 3), dy * (4 + i / 3)))
				spawn("lance_warden", 4, s + Vector2i(dx * 7, dy * 4))
				spawn("lance_warden", 4, s + Vector2i(dx * 7, dy * 6))
				spawn("faraday", 4, s + Vector2i(dx * 9, dy * 4))
				spawn("ion_carriage", 4, s + Vector2i(dx * 9, dy * 6))
				spawn("glimmer", 4, s + Vector2i(dx * 11, dy * 2))


func _process(dt: float) -> void:
	for u in units:
		if u.garrisoned_in >= 0:
			# step() is skipped in here, and that is where deploy_t drains — so a
			# unit that garrisons mid-transition would keep deploy_t > 0 forever
			# and _combat would silence its weapon for the rest of the game
			u.deploy_t = maxf(0.0, u.deploy_t - dt)
			continue
		u.step(dt, world)
		if u.is_infantry():
			u.squad_tick(dt)
		if u.is_harvester():
			u.harvest_tick(dt, self)
		_stall_watch(u, dt)
		if u.stuck_time > 0.7 and u.goal_cell.x >= 0:
			# Repath to the unit's OWN destination, not the shared goal tile —
			# sending every jammed unit to one tile centre was what made a stuck
			# group pile onto a single point instead of spreading out.
			u.repath_tries += 1
			if u.repath_tries > 3:
				# It has tried and failed repeatedly: it is boxed in by its own
				# side in a choke point. Stand down rather than grind forever;
				# the crowd will drain and a fresh order always works.
				u.path.clear()
				u.goal_cell = Vector2i(-1, -1)
				u.slot_point = Vector3.INF
				u.repath_tries = 0
			elif u.slot_point != Vector3.INF:
				_path_unit(u, u.slot_point)
			else:
				_path_unit(u, Vector3((u.goal_cell.x + 0.5) * T, 0,
					(u.goal_cell.y + 0.5) * T))
			u.stuck_time = 0.0
		# arriving at a garrison door?
		if u.garrison_target >= 0 and u.path.is_empty():
			var g: Dictionary = structures.garrisons[u.garrison_target]
			var door_pos := Vector3((g["door"].x + 0.5) * T, 0, (g["door"].y + 0.5) * T)
			if u.global_position.distance_to(door_pos) < 1.9:
				var idx: int = u.garrison_target
				u.garrison_target = -1
				if structures.enter(u, idx):
					selection.erase(u)
					selection_dirty = true
			else:
				u.garrison_target = -1
	_separate()
	_dust_t -= dt
	if _dust_t <= 0.0:
		_dust_t = 0.45
		for u in units:
			if u.hp > 0 and not u.flying and not u.is_infantry() \
					and u.garrisoned_in < 0 and u.vel.length() > 2.5:
				_puff(u.global_position + u.global_transform.basis.z * u.radius
					+ Vector3(0, 0.25, 0), Color(0.42, 0.38, 0.32), 0.55)
	_fade_markers(dt)
	_combat(dt)
	_transport_tick()
	_fort_tick(dt)
	shields_tick(dt)
	_reveal_tick(dt)
	_heal_tick(dt)
	_salvage_tick(dt)
	_wrecks_tick(dt)
	_sw_tick(dt)
	_projectiles_tick(dt)
	_fx_tick(dt)


# --- selection -------------------------------------------------------------------

func has_selection() -> bool:
	return not selection.is_empty()


signal selection_cleared


func clear_selection() -> void:
	for u in selection:
		u.selected = false
	selection.clear()
	selection_dirty = true
	# clicking off your troops should also stop the camera trailing them
	selection_cleared.emit()


func click_select(screen_pos: Vector2, additive: bool, cam: Camera3D) -> void:
	var origin := cam.project_ray_origin(screen_pos)
	var dirn := cam.project_ray_normal(screen_pos)
	var best: EFUnit = null
	var best_d := 1e9
	if dirn.y < -0.0001:
		for u in units:
			if u.faction != player_faction or u.garrisoned_in >= 0:
				continue
			# project the click ray to THIS unit's altitude — planes fly at ~8 m
			var hit := origin + dirn * ((u.global_position.y - origin.y) / dirn.y)
			var d := Vector2(u.global_position.x - hit.x, u.global_position.z - hit.z).length()
			if d < u.radius + 0.4 and d < best_d:
				best_d = d
				best = u
	if not additive:
		clear_selection()
	if best and not selection.has(best):
		best.selected = true
		selection.append(best)
	selection_dirty = true


func box_select(rect: Rect2, additive: bool, cam: Camera3D) -> void:
	if not additive:
		clear_selection()
	for u in units:
		if u.faction != player_faction or selection.has(u) or u.garrisoned_in >= 0:
			continue
		var p := u.global_position + Vector3(0, 0.5, 0)
		if cam.is_position_behind(p):
			continue
		if rect.has_point(cam.unproject_position(p)):
			u.selected = true
			selection.append(u)
	selection_dirty = true


func select_all_player() -> void:
	clear_selection()
	for u in units:
		if u.faction == player_faction:
			u.selected = true
			selection.append(u)
	selection_dirty = true


func get_selection_summary() -> Dictionary:
	var counts := {}
	for u in selection:
		counts[u.display_name] = counts.get(u.display_name, 0) + 1
		for c: EFUnit in u.cargo_units:
			var key: String = c.display_name + " (aboard)"
			counts[key] = counts.get(key, 0) + 1
	return counts


func select_same_kind_on_screen(screen_pos: Vector2, additive: bool, cam: Camera3D,
		view_w: float, view_h: float) -> bool:
	# double-click: grab every one of that kind the player can actually see
	var origin := cam.project_ray_origin(screen_pos)
	var dirn := cam.project_ray_normal(screen_pos)
	if dirn.y >= -0.0001:
		return false
	var best: EFUnit = null
	var best_d := 1e9
	for u in units:
		if u.faction != player_faction or u.garrisoned_in >= 0 or u.hp <= 0:
			continue
		var hit := origin + dirn * ((u.global_position.y - origin.y) / dirn.y)
		var d := Vector2(u.global_position.x - hit.x, u.global_position.z - hit.z).length()
		if d < u.radius + 0.4 and d < best_d:
			best_d = d
			best = u
	if best == null:
		return false
	var kind_key: String = best.kind
	if not additive:
		clear_selection()
	for u2 in units:
		if u2.faction != player_faction or u2.kind != kind_key:
			continue
		if u2.garrisoned_in >= 0 or u2.stowed or u2.hp <= 0 or not u2.visible:
			continue
		if selection.has(u2) or not _on_screen(u2, cam, view_w, view_h):
			continue
		u2.selected = true
		selection.append(u2)
	selection_dirty = true
	return true


func _on_screen(u: EFUnit, cam: Camera3D, view_w: float, view_h: float) -> bool:
	var p := u.global_position + Vector3(0, 0.5, 0)
	if cam.is_position_behind(p):
		return false
	var sp := cam.unproject_position(p)
	return sp.x >= 0.0 and sp.x < view_w and sp.y >= 0.0 and sp.y < view_h


# --- orders ---------------------------------------------------------------------

func order_move(point: Vector3) -> void:
	var offs := _formation(selection.size(), _spread_pitch(selection))
	for i in range(selection.size()):
		var u := selection[i]
		u.clear_targets()
		_path_unit(u, Vector3(point.x + offs[i].x, 0, point.z + offs[i].y))
	_spawn_marker(point)


func _spread_pitch(list) -> float:
	# spacing for a loose move order, sized to the BIGGEST unit in the group so
	# a column of bastions is not handed destinations closer together than the
	# push-apart will tolerate
	var big := 0.0
	for u in list:
		if u is EFUnit and not u.flying:
			big = maxf(big, u.radius)
	return maxf(1.05, big * 2.0 + 0.45)


func _enemy_unit_near(point: Vector3, air_point: Vector3 = Vector3.INF) -> EFUnit:
	var best: EFUnit = null
	var best_d := 1.1
	for u in units:
		if not world.is_hostile(player_faction, u.faction) or u.hp <= 0 \
				or u.garrisoned_in >= 0 or not u.visible:
			continue
		var ref := point
		if u.flying and air_point != Vector3.INF:
			ref = air_point
		var d := Vector2(u.global_position.x - ref.x, u.global_position.z - ref.z).length()
		if d < u.radius + 0.5 and d < best_d:
			best_d = d
			best = u
	return best


func _own_transport_near(point: Vector3, air_point: Vector3) -> EFUnit:
	# a hovering Pelican sits at y ~= 3, not at ALT, so the click has to be
	# measured against the ground ray AND the high-altitude ray
	var best: EFUnit = null
	var best_d := 1e9
	for u in units:
		if u.faction != player_faction or u.hp <= 0 or u.kind != "pelican" \
				or u.garrisoned_in >= 0:
			continue
		if u.cargo_units.size() >= EFUnit.CARGO_SLOTS:
			continue
		var d := Vector2(u.global_position.x - point.x,
			u.global_position.z - point.z).length()
		if air_point != Vector3.INF:
			d = minf(d, Vector2(u.global_position.x - air_point.x,
				u.global_position.z - air_point.z).length())
		if d < u.radius + 0.6 and d < best_d:
			best_d = d
			best = u
	return best


func ray_point_at_y(screen_pos: Vector2, cam: Camera3D, y: float) -> Vector3:
	var origin := cam.project_ray_origin(screen_pos)
	var dirn := cam.project_ray_normal(screen_pos)
	if dirn.y > -0.0001:
		return Vector3.INF
	return origin + dirn * ((y - origin.y) / dirn.y)


func select_combat_player() -> void:
	clear_selection()
	for u in units:
		if u.faction == player_faction and not u.weapon.is_empty() and u.garrisoned_in < 0:
			u.selected = true
			selection.append(u)
	selection_dirty = true


func order_smart(point: Vector3, structs: EFStructures,
		air_point: Vector3 = Vector3.INF) -> void:
	# context-sensitive RMB: attack enemies, harvest fields, garrison ruins,
	# otherwise move in formation
	var tile := _cell_of(point)
	var ch := world.tile_char(tile.x, tile.y)
	var g_idx := structs.garrison_at(tile)

	# --- attack orders take priority ---
	var enemy_u := _enemy_unit_near(point, air_point)
	var b := buildings.building_at(tile)
	var enemy_b: int = buildings.cell_map.get(tile, -1) \
		if (not b.is_empty() and world.is_hostile(player_faction, b["faction"])
		and b["hp"] > 0) else -1
	var enemy_g := g_idx if (g_idx >= 0
		and not structs.garrisons[g_idx]["occupants"].is_empty()
		and world.is_hostile(player_faction,
			structs.garrisons[g_idx]["occupants"][0].faction)) else -1
	if enemy_u != null or enemy_b >= 0 or enemy_g >= 0:
		var escorts: Array[EFUnit] = []
		for u in selection:
			if u.is_harvester():
				continue
			var can := not u.weapon.is_empty()
			if can and enemy_u != null and not can_hurt(u.weapon["class"], enemy_u):
				can = false                 # cannons can't touch planes, etc.
			if not can:
				escorts.append(u)
				continue
			u.clear_targets()
			u.auto_tgt = false
			if enemy_u != null:
				u.tgt_unit = enemy_u
			elif enemy_b >= 0:
				u.tgt_building = enemy_b
			else:
				u.tgt_garrison = enemy_g
		var offs2 := _formation(escorts.size(), _spread_pitch(escorts))
		for i in range(escorts.size()):
			escorts[i].clear_targets()
			_path_unit(escorts[i], Vector3(point.x + offs2[i].x, 0, point.z + offs2[i].y))
		_spawn_marker(point)
		return

	# --- climb aboard: RMB your own Pelican with ground troops selected ---
	var lift := _own_transport_near(point, air_point)
	if lift != null:
		var free: int = EFUnit.CARGO_SLOTS - lift.cargo_units.size()
		var li := 0
		for u in selection:
			if free <= 0:
				break
			if u == lift or u.flying or u.is_harvester():
				continue
			u.clear_targets()
			u.garrison_target = -1
			u.load_target = lift
			path_single(u, Vector3(lift.global_position.x, 0,
				lift.global_position.z), li)
			li += 1
			free -= 1
		if li > 0:
			_spawn_marker(point)
			return

	var htile := nearest_field_tile(tile, 2)
	var movers: Array[EFUnit] = []
	var gi := 0
	for u in selection:
		u.clear_targets()
		# A deployed gun packs up when told to go somewhere. Without this the
		# ordinary quick right-click — by far the common case — would hand it a
		# path that step() throws away every frame, and it would sit there
		# looking broken with no hint that Z is the way out.
		if u.is_deployed():
			u.set_stance(EFUnit.MOBILE)
		if u.fort_ref >= 0:
			_drop_fort(u.fort_ref, false)
			u.stance = 0
		if u.is_harvester():
			if htile.x >= 0:
				u.force_harvest(htile, self)
			else:
				u.h_state = "hold"
				movers.append(u)
		elif u.is_infantry() and g_idx >= 0:
			u.garrison_target = g_idx
			var door: Vector2i = structs.garrisons[g_idx]["door"]
			path_single(u, Vector3((door.x + 0.5) * T, 0, (door.y + 0.5) * T), gi)
			gi += 1
		else:
			movers.append(u)
			if u.kind == "pelican" and not u.cargo_units.is_empty():
				u.unload_at = Vector3(point.x, 0, point.z)
	var offs := _formation(movers.size(), _spread_pitch(movers))
	for i in range(movers.size()):
		_path_unit(movers[i], Vector3(point.x + offs[i].x, 0, point.z + offs[i].y))
	_spawn_marker(point)


func stop_selected() -> void:
	for u in selection:
		u.path.clear()
		if u.flying:
			u.orbit_anchor = Vector3(u.global_position.x, 0, u.global_position.z)
		u.goal_cell = Vector2i(-1, -1)
		u.garrison_target = -1
		u.unload_at = Vector3.INF
		u.load_target = null
		u.clear_targets()
		if u.is_harvester():
			u.h_state = "hold"


# --- stance orders ----------------------------------------------------------------

func stance_summary() -> Array:
	# [options, current_name, mixed] for the sidebar; options empty = hide the row
	var opts: Array = []
	var cur := ""
	var mixed := false
	for u in selection:
		if u.hp <= 0:
			continue
		var o: Array = u.stance_options()
		if o.size() < 2:
			continue
		if opts.is_empty():
			opts = o
			cur = u.stance_name()
		elif o != opts:
			return [[], "", true]          # tanks and planes together: no row
		elif u.stance_name() != cur:
			mixed = true
	return [opts, cur, mixed]


func set_stance_selected(name: String) -> void:
	for u in selection:
		if u.hp <= 0:
			continue
		var o: Array = u.stance_options()
		var idx := o.find(name)
		if idx < 0 or idx == u.stance:
			continue
		if u.stance == 2 and u.fort_ref >= 0:
			_drop_fort(u.fort_ref, false)
		u.set_stance(idx)
		if idx == 2 and u.role == "inf":
			u.path.clear()
			_make_fort(u)
	selection_dirty = true


func cycle_stance_selected() -> void:
	var s := stance_summary()
	var opts: Array = s[0]
	if opts.size() < 2:
		return
	var cur: String = String(s[1])
	var i := opts.find(cur)
	set_stance_selected(String(opts[(i + 1) % opts.size()]))


func path_single(u: EFUnit, target: Vector3, idx: int = 0) -> void:
	var off := Vector2.ZERO
	if idx > 0:
		# spacing scaled to this unit's own size — the flat 0.9 packed AI tank
		# waves tighter than the push-apart allows, so they arrived jammed
		var r := maxf(0.9, u.radius * 2.0 + 0.45) * sqrt(float(idx))
		var a := float(idx) * 2.39996
		off = Vector2(cos(a) * r, sin(a) * r)
	_path_unit(u, Vector3(target.x + off.x, 0, target.z + off.y))


func block_cells(cells: Array) -> void:
	for c in cells:
		astar.set_point_solid(c, true)
	_refresh_wide_around(cells)


func unblock_cells(cells: Array) -> void:
	for c in cells:
		astar.set_point_solid(c, false)
	_refresh_wide_around(cells)


func mark(point: Vector3) -> void:
	_spawn_marker(point)


func _formation(n: int, pitch := 1.05) -> Array[Vector2]:
	# Golden-angle spiral: tight, roughly round, works for any count. `pitch` is
	# the nearest-neighbour spacing and MUST exceed _separate's min_d for the
	# units involved (radius_a + radius_b + 0.06), or every unit is shoved off
	# its own destination forever and the group grinds instead of arriving.
	var offs: Array[Vector2] = [Vector2.ZERO]
	for i in range(1, n):
		var r := pitch * sqrt(float(i))
		var a := float(i) * 2.39996
		offs.append(Vector2(cos(a) * r, sin(a) * r))
	return offs


# ============================ FORMATIONS ======================================
# A quick right-click marches the selection as a battle line; holding right-click
# opens the picker and the silhouette preview in main.gd. Flyers are excluded —
# they orbit rather than stand in ranks.

const SHAPES := ["LINE", "WEDGE", "COLUMN", "BOX"]


func _formation_pitch(list: Array[EFUnit]) -> float:
	# Must stay wider than _separate's worst min_d (2 * biggest radius + 0.06),
	# or the crowd push-apart fights the formation and scrambles it on arrival.
	var big := 0.0
	for u in list:
		big = maxf(big, u.radius)
	return big * 2.0 + 0.5


func _rank_of(u: EFUnit) -> int:
	# low rank = front of the formation. Test is_deployed(), never
	# stance == ARTILLERY: ARTILLERY is index 1 and so is infantry's LIGHT FEET,
	# so the raw comparison would banish light infantry to the rear.
	if u.is_deployed():
		return 5
	if u.is_harvester() or u.weapon.is_empty():
		return 5
	if u.armor == "HEAVY":
		return 0
	if u.role == "tank" or u.role == "smalltank":
		return 1
	if u.role == "scout":
		return 2
	var rng: float = u.weapon.get("range", 8.0)
	return 3 if rng <= 9.0 else 4


func _sort_for_formation(list: Array[EFUnit]) -> void:
	# the instance-id tiebreak is required: sort_custom is not stable in Godot,
	# so without it the previewed ghosts and the issued order can disagree
	list.sort_custom(func(a: EFUnit, b: EFUnit) -> bool:
		var ra := _rank_of(a)
		var rb := _rank_of(b)
		if ra != rb:
			return ra < rb
		return a.get_instance_id() < b.get_instance_id())


func formation_units() -> Array[EFUnit]:
	var out: Array[EFUnit] = []
	for u in selection:
		if u.hp > 0 and not u.flying and u.garrisoned_in < 0 and not u.stowed:
			out.append(u)
	_sort_for_formation(out)
	return out


func selection_centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in selection:
		if u.hp > 0:
			c += u.global_position
			n += 1
	return c / maxf(float(n), 1.0)


func formation_slots(list: Array[EFUnit], center: Vector3, facing: Vector2,
		shape: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := list.size()
	if n == 0:
		return out
	var fwd := facing.normalized() if facing.length() > 0.001 else Vector2(0, 1)
	var right := Vector2(-fwd.y, fwd.x)
	var pitch := _formation_pitch(list)
	var used := {}
	var per := 1
	match shape:
		"BOX":
			per = maxi(1, int(ceil(sqrt(float(n)))))
		"COLUMN":
			per = 2
		_:
			per = maxi(1, mini(n, int(ceil(sqrt(float(n)) * 2.0))))
	for i in range(n):
		var local := Vector2.ZERO
		if shape == "WEDGE":
			# i == 0 is the tip and stands alone; every pair after it steps one
			# rank back and one file out. Deriving the arm as i/2 put indices 0
			# and 1 on the same spot.
			if i > 0:
				var arm := (i + 1) / 2
				var side := 1 if i % 2 == 1 else -1
				local = right * (float(side * arm) * pitch * 0.7) \
					- fwd * (float(arm) * pitch * 0.6)
		else:
			var col := i % per
			var row := i / per
			local = right * ((float(col) - float(per - 1) * 0.5) * pitch) \
				- fwd * (float(row) * pitch)
		var p := center + Vector3(local.x, 0.0, local.y)
		if not world.clear_at(p.x, p.z, list[i].radius * 0.8):
			# _nearest_open is stateless, so several blocked slots sharing one
			# walkable neighbour would all snap to the same cell centre and the
			# units would pile up. Remember what has been handed out.
			var c := _nearest_open(_cell_of(p), list[i].radius > WIDE_MIN)
			if used.has(c):
				var found := false
				for ring in range(1, 5):
					for dy in range(-ring, ring + 1):
						for dx in range(-ring, ring + 1):
							if found or maxi(absi(dx), absi(dy)) != ring:
								continue
							var c2: Vector2i = c + Vector2i(dx, dy)
							if not used.has(c2) and world.is_walkable(c2.x, c2.y):
								c = c2
								found = true
					if found:
						break
			used[c] = true
			p = Vector3((c.x + 0.5) * T, 0.0, (c.y + 0.5) * T)
		out.append(p)
	return out


func order_formation(point: Vector3, facing: Vector2, shape: String) -> void:
	var list := formation_units()
	if list.is_empty():
		order_move(point)
		return
	var face := facing
	if face.length() < 0.5:
		var c := selection_centroid()
		face = Vector2(point.x - c.x, point.z - c.z)
	var slots := formation_slots(list, point, face, shape)
	for i in range(list.size()):
		var u: EFUnit = list[i]
		u.clear_targets()
		if u.is_deployed():
			u.set_stance(EFUnit.MOBILE)      # ordering a deployed gun packs it up
		if u.fort_ref >= 0:
			_drop_fort(u.fort_ref, false)    # and a dug-in soldier leaves his hole
		if u.is_harvester():
			# without this the harvester FSM keeps running and re-paths him off
			# the slot the moment he reaches it
			u.h_state = "hold"
		_path_unit(u, slots[i])
	# flyers still get the plain order so a mixed selection all responds
	for u2 in selection:
		if u2.flying and u2.hp > 0:
			u2.clear_targets()
			# match order_smart: a loaded transport drops here, and a stale drop
			# point must be cleared or _transport_tick hovers it forever
			if u2.kind == "pelican" and not u2.cargo_units.is_empty():
				u2.unload_at = Vector3(point.x, 0, point.z)
			else:
				u2.unload_at = Vector3.INF
			_path_unit(u2, point)
	_spawn_marker(point)


func _path_unit(u: EFUnit, target: Vector3) -> void:
	if u.flying:
		# planes ignore terrain: straight line out, lazy circles on arrival
		u.path = [Vector3(target.x, 0, target.z)]
		u.orbit_anchor = Vector3(target.x, 0, target.z)
		u.goal_cell = _cell_of(target)
		return
	var wide := u.radius > WIDE_MIN
	var from := _cell_of(u.global_position)
	var to := _nearest_open(_cell_of(target), wide)
	if from == to:
		# a ternary over two array literals is statically plain Array, which
		# cannot be assigned to path's Array[Vector3] — build it explicitly
		var direct: Array[Vector3] = []
		if world.clear_at(target.x, target.z, u.radius * 0.8):
			direct.append(Vector3(target.x, 0, target.z))
		u.path = direct
		u.goal_cell = to
		return
	var grid_a: AStarGrid2D = astar_wide if wide else astar
	var id_path := grid_a.get_id_path(from, to)
	if id_path.size() < 2 and wide:
		# no wide-safe corridor exists: rather than freeze, fall back to the
		# ordinary grid and let the crowd/slide logic do what it can
		id_path = astar.get_id_path(from, to)
	if id_path.size() < 2:
		# A* returns nothing when the unit is STANDING on a solid cell — wedged
		# under a building that went up on top of it, or shoved into rock. It
		# was then unpathable for the rest of the match: every future order
		# silently did nothing. Walk it to the nearest open cell so it can move
		# again, and it will re-path from there on the next order.
		# A wide unit counts as wedged whenever its own tile is illegal FOR IT,
		# which is how a Juggernaut jammed the moment it left the Doomworks.
		if not world.is_walkable(from.x, from.y) or (wide and not _open_for(from, true)):
			var esc := _nearest_open(from, wide)
			if esc != from:
				var out: Array[Vector3] = [
					Vector3((esc.x + 0.5) * T, 0, (esc.y + 0.5) * T)]
				u.path = out
				u.goal_cell = esc
				u.slot_point = out[0]
				u.repath_tries = 0
		return
	var pts: Array[Vector3] = []
	for c in id_path:
		pts.append(Vector3((c.x + 0.5) * T, 0, (c.y + 0.5) * T))
	pts[pts.size() - 1] = Vector3(
		(to.x + 0.5) * T, 0, (to.y + 0.5) * T)
	# greedy string-pull: from each anchor, keep the farthest visible waypoint
	var smoothed: Array[Vector3] = []
	var anchor := u.global_position
	var k := 1
	while k < pts.size():
		var far := k
		for j in range(k, pts.size()):
			if _line_clear(anchor, pts[j], u.radius * 0.8):
				far = j
			else:
				break
		smoothed.append(pts[far])
		anchor = pts[far]
		k = far + 1
	# The last waypoint above is the CENTRE of the destination tile, so every
	# formation slot inside one 2 m tile collapsed onto the same point and the
	# line bunched up. Finish on the exact requested spot when it is legal and
	# visible from the last waypoint.
	var exact := Vector3(target.x, 0, target.z)
	if world.clear_at(exact.x, exact.z, u.radius * 0.8):
		var last: Vector3 = smoothed[smoothed.size() - 1] if not smoothed.is_empty() \
			else u.global_position
		if _line_clear(last, exact, u.radius * 0.8):
			smoothed.append(exact)
	u.path = smoothed
	u.goal_cell = to
	u.slot_point = Vector3(target.x, 0, target.z)
	u.repath_tries = 0


func _line_clear(a: Vector3, b: Vector3, r: float) -> bool:
	var d := b - a
	d.y = 0.0
	var steps := int(d.length() / 0.5) + 1
	for i in range(1, steps + 1):
		var p := a + d * (float(i) / steps)
		if not world.clear_at(p.x, p.z, r):
			return false
	return true


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(p.x / T), 0, world.w - 1), clampi(int(p.z / T), 0, world.h - 1))


func _refresh_wide(c: Vector2i) -> void:
	if not world.in_bounds(c.x, c.y):
		return
	var ok := world.is_walkable(c.x, c.y) and world.clear_at(
		(c.x + 0.5) * T, (c.y + 0.5) * T, WIDE_R * 0.8)
	astar_wide.set_point_solid(c, not ok)


func _refresh_wide_around(cells: Array) -> void:
	# one newly solid tile invalidates all EIGHT of its neighbours for a wide
	# unit, so the whole 3x3 has to be re-tested
	for c in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_refresh_wide(c + Vector2i(dx, dy))


func _open_for(c: Vector2i, wide: bool) -> bool:
	if not world.is_walkable(c.x, c.y):
		return false
	return not wide or world.clear_at((c.x + 0.5) * T, (c.y + 0.5) * T, WIDE_R * 0.8)


func _nearest_open(cell: Vector2i, wide := false) -> Vector2i:
	cell = Vector2i(clampi(cell.x, 0, world.w - 1), clampi(cell.y, 0, world.h - 1))
	if _open_for(cell, wide):
		return cell
	for ring in range(1, 8):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := cell + Vector2i(dx, dy)
				if _open_for(c, wide):
					return c
	return cell


# --- crowd stall watchdog ----------------------------------------------------------
# The old watchdog keyed off stuck_time, which only accrues when TERRAIN blocks
# a unit. A unit jammed by its own side is never terrain-blocked: it is shoved
# off its destination, walks back, and is shoved again — covering no ground at
# all while believing it is en route. Measuring distance actually travelled
# catches that; measuring distance-to-goal would not, because a unit correctly
# routing around an obstacle moves away from its goal on purpose.

const STALL_WINDOW := 2.0          # seconds per measurement window
const STALL_MOVED := 0.5           # metres below which the window counts as stalled
const STALL_GIVE_UP := 3           # windows before the unit stands down


func _stall_watch(u: EFUnit, dt: float) -> void:
	if u.path.is_empty() or u.is_pinned() or u.flying:
		u.stall_t = 0.0
		u.stall_ref = Vector3.INF
		u.stall_count = 0
		return
	u.stall_t += dt
	if u.stall_t < STALL_WINDOW:
		return
	u.stall_t = 0.0
	if u.stall_ref == Vector3.INF:
		u.stall_ref = u.global_position
		return
	var moved := u.global_position.distance_to(u.stall_ref)
	u.stall_ref = u.global_position
	if moved >= STALL_MOVED:
		u.stall_count = 0
		return
	u.stall_count += 1
	_unstall(u)


func _unstall(u: EFUnit) -> void:
	if u.goal_cell.x < 0:
		return
	var goal: Vector3 = u.slot_point
	if goal == Vector3.INF:
		goal = Vector3((u.goal_cell.x + 0.5) * T, 0, (u.goal_cell.y + 0.5) * T)
	# Close enough: the destination is simply crowded. Take it as arrived rather
	# than shoving at the back of the pack forever — this is what a player means
	# by "move here" when twenty units share one point.
	if u.global_position.distance_to(goal) < u.radius * 2.0 + 2.5:
		_stand_down(u)
		return
	if u.stall_count >= STALL_GIVE_UP:
		_stand_down(u)
		return
	# One more try on a slightly different point, so a whole jammed column does
	# not re-target the identical spot and reproduce the pile it just escaped.
	_path_unit(u, goal + Vector3(randf_range(-1.6, 1.6), 0.0, randf_range(-1.6, 1.6)))


func _stand_down(u: EFUnit) -> void:
	u.path.clear()
	u.goal_cell = Vector2i(-1, -1)
	u.slot_point = Vector3.INF
	u.stall_count = 0
	u.stuck_time = 0.0


# --- crowd push-apart --------------------------------------------------------------

func _separate() -> void:
	for i in range(units.size()):
		var a := units[i]
		if a.garrisoned_in >= 0:
			continue
		for j in range(i + 1, units.size()):
			var b := units[j]
			if b.garrisoned_in >= 0:
				continue
			if a.flying != b.flying:
				continue
			var d := b.global_position - a.global_position
			d.y = 0.0
			var min_d := a.radius + b.radius + 0.06
			if a.role == "inf" and b.role == "inf":
				# a six-man section visually overflows its collision circle,
				# so squads packed at vehicle tolerances merged into one
				# penguin crowd. +0.24 keeps the WORST pair (two 0.36 radius
				# squads, 1.02 m) under the tightest formation pitch (1.05) —
				# above it, push-apart fights every formation on arrival.
				min_d += 0.24
			var l := d.length()
			if l < min_d and l > 0.001:
				var push := d.normalized() * (min_d - l) * 0.5
				# The unit that is GOING somewhere should hold its line; the one
				# parked in the way should yield. These weights were the other
				# way round, so a marching column shoved itself off its own
				# route three times harder than the obstacle it was passing.
				_try_shift(a, -push * (0.55 if not a.path.is_empty() else 1.25))
				_try_shift(b, push * (0.55 if not b.path.is_empty() else 1.25))


func _try_shift(u: EFUnit, delta: Vector3) -> void:
	# radius * 0.8 to match step()'s own legality test — at 0.7 separation could
	# wedge a unit into a spot step() then considered illegal, and it would be
	# stuck there relying on the unstick rule to crawl back out
	var np := u.global_position + delta
	if u.flying or world.clear_at(np.x, np.z, u.radius * 0.8) \
			or not world.clear_at(u.global_position.x, u.global_position.z, u.radius * 0.8):
		u.global_position = np


func nearest_field_tile(tile: Vector2i, r: int) -> Vector2i:
	# forgiving harvest targeting: the closest live ember tile within r
	if world.in_bounds(tile.x, tile.y) and world.tile_char(tile.x, tile.y) == "E" 			and economy.has_reserves(tile):
		return tile
	var best := Vector2i(-1, -1)
	var bd := 999
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := tile + Vector2i(dx, dy)
			if world.in_bounds(c.x, c.y) and world.tile_char(c.x, c.y) == "E" 					and economy.has_reserves(c):
				var d := absi(dx) + absi(dy)
				if d < bd:
					bd = d
					best = c
	return best


# --- shared ray helper + order markers ------------------------------------------------

func ground_point(screen_pos: Vector2, cam: Camera3D) -> Vector3:
	var origin := cam.project_ray_origin(screen_pos)
	var dirn := cam.project_ray_normal(screen_pos)
	if dirn.y > -0.0001:
		return Vector3.INF
	return origin + dirn * (-origin.y / dirn.y)


func _spawn_marker(point: Vector3) -> void:
	var ring := TorusMesh.new()
	ring.rings = 12
	ring.ring_segments = 8
	ring.inner_radius = 0.5
	ring.outer_radius = 0.62
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 1.0, 0.55)
	m.emission_enabled = true
	m.emission = Color(0.35, 1.0, 0.4)
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(point.x, 0.08, point.z)
	add_child(mi)
	_markers.append({"node": mi, "mat": m, "t": 0.0})


func _fade_markers(dt: float) -> void:
	for k in range(_markers.size() - 1, -1, -1):
		var mk: Dictionary = _markers[k]
		mk["t"] += dt
		var f: float = mk["t"] / 0.6
		if f >= 1.0:
			mk["node"].queue_free()
			_markers.remove_at(k)
		else:
			mk["node"].scale = Vector3.ONE * (1.0 + f * 0.9)
			mk["mat"].albedo_color.a = 1.0 - f


# --- Phase 11: the air bridge -------------------------------------------------------
# A passenger is removed from `units` while it rides, which is what keeps every
# other system (movement, combat, vision, selection, health bars) hands-off.
# MUST run after _combat's `for u in units` loop and iterate a duplicate: both
# _board and _disgorge mutate `units`.

func _transport_tick() -> void:
	var awaited := {}
	for u in units.duplicate():
		if u.load_target == null:
			continue
		var t: EFUnit = u.load_target
		if u.hp <= 0 or not is_instance_valid(t) or t.hp <= 0 \
				or t.cargo_units.size() >= EFUnit.CARGO_SLOTS:
			u.load_target = null
			continue
		var d := Vector2(t.global_position.x - u.global_position.x,
			t.global_position.z - u.global_position.z).length()
		if d < 2.2:
			_board(u, t)
			continue
		awaited[t] = true
		if u.path.is_empty():
			path_single(u, Vector3(t.global_position.x, 0, t.global_position.z), 0)
	for t in units.duplicate():
		if t.kind != "pelican" or t.hp <= 0:
			continue
		t.hovering = awaited.has(t) \
			or (t.unload_at != Vector3.INF and t.path.is_empty())
		if t.unload_at != Vector3.INF and t.path.is_empty() \
				and t.global_position.y < 4.5 \
				and Vector2(t.global_position.x - t.unload_at.x,
					t.global_position.z - t.unload_at.z).length() < 4.0:
			_disgorge(t, t.unload_at)
			t.unload_at = Vector3.INF


func _board(u: EFUnit, t: EFUnit) -> void:
	t.cargo_units.append(u)
	u.stowed = true
	u.load_target = null
	u.selected = false
	selection.erase(u)
	u.clear_targets()
	u.visible = false
	u.path.clear()
	u.vel = Vector3.ZERO
	u.goal_cell = Vector2i(-1, -1)
	units.erase(u)
	selection_dirty = true
	_puff(u.global_position + Vector3(0, 0.4, 0), Color(0.44, 0.41, 0.36), 0.45)


func _disgorge(t: EFUnit, point: Vector3) -> void:
	var cell := _nearest_open(_cell_of(point))
	var base := Vector3((cell.x + 0.5) * T, 0, (cell.y + 0.5) * T)
	var i := 0
	for u: EFUnit in t.cargo_units:
		u.stowed = false
		u.visible = true
		var a := float(i) * 2.39996
		var r := 0.75 * sqrt(float(i + 1))
		u.global_position = Vector3(base.x + cos(a) * r, 0.0, base.z + sin(a) * r)
		units.append(u)
		path_single(u, base, i)
		i += 1
	t.cargo_units.clear()
	selection_dirty = true
	if audio:
		audio.play("place", base, -6.0)


func _drown_cargo(t: EFUnit) -> void:
	# passengers are already out of `units` and `selection` — nothing to unwind
	for u: EFUnit in t.cargo_units:
		u.stowed = false
		u.hp = 0.0
		_puff(t.global_position + Vector3(0, 0.4, 0), Color(0.45, 0.42, 0.4), 0.7)
		_fx.append({"kind": "corpse", "node": u, "ttl": 3.0})
	t.cargo_units.clear()


# ================================ WAR ========================================
# Damage = weapon dmg x ARMOR_MULT (GAME_DESIGN.md §7). Units auto-fire at
# enemies in range but hold position; explicit RMB attack orders chase.
# Garrisoned infantry fire from the building (+2 m range) and are hit
# THROUGH it at GARRISON_DAMAGE_MULT. Gun turrets need grid power.

var _projs := []
var _fx := []


func _combat(dt: float) -> void:
	for u in units:
		if u.hp <= 0 or u.weapon.is_empty():
			continue
		u.cd = maxf(0.0, u.cd - dt)
		u.scan_t -= dt
		u.repath_t -= dt
		var garrisoned := u.garrisoned_in >= 0
		var origin := u.global_position + Vector3(0, 1.0, 0)
		var rng: float = u.weapon["range"] * u.range_mult()
		if garrisoned:
			origin = structures.garrisons[u.garrisoned_in]["center"] + Vector3(0, 1.7, 0)
			rng += 2.0
		if u.deploy_t > 0.0:
			continue                          # setting up or packing away: no gun

		# validate explicit targets
		if u.tgt_unit != null and (not is_instance_valid(u.tgt_unit)
				or u.tgt_unit.hp <= 0 or u.tgt_unit.garrisoned_in >= 0):
			u.tgt_unit = null
		if u.tgt_building >= 0 and buildings.list[u.tgt_building]["hp"] <= 0:
			u.tgt_building = -1
		if u.tgt_garrison >= 0 and structures.garrisons[u.tgt_garrison]["occupants"].is_empty():
			u.tgt_garrison = -1
		if u.tgt_unit != null and u.auto_tgt:
			# self-acquired targets are dropped when they flee, never chased.
			# A patrolling plane is stricter still: it shoots what happens to be
			# in range as it sweeps past and lets everything else go, so its
			# circuit — and the vision that comes with it — is never abandoned.
			var leash := Vector2(u.tgt_unit.global_position.x - origin.x,
				u.tgt_unit.global_position.z - origin.z).length()
			if leash > (rng if u.is_patrolling() else rng * 1.2):
				u.tgt_unit = null

		if u.tgt_unit != null:
			var aim: Vector3 = u.tgt_unit.global_position
			var d := Vector2(aim.x - origin.x, aim.z - origin.z).length()
			var los_ok: bool = u.flying or u.tgt_unit.flying or world.sight_clear(origin, aim + Vector3(0, 0.8, 0), 4.8 if garrisoned else 0.0, garrisoned)
			if d <= rng and los_ok:
				if not u.is_patrolling():
					u.path.clear()
				if u.flying and not u.is_patrolling():
					u.orbit_anchor = Vector3(aim.x, 0, aim.z)
				var t: EFUnit = u.tgt_unit
				var aim_pt: Vector3 = aim + Vector3(0, 0.6, 0) if not u.tgt_unit.flying else aim
				var punch: float = u.weapon["dmg"] * u.dmg_mult()
				_fire(u, origin, aim_pt, func():
					damage_unit(t, u.weapon["class"], punch)
					if u.weapon["class"] == "ARC":
						_arc_chain(u, t))
			elif not garrisoned and u.repath_t <= 0.0 and not u.is_pinned() \
					and not u.is_patrolling():
				u.repath_t = 0.8
				path_single(u, aim, 0)
		elif u.tgt_building >= 0:
			var b: Dictionary = buildings.list[u.tgt_building]
			var size: int = EFBuildings.DEFS[b["type"]]["size"]
			var aim2 := Vector3((b["origin"].x + size * 0.5) * T, 0.9,
				(b["origin"].y + size * 0.5) * T)
			var d2 := Vector2(aim2.x - origin.x, aim2.z - origin.z).length() - size * 0.9
			if d2 <= rng:
				u.path.clear()
				if u.flying:
					u.orbit_anchor = Vector3(aim2.x, 0, aim2.z)
				var bi: int = u.tgt_building
				_fire(u, origin, aim2,
					func(): buildings.take_damage(bi, u.weapon["class"], u.weapon["dmg"]))
			elif u.auto_tgt:
				u.tgt_building = -1         # self-picked structures aren't chased
			elif not garrisoned and u.repath_t <= 0.0:
				u.repath_t = 0.8
				path_single(u, aim2, 0)
		elif u.tgt_garrison >= 0:
			var g: Dictionary = structures.garrisons[u.tgt_garrison]
			var aim3: Vector3 = g["center"] + Vector3(0, 1.0, 0)
			var d3 := Vector2(aim3.x - origin.x, aim3.z - origin.z).length() - 1.2
			if d3 <= rng:
				u.path.clear()
				if u.flying:
					u.orbit_anchor = Vector3(aim3.x, 0, aim3.z)
				var gi: int = u.tgt_garrison
				_fire(u, origin, aim3,
					func(): structures.damage_garrison(gi, u.weapon["class"], u.weapon["dmg"], self))
			elif not garrisoned and u.repath_t <= 0.0:
				u.repath_t = 0.8
				path_single(u, aim3, 0)
		else:
			# no orders: hold ground, shoot what wanders into range
			if u.scan_t <= 0.0:
				u.scan_t = 0.25 + (u.get_instance_id() % 5) * 0.03
				u.tgt_unit = null
				var auto := _nearest_enemy(u.faction, origin, rng, u.weapon["class"],
					u.flying, false, 4.8 if garrisoned else 0.0, garrisoned)
				if auto != null:
					u.tgt_unit = auto
					u.auto_tgt = true
				elif u.path.is_empty() and (u.goal_cell.x < 0 or u.flying) \
						and _auto_building(u, origin, rng):
					pass                        # opened fire on a structure
				elif not garrisoned and u.path.is_empty() and u.goal_cell.x >= 0 \
						and not u.is_harvester():
					# the fight is over — finish the march we were on
					var gp := Vector3((u.goal_cell.x + 0.5) * T, 0,
						(u.goal_cell.y + 0.5) * T)
					if Vector2(gp.x - u.global_position.x,
							gp.z - u.global_position.z).length() > 4.0:
						path_single(u, gp, 0)
					else:
						u.goal_cell = Vector2i(-1, -1)
				elif u.faction != player_faction and not garrisoned and u.path.is_empty():
					# the Ashfall pickets defend their ground
					var intruder := _nearest_enemy(u.faction, origin, AGGRO_RANGE,
						u.weapon["class"], u.flying, false,
						4.8 if garrisoned else 0.0, garrisoned)
					if intruder != null:
						u.tgt_unit = intruder
						u.auto_tgt = true

	_turrets(dt)


func can_hurt(wclass: String, t: EFUnit) -> bool:
	return ARMOR_MULT[wclass][t.armor] > 0.0


# ============================ DIG IN =========================================
# A dug-in soldier throws up a sandbag ring: more reach, far better protection,
# and the ring soaks most of what comes at him. When the ring is gone he is out
# in the open again whether he likes it or not.

const FORT_HP := 420.0
const FORT_SOAK := 0.75          # share of each hit the sandbags take
var forts := []                  # {node, unit, hp, pos}


func _make_fort(u: EFUnit) -> void:
	if u.fort_ref >= 0:
		return
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.rings = 12
	tor.ring_segments = 8
	tor.inner_radius = 0.85
	tor.outer_radius = 1.35
	tor.rings = 10
	tor.ring_segments = 14
	ring.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.38, 0.28)
	mat.roughness = 1.0
	ring.material_override = mat
	ring.position = Vector3(u.global_position.x, 0.16, u.global_position.z)
	add_child(ring)
	forts.append({"node": ring, "unit": u, "hp": FORT_HP,
		"pos": ring.position})
	u.fort_ref = forts.size() - 1


func _drop_fort(idx: int, collapsed: bool) -> void:
	if idx < 0 or idx >= forts.size():
		return
	var f: Dictionary = forts[idx]
	if f.is_empty():
		return
	var u: EFUnit = f["unit"]
	if is_instance_valid(u) and u.fort_ref == idx:
		u.fort_ref = -1
		# Always leave DIG IN, not just on collapse. Being shoved out by the
		# crowd, teleported into a garrison or unloaded from a transport also
		# drops the hole, and leaving the stance set meant the unit displayed
		# DIG IN with none of its benefits and could never re-entrench.
		if u.stance == 2 and u.role == "inf":
			u.stance = 0
	if f["node"] != null and is_instance_valid(f["node"]):
		if collapsed:
			_puff(f["pos"] + Vector3(0, 0.4, 0), Color(0.5, 0.46, 0.36), 1.1)
		f["node"].queue_free()
	forts[idx] = {}                       # tombstone: indices must stay stable


func _fort_tick(_dt: float) -> void:
	for i in range(forts.size()):
		var f: Dictionary = forts[i]
		if f.is_empty():
			continue
		var u: EFUnit = f["unit"]
		if not is_instance_valid(u) or u.hp <= 0 or u.fort_ref != i:
			_drop_fort(i, false)
			continue
		# a soldier who walked away loses the hole he dug
		if Vector2(u.global_position.x - f["pos"].x,
				u.global_position.z - f["pos"].z).length() > 1.6:
			_drop_fort(i, false)


func _auto_building(u: EFUnit, origin: Vector3, rng: float) -> bool:
	# nothing living in range? shell whatever the enemy BUILT in range
	var best := -1
	var bd := rng
	for k in range(buildings.list.size()):
		var b: Dictionary = buildings.list[k]
		if not world.is_hostile(u.faction, b["faction"]) or b["hp"] <= 0:
			continue
		var size: int = EFBuildings.DEFS[b["type"]]["size"]
		var c := Vector3((b["origin"].x + size * 0.5) * T, 0,
			(b["origin"].y + size * 0.5) * T)
		var d := Vector2(c.x - origin.x, c.z - origin.z).length() - size * 0.9
		if d < bd:
			bd = d
			best = k
	if best < 0:
		return false
	u.tgt_building = best
	u.auto_tgt = true
	return true


func _nearest_enemy(fac: int, from: Vector3, rng: float, wclass := "",
		shooter_flying := false, air_only := false, origin_clear := 0.0,
		over_walls := false) -> EFUnit:
	var best: EFUnit = null
	var best_d := rng
	for t in units:
		if not world.is_hostile(fac, t.faction) or t.hp <= 0 or t.garrisoned_in >= 0:
			continue
		if air_only and not t.flying:
			continue
		if wclass != "" and not can_hurt(wclass, t):
			continue
		var d := Vector2(t.global_position.x - from.x, t.global_position.z - from.z).length()
		if d > best_d:
			continue
		if not (shooter_flying or t.flying) and not world.sight_clear(from, t.global_position + Vector3(0, 0.8, 0), origin_clear, over_walls):
			continue
		best_d = d
		best = t
	return best


func _turrets(dt: float) -> void:
	for bi in range(buildings.list.size()):
		var b: Dictionary = buildings.list[bi]
		var is_aa: bool = b["type"] == "aa_turret"
		# No head clause here: the head is a VISUAL. Gating combat on it is
		# what turned the building-model swap into every turret going silent.
		if (b["type"] != "gun_turret" and not is_aa) or b["hp"] <= 0:
			continue
		var wpn: Dictionary = AA_TURRET_WEAPON if is_aa else TURRET_WEAPON
		b["cd"] = maxf(0.0, b.get("cd", 0.0) - dt)
		if buildings.low_power(b["faction"]):
			b["tgt"] = null
			continue
		var origin: Vector3 = b["head"].global_position if b["head"] != null 			else b["node"].global_position + Vector3(0, 1.2, 0)
		var tgt: EFUnit = b.get("tgt")
		var lost: bool = tgt == null or not is_instance_valid(tgt) or tgt.hp <= 0 \
				or tgt.garrisoned_in >= 0 \
				or Vector2(tgt.global_position.x - origin.x,
					tgt.global_position.z - origin.z).length() > wpn["range"]
		if is_aa and not lost and not tgt.flying:
			# flak keeps one eye on the sky even while strafing the ground
			var winged := _nearest_enemy(b["faction"], origin, wpn["range"],
				wpn["class"], false, true, 1.9, true)
			if winged != null:
				tgt = winged
				b["tgt"] = tgt
		if lost:
			tgt = _nearest_enemy(b["faction"], origin, wpn["range"], wpn["class"],
				false, is_aa, 1.9, true)
			if is_aa and tgt == null:
				# no wings about: chip at ground targets rather than sit idle
				tgt = _nearest_enemy(b["faction"], origin, wpn["range"],
					wpn["class"], false, false, 1.9, true)
			b["tgt"] = tgt
		if tgt == null:
			continue
		var to: Vector3 = tgt.global_position - origin
		if b["head"] != null:
			b["head"].rotation.y = lerp_angle(b["head"].rotation.y,
				atan2(-to.x, -to.z) - b["node"].rotation.y, 6.0 * dt)
		if b["cd"] <= 0.0:
			b["cd"] = 1.0 / wpn["rof"]
			var t2: EFUnit = tgt
			var aim_pt: Vector3 = tgt.global_position + Vector3(0, 0.6, 0) 				if not tgt.flying else tgt.global_position
			if is_aa:
				_flak(origin, aim_pt)
				damage_unit(t2, wpn["class"], wpn["dmg"])
			else:
				_spawn_shell(origin, aim_pt,
					func(): damage_unit(t2, wpn["class"], wpn["dmg"]))
			_muzzle(origin + to.normalized() * 1.1, not is_aa)


# --- firing & projectiles -------------------------------------------------------

func _fire(u: EFUnit, origin: Vector3, aim: Vector3, apply: Callable) -> void:
	if u.cd > 0.0:
		return
	u.cd = 1.0 / u.weapon["rof"]
	if u.is_infantry():
		u.squad_fire_kick()      # the rifleman's shoulder, done in-shader
	# the gun kicks the hull: heavy shells rock a vehicle back on its
	# suspension, small arms barely stir it. Infantry and aircraft skip it.
	if not u.is_infantry() and not u.flying:
		match u.weapon["class"]:
			"CANNON", "BLAST":
				u.recoil_v = 0.11
			"ROCKET", "ARC":
				u.recoil_v = 0.06
			_:
				u.recoil_v = maxf(u.recoil_v, 0.025)
	match u.weapon["class"]:
		"BULLET":
			_tracer(origin, aim)
			if audio:
				audio.play("shot_bullet", origin, -8.0)
			apply.call()
		"CANNON":
			_spawn_shell(origin, aim, apply)
			_muzzle(origin + (aim - origin).normalized() * 1.2, true)
			_puff(origin + (aim - origin).normalized() * 1.4, Color(0.5, 0.48, 0.45), 0.5)
			if audio:
				audio.play("shot_cannon", origin, -3.0)
		"BLAST":
			_spawn_lob(origin, aim, apply)
			if audio:
				audio.play("shot_cannon", origin, -7.0)
		"FLAK":
			_flak(origin, aim)
			if audio:
				audio.play("shot_flak", origin, -7.0)
			apply.call()
		"ROCKET":
			_spawn_rocket(origin, aim, apply)
			if audio:
				audio.play("shot_rocket", origin, -6.0)
		"ARC":
			_arc_bolt(origin, aim)
			if audio:
				audio.play("arc_zap", origin, -5.0)
			apply.call()


func damage_unit(t: EFUnit, wclass: String, dmg: float) -> void:
	if not is_instance_valid(t) or t.hp <= 0:
		return
	t.since_hit = 0.0
	var amount: float = dmg * ARMOR_MULT[wclass][t.armor] * t.incoming_mult()
	if t.fort_ref >= 0 and t.fort_ref < forts.size():
		# the sandbags take the brunt; incoming_mult already softened the rest
		var f: Dictionary = forts[t.fort_ref]
		if not f.is_empty():
			f["hp"] = float(f["hp"]) - dmg * ARMOR_MULT[wclass][t.armor] * FORT_SOAK
			if f["hp"] <= 0.0:
				_drop_fort(t.fort_ref, true)
	if t.max_shield > 0.0 and t.shield > 0.0:
		var absorbed := minf(t.shield, amount)
		t.shield -= absorbed
		amount -= absorbed
		if absorbed > 1.0:
			_shield_blip(t.global_position + Vector3(0, t.body_height * 0.6, 0))
	t.hp -= amount
	if music != null:
		# every wound feeds the score's war layer; it decays on its own
		music.bump(0.05 if t.hp > 0.0 else 0.22)
	if t.hp <= 0.0:
		kill_unit(t, true)


func kill_unit(u: EFUnit, with_wreck: bool) -> void:
	if not u.cargo_units.is_empty():
		_drown_cargo(u)
	if with_wreck:
		if u.role == "inf":
			# a section is six men: one puff read as a single casualty
			var n_puff := maxi(u.squad_alive(), 1)
			for pi in range(mini(n_puff, 4)):
				var spread := Vector3(
					cos(float(pi) * 2.4) * 0.28, 0.5, sin(float(pi) * 2.4) * 0.28)
				_puff(u.global_position + spread, Color(0.45, 0.42, 0.4))
		else:
			_wreck(u)
	if u.faction == player_faction and audio:
		audio.announce("unit_lost")
	selection.erase(u)
	selection_dirty = true
	units.erase(u)
	# don't free immediately — in-flight shells may still hold a reference;
	# the corpse lingers hidden for a moment, then the fx sweeper frees it
	u.visible = false
	u.hp = 0.0
	_fx.append({"kind": "corpse", "node": u, "ttl": 3.0})


func _wreck(u: EFUnit) -> void:
	if audio:
		audio.play("expl_big", u.global_position, -2.0)
	if u.flying:
		_crash(u)
		return
	var hull := BoxMesh.new()
	hull.size = Vector3(u.radius * 2.0, 0.5, u.radius * 2.6)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.085, 0.08)
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = hull
	mi.material_override = m
	mi.position = u.global_position + Vector3(0, 0.25, 0)
	mi.rotation = u.rotation
	add_child(mi)
	wrecks.append({"node": mi, "pos": mi.position, "ttl": 30.0, "gone": false,
		"value": int(EFBuildings.TRAIN.get(u.kind, {}).get("cost", 250) * 0.4)})
	_puff(u.global_position + Vector3(0, 0.8, 0), Color(0.25, 0.22, 0.2))
	_boom(u.global_position + Vector3(0, 0.6, 0))


func _spawn_shell(from: Vector3, to: Vector3, apply: Callable) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.1
	mesh.height = 0.2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = from
	add_child(mi)
	var dur := from.distance_to(to) / 30.0
	_projs.append({"kind": "shell", "node": mi, "from": from, "to": to,
		"t": 0.0, "dur": maxf(0.12, dur), "apply": apply})


func _spawn_lob(from: Vector3, to: Vector3, apply: Callable) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.13
	mesh.height = 0.26
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.12, 0.08)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = from
	add_child(mi)
	_projs.append({"kind": "lob", "node": mi, "from": from, "to": to,
		"t": 0.0, "dur": 0.7, "apply": apply})


func _projectiles_tick(dt: float) -> void:
	for k in range(_projs.size() - 1, -1, -1):
		var p: Dictionary = _projs[k]
		p["t"] += dt
		var f: float = minf(p["t"] / p["dur"], 1.0)
		var pos: Vector3 = p["from"].lerp(p["to"], f)
		if p["kind"] == "lob":
			pos.y += 2.6 * sin(f * PI)
		else:
			if p["kind"] == "shell":
				pos.y += 0.5 * sin(f * PI)
		p["node"].position = pos
		if f >= 1.0:
			p["apply"].call()
			_boom(p["to"])
			p["node"].queue_free()
			_projs.remove_at(k)


# --- battle effects --------------------------------------------------------------

# Tracers were the hottest allocation in the game: a fresh BoxMesh, material
# and node per SHOT, for a streak that lives 0.07 s — hundreds a second in a
# big fight. One MultiMesh ring buffer now draws every tracer on the map in a
# single call. (The old material also asked an UNSHADED material for emission,
# which Godot drops — tracers never actually glowed. HDR instance colour does.)
const TRACER_POOL := 128

var _tracer_mm: MultiMeshInstance3D = null
var _tracers: Array = []
var _tracer_next := 0


func _ensure_tracer_pool() -> void:
	if _tracer_mm != null:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.045, 0.045, 1.0)   # unit length; scaled per instance
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = TRACER_POOL
	_tracer_mm = MultiMeshInstance3D.new()
	_tracer_mm.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	_tracer_mm.material_override = m
	_tracer_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracer_mm.custom_aabb = AABB(Vector3.ZERO,
		Vector3(world.w * T, 40.0, world.h * T))
	add_child(_tracer_mm)
	_tracers.resize(TRACER_POOL)
	for i in range(TRACER_POOL):
		_tracers[i] = {"live": false, "t": 0.0}
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -900, 0)))
		mm.set_instance_color(i, Color(0, 0, 0, 0))


func _tracer(from: Vector3, to: Vector3) -> void:
	_ensure_tracer_pool()
	var d := to - from
	var len := d.length()
	if len < 0.05:
		return
	var dir := d / len
	# a flak shot can be near-vertical, where UP is a degenerate look basis
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, len))
	var mm := _tracer_mm.multimesh
	var i := _tracer_next
	_tracer_next = (_tracer_next + 1) % TRACER_POOL
	var s: Dictionary = _tracers[i]
	s["live"] = true
	s["t"] = 0.0
	mm.set_instance_transform(i, Transform3D(basis, (from + to) * 0.5))
	# > 1.0 goes to the HDR buffer, so the streak finally catches the glow pass
	mm.set_instance_color(i, Color(2.2, 1.8, 0.85, 0.9))


func _tracer_tick(dt: float) -> void:
	if _tracer_mm == null:
		return
	var mm := _tracer_mm.multimesh
	for i in range(TRACER_POOL):
		var s: Dictionary = _tracers[i]
		if not bool(s["live"]):
			continue
		s["t"] = float(s["t"]) + dt
		var f: float = float(s["t"]) / 0.07
		if f >= 1.0:
			s["live"] = false
			mm.set_instance_color(i, Color(0, 0, 0, 0))
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -900, 0)))
			continue
		mm.set_instance_color(i, Color(2.2, 1.8, 0.85, 0.9 * (1.0 - f)))


func _muzzle(at: Vector3, with_light: bool) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.22
	mesh.height = 0.44
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.65, 0.2)
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	add_child(mi)
	_fx.append({"kind": "flash", "node": mi, "ttl": 0.08})
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.3)
		l.light_energy = 2.2
		l.omni_range = 6.0
		l.shadow_enabled = false
		l.position = at
		add_child(l)
		_fx.append({"kind": "flash", "node": l, "ttl": 0.09})


# Explosions, pooled like the smoke — and finally glowing. The old per-event
# material was UNSHADED with emission settings, and unshaded drops emission
# entirely, so no explosion in this war has ever actually bloomed. An HDR
# instance colour (values above 1.0) reaches the glow pass for real.
const BOOM_POOL := 48

var _boom_mm: MultiMeshInstance3D = null
var _booms: Array = []
var _boom_next := 0


func _ensure_boom_pool() -> void:
	if _boom_mm != null:
		return
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.4
	mesh.height = 0.8
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = BOOM_POOL
	_boom_mm = MultiMeshInstance3D.new()
	_boom_mm.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	_boom_mm.material_override = m
	_boom_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boom_mm.custom_aabb = AABB(Vector3.ZERO,
		Vector3(world.w * T, 40.0, world.h * T))
	add_child(_boom_mm)
	_booms.resize(BOOM_POOL)
	for i in range(BOOM_POOL):
		_booms[i] = {"live": false, "t": 0.0, "pos": Vector3.ZERO}
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -900, 0)))
		mm.set_instance_color(i, Color(0, 0, 0, 0))


func _boom(at: Vector3) -> void:
	if audio:
		audio.play("expl_small", at, -6.0)
	_ensure_boom_pool()
	var s: Dictionary = _booms[_boom_next]
	s["live"] = true
	s["t"] = 0.0
	s["pos"] = at
	_boom_next = (_boom_next + 1) % BOOM_POOL


func _boom_tick(dt: float) -> void:
	if _boom_mm == null:
		return
	var mm := _boom_mm.multimesh
	for i in range(BOOM_POOL):
		var s: Dictionary = _booms[i]
		if not bool(s["live"]):
			continue
		s["t"] = float(s["t"]) + dt
		var f: float = float(s["t"]) / 0.55
		if f >= 1.0:
			s["live"] = false
			mm.set_instance_color(i, Color(0, 0, 0, 0))
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -900, 0)))
			continue
		var sc := 1.0 + f * 2.6
		mm.set_instance_transform(i,
			Transform3D(Basis().scaled(Vector3(sc, sc, sc)), s["pos"]))
		# hot white-orange core cooling to ember as it swells and thins
		mm.set_instance_color(i, Color(3.0 - f * 1.6, 1.5 - f * 0.9,
			0.45 - f * 0.25, 0.85 * (1.0 - f)))


# Every puff used to allocate its own SphereMesh, its own StandardMaterial3D and
# its own MeshInstance3D — around 90 allocations a second in a busy fight, each
# one its own draw call. They now all live in a single MultiMesh ring buffer:
# one draw call for every puff of smoke on the map, and nothing allocated after
# the pool is built.
const PUFF_POOL := 256

var _puff_mm: MultiMeshInstance3D = null
var _puffs: Array = []          # ring slots: {t, life, pos, size, col, live}
var _puff_next := 0


func _ensure_puff_pool() -> void:
	if _puff_mm != null:
		return
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.5
	mesh.height = 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true            # per-puff colour AND fade ride the instance
	mm.mesh = mesh
	mm.instance_count = PUFF_POOL
	_puff_mm = MultiMeshInstance3D.new()
	_puff_mm.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true   # without this the instance colour is ignored
	_puff_mm.material_override = m
	_puff_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the pool spans the whole map, so never let Godot recompute it per frame
	_puff_mm.custom_aabb = AABB(Vector3.ZERO,
		Vector3(world.w * T, 40.0, world.h * T))
	add_child(_puff_mm)
	_puffs.resize(PUFF_POOL)
	for i in range(PUFF_POOL):
		_puffs[i] = {"live": false, "t": 0.0, "life": 0.9, "pos": Vector3.ZERO,
			"size": 1.0, "col": Color.WHITE}
		# park unused slots far below the map rather than at the origin
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -900, 0)))
		mm.set_instance_color(i, Color(1, 1, 1, 0))


func _puff(at: Vector3, col: Color, size := 1.0) -> void:
	_ensure_puff_pool()
	var slot: Dictionary = _puffs[_puff_next]
	slot["live"] = true
	slot["t"] = 0.0
	slot["life"] = 0.9
	slot["pos"] = at
	slot["size"] = size
	slot["col"] = col
	_puff_next = (_puff_next + 1) % PUFF_POOL


func _puff_tick(dt: float) -> void:
	if _puff_mm == null:
		return
	var mm := _puff_mm.multimesh
	for i in range(PUFF_POOL):
		var s: Dictionary = _puffs[i]
		if not bool(s["live"]):
			continue
		s["t"] = float(s["t"]) + dt
		var f: float = float(s["t"]) / float(s["life"])
		if f >= 1.0:
			s["live"] = false
			mm.set_instance_color(i, Color(1, 1, 1, 0))
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -900, 0)))
			continue
		var p: Vector3 = s["pos"]
		p.y += float(s["t"]) * 1.1            # smoke rises
		var sc: float = float(s["size"]) * (1.0 + f * 1.4)
		mm.set_instance_transform(i,
			Transform3D(Basis().scaled(Vector3(sc, sc, sc)), p))
		var c: Color = s["col"]
		mm.set_instance_color(i, Color(c.r, c.g, c.b, 0.5 * (1.0 - f)))


var _wound_t := 0.0
var _wound_i := 0


func _wound_smoke_tick(dt: float) -> void:
	# Wounded machines SHOW it: below ~55% hp a vehicle trails dark smoke,
	# badly hurt ones spit ember sparks; damaged buildings smoulder from the
	# roof. All of it rides the existing puff pool — zero allocations.
	_wound_t -= dt
	if _wound_t > 0.0:
		return
	_wound_t = 0.35
	_wound_i += 1
	var emitted := 0
	for k in range(units.size()):
		if emitted >= 6:
			break
		if (k + _wound_i) % 3 != 0:
			continue                    # stagger so smokers take turns
		var u := units[k]
		if u.hp <= 0 or u.is_infantry() or u.garrisoned_in >= 0 or u.stowed:
			continue
		var frac := u.hp / maxf(u.max_hp, 1.0)
		if frac >= 0.55:
			continue
		var at := u.global_position + Vector3(randf_range(-0.3, 0.3),
			0.9 if not u.flying else 0.2, randf_range(-0.3, 0.3))
		if frac < 0.28:
			_puff(at, Color(1.0, 0.45, 0.15), 0.5)   # sparks in the smoke
		_puff(at, Color(0.13, 0.12, 0.11), 0.7 + (0.55 - frac))
		emitted += 1
	for b in buildings.list:
		if emitted >= 9:
			break
		var bh: float = b["hp"]
		if bh <= 0:
			continue
		var bmax: float = float(EFBuildings.DEFS[b["type"]]["hp"])
		if bh / bmax >= 0.6:
			continue
		var o: Vector2i = b["origin"]
		var sz: int = int(EFBuildings.DEFS[b["type"]]["size"])
		if (o.x + o.y + _wound_i) % 2 != 0:
			continue
		_puff(Vector3((o.x + sz * 0.5) * T + randf_range(-0.8, 0.8),
			1.6 + sz * 0.5,
			(o.y + sz * 0.5) * T + randf_range(-0.8, 0.8)),
			Color(0.1, 0.09, 0.09), 1.0)
		emitted += 1


func _fx_tick(dt: float) -> void:
	_puff_tick(dt)
	_tracer_tick(dt)
	_boom_tick(dt)
	_wound_smoke_tick(dt)
	for k in range(_fx.size() - 1, -1, -1):
		var e: Dictionary = _fx[k]
		e["ttl"] -= dt
		if e["ttl"] <= 0.0:
			e["node"].queue_free()
			_fx.remove_at(k)
			continue
		match e["kind"]:
			"boom":
				var f: float = 1.0 - e["ttl"] / e["max"]
				e["node"].scale = Vector3.ONE * (1.0 + f * 2.6)
				e["mat"].albedo_color.a = 0.85 * (1.0 - f)
			"crash":
				e["vel"] += Vector3(0, -14.0, 0) * dt
				var cn: Node3D = e["node"]
				cn.global_position += e["vel"] * dt
				cn.rotate_x(3.2 * dt)
				cn.rotate_z(2.1 * dt)
				if cn.global_position.y <= 0.3:
					_boom(cn.global_position)
					_puff(cn.global_position, Color(0.3, 0.27, 0.24))
					cn.queue_free()
					_fx.remove_at(k)
			"wreck":
				if e["ttl"] < 2.0:
					e["node"].position.y -= dt * 0.35


# --- Phase 8: the Second Sun — arc lightning and shields ---------------------------

func shields_tick(dt: float) -> void:
	# Luminar shields drink the first blow and refill near the powered grid
	for u in units:
		if u.max_shield <= 0.0 or u.hp <= 0 or u.shield >= u.max_shield:
			continue
		if buildings.low_power(u.faction):
			continue
		var near := false
		for b in buildings.list:
			if b["faction"] != u.faction or b["hp"] <= 0:
				continue
			var size: int = EFBuildings.DEFS[b["type"]]["size"]
			var c := Vector3((b["origin"].x + size * 0.5) * T, 0,
				(b["origin"].y + size * 0.5) * T)
			if Vector2(c.x - u.global_position.x, c.z - u.global_position.z).length() < 16.0:
				near = true
				break
		if not near:
			# a Dynamo Wagon is a rolling piece of the grid
			for d in units:
				if d.kind == "dynamo" and d.faction == u.faction and d.hp > 0 and d != u \
						and Vector2(d.global_position.x - u.global_position.x,
							d.global_position.z - u.global_position.z).length() < 10.0:
					near = true
					break
		if near:
			u.shield = minf(u.max_shield, u.shield + 5.0 * dt)


func _arc_chain(shooter: EFUnit, primary: EFUnit) -> void:
	# lightning loves a crowd: leaps to up to 2 more enemies for 50% / 25%
	if not is_instance_valid(primary):
		return
	var from_pos: Vector3 = primary.global_position + Vector3(0, 0.8, 0)
	var candidates := []
	for t in units:
		if t == primary or not world.is_hostile(shooter.faction, t.faction) \
				or t.hp <= 0 or t.garrisoned_in >= 0 or t.flying != primary.flying:
			continue
		var d := Vector2(t.global_position.x - from_pos.x,
			t.global_position.z - from_pos.z).length()
		if d <= 4.0:
			candidates.append([d, t])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var mults := [0.5, 0.25]
	for i in range(mini(2, candidates.size())):
		var victim: EFUnit = candidates[i][1]
		_arc_bolt(from_pos, victim.global_position + Vector3(0, 0.8, 0))
		damage_unit(victim, "ARC", shooter.weapon["dmg"] * mults[i])


func _arc_bolt(from: Vector3, to: Vector3) -> void:
	# a jittered violet lightning stroke, three segments of glowing wire
	var prev := from
	var seg := (to - from) / 3.0
	for i in range(3):
		var nxt := from + seg * (i + 1)
		if i < 2:
			nxt += Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3),
				randf_range(-0.5, 0.5))
		var d := nxt - prev
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, 0.06, maxf(0.1, d.length()))
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.75, 0.6, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.62, 0.45, 1.0)
		m.emission_energy_multiplier = 3.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = (prev + nxt) * 0.5
		if d.length() > 0.05:
			mi.look_at(nxt, Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.FORWARD)
		_fx.append({"kind": "flash", "node": mi, "ttl": 0.09})
		prev = nxt


func _shield_blip(at: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.5
	mesh.height = 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.5, 1.0, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	add_child(mi)
	_fx.append({"kind": "flash", "node": mi, "ttl": 0.1})


# --- Phase 6 ordnance: flak bursts, rockets, falling planes ------------------------

func _flak(from: Vector3, to: Vector3) -> void:
	_tracer(from, to)
	_puff(to, Color(0.22, 0.2, 0.19))


func _spawn_rocket(from: Vector3, to: Vector3, apply: Callable) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 3
	mesh.radius = 0.07
	mesh.height = 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.22, 0.2)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.25)
	m.emission_energy_multiplier = 1.6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	if from.distance_to(to) > 0.1:
		mi.look_at(to, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2)
	var dur := from.distance_to(to) / 45.0
	_projs.append({"kind": "rocket", "node": mi, "from": from, "to": to,
		"t": 0.0, "dur": maxf(0.1, dur), "apply": apply})


func _crash(u: EFUnit) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 0.3, 2.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.09, 0.09)
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	add_child(mi)
	mi.global_position = u.global_position
	mi.rotation = u.rotation
	var fwd: Vector3 = -u.global_transform.basis.z
	_fx.append({"kind": "crash", "node": mi,
		"vel": Vector3(fwd.x, 0, fwd.z).normalized() * 7.0 + Vector3(0, 1.5, 0),
		"ttl": 3.0})
	_puff(u.global_position, Color(0.2, 0.18, 0.16))


# --- Phase 10: the player's eyes lift the veil --------------------------------------

var _reveal_t := 0.0


func _reveal_tick(dt: float) -> void:
	_reveal_t -= dt
	if _reveal_t > 0.0:
		return
	_reveal_t = 0.3
	world.begin_vision()
	# allies share vision: the player sees through their ally's eyes in 2v2
	for u in units:
		if u.hp <= 0 or (u.faction != player_faction
				and not world.is_ally(player_faction, u.faction)):
			continue
		var cell := Vector2i(int(u.global_position.x / T), int(u.global_position.z / T))
		# aircraft are the scouts of this war — from cruising altitude they see
		# a great deal further than a rifleman on the ash
		world.mark_visible(cell, 22 if u.flying else 10)
	for b in buildings.list:
		if b["hp"] > 0 and (b["faction"] == player_faction
				or world.is_ally(player_faction, b["faction"])):
			# a command post is a watchtower, a signals mast and a garrison:
			# it should light up its whole neighbourhood, not just its yard
			world.mark_visible(b["origin"],
				18 if b["type"] == "command_post" else 9)
	world.end_vision()
	# what the fog holds, the fog hides — but never an ally
	for u in units:
		if world.is_hostile(player_faction, u.faction):
			u.visible = u.hp > 0 and u.garrisoned_in < 0 and world.tile_visible(
				int(u.global_position.x / T), int(u.global_position.z / T))
		elif u.faction != player_faction:
			u.visible = u.hp > 0 and u.garrisoned_in < 0


var _heal_t := 0.0


func _heal_tick(dt: float) -> void:
	for u in units:
		u.since_hit += dt
	_heal_t -= dt
	if _heal_t > 0.0:
		return
	_heal_t = 0.5
	# A faction can hold up to three posts now, so this keeps a LIST per side.
	# Keying a dictionary by faction meant later posts overwrote earlier ones
	# and only one base in the empire could heal anybody.
	var hq := {}
	for b in buildings.list:
		if b["type"] == "command_post" and b["hp"] > 0:
			var fkey: int = b["faction"]
			if not hq.has(fkey):
				hq[fkey] = []
			hq[fkey].append(Vector3((b["origin"].x + 1.5) * T, 0,
				(b["origin"].y + 1.5) * T))
	for u in units:
		if u.hp <= 0 or u.hp >= u.max_hp or u.since_hit < 8.0 or u.garrisoned_in >= 0:
			continue
		var homes: Array = hq.get(u.faction, [])
		for home in homes:
			if Vector2(home.x - u.global_position.x,
					home.z - u.global_position.z).length() < 24.0:
				u.hp = minf(u.max_hp, u.hp + 1.0)   # 2 hp/s of quiet field medicine
				break


# --- Phase 9: salvage, wrecks with value, and the superweapons ----------------------

signal superweapon_launched(fac: int, pos: Vector3)
signal superweapon_impact(pos: Vector3)

var wrecks := []
var _sw_strikes := []


func restore_wreck(pos: Vector3, value: int, ttl: float) -> void:
	var hull := BoxMesh.new()
	hull.size = Vector3(1.4, 0.5, 1.8)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.085, 0.08)
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = hull
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	wrecks.append({"node": mi, "pos": pos, "ttl": ttl, "gone": false, "value": value})


func wreck_near(point: Vector3) -> Dictionary:
	for w in wrecks:
		if w["gone"]:
			continue
		if Vector2(w["pos"].x - point.x, w["pos"].z - point.z).length() < 1.8:
			return w
	return {}


func _salvage_tick(dt: float) -> void:
	for u in units:
		if u.kind != "vulture" or u.hp <= 0 or u.garrisoned_in >= 0:
			continue
		if not u.salv_ref.is_empty():
			var w: Dictionary = u.salv_ref
			if w.get("gone", false):
				u.salv_ref = {}
				continue
			var d := Vector2(w["pos"].x - u.global_position.x,
				w["pos"].z - u.global_position.z).length()
			if d < 2.0:
				u.path.clear()
				u.salv_t += dt
				if fmod(u.salv_t, 0.6) < dt:
					_tracer(u.global_position + Vector3(0, 0.8, 0),
						w["pos"] + Vector3(0, 0.5, 0))
				if u.salv_t >= 3.0:
					economy.credits[u.faction] = \
						economy.credits.get(u.faction, 0) + w["value"]
					if audio and u.faction == player_faction:
						audio.play("salvage", w["pos"], -4.0)
					_puff(w["pos"] + Vector3(0, 0.6, 0), Color(0.4, 0.75, 0.35))
					_consume_wreck(w)
					u.salv_ref = {}
			elif u.path.is_empty() and u.repath_t <= 0.0:
				u.repath_t = 0.8
				path_single(u, w["pos"], 0)
			u.repath_t -= dt
		else:
			# idle crews sniff out the nearest wreck on their own
			u.scan_t -= dt
			if u.scan_t <= 0.0:
				u.scan_t = 0.5
				var best := {}
				var bd := 26.0
				for w2 in wrecks:
					if w2["gone"]:
						continue
					var d2 := Vector2(w2["pos"].x - u.global_position.x,
						w2["pos"].z - u.global_position.z).length()
					if d2 < bd:
						bd = d2
						best = w2
				if not best.is_empty():
					u.salv_ref = best
					u.salv_t = 0.0


func _consume_wreck(w: Dictionary) -> void:
	w["gone"] = true
	if is_instance_valid(w["node"]):
		w["node"].queue_free()
	wrecks.erase(w)


func _wrecks_tick(dt: float) -> void:
	for k in range(wrecks.size() - 1, -1, -1):
		var w: Dictionary = wrecks[k]
		w["ttl"] -= dt
		if w["ttl"] <= 0.0:
			_consume_wreck(w)
		elif w["ttl"] < 2.0 and is_instance_valid(w["node"]):
			w["node"].position.y -= dt * 0.35


func superweapon_strike(fac: int, pos: Vector3) -> void:
	superweapon_launched.emit(fac, pos)
	var ring := TorusMesh.new()
	ring.rings = 12
	ring.ring_segments = 8
	ring.inner_radius = 8.4
	ring.outer_radius = 9.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.2, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.15, 0.1)
	m.emission_energy_multiplier = 2.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(pos.x, 12.4, pos.z)   # above the shroud: all must see it
	add_child(mi)
	if audio:
		audio.play_ui("sw_klaxon", -2.0)
		audio.announce("sw_launch", true)
	_sw_strikes.append({"pos": pos, "t": 4.0, "ring": mi, "mat": m})


func _sw_tick(dt: float) -> void:
	for k in range(_sw_strikes.size() - 1, -1, -1):
		var s: Dictionary = _sw_strikes[k]
		s["t"] -= dt
		if is_instance_valid(s["ring"]):
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.02)
			s["mat"].albedo_color.a = pulse
		if s["t"] > 0.0:
			continue
		var pos: Vector3 = s["pos"]
		if is_instance_valid(s["ring"]):
			s["ring"].queue_free()
		_sw_strikes.remove_at(k)
		# the blow lands
		superweapon_impact.emit(pos)
		if audio:
			audio.play_ui("sw_boom", 2.0)
		_boom(pos + Vector3(0, 1.0, 0))
		for i in range(7):
			var off := Vector3(randf_range(-6.0, 6.0), randf_range(0.4, 1.6),
				randf_range(-6.0, 6.0))
			_boom(pos + off)
			_puff(pos + off, Color(0.3, 0.26, 0.22))
		var scorch := MeshInstance3D.new()
		var smesh := CylinderMesh.new()
		smesh.top_radius = 7.0
		smesh.bottom_radius = 7.0
		smesh.height = 0.06
		scorch.mesh = smesh
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.06, 0.055, 0.05)
		sm.roughness = 1.0
		scorch.material_override = sm
		scorch.position = Vector3(pos.x, 0.05, pos.z)
		add_child(scorch)
		for u in units.duplicate():
			if u.hp <= 0 or u.garrisoned_in >= 0:
				continue
			var d := Vector2(u.global_position.x - pos.x,
				u.global_position.z - pos.z).length()
			if d <= 9.0:
				damage_unit(u, "BLAST", 320.0 * (1.0 - d / 14.0))
		for bi in range(buildings.list.size()):
			var b: Dictionary = buildings.list[bi]
			if b["hp"] <= 0:
				continue
			var size: int = EFBuildings.DEFS[b["type"]]["size"]
			var c := Vector3((b["origin"].x + size * 0.5) * T, 0,
				(b["origin"].y + size * 0.5) * T)
			if Vector2(c.x - pos.x, c.z - pos.z).length() <= 9.5:
				buildings.take_damage(bi, "BLAST", 380.0)

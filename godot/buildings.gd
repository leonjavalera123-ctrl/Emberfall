# EMBERFALL: 1940 — buildings.gd
# Base construction (GAME_DESIGN.md §6/§9): the tech tree, RA-style build
# queues that drain credits over time, the power grid, placement rules
# (buildable ground, nothing standing there, within 4 tiles of your base),
# walls that link up, turrets, and unit training from your buildings.

class_name EFBuildings
extends Node3D

const T := 2.0
const BUILD_RATE := 100.0          # credits/second at full power
const LOW_POWER_MULT := 0.5
const ADJACENCY := 4               # max tiles from an existing friendly building

const DEFS := {
	"command_post": {"name": "Command Post", "cost": 0, "size": 3, "power": 50,
		"hp": 1800, "prereq": [], "tile": "C"},
	"boiler": {"name": "Boiler House", "cost": 300, "size": 2, "power": 100,
		"hp": 600, "prereq": [], "tile": "C"},
	"refinery": {"name": "Refinery", "cost": 1200, "size": 3, "power": -25,
		"hp": 900, "prereq": ["boiler"], "tile": "R", "free_unit": true},
	"barracks": {"name": "Barracks", "cost": 400, "size": 2, "power": -15,
		"hp": 700, "prereq": ["boiler"], "tile": "C"},
	"vehicle_works": {"name": "Vehicle Works", "cost": 1000, "size": 3, "power": -30,
		"hp": 1000, "prereq": ["refinery"], "tile": "C"},
	"airfield": {"name": "Airfield", "cost": 800, "size": 3, "power": -25,
		"hp": 800, "prereq": ["vehicle_works"], "tile": "C"},
	"doomworks": {"name": "Doomworks", "cost": 2500, "size": 3, "power": -50,
		"hp": 1000, "prereq": ["vehicle_works"], "tile": "C"},
	"gun_turret": {"name": "Gun Turret", "cost": 500, "size": 1, "power": -15,
		"hp": 500, "prereq": ["barracks"], "tile": "C"},
	"aa_turret": {"name": "AA Turret", "cost": 500, "size": 1, "power": -15,
		"hp": 450, "prereq": ["vehicle_works"], "tile": "C"},
	"wall": {"name": "Iron Wall", "cost": 50, "size": 1, "power": 0,
		"hp": 350, "prereq": ["barracks"], "tile": "W", "instant": true},
}

const TRAIN := {
	"iron_guard": {"cost": 100, "from": "barracks"},
	"grenadier": {"cost": 350, "from": "barracks"},
	"outrider": {"cost": 350, "from": "vehicle_works"},
	"bastion": {"cost": 700, "from": "vehicle_works"},
	"sperrwagen": {"cost": 575, "from": "vehicle_works"},
	"mule": {"cost": 800, "from": "refinery"},
	"kondor": {"cost": 1050, "from": "airfield"},
	"conscript": {"cost": 70, "from": "barracks"},
	"sapper": {"cost": 250, "from": "barracks"},
	"rat": {"cost": 250, "from": "vehicle_works"},
	"warpig": {"cost": 500, "from": "vehicle_works"},
	"stovepipe": {"cost": 350, "from": "vehicle_works"},
	"magpie": {"cost": 560, "from": "refinery"},
	"duster": {"cost": 630, "from": "airfield"},
	"sky_marine": {"cost": 100, "from": "barracks"},
	"rocketeer": {"cost": 300, "from": "barracks"},
	"dart": {"cost": 350, "from": "vehicle_works"},
	"pavise": {"cost": 650, "from": "vehicle_works"},
	"zephyr": {"cost": 500, "from": "vehicle_works"},
	"dray": {"cost": 800, "from": "refinery"},
	"sparrowhawk": {"cost": 720, "from": "airfield"},
	"pelican": {"cost": 900, "from": "airfield"},
	"arc_templar": {"cost": 150, "from": "barracks"},
	"lance_warden": {"cost": 450, "from": "barracks"},
	"glimmer": {"cost": 520, "from": "vehicle_works"},
	"faraday": {"cost": 1050, "from": "vehicle_works"},
	"ion_carriage": {"cost": 750, "from": "vehicle_works"},
	"collector": {"cost": 1200, "from": "refinery"},
	"forge_crawler": {"cost": 2500, "from": "vehicle_works"},
	"scrap_hauler": {"cost": 2300, "from": "vehicle_works"},
	"keelwright": {"cost": 2400, "from": "vehicle_works"},
	"ark_carriage": {"cost": 2600, "from": "vehicle_works"},
	"seraph": {"cost": 1350, "from": "airfield"},
	"hammerfall": {"cost": 900, "from": "vehicle_works"},
	"wasp": {"cost": 450, "from": "airfield"},
	"vulture": {"cost": 200, "from": "barracks"},
	"dynamo": {"cost": 600, "from": "vehicle_works"},
	"juggernaut": {"cost": 3200, "from": "doomworks"},
	"ashworm": {"cost": 2100, "from": "doomworks"},
	"leviathan": {"cost": 2800, "from": "doomworks"},
	"cathedral": {"cost": 3800, "from": "doomworks"},
}

const TABS := {
	"BASE": ["boiler", "refinery", "barracks", "vehicle_works", "airfield",
		"gun_turret", "aa_turret", "wall", "doomworks"],
	"INF": [], "VEH": [], "AIR": [],   # filled per faction via tab_items()
}

const FACTION_TABS := {
	1: {"INF": ["iron_guard", "grenadier"],
		"VEH": ["outrider", "bastion", "sperrwagen", "hammerfall", "mule",
			"forge_crawler", "juggernaut"],
		"AIR": ["kondor"]},
	2: {"INF": ["conscript", "sapper", "vulture"],
		"VEH": ["rat", "warpig", "stovepipe", "magpie", "scrap_hauler", "ashworm"],
		"AIR": ["duster"]},
	3: {"INF": ["sky_marine", "rocketeer"],
		"VEH": ["dart", "pavise", "zephyr", "dray", "keelwright"],
		"AIR": ["sparrowhawk", "pelican", "wasp", "leviathan"]},
	4: {"INF": ["arc_templar", "lance_warden"],
		"VEH": ["glimmer", "faraday", "ion_carriage", "dynamo", "collector",
			"ark_carriage"],
		"AIR": ["seraph", "cathedral"]},
}

var player_faction := 1


func tab_items(tab: String) -> Array:
	if tab == "BASE":
		return TABS["BASE"]
	return FACTION_TABS[player_faction][tab]

signal placed(cells: Array)

# Why the last build-tab click did nothing: {"kind": "prereq"|"cost", "text": ...}.
# Written by note_denied / _note_if_short, read and cleared by campaign.gd's
# hints. Empty means the last click was accepted.
var last_deny := {}

const SW_TIME := 180.0
const SW_NAMES := {1: "WORLDHAMMER", 2: "THE UNDERMINE", 3: "TEMPEST PROTOCOL",
	4: "SECOND SUN"}
var sw_charge := {}
var sw_targeting := false


func sw_name(fac: int) -> String:
	return SW_NAMES.get(fac, "SUPERWEAPON")


func display_name(type: String, fac: int) -> String:
	if type == "doomworks":
		return sw_name(fac).capitalize() + " Works"
	return String(DEFS[type]["name"])


func sw_ready(fac: int) -> bool:
	return sw_charge.get(fac, 0.0) >= SW_TIME


func fire_superweapon(fac: int, pos: Vector3) -> void:
	if not sw_ready(fac) or not _owns(fac, "doomworks"):
		return
	sw_charge[fac] = 0.0
	sw_targeting = false
	army.superweapon_strike(fac, pos)

var world: EFWorld
var army: EFArmy
var audio: EFAudio
var music: EFMusic
var economy: EFEconomy
var list := []                     # {type, faction, origin, cells, node, hp, head}
var cell_map := {}                 # Vector2i -> index into list
var queues := {"BASE": null, "INF": null, "VEH": null, "AIR": null}
var backlog := {"INF": [], "VEH": [], "AIR": []}   # units queued beyond the active build
var pending_place := ""            # a READY building waiting for the player's ghost
var _wall_nodes := {}              # Vector2i -> wall visual (for reconnecting)
var _growing := []                 # construction pop-up animations
var _pay_frac := 0.0               # fractional credits owed (credits stay ints)
var repairing := {}                # building idx -> true while under repair
var _repair_frac := 0.0


func setup(w: EFWorld, a: EFArmy, eco: EFEconomy) -> void:
	world = w
	army = a
	economy = eco


# ============================ THE START BASE ==================================

func register_start_base(faction: int, start: Vector2i) -> void:
	# the HQ visual already exists in world.gd — register its footprint
	var hq_cells: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			hq_cells.append(start + Vector2i(dx, dy))
	_register("command_post", faction, start + Vector2i(-1, -1), hq_cells, null)
	world.set_runtime_tile(hq_cells, "C")
	army.block_cells(hq_cells)
	# every commander starts with a refinery + its free harvester
	var origin := _find_start_refinery_spot(start)
	_create("refinery", faction, origin)


func _find_start_refinery_spot(start: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for dy in range(-9, 10):
		for dx in range(-9, 10):
			candidates.append(Vector2i(dx, dy))
	candidates.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	for off in candidates:
		var tl: Vector2i = start + off + Vector2i(2, -1)
		if absi(tl.x - start.x) < 3 and absi(tl.y - start.y) < 3:
			continue
		var ok := true
		for dy in range(3):
			for dx in range(3):
				if not world.is_buildable(tl.x + dx, tl.y + dy):
					ok = false
					break
			if not ok:
				break
		if ok and world.is_walkable(tl.x + 1, tl.y + 3):
			return tl
	return start + Vector2i(4, 0)


func best_refinery(fac: int) -> int:
	# the refinery with the fewest bound harvesters gets the new one
	var best := -1
	var best_n := 9999
	for k in range(list.size()):
		var b: Dictionary = list[k]
		if b["type"] != "refinery" or b["faction"] != fac or b["hp"] <= 0:
			continue
		var n := 0
		for u in army.units:
			if u.is_harvester() and u.home_refinery == k and u.hp > 0:
				n += 1
		if n < best_n:
			best_n = n
			best = k
	return best


func dock_for(u: EFUnit) -> Vector3:
	# a harvester serves ITS refinery; if it's gone, adopt the nearest one
	if u.home_refinery >= 0 and u.home_refinery < list.size():
		var b: Dictionary = list[u.home_refinery]
		if b["type"] == "refinery" and b["faction"] == u.faction and b["hp"] > 0:
			return _dock_of(b)
	var best := -1
	var bd := 1e18
	for k in range(list.size()):
		var b2: Dictionary = list[k]
		if b2["type"] != "refinery" or b2["faction"] != u.faction or b2["hp"] <= 0:
			continue
		var d := _dock_of(b2).distance_squared_to(u.global_position)
		if d < bd:
			bd = d
			best = k
	if best >= 0:
		u.home_refinery = best
		return _dock_of(list[best])
	return Vector3.INF


func _dock_of(b: Dictionary) -> Vector3:
	var o: Vector2i = b["origin"]
	return Vector3((o.x + 1.5) * T, 0, (o.y + 3.5) * T)


func refinery_dock(faction: int) -> Vector3:
	for b in list:
		if b["type"] == "refinery" and b["faction"] == faction and b["hp"] > 0:
			var o: Vector2i = b["origin"]
			return Vector3((o.x + 1.5) * T, 0, (o.y + 3.5) * T)
	return Vector3.INF


# ============================ POWER ==========================================

func power_report(faction: int) -> Vector2i:
	# x = generated, y = consumed
	var gen := 0
	var use := 0
	for b in list:
		if b["faction"] != faction or b["hp"] <= 0:
			continue
		var p: int = DEFS[b["type"]]["power"]
		if p > 0:
			gen += p
		else:
			use += -p
	return Vector2i(gen, use)


func low_power(faction: int) -> bool:
	var p := power_report(faction)
	return p.y > p.x


# ============================ BUILD QUEUES ====================================

func click_item(tab: String, id: String) -> void:
	if pending_place != "":
		return
	var q = queues[tab]
	if TRAIN.has(id):
		# units stack: click again to queue more (shown as xN on the button)
		if not prereq_ok(id):
			note_denied(id)
			return
		_note_if_short(id)
		if q == null:
			queues[tab] = _new_item(id)
		elif backlog[tab].size() < 8:
			backlog[tab].append(id)
		return
	if q != null:
		if q["ready"] and q["id"] == id:
			pending_place = id                 # READY — arm the placement ghost
		return
	if not prereq_ok(id):
		note_denied(id)
		return
	if id == "wall":
		if economy.credits.get(player_faction, 0) >= DEFS["wall"]["cost"]:
			pending_place = "wall"             # walls skip the queue entirely
		else:
			_note_if_short(id)                 # the one item refused outright
		return
	_note_if_short(id)
	queues[tab] = _new_item(id)


# --- why a click did nothing ------------------------------------------------------
#
# Every refusal above used to be a bare `return`. That is fine for a player who
# already knows the tech tree and reads greyed-out buttons; it is a dead end for
# the one this slice is built for. These two record the reason, and campaign.gd's
# hint system is what decides whether anyone gets told (AC-3).

func note_denied(id: String) -> void:
	var need := missing_prereq(id)
	if need == "":
		return
	last_deny = {"kind": "prereq",
		"text": "%s needs a %s before you can build it."
			% [item_name(id).to_upper(), need]}


func _note_if_short(id: String) -> void:
	var cost := int(_cost_of(id))
	var have: int = int(economy.credits.get(player_faction, 0))
	if have >= cost:
		return
	# Walls are paid up front and genuinely refused; everything else drains its
	# cost out of the treasury as the money arrives, so it starts and crawls.
	# Those are different outcomes and the player is told which one they got.
	var tail := " It will start anyway and fill as your harvesters bring it in." \
		if id != "wall" else " Walls are paid up front, so this one cannot start yet."
	if audio:
		audio.announce("no_funds")
	last_deny = {"kind": "cost",
		"text": "%s costs $%d and you have $%d.%s"
			% [item_name(id).to_upper(), cost, have, tail]}


# What to call a build-tab entry on screen, buildings and units alike. ui.gd's
# _name_of was the original and now defers to this: the refusal text and the
# button label have to say the same word for the player to connect them.
func item_name(id: String) -> String:
	if id == "doomworks":
		return display_name(id, player_faction)
	return String(DEFS[id]["name"]) if DEFS.has(id) \
		else String(EFArmy.KINDS[id]["name"])


func _new_item(id: String) -> Dictionary:
	return {"id": id, "cost": _cost_of(id), "paid": 0.0,
		"is_unit": TRAIN.has(id), "ready": false}


func prereq_ok(id: String, fac: int = -1) -> bool:
	if fac < 0:
		fac = player_faction
	var reqs: Array = [TRAIN[id]["from"]] if TRAIN.has(id) else DEFS[id]["prereq"]
	for r in reqs:
		if not _owns(fac, r):
			return false
	return true


func _owns(faction: int, type: String) -> bool:
	for b in list:
		if b["faction"] == faction and b["type"] == type and b["hp"] > 0:
			return true
	return false


func _cost_of(id: String) -> float:
	return float(TRAIN[id]["cost"] if TRAIN.has(id) else DEFS[id]["cost"])


var _was_low_power := false


func _process(dt: float) -> void:
	# the transition INTO deficit is the announcement; the state itself is not,
	# or the line would repeat every cooldown for as long as the grid sags
	var lp := low_power(player_faction)
	if lp and not _was_low_power and audio:
		audio.announce("low_power")
	_was_low_power = lp
	# drain credits into whatever's building, halved when the grid is overdrawn
	var rate := BUILD_RATE * (LOW_POWER_MULT if low_power(player_faction) else 1.0) * dt
	for tab in queues:
		var q = queues[tab]
		if q == null or q["ready"]:
			continue
		var want: float = minf(rate, q["cost"] - q["paid"])
		var pay: float = minf(want, float(economy.credits.get(player_faction, 0)) + _pay_frac)
		_pay_frac += pay
		var take := int(_pay_frac)
		_pay_frac -= take
		economy.credits[player_faction] = economy.credits.get(player_faction, 0) - take
		q["paid"] += pay
		if q["paid"] >= q["cost"] - 0.01:
			if q["is_unit"]:
				train_spawn(q["id"], player_faction)
				if audio:
					audio.announce("unit_ready")
				queues[tab] = null
				if backlog.has(tab) and not backlog[tab].is_empty():
					queues[tab] = _new_item(backlog[tab].pop_front())
			else:
				q["ready"] = true
				if audio:
					audio.announce("construction")

	# engineers patch what money allows: 20 hp/s at 1 credit per 2 hp
	for idx in repairing.keys():
		var rb: Dictionary = list[idx]
		var rmax: float = DEFS[rb["type"]]["hp"]
		if rb["hp"] <= 0 or rb["hp"] >= rmax:
			repairing.erase(idx)
			continue
		if economy.credits.get(rb["faction"], 0) <= 0:
			continue
		var heal := minf(20.0 * dt, rmax - rb["hp"])
		rb["hp"] += heal
		_repair_frac += heal * 0.5
		var take := int(_repair_frac)
		_repair_frac -= take
		economy.credits[rb["faction"]] = economy.credits.get(rb["faction"], 0) - take

	# doomworks charge their terrible cargo (stalls during power deficits)
	for b in list:
		if b["type"] == "doomworks" and b["hp"] > 0 and not low_power(b["faction"]):
			var swc0: float = sw_charge.get(b["faction"], 0.0)
			sw_charge[b["faction"]] = minf(SW_TIME, swc0 + dt)
			if b["faction"] == player_faction and audio and swc0 < SW_TIME 					and sw_charge[b["faction"]] >= SW_TIME:
				audio.announce("sw_ready", true)

	for k in range(_growing.size() - 1, -1, -1):
		var g: Dictionary = _growing[k]
		if not is_instance_valid(g["node"]):
			_growing.remove_at(k)
			continue
		g["t"] += dt * 2.2
		if g["t"] >= 1.0:
			g["node"].scale.y = 1.0
			_growing.remove_at(k)
		else:
			g["node"].scale.y = 0.15 + 0.85 * g["t"]

	# idle turret heads slowly scan the horizon (combat aiming overrides)
	for b in list:
		if b["head"] != null and b.get("tgt") == null:
			b["head"].rotation.y += 0.35 * dt


# What a unit sounds like rolling out. Keyed by kind first, then role, so a new
# kind never falls silent. Played 3D at the door — positional tells you WHICH
# factory finished, and it uses the 12-deep spatial pool instead of the 3-deep
# UI pool, which is shared with the superweapon klaxon and victory stings.
const DEPLOY_SND := {
	"inf": "dep_infantry", "tank": "dep_vehicle", "smalltank": "dep_vehicle",
	"scout": "dep_vehicle", "harvester": "dep_harvester", "plane": "dep_air",
	# the MCVs had no entry and fell through to the generic vehicle sound, so a
	# mobile base left the factory sounding like a scout car
	"mcv": "dep_crawler",
}
const DEPLOY_SUPER := ["juggernaut", "ashworm", "leviathan", "cathedral"]


func _deploy_sound(id: String, fac: int, cell: Vector2i) -> void:
	if audio == null or fac != player_faction:
		return          # the enemy's motor pool is not the player's business
	var snd := "dep_vehicle"
	if id in DEPLOY_SUPER:
		snd = "dep_super"
	elif fac == 4 and String(EFArmy.KINDS[id].get("kind", "")) != "plane":
		snd = "dep_arc"     # the Covenant charges everything it fields
	else:
		snd = String(DEPLOY_SND.get(String(EFArmy.KINDS[id].get("kind", "")),
			"dep_vehicle"))
	audio.play(snd, Vector3((cell.x + 0.5) * T, 0.6, (cell.y + 0.5) * T), -4.0)


# ============================ RALLY POINTS ===================================
# Right-click with a factory selected plants its rally: everything it trains
# marches there instead of milling at the door. Stored per building dict (so a
# second barracks can rally somewhere else), shown as a pennant while selected.

var _rally_node: Node3D = null


func is_factory(idx: int) -> bool:
	if idx < 0 or idx >= list.size():
		return false
	var t: String = list[idx]["type"]
	for k in TRAIN:
		if TRAIN[k]["from"] == t:
			return true
	return false


func set_rally(idx: int, pos: Vector3) -> void:
	if not is_factory(idx):
		return
	list[idx]["rally"] = Vector3(pos.x, 0.0, pos.z)
	show_rally_for(idx)


func show_rally_for(idx: int) -> void:
	# called whenever the selected building changes; -1 hides the pennant
	if _rally_node == null:
		_rally_node = Node3D.new()
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.04
		pm.bottom_radius = 0.06
		pm.height = 2.2
		pm.radial_segments = 6
		pole.mesh = pm
		pole.position = Vector3(0, 1.1, 0)
		pole.material_override = _m(Color(0.2, 0.19, 0.18), 0.7, 0.4)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rally_node.add_child(pole)
		var flag := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.7, 0.4, 0.05)
		flag.mesh = fm
		flag.position = Vector3(0.36, 1.9, 0)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(1.4, 0.85, 0.3)   # >1.0: catches the glow pass
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flag.material_override = fmat
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rally_node.add_child(flag)
		add_child(_rally_node)
	if idx < 0 or idx >= list.size():
		_rally_node.visible = false
		return
	var rp = list[idx].get("rally", null)
	if rp is Vector3:
		_rally_node.position = rp
		_rally_node.visible = true
	else:
		_rally_node.visible = false


func train_spawn(id: String, fac: int) -> void:
	# NOTE: the sound fires AFTER a unit actually exists. It used to play up
	# here, before the early returns below, so a destroyed factory still
	# announced units it never built.
	if TRAIN[id]["from"] == "refinery":
		var ridx := best_refinery(fac)
		if ridx < 0:
			return
		var rb: Dictionary = list[ridx]
		var rdoor := Vector2i(rb["origin"].x + 1, rb["origin"].y + 3)
		var hu := army.spawn(id, fac, rdoor)
		hu.home_refinery = ridx
		var rrp = rb.get("rally", null)
		if rrp is Vector3:
			# a rallied harvester drives there first, then mines the nearest
			# field to the rally — so the rally chooses WHICH field it works
			army.path_single(hu, rrp, 0)
		_deploy_sound(id, fac, rdoor)
		return
	var producer := ""
	var origin := Vector2i.ZERO
	var size := 2
	var prod_idx := -1
	for bi in range(list.size()):
		var b: Dictionary = list[bi]
		if b["faction"] == fac and b["type"] == TRAIN[id]["from"] and b["hp"] > 0:
			origin = b["origin"]
			size = DEFS[b["type"]]["size"]
			producer = b["type"]
			prod_idx = bi
			break
	if producer == "":
		return
	var door := origin + Vector2i(size / 2, size)
	if EFArmy.KINDS[id].get("flying", false):
		door = origin + Vector2i(size / 2, size / 2)
	var u := army.spawn(id, fac, door)
	var rp = list[prod_idx].get("rally", null)
	if rp is Vector3:
		army.path_single(u, rp, 0)
	else:
		army.path_single(u, Vector3((door.x + 0.5) * T, 0, (door.y + 3.5) * T), 0)
	_deploy_sound(id, fac, door)


# ============================ MOBILE BASES ===================================
# A crawler carries one Command Post. Deploying consumes the vehicle, founds a
# base anywhere legal, and is capped so no side can carpet the map with them.

const MCV_KINDS := {1: "forge_crawler", 2: "scrap_hauler",
	3: "keelwright", 4: "ark_carriage"}
const MAX_POSTS := 3
const MCV_SPACING := 6          # tiles a new post must keep from an existing one


static func mcv_for(fac: int) -> String:
	return String(MCV_KINDS.get(fac, "forge_crawler"))


func count_posts(fac: int) -> int:
	var n := 0
	for b in list:
		if b["type"] == "command_post" and b["faction"] == fac and b["hp"] > 0:
			n += 1
	return n


func deploy_origin(u: EFUnit) -> Vector2i:
	# a 3x3 centred on the crawler
	return Vector2i(int(u.global_position.x / T) - 1, int(u.global_position.z / T) - 1)


func can_deploy(u: EFUnit) -> Dictionary:
	"""Returns {ok: bool, why: String} so the UI can explain a refusal."""
	if u == null or u.hp <= 0 or u.role != "mcv":
		return {"ok": false, "why": ""}
	if count_posts(u.faction) >= MAX_POSTS:
		return {"ok": false, "why": "THREE COMMAND POSTS IS THE LIMIT"}
	var origin := deploy_origin(u)
	# Say WHICH rule refused. One catch-all message meant a player parked on
	# perfectly good ground got "no room" for reasons invisible to them.
	var size: int = DEFS["command_post"]["size"]
	for dy in range(size):
		for dx in range(size):
			var c := origin + Vector2i(dx, dy)
			if not world.in_bounds(c.x, c.y):
				return {"ok": false, "why": "TOO CLOSE TO THE MAP EDGE"}
			if not world.is_buildable(c.x, c.y):
				return {"ok": false, "why": "THE GROUND HERE WILL NOT TAKE A BASE"}
			if u.faction == player_faction and not world.is_explored(c.x, c.y):
				return {"ok": false, "why": "SCOUT THIS GROUND FIRST"}
			for other in army.units:
				if other == u or other.garrisoned_in >= 0 or other.hp <= 0:
					continue
				if Vector2i(int(other.global_position.x / T),
						int(other.global_position.z / T)) == c:
					return {"ok": false, "why": "CLEAR YOUR OWN UNITS OFF THE SITE"}
	if not can_place("command_post", origin, u.faction, u, true):
		return {"ok": false, "why": "NO ROOM TO UNFOLD HERE"}
	for b in list:
		if b["type"] != "command_post" or b["hp"] <= 0:
			continue
		var bo: Vector2i = b["origin"]
		if maxi(absi(bo.x - origin.x), absi(bo.y - origin.y)) < MCV_SPACING:
			return {"ok": false, "why": "TOO CLOSE TO AN EXISTING POST"}
	return {"ok": true, "why": ""}


func deploy_mcv(u: EFUnit) -> bool:
	var chk := can_deploy(u)
	if not bool(chk["ok"]):
		return false
	var origin := deploy_origin(u)
	var fac: int = u.faction
	_create("command_post", fac, origin)
	if audio != null:
		audio.play("dep_vehicle", u.global_position, 1.0)
	army.kill_unit(u, false)     # the vehicle IS the building now — no wreck
	return true


# ============================ PLACEMENT ======================================

func can_place(id: String, origin: Vector2i, fac: int = -1,
		ignore_unit: EFUnit = null, free_standing := false) -> bool:
	# ignore_unit  — a deploying crawler necessarily stands on its own footprint
	# free_standing — a Command Post founds a base, so it is exempt from the
	#                 "within ADJACENCY of an existing building" rule. Without
	#                 this a side with zero buildings could never place anything.
	if fac < 0:
		fac = player_faction
	var size: int = DEFS[id]["size"]
	var near_base := false
	for dy in range(size):
		for dx in range(size):
			var c := origin + Vector2i(dx, dy)
			if not world.is_buildable(c.x, c.y):
				return false
			if fac == player_faction and not world.is_explored(c.x, c.y):
				return false            # the player can't build in the dark
			for u in army.units:
				if u == ignore_unit or u.garrisoned_in >= 0:
					continue
				if Vector2i(int(u.global_position.x / T),
						int(u.global_position.z / T)) == c:
					return false
	if free_standing:
		return true
	for b in list:
		if b["faction"] != fac or b["hp"] <= 0:
			continue
		for bc in b["cells"]:
			for dy in range(size):
				for dx in range(size):
					var c2: Vector2i = origin + Vector2i(dx, dy)
					if maxi(absi(bc.x - c2.x), absi(bc.y - c2.y)) <= ADJACENCY:
						near_base = true
	return near_base


func try_place(id: String, origin: Vector2i) -> bool:
	if not can_place(id, origin):
		return false
	if id == "wall":
		if economy.credits.get(player_faction, 0) < DEFS["wall"]["cost"]:
			pending_place = ""
			return false
		economy.credits[player_faction] -= int(DEFS["wall"]["cost"])
		_create("wall", player_faction, origin)
		return true                            # stay in wall mode — keep placing
	_create(id, player_faction, origin)
	for tab in queues:
		var q = queues[tab]
		if q != null and q["ready"] and q["id"] == id:
			queues[tab] = null
	pending_place = ""
	return true


func restore_building(id: String, faction: int, origin: Vector2i, hp: float) -> void:
	_create(id, faction, origin, true)
	list[list.size() - 1]["hp"] = hp


func _create(id: String, faction: int, origin: Vector2i, silent := false) -> void:
	var size: int = DEFS[id]["size"]
	var cells: Array[Vector2i] = []
	for dy in range(size):
		for dx in range(size):
			cells.append(origin + Vector2i(dx, dy))
	world.set_runtime_tile(cells, DEFS[id]["tile"])
	army.block_cells(cells)
	var node := _build_mesh(id, faction, origin)
	_register(id, faction, origin, cells, node)
	if not silent and audio:
		audio.play("place", Vector3((origin.x + size * 0.5) * T, 0.5,
			(origin.y + size * 0.5) * T), -2.0)
	if not silent and faction == player_faction:
		world.reveal(origin + Vector2i(size / 2, size / 2), 9)
	if node and not silent:
		_growing.append({"node": node, "t": 0.0})
	if id == "wall":
		_wall_nodes[origin] = node
		_reconnect_walls_around(origin)
	if DEFS[id].get("free_unit", false) and not silent:
		var kind: String = {1: "mule", 2: "magpie", 3: "dray", 4: "collector"}.get(faction, "magpie")
		var fu := army.spawn(kind, faction, Vector2i(origin.x + 1, origin.y + 3))
		fu.home_refinery = list.size() - 1
	placed.emit(cells)


func _register(id: String, faction: int, origin: Vector2i, cells: Array[Vector2i],
		node: Node3D) -> void:
	var head: Node3D = null
	if node and node.has_meta("head"):
		head = node.get_meta("head")
	list.append({"type": id, "faction": faction, "origin": origin, "cells": cells,
		"node": node, "hp": DEFS[id]["hp"], "head": head})
	for c in cells:
		cell_map[c] = list.size() - 1


func ai_place_near(id: String, fac: int, around: Vector2i) -> bool:
	for ring in range(2, 15):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := around + Vector2i(dx, dy)
				if can_place(id, c, fac):
					_create(id, fac, c)
					return true
	return false


func toggle_repair(idx: int) -> void:
	if repairing.has(idx):
		repairing.erase(idx)
	else:
		repairing[idx] = true


func sell(idx: int) -> void:
	# demolish for half the iron back — the emergency lever for bad power math
	var b: Dictionary = list[idx]
	if b["hp"] <= 0 or b["type"] == "command_post":
		return
	var refund := int(DEFS[b["type"]]["cost"] * 0.5)
	economy.credits[b["faction"]] = economy.credits.get(b["faction"], 0) + refund
	_remove_building(idx, false)


func cancel_item(tab: String, id: String) -> void:
	# RMB on a build button: pull it from the backlog first, else refund
	# whatever the active build already paid
	if backlog.has(tab):
		var k: int = backlog[tab].rfind(id)
		if k >= 0:
			backlog[tab].remove_at(k)
			return
	var q = queues[tab]
	if q != null and q["id"] == id:
		economy.credits[player_faction] = 			economy.credits.get(player_faction, 0) + int(q["paid"])
		if pending_place == id:
			pending_place = ""
		queues[tab] = null


func missing_prereq(id: String) -> String:
	# the NAME of the first unmet requirement, "" when buildable
	if TRAIN.has(id):
		var from: String = TRAIN[id]["from"]
		return "" if _owns(player_faction, from) else String(DEFS[from]["name"])
	for r in DEFS[id]["prereq"]:
		if not _owns(player_faction, r):
			return String(DEFS[r]["name"])
	return ""


func produces(type: String) -> Array:
	var out := []
	for tab in ["INF", "VEH", "AIR"]:
		for id in tab_items(tab):
			if TRAIN[id]["from"] == type:
				out.append(id)
	return out


func tab_for_building(type: String) -> String:
	for tab in ["INF", "VEH", "AIR"]:
		for id in tab_items(tab):
			if TRAIN[id]["from"] == type:
				return tab
	return ""


func building_at(tile: Vector2i) -> Dictionary:
	var idx: int = cell_map.get(tile, -1)
	return {} if idx < 0 else list[idx]


func take_damage(idx: int, wclass: String, dmg: float) -> void:
	var b: Dictionary = list[idx]
	if b["hp"] <= 0:
		return
	b["hp"] -= dmg * EFArmy.ARMOR_MULT[wclass]["BLDG"]
	if b["faction"] == player_faction and audio:
		audio.announce("base_attack")
	if music != null:
		music.bump(0.09)        # shelling a structure counts as a battle too
	var max_hp: float = DEFS[b["type"]]["hp"]
	if b["hp"] > 0 and b["hp"] < max_hp * 0.5 and not b.has("smoke"):
		b["smoke"] = true
		if b["node"]:
			_damage_smoke(b["node"])
	if b["hp"] <= 0:
		_destroy(idx)


func _destroy(idx: int) -> void:
	_remove_building(idx, true)


func _remove_building(idx: int, rubble: bool) -> void:
	var b: Dictionary = list[idx]
	b["hp"] = 0
	b["head"] = null
	# clear the footprint: ground returns, paths reopen
	world.set_runtime_tile(b["cells"], ".")
	army.unblock_cells(b["cells"])
	for c in b["cells"]:
		cell_map.erase(c)
	if b["node"]:
		b["node"].queue_free()
		b["node"] = null
	if b["type"] == "wall":
		_wall_nodes.erase(b["origin"])
		_reconnect_walls_around(b["origin"])
	if rubble:
		# scorched rubble where it stood
		var size: int = DEFS[b["type"]]["size"]
		var rb := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size * T * 0.8, 0.35, size * T * 0.8)
		rb.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.07, 0.065, 0.06)
		m.roughness = 1.0
		rb.material_override = m
		rb.position = Vector3((b["origin"].x + size * 0.5) * T, 0.17,
			(b["origin"].y + size * 0.5) * T)
		add_child(rb)
	placed.emit(b["cells"])


func _damage_smoke(node: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 1.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.12, 0.11, 0.1, 0.55))
	ramp.set_color(1, Color(0.2, 0.19, 0.18, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var puff := SphereMesh.new()
	puff.radius = 0.3
	puff.height = 0.6
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	puff.material = mat
	p.draw_pass_1 = puff
	p.position = Vector3(0, 2.0, 0)
	node.add_child(p)


# ============================ MESHES =========================================

func _build_mesh(id: String, faction: int, origin: Vector2i) -> Node3D:
	var size: int = DEFS[id]["size"]
	var root := Node3D.new()
	root.position = Vector3((origin.x + size * 0.5) * T, 0, (origin.y + size * 0.5) * T)
	add_child(root)
	if id != "wall":
		_ground_pad(root, size, faction)
	var glb := "res://models/%s_%s.glb" % [id, String(EFWorld.FACTIONS[faction]["name"]).to_lower()]
	if not ResourceLoader.exists(glb):
		glb = "res://models/bld_%s.glb" % id       # shared model, faction-tinted
	if ResourceLoader.exists(glb):
		var inst: Node3D = (load(glb) as PackedScene).instantiate()
		root.add_child(inst)
		_tint_glb(inst, EFWorld.hull_of(faction), faction)
		_faction_dressing(root, id, faction, size)
		var hd := inst.find_child("Head", true, false)
		if hd is Node3D:
			# imported nodes carry glTF axis-conversion rotations; yaw a clean
			# identity pivot instead so aiming/idle-spin stays pure yaw
			var pivot := Node3D.new()
			(hd as Node3D).get_parent().add_child(pivot)
			pivot.global_transform = Transform3D(Basis.IDENTITY,
				(hd as Node3D).global_position)
			(hd as Node3D).reparent(pivot)
			root.set_meta("head", pivot)
		elif id == "gun_turret" or id == "aa_turret":
			# A pipeline turret is ONE Hunyuan mesh, so there is no "Head"
			# child to find — and army._turrets skipped any turret without a
			# head, which silently disarmed every turret on the map the day
			# the new building models landed. Spin the whole tower from a
			# pivot at barrel height instead: on a 1-tile turret the full-body
			# traverse reads as the mount slewing onto target.
			var pivot2 := Node3D.new()
			root.add_child(pivot2)
			pivot2.position = Vector3(0, 1.3 if id == "aa_turret" else 1.05, 0)
			inst.reparent(pivot2)
			root.set_meta("head", pivot2)
		return root

	var fac_col: Color = EFWorld.FACTIONS[faction]["color"]
	var iron := _m(Color(0.27, 0.24, 0.22), 0.6, 0.45)
	var dark := _m(Color(0.13, 0.125, 0.13), 0.7, 0.4)
	var steel := _m(Color(0.35, 0.35, 0.38), 0.4, 0.8)
	var trim := _m(fac_col, 0.7, 0.1)
	trim.emission_enabled = true
	trim.emission = fac_col
	trim.emission_energy_multiplier = 0.55
	var glow := _m(Color(1.0, 0.55, 0.2), 0.5, 0.0)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.15)
	glow.emission_energy_multiplier = 2.0

	match id:
		"command_post":
			# A post deployed from a crawler must look like a starting base, so
			# it borrows world.gd's own HQ visual (pad, trim, faction model).
			# Without this case _build_mesh fell through and returned an empty
			# node — a working but completely invisible base.
			world.hq_visual(root, faction)
		"boiler":
			_box(root, Vector3(3.6, 0.35, 3.6), Vector3(0, 0.18, 0), dark)
			var drum := CylinderMesh.new()
			drum.top_radius = 0.85
			drum.bottom_radius = 0.85
			drum.height = 2.6
			var dm := MeshInstance3D.new()
			dm.mesh = drum
			dm.material_override = iron
			dm.rotation_degrees = Vector3(90, 0, 0)
			dm.position = Vector3(-0.4, 1.15, 0)
			root.add_child(dm)
			_box(root, Vector3(0.9, 1.3, 1.1), Vector3(1.2, 0.85, 0), dark)
			_box(root, Vector3(0.5, 0.5, 0.1), Vector3(1.2, 0.7, 0.56), glow)
			_cyl(root, 0.22, 0.3, 2.8, Vector3(1.2, 2.2, -0.4), dark)
			_box(root, Vector3(3.6, 0.12, 0.25), Vector3(0, 0.42, 1.68), trim)
		"refinery":
			_box(root, Vector3(5.6, 0.5, 5.6), Vector3(0, 0.25, 0), iron)
			var silo := CylinderMesh.new()
			silo.top_radius = 1.25
			silo.bottom_radius = 1.4
			silo.height = 3.6
			var smi := MeshInstance3D.new()
			smi.mesh = silo
			smi.material_override = iron
			smi.position = Vector3(-1.2, 2.3, -1.0)
			root.add_child(smi)
			_box(root, Vector3(2.4, 1.8, 2.6), Vector3(1.5, 1.4, -0.6), dark)
			_box(root, Vector3(1.4, 0.25, 1.4), Vector3(1.5, 2.42, -0.6), trim)
			var intake := CylinderMesh.new()
			intake.top_radius = 0.55
			intake.bottom_radius = 0.55
			intake.height = 0.3
			var imi := MeshInstance3D.new()
			imi.mesh = intake
			imi.material_override = glow
			imi.position = Vector3(0.2, 0.55, 2.1)
			root.add_child(imi)
			_box(root, Vector3(0.35, 2.8, 0.35), Vector3(-2.3, 1.9, 1.6), dark)
		"barracks":
			_box(root, Vector3(3.4, 1.6, 2.6), Vector3(0, 0.95, 0), iron)
			var roof := PrismMesh.new()
			roof.size = Vector3(3.7, 0.7, 2.9)
			var rmi := MeshInstance3D.new()
			rmi.mesh = roof
			rmi.material_override = dark
			rmi.position = Vector3(0, 2.1, 0)
			root.add_child(rmi)
			_box(root, Vector3(0.75, 1.2, 0.1), Vector3(-0.9, 0.75, 1.31), dark)
			for wx in [0.3, 1.15]:
				_box(root, Vector3(0.5, 0.4, 0.1), Vector3(wx, 1.25, 1.31), glow)
			_box(root, Vector3(3.4, 0.14, 0.2), Vector3(0, 0.3, 1.36), trim)
		"vehicle_works":
			_box(root, Vector3(5.4, 2.4, 4.6), Vector3(0, 1.25, -0.3), iron)
			_box(root, Vector3(3.2, 1.7, 0.4), Vector3(0, 0.9, 2.05), dark)
			_box(root, Vector3(2.8, 1.5, 0.2), Vector3(0, 0.8, 2.2), _m(Color(0.05, 0.05, 0.06), 1.0))
			for vx in [-1.6, 0.0, 1.6]:
				_box(root, Vector3(0.7, 0.5, 0.7), Vector3(vx, 2.7, -1.0), dark)
			_box(root, Vector3(5.4, 0.16, 0.24), Vector3(0, 2.5, 1.95), trim)
			_box(root, Vector3(0.3, 2.9, 0.3), Vector3(2.4, 1.9, -2.0), steel)
			_box(root, Vector3(2.2, 0.18, 0.18), Vector3(1.4, 3.3, -2.0), steel)
		"airfield":
			_box(root, Vector3(5.8, 0.22, 5.8), Vector3(0, 0.11, 0), dark)
			_box(root, Vector3(0.5, 0.24, 5.4), Vector3(-0.4, 0.12, 0),
				_m(Color(0.75, 0.72, 0.65), 0.9))
			_box(root, Vector3(2.2, 1.6, 2.6), Vector3(1.7, 0.95, -1.4), iron)
			_box(root, Vector3(2.4, 0.2, 2.8), Vector3(1.7, 1.85, -1.4), dark)
			_cyl(root, 0.05, 0.05, 3.4, Vector3(-2.4, 1.7, 2.4), steel)
			var sock := CylinderMesh.new()
			sock.top_radius = 0.06
			sock.bottom_radius = 0.16
			sock.height = 0.7
			var smi2 := MeshInstance3D.new()
			smi2.mesh = sock
			smi2.material_override = _m(Color(0.95, 0.5, 0.15), 0.9)
			smi2.rotation_degrees = Vector3(0, 0, -90)
			smi2.position = Vector3(-2.0, 3.2, 2.4)
			root.add_child(smi2)
			for li in range(3):
				_box(root, Vector3(0.14, 0.1, 0.14), Vector3(-0.4, 0.28, -2.2 + li * 2.2), glow)
			_box(root, Vector3(5.8, 0.12, 0.2), Vector3(0, 0.3, 2.85), trim)
		"doomworks":
			_box(root, Vector3(5.6, 0.5, 5.6), Vector3(0, 0.25, 0), dark)
			_cyl(root, 1.6, 1.9, 0.7, Vector3(0, 0.85, 0), iron)
			var breech := BoxMesh.new()
			breech.size = Vector3(1.2, 1.0, 2.2)
			var bmi2 := MeshInstance3D.new()
			bmi2.mesh = breech
			bmi2.material_override = iron
			bmi2.position = Vector3(0, 1.6, 0.4)
			root.add_child(bmi2)
			var great_barrel := CylinderMesh.new()
			great_barrel.top_radius = 0.22
			great_barrel.bottom_radius = 0.34
			great_barrel.height = 4.2
			var gb := MeshInstance3D.new()
			gb.mesh = great_barrel
			gb.material_override = steel
			gb.rotation_degrees = Vector3(55, 0, 0)
			gb.position = Vector3(0, 2.6, -1.2)
			root.add_child(gb)
			for li2 in range(4):
				_box(root, Vector3(0.18, 0.12, 0.18),
					Vector3(-2.2 + li2 * 1.45, 0.56, 2.5), glow)
			_box(root, Vector3(5.6, 0.14, 0.22), Vector3(0, 0.55, 2.75), trim)
		"gun_turret":
			_cyl(root, 0.95, 1.05, 0.5, Vector3(0, 0.25, 0), dark)
			_cyl(root, 0.62, 0.62, 0.5, Vector3(0, 0.7, 0), iron)
			var head := Node3D.new()
			head.position = Vector3(0, 1.05, 0)
			root.add_child(head)
			_box(head, Vector3(0.55, 0.38, 0.95), Vector3(0, 0.1, 0), iron)
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.07
			barrel.bottom_radius = 0.09
			barrel.height = 1.5
			var bm := MeshInstance3D.new()
			bm.mesh = barrel
			bm.material_override = steel
			bm.rotation_degrees = Vector3(90, 0, 0)
			bm.position = Vector3(0, 0.12, -1.0)
			head.add_child(bm)
			_cyl(root, 0.68, 0.72, 0.1, Vector3(0, 0.5, 0), trim)
			root.set_meta("head", head)
		"aa_turret":
			_cyl(root, 0.95, 1.05, 0.5, Vector3(0, 0.25, 0), dark)
			_box(root, Vector3(0.6, 0.7, 0.6), Vector3(0, 0.85, 0), iron)
			var head := Node3D.new()
			head.position = Vector3(0, 1.3, 0)
			root.add_child(head)
			for bx in [-0.16, 0.16]:
				for bz in [-0.1, 0.14]:
					var b := CylinderMesh.new()
					b.top_radius = 0.05
					b.bottom_radius = 0.06
					b.height = 1.2
					var bmi := MeshInstance3D.new()
					bmi.mesh = b
					bmi.material_override = steel
					bmi.rotation_degrees = Vector3(35, 0, 0)
					bmi.position = Vector3(bx, 0.3, bz - 0.3)
					head.add_child(bmi)
			_cyl(root, 0.68, 0.72, 0.1, Vector3(0, 0.55, 0), trim)
			root.set_meta("head", head)
		"wall":
			_build_wall_mesh(root, origin, faction)
	return root


var _wall_mats := {}       # faction -> [stone, cap], shared across every wall


func _wall_kit(fac: int) -> Array:
	if _wall_mats.has(fac):
		return _wall_mats[fac]
	var stone: StandardMaterial3D
	var cap: StandardMaterial3D
	match fac:
		2:      # Ashfall: scorched brown stone under a rust cap
			stone = _m(Color(0.27, 0.23, 0.19), 0.95, 0.05)
			cap = _m(Color(0.38, 0.22, 0.13), 0.9, 0.15)
		3:      # Aurelia: pale dressed stone, brass rail
			stone = _m(Color(0.36, 0.34, 0.3), 0.85, 0.1)
			cap = _m(Color(0.55, 0.42, 0.22), 0.45, 0.7)
		4:      # Luminar: cool grey, a faint violet charge along the top
			stone = _m(Color(0.28, 0.28, 0.32), 0.8, 0.2)
			cap = _m(Color(0.4, 0.33, 0.55), 0.6, 0.4)
			cap.emission_enabled = true
			cap.emission = Color(0.55, 0.4, 0.9)
			cap.emission_energy_multiplier = 0.5
		_:      # Karvath: the original iron-capped stone
			stone = _m(Color(0.3, 0.28, 0.26), 0.9, 0.1)
			cap = _m(Color(0.17, 0.16, 0.17), 0.6, 0.5)
	_wall_mats[fac] = [stone, cap]
	return _wall_mats[fac]


func _build_wall_mesh(root: Node3D, origin: Vector2i, fac := -1) -> void:
	for c in root.get_children():
		c.queue_free()
	# At initial placement cell_map is not yet populated (_register runs after
	# _build_mesh), so the lookup silently fell back to Karvath and every new
	# wall wore faction 1's kit. The creator passes the owner explicitly now;
	# the cell_map path serves only the neighbor-reconnect rebuilds.
	var wfac := fac
	if wfac < 0:
		wfac = 1
		if cell_map.has(origin):
			wfac = int(list[cell_map[origin]]["faction"])
	var kit := _wall_kit(wfac)
	var stone: StandardMaterial3D = kit[0]
	var iron: StandardMaterial3D = kit[1]
	_box(root, Vector3(0.7, 1.5, 0.7), Vector3(0, 0.75, 0), stone)
	_box(root, Vector3(0.5, 0.16, 0.5), Vector3(0, 1.56, 0), iron)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _wall_nodes.has(origin + d):
			_box(root, Vector3(0.36 if d.x == 0 else 1.4, 1.15,
				0.36 if d.y == 0 else 1.4),
				Vector3(d.x * 0.7, 0.58, d.y * 0.7), stone)


func _reconnect_walls_around(origin: Vector2i) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = origin + d
		if _wall_nodes.has(n):
			_build_wall_mesh(_wall_nodes[n], n)


# Each faction's structures are clad in their own scanned plate: Karvath in
# riveted rust, the Compact in salvaged corrugated sheet, the League and the
# Covenant in cleaner works-metal. The .glb geometry is boxy and carries no
# useful UVs, so these map by WORLD triplanar exactly like the terrain does —
# no unwrapping, and each building lands on a different patch of the texture.
const FAC_PLATE := {
	1: "rusty_metal_02", 2: "corrugated_iron",
	3: "factory_wall", 4: "factory_wall",
}
const PLATE_SCALE := {1: 0.42, 2: 0.30, 3: 0.36, 4: 0.36}
var _plate_cache := {}
var _relief_cache := {}
var relief_on := true          # --norelief turns this off for A/B comparison shots


func _plate_mat(faction: int) -> StandardMaterial3D:
	# One material per faction, shared by every building of that banner. The
	# colour is looked up here rather than passed in: the result is cached by
	# faction alone, so a caller's colour argument would silently lose to
	# whoever populated the cache first.
	if _plate_cache.has(faction):
		return _plate_cache[faction]
	var base: String = FAC_PLATE.get(faction, "rusty_metal_02")
	var diff := "res://textures/%s_Diffuse.jpg" % base
	if not ResourceLoader.exists(diff):
		_plate_cache[faction] = null
		return null
	var col: Color = EFWorld.hull_of(faction)
	var m := StandardMaterial3D.new()
	# Deliberately NO albedo_texture: albedo_texture multiplies albedo_color, and
	# these scans are dark, so cladding the walls in one crushed both the
	# brightness and the faction hue — and in an RTS you must read ownership at a
	# glance. Take the plate's RELIEF instead (normal + roughness), which is what
	# actually kills the "blocky" look, and leave the banner colour flat on top.
	m.albedo_color = col.darkened(0.1)
	var norp := "res://textures/%s_nor_gl.jpg" % base
	if ResourceLoader.exists(norp):
		m.normal_enabled = true
		m.normal_texture = load(norp)
		m.normal_scale = 1.15         # push the rivets and ribs
	var rgp := "res://textures/%s_Rough.jpg" % base
	if ResourceLoader.exists(rgp):
		m.roughness_texture = load(rgp)
	m.roughness = 0.95
	# a little metal so the sun glances off the sheeting, but low: there is no
	# reflection probe in this scene, so high metallic just reads as dark
	m.metallic = 0.16
	m.metallic_specular = 0.4
	if faction == 4:
		# Luminar shares Aurelia's factory_wall scan but wears it polished —
		# "glass city" against the League's ribbed workshop metal
		m.normal_scale = 0.35
		m.roughness = 0.55
		m.metallic = 0.3
	# WORLD triplanar, as the terrain does. Local mapping looked safer for the
	# turrets' rotating "Head", but every mesh in these .glb models is a
	# unit-sized primitive scaled by its node transform, and local triplanar
	# spans model space — so each surface got exactly uv1_scale of the texture
	# (well under one tile), squashed by that node's scale, which is a smooth
	# smear rather than grain. Rotating parts are excluded by _tint_glb instead.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s: float = PLATE_SCALE.get(faction, 0.38)
	m.uv1_scale = Vector3(s, s, s)
	_plate_cache[faction] = m
	return m


# Give one .glb surface the plate's relief while keeping its authored colour.
# Cached by (source material, faction): a .glb's PackedScene is resource-cached,
# so every instance of a building shares the same source materials and therefore
# the same derived one — a few materials total, not a few per building.
func _relief_of(src: BaseMaterial3D, faction: int) -> BaseMaterial3D:
	var key := "%d|%d" % [src.get_instance_id(), faction]
	if _relief_cache.has(key):
		return _relief_cache[key]
	var plate: StandardMaterial3D = _plate_mat(faction)
	if plate == null:
		_relief_cache[key] = null
		return null
	var d: BaseMaterial3D = src.duplicate()
	d.normal_enabled = true
	d.normal_texture = plate.normal_texture
	d.normal_scale = 0.75            # gentler than the banner panels
	if plate.roughness_texture != null:
		d.roughness_texture = plate.roughness_texture
	d.uv1_triplanar = true
	d.uv1_world_triplanar = true
	d.uv1_scale = plate.uv1_scale
	_relief_cache[key] = d
	return d


# True for anything parented under a turret's "Head": those rotate to track a
# target, and world-space mapping would slide the texture across them as they turn.
func _spins(mi: MeshInstance3D) -> bool:
	var n: Node = mi
	while n != null:
		if "head" in n.name.to_lower():
			return true
		n = n.get_parent()
	return false


# A slab of poured foundation exactly the size of the tiles the structure
# occupies. Only the Command Post had one, and without it every other building
# sat straight on the grass like a dropped prop — the pad is what tells the
# player how much ground a structure actually claims, which matters when they
# are fitting a base together. Sized from DEFS.size so it can never disagree
# with the cells that were actually blocked out.
func _ground_pad(root: Node3D, size: int, faction: int) -> void:
	var span := float(size) * T
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(span * 0.98, 0.22, span * 0.98)
	pad.mesh = pm
	pad.material_override = _pad_mat()
	pad.position = Vector3(0, 0.05, 0)
	root.add_child(pad)

	# a faction rim so ownership reads from the ground up, not only from the
	# building's paint — the same job the Command Post's glowing trim does
	var rim_mat := _pad_rim_mat(faction)
	var half := span * 0.5 - 0.06
	for side in range(4):
		var rm := BoxMesh.new()
		var along := span * 0.98
		rm.size = Vector3(along, 0.09, 0.16) if side < 2 \
			else Vector3(0.16, 0.09, along)
		var rim := MeshInstance3D.new()
		rim.mesh = rm
		rim.material_override = rim_mat
		rim.position = Vector3(0, 0.17, half) if side == 0 \
			else (Vector3(0, 0.17, -half) if side == 1
				else (Vector3(half, 0.17, 0) if side == 2
					else Vector3(-half, 0.17, 0)))
		root.add_child(rim)


static var _pad_mat_cache: StandardMaterial3D
static var _pad_rim_cache := {}


func _pad_mat() -> StandardMaterial3D:
	if _pad_mat_cache == null:
		_pad_mat_cache = StandardMaterial3D.new()
		_pad_mat_cache.albedo_color = Color(0.15, 0.145, 0.15)
		_pad_mat_cache.roughness = 0.95
		_pad_mat_cache.metallic = 0.0
	return _pad_mat_cache


func _pad_rim_mat(faction: int) -> StandardMaterial3D:
	if _pad_rim_cache.has(faction):
		return _pad_rim_cache[faction]
	var col: Color = EFWorld.FACTIONS.get(faction, EFWorld.FACTIONS[1])["color"]
	var m := StandardMaterial3D.new()
	# Painted kerb, not a light strip. At full team colour and 0.55 emission
	# these glowed hard enough to read as SELECTION boxes — every building on
	# the field permanently looking selected, which is worse than having no pad
	# at all. Darkened and dimmed to where it marks ownership without shouting.
	m.albedo_color = col.darkened(0.32)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.14
	m.roughness = 0.75
	_pad_rim_cache[faction] = m
	return m


func _tint_glb(root: Node3D, col: Color, faction := 0) -> void:
	var plate: StandardMaterial3D = _plate_mat(faction) if faction > 0 else null
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var m := mi.get_active_material(i)
			if m == null:
				continue
			var mname := m.resource_name.to_lower()
			if mname == "" and i < EFUnit.CUSTOM_SLOT_ROLE.size():
				# same convention the unit baker relies on: Godot's importer can
				# drop material names, so role falls back to slot INDEX
				mname = "u_" + EFUnit.CUSTOM_SLOT_ROLE[i]
				if i == 0:
					mname = "unit_tint"
			# pipeline buildings carry the same four slots as the vehicles, so
			# the brass/steel trim reads on a refinery exactly as on a tank
			if mname.begins_with("u_trim"):
				mi.set_surface_override_material(i, EFUnit._accent_mat(faction))
				continue
			if mname.begins_with("u_steel") or mname.begins_with("u_track"):
				mi.set_surface_override_material(i, EFUnit._gunmetal_mat())
				continue
			if "tint" in mname:
				# The plate material carries its detail in a NORMAL MAP, and a
				# normal map needs UVs. Hunyuan hulls have none — so a pipeline
				# building wearing the plate lost the relief AND the baked AO
				# (the plate never enables vertex_color_use_as_albedo), which is
				# why the first batch rendered as flat plastic blobs. Units
				# already solved this: object-space triplanar needs no UVs, and
				# reads the AO. Route UV-less meshes down the unit path and let
				# the hand-authored models keep the plate they were built for.
				var has_uv: bool = (int(mi.mesh.surface_get_format(i))
					& int(Mesh.ARRAY_FORMAT_TEX_UV)) != 0
				if plate != null and has_uv:
					mi.set_surface_override_material(i, plate)
					continue
				var dup: Material = m.duplicate()
				if dup is BaseMaterial3D:
					(dup as BaseMaterial3D).albedo_color = col.darkened(0.1)
					if not has_uv and faction > 0:
						dup = EFUnit._unit_relief(dup as BaseMaterial3D, faction)
				mi.set_surface_override_material(i, dup)
			elif relief_on and faction > 0 and m is BaseMaterial3D \
					and not _spins(mi):
				# walls, roofs, stacks: keep their colour, borrow the sheeting's
				# grain so they stop reading as smooth plastic boxes
				var rel: BaseMaterial3D = _relief_of(m as BaseMaterial3D, faction)
				if rel != null:
					mi.set_surface_override_material(i, rel)


# ============================ FACTION DRESSING ================================
# Small per-faction attachments on every glb building, so a Karvath base reads
# as iron and smoke while a Luminar base glows — without re-exporting a single
# model. Materials come from EFUnit's shared kit (same cache as the units, so
# the whole faction batches together). Attached to root (ground y=0, door +Z);
# construction growth scales root, so these rise with the build for free.

func _faction_dressing(root: Node3D, id: String, faction: int, size: int) -> void:
	if size < 2:
		return                     # turrets and walls keep their clean silhouette
	var first_dress := root.get_child_count()
	var s := size * T * 0.38
	var iron: StandardMaterial3D = EFUnit._kit_mat("iron")
	var rust: StandardMaterial3D = EFUnit._kit_mat("rust")
	var brass: StandardMaterial3D = EFUnit._kit_mat("brass")
	var arc: StandardMaterial3D = EFUnit._kit_mat("arc")
	var ember: StandardMaterial3D = EFUnit._kit_mat("ember")
	var canvas: StandardMaterial3D = EFUnit._kit_mat("canvas")
	match faction:
		1:      # KARVATH — auxiliary stack, ember mouth, parapet rivets
			_cyl(root, 0.12, 0.17, 2.1, Vector3(-s, 1.05, -s), iron)
			_cyl(root, 0.15, 0.15, 0.1, Vector3(-s, 2.12, -s), ember)
			for i in range(3):
				_box(root, Vector3(0.14, 0.14, 0.14),
					Vector3(-s * 0.5 + i * s * 0.5, 0.3, s), iron)
		2:      # ASHFALL — scrap pile, leaning sheet, door sandbags
			for i in range(3):
				var yaw := float(i) * 47.0
				var bx := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.7 - i * 0.12, 0.16, 0.5 - i * 0.08)
				bx.mesh = bm
				bx.material_override = rust
				bx.position = Vector3(s, 0.1 + i * 0.15, -s)
				bx.rotation_degrees = Vector3(0, yaw, 4)
				bx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(bx)
			var sheet := MeshInstance3D.new()
			var shm := BoxMesh.new()
			shm.size = Vector3(1.3, 0.05, 0.9)
			sheet.mesh = shm
			sheet.material_override = rust
			sheet.position = Vector3(-s, 0.5, s * 0.4)
			sheet.rotation_degrees = Vector3(0, 15, 55)
			root.add_child(sheet)
			for i in range(4):
				_box(root, Vector3(0.5, 0.22, 0.3),
					Vector3(-0.9 + i * 0.6, 0.11, s + 0.25), canvas)
		3:      # AURELIA — signal mast with pennant, door roundel, brass sill
			_cyl(root, 0.035, 0.05, 3.2, Vector3(s, 1.6, -s), brass)
			var pen := MeshInstance3D.new()
			var pq := QuadMesh.new()
			pq.size = Vector2(0.9, 0.4)
			pen.mesh = pq
			if ResourceLoader.exists("res://flag.gdshader"):
				var sm := ShaderMaterial.new()
				sm.shader = load("res://flag.gdshader")
				sm.set_shader_parameter("col", Color(0.28, 0.52, 0.73))
				pen.material_override = sm
			else:
				pen.material_override = brass
			pen.position = Vector3(s + 0.48, 3.0, -s)
			pen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(pen)
			_box(root, Vector3(size * T * 0.6, 0.07, 0.07),
				Vector3(0, 0.22, s + 0.12), brass)
		4:      # LUMINAR — arc pylon and a lit roof edge
			_cyl(root, 0.06, 0.1, 1.7, Vector3(s, 0.85, -s), iron)
			var orb := MeshInstance3D.new()
			var om := SphereMesh.new()
			om.radius = 0.17
			om.height = 0.34
			om.radial_segments = 10
			om.rings = 5
			orb.mesh = om
			orb.material_override = arc
			orb.position = Vector3(s, 1.85, -s)
			orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(orb)
			_box(root, Vector3(size * T * 0.5, 0.05, 0.05),
				Vector3(0, 0.24, s + 0.1), arc)
	# trim-scale pieces must not enter the directional shadow pass — it roughly
	# doubles their draw cost. _box/_cyl don't set this, so sweep what we added.
	for i in range(first_dress, root.get_child_count()):
		var child := root.get_child(i)
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _m(col: Color, rough := 0.8, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _cyl(parent: Node3D, r1: float, r2: float, h: float, pos: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r1
	mesh.bottom_radius = r2
	mesh.height = h
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

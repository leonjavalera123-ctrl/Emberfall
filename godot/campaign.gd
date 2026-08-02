# EMBERFALL: 1940 — campaign.gd
#
# THE CRADLE WAR, in acts. Missions are pure data: briefing, objectives, a
# parallel list of machine-checkable goals, and optional setup hooks. Adding a
# mission means adding a dictionary entry — no new engine code.
#
#   ACT I  — THE IRON CONCORD    Karvath takes the Cradle (missions 1-3)
#   ACT II — THE THOUSAND SAILS  the Aurelian League answers from the sky (4-6)
#
# Progress lives in user://campaign.cfg, one section per act. Act I is open from
# the start; later acts stay sealed until the act before them is finished.
#
# Offsets in "prebuild" / "veterans" are [dx, dy] relative to the player's own
# start tile, and are plain arrays rather than Vector2i so the whole table stays
# a legal GDScript constant.

class_name EFCampaign
extends Node

const ACTS := {
	1: {
		"name": "ACT I: THE IRON CONCORD",
		"blurb": "Karvath lands on the Cradle",
		"missions": [1, 2, 3],
		"cfg": "act1",
		"outro": "Act I complete. The Cradle belongs to the Concord.",
	},
	2: {
		"name": "ACT II: THE THOUSAND SAILS",
		"blurb": "the League answers from the sky",
		"missions": [4, 5, 6],
		"cfg": "act2",
		"outro": "Act II complete. The sky belongs to the League.",
	},
	3: {
		"name": "ACT III: THE SCRAP TIDE",
		"blurb": "the Compact throws it all back",
		"missions": [7, 8, 9],
		"cfg": "act3",
		"outro": "Act III complete. The ash keeps what it takes.",
	},
	4: {
		"name": "ACT IV: THE SECOND SUN",
		"blurb": "the Covenant comes for the fire",
		"missions": [10, 11, 12],
		"cfg": "act4",
		"outro": "Act IV complete. The Cradle answers to no one now.",
	},
}

const MISSIONS := {
	# ------------------------------------------------ ACT I -----------------
	1: {
		"act": 1,
		"title": "OPERATION LANDFALL",
		"map": "res://maps/cradle_landing.txt",
		"pfac": 1, "efac": 2, "diff": 1,
		"brief": [
			"Commander. The Cradle is real — the deep-bore charts confirm a",
			"virgin emberstone field greater than every known vein combined,",
			"buried beneath the corpse of old Veyre.",
			"",
			"You land tonight with the first expedition. The Ashfall Compact",
			"already has a forward camp on the northern ridge — scavengers,",
			"but dug in. Establish your foothold, raise a fighting force, and",
			"remove them from the Concord's path.",
			"",
			"Iron remembers, Commander. Make it remember this landing.",
			"                                  — Forge-Marshal Odann Kray",
		],
		"objectives": ["Raise a Boiler House and a Barracks",
			"Muster 8 Iron Guard", "Destroy the Ashfall forward camp"],
		"goals": [
			{"type": "own", "ids": ["boiler", "barracks"]},
			{"type": "muster", "kind": "iron_guard", "n": 8},
			{"type": "kill_hq"},
		],
		"ai_tech_limit": "infantry",
	},
	2: {
		"act": 1,
		"title": "THE GREY TIDE",
		"map": "res://maps/greyfen_redoubt.txt",
		"pfac": 1, "efac": 2, "diff": 2,
		"brief": [
			"The Compact's answer came before dawn. Warden Sixt has raised",
			"every cell in the Greyfen — they mean to drown your foothold in",
			"bodies before the main fleet arrives.",
			"",
			"You hold a ruined redoubt in the open ash. The relief column is",
			"six minutes out. There is nowhere to retreat, Commander — the",
			"walls you raise and the ground you hold are all there is.",
			"",
			"Hold the redoubt. Make every shell count.",
		],
		"objectives": ["Survive the Ashfall tide (6:00)",
			"Your Command Post must stand"],
		"goals": [
			{"type": "survive", "t": 360.0, "fmt": "Survive the Ashfall tide (%d:%02d)"},
			{"type": "hold_hq"},
		],
		"ai_off": true,
		"grant": 2000,
		"drive_tide": true,
		"prebuild": [["gun_turret", [0, -10]], ["gun_turret", [0, 10]],
			["wall", [-2, -11]], ["wall", [-1, -11]], ["wall", [1, -11]],
			["wall", [2, -11]], ["wall", [-2, 11]], ["wall", [-1, 11]],
			["wall", [1, 11]], ["wall", [2, 11]]],
		"veterans": [["iron_guard", [-3, 4]], ["iron_guard", [-1, 4]],
			["iron_guard", [1, 4]], ["iron_guard", [3, 4]],
			["grenadier", [-2, -4]], ["grenadier", [2, -4]],
			["bastion", [0, 5]]],
		"waves": [
			[45.0, "N", [["conscript", 4], ["rat", 1]]],
			[120.0, "E", [["conscript", 6], ["sapper", 2], ["rat", 2]]],
			[200.0, "W", [["conscript", 8], ["warpig", 1], ["rat", 2]]],
			[280.0, "N", [["conscript", 6], ["sapper", 3], ["warpig", 2]]],
			[320.0, "E", [["conscript", 8], ["rat", 3], ["warpig", 1]]],
		],
	},
	3: {
		"act": 1,
		"title": "THE CRADLE GATE",
		"map": "res://maps/the_cradle.txt",
		"pfac": 1, "efac": 2, "diff": 3,
		"brief": [
			"This is the one the histories will argue about.",
			"",
			"The Compact has fortified the Cradle approaches in strength —",
			"walls, flak, and the Warden's own guard. Intelligence believes",
			"they are assembling an Ashworm and worse behind those gates.",
			"",
			"No more foothold. No more holding. Take your army through the",
			"crossings and burn their command post out of the ash.",
			"",
			"The Cradle belongs to the Concord. Go and collect it.",
		],
		"objectives": ["Destroy the Ashfall command post"],
		"goals": [{"type": "kill_hq"}],
		"veterans": [["bastion", [6, 8]], ["bastion", [8, 8]],
			["hammerfall", [7, 10]], ["grenadier", [5, 9]],
			["grenadier", [9, 9]]],
	},
	# ------------------------------------------------ ACT II ----------------
	4: {
		"act": 2,
		"title": "THE THOUSAND SAILS",
		"map": "res://maps/sailwright_reach.txt",
		"pfac": 3, "efac": 1, "diff": 1,
		"brief": [
			"Sky-Regent. The Concord holds the Cradle and calls it settled.",
			"",
			"They have crossed the Sailwright and put a bridgehead on our own",
			"bank — iron on League soil, as though the ash were theirs to give",
			"away. Their armour is heavier than ours and always will be.",
			"",
			"So we do not meet it on the ground. Raise the yards, put wings",
			"over the canal, and take that bridgehead apart from above.",
			"",
			"A thousand sails, Regent. Let them look up.",
			"                                — Sky-Regent Lyra Vantelle",
		],
		"objectives": ["Raise an Airfield", "Muster 4 Sparrowhawks",
			"Destroy the Karvath bridgehead"],
		"goals": [
			{"type": "own", "ids": ["airfield"]},
			{"type": "muster", "kind": "sparrowhawk", "n": 4},
			{"type": "kill_hq"},
		],
		"grant": 800,
	},
	5: {
		"act": 2,
		"title": "THE FLAK COAST",
		"map": "res://maps/the_flak_coast.txt",
		"pfac": 3, "efac": 1, "diff": 2,
		"brief": [
			"The Concord learns quickly. Kray has strung flak the length of",
			"the coast escarpment and dares us to fly it.",
			"",
			"Two gaps in that wall, both covered. Ground assault through them",
			"is a funeral. But flak is a machine like any other, and machines",
			"can be broken by anyone patient enough to reach them.",
			"",
			"Silence their flak, then finish the works behind it.",
		],
		"objectives": ["Destroy every Karvath AA emplacement",
			"Destroy the Karvath command post"],
		"goals": [
			{"type": "razed_all", "id": "aa_turret"},
			{"type": "kill_hq"},
		],
		"grant": 600,
		"prebuild": [["airfield", [6, -4]]],
		# the flak line the briefing describes: strung along the escarpment and
		# its two gaps, plus a boiler so the emplacements actually have power
		"prebuild_enemy": [["boiler", [-7, 7]], ["aa_turret", [-14, 14]],
			["aa_turret", [-22, 12]], ["aa_turret", [-4, 11]],
			["aa_turret", [-30, 15]]],
		"veterans": [["sparrowhawk", [3, 3]], ["sparrowhawk", [5, 3]],
			["rocketeer", [2, 2]], ["rocketeer", [4, 2]]],
	},
	6: {
		"act": 2,
		"title": "THE SECOND SKY",
		"map": "res://maps/the_cradle.txt",
		"pfac": 3, "efac": 1, "diff": 3,
		"brief": [
			"Kray has pulled everything back to the Cradle itself.",
			"",
			"Every gun the Concord owns is pointed at the sky above that",
			"field. They have a Juggernaut on the plate and the will to use",
			"it. This is the last flight of the war, Regent, one way or the",
			"other.",
			"",
			"Take the Cradle. Not for the emberstone — for the precedent.",
			"",
			"The sky was never theirs.",
		],
		"objectives": ["Destroy the Karvath command post"],
		"goals": [{"type": "kill_hq"}],
		"grant": 1200,
		"prebuild": [["airfield", [5, -4]]],
		"veterans": [["sparrowhawk", [4, 4]], ["sparrowhawk", [6, 4]],
			["kondor", [8, 4]], ["pavise", [3, 6]], ["rocketeer", [5, 6]]],
	},
	# ------------------------------------------------ ACT III ---------------
	7: {
		"act": 3,
		"title": "THE RAT'S OATH",
		"map": "res://maps/greyfen_redoubt.txt",
		"pfac": 2, "efac": 3, "diff": 1,
		"brief": [
			"The great powers have traded our home twice now. The League",
			"parks its thousand sails over the Cradle and calls the ash",
			"pacified.",
			"",
			"We were in these cellars before the iron came. Raise the",
			"militia, raise it cheap, and take their garrison post apart",
			"bolt by bolt.",
			"                                  — Warden Mara Sixt",
		],
		"objectives": ["Raise a Boiler House and a Barracks",
			"Muster 12 Conscripts", "Destroy the League garrison post"],
		"goals": [
			{"type": "own", "ids": ["boiler", "barracks"]},
			{"type": "muster", "kind": "conscript", "n": 12},
			{"type": "kill_hq"},
		],
		"ai_tech_limit": "infantry",
		"grant": 300,
	},
	8: {
		"act": 3,
		"title": "THE WRECKING YARD",
		"map": "res://maps/sailwright_reach.txt",
		"pfac": 2, "efac": 3, "diff": 2,
		"brief": [
			"Every wreck they leave in the ash is Compact materiel that",
			"has not been delivered yet.",
			"",
			"The League flies from two yards on the far bank of the",
			"Sailwright. Ground their sails, strip the wreckage, and let",
			"them learn what the ash does to the grounded.",
			"",
			"Waste nothing. Not even them.",
		],
		"objectives": ["Field 3 Vulture salvage crews",
			"Tear down every League airfield",
			"Destroy the League command post"],
		"goals": [
			{"type": "muster", "kind": "vulture", "n": 3},
			{"type": "razed_all", "id": "airfield"},
			{"type": "kill_hq"},
		],
		"grant": 500,
		"prebuild_enemy": [["airfield", [-6, 6]], ["airfield", [6, -6]],
			["aa_turret", [0, 8]]],
		"veterans": [["rat", [-3, 3]], ["rat", [-1, 3]], ["rat", [1, 3]],
			["sapper", [3, 3]]],
	},
	9: {
		"act": 3,
		"title": "EVERYTHING THROWN BACK",
		"map": "res://maps/ashfall_plain.txt",
		"pfac": 2, "efac": 3, "diff": 3,
		"brief": [
			"They named the plain after what they did to it. Tonight it",
			"answers to its own.",
			"",
			"The League has massed everything it has left on the open ash —",
			"the full weight of the Thousand Sails, Leviathan and all.",
			"",
			"We have numbers, wrecks, and nowhere else to go. Throw it all",
			"back, Warden. All of it.",
		],
		"objectives": ["Destroy the League command post"],
		"goals": [{"type": "kill_hq"}],
		"grant": 400,
		"prebuild_enemy": [["gun_turret", [-4, 4]], ["gun_turret", [4, -4]],
			["aa_turret", [0, 6]]],
		"veterans": [["warpig", [4, 4]], ["warpig", [6, 4]],
			["stovepipe", [5, 6]], ["rat", [2, 4]], ["rat", [8, 4]],
			["vulture", [3, 6]]],
	},
	# ------------------------------------------------ ACT IV ----------------
	10: {
		"act": 4,
		"title": "THE LONG MARCH SOUTH",
		"map": "res://maps/cradle_gate.txt",
		"pfac": 4, "efac": 1, "diff": 1,
		"brief": [
			"The Glass City has emptied for the first time in a generation.",
			"",
			"Karvath's cordon holds the only pass south to the Cradle.",
			"Iron gates, iron patience. They expect us to bargain.",
			"",
			"Raise the grid. The Archlumen's word carries: we have not come",
			"to take the fire. We have come to take it away from everyone.",
			"                                — Archlumen Cassian Vael",
		],
		"objectives": ["Raise a Boiler House and a Vehicle Works",
			"Muster 12 Arc Templars", "Destroy the Karvath cordon post"],
		"goals": [
			{"type": "own", "ids": ["boiler", "vehicle_works"]},
			# a Luminar side already spawns with 6 templars, so asking for 6 was
			# complete before the briefing finished — this must exceed the spawn
			{"type": "muster", "kind": "arc_templar", "n": 12},
			{"type": "kill_hq"},
		],
		"ai_tech_limit": "infantry",
		"grant": 800,
	},
	11: {
		"act": 4,
		"title": "THE SHIELD AND THE STORM",
		"map": "res://maps/greyfen_redoubt.txt",
		"pfac": 4, "efac": 3, "diff": 2,
		"brief": [
			"The League learned siegecraft from Karvath, and they have",
			"chosen our ground to prove it on.",
			"",
			"The relay grid in the Greyfen feeds every shield the Covenant",
			"fields. If the grid falls, the Covenant falls with it.",
			"",
			"So the grid does not fall. Seven minutes to the storm's eye.",
		],
		"objectives": ["Hold the grid (7:00)", "Your Command Post must stand"],
		"goals": [
			{"type": "survive", "t": 420.0, "fmt": "Hold the grid (%d:%02d)"},
			{"type": "hold_hq"},
		],
		"ai_off": true,
		"grant": 2600,
		"drive_tide": true,
		# Two boilers come FIRST: a command post (+50) and refinery (-25) cannot
		# carry four turrets (-15 each), and low power makes turrets hold fire
		# entirely — the whole prebuilt grid stood dark until the player worked
		# out they had to rush a boiler at half build speed before wave one.
		"prebuild": [["boiler", [-5, -6]], ["boiler", [5, -6]],
			["gun_turret", [0, -10]], ["gun_turret", [0, 10]],
			["aa_turret", [-8, 0]], ["aa_turret", [8, 0]],
			["wall", [-2, -11]], ["wall", [-1, -11]], ["wall", [1, -11]],
			["wall", [2, -11]]],
		"veterans": [["arc_templar", [-3, 4]], ["arc_templar", [-1, 4]],
			["arc_templar", [1, 4]], ["lance_warden", [3, 4]],
			["faraday", [0, 5]], ["dynamo", [2, 6]]],
		"waves": [
			[45.0, "N", [["sky_marine", 4], ["dart", 1]]],
			[120.0, "E", [["sky_marine", 6], ["rocketeer", 2], ["dart", 2]]],
			[200.0, "W", [["dart", 3], ["zephyr", 2], ["sky_marine", 4]]],
			[290.0, "N", [["pavise", 2], ["rocketeer", 3], ["sky_marine", 6]]],
			[350.0, "E", [["zephyr", 3], ["dart", 3], ["pavise", 2]]],
		],
	},
	12: {
		"act": 4,
		"title": "THE SECOND SUN",
		"map": "res://maps/the_cradle_crown.txt",
		"pfac": 4, "efac": 2, "diff": 3,
		"brief": [
			"It ends where it began: the Compact holds the Cradle now, and",
			"in the crown of rock at its heart they are building the engine",
			"of everyone's ruin.",
			"",
			"The Archlumen has not come to win the argument. He has come to",
			"end it. Tear down the Doomworks before the Ashworm walks, and",
			"put out the fire the world keeps cutting itself on.",
			"",
			"After tonight, no one bleeds for this field again.",
		],
		"objectives": ["Tear down the Doomworks before the Ashworm walks",
			"Destroy the Compact command post"],
		"goals": [
			{"type": "razed_all", "id": "doomworks"},
			{"type": "kill_hq"},
		],
		"grant": 1500,
		"prebuild_enemy": [["doomworks", [4, 4]], ["gun_turret", [-5, 5]],
			["gun_turret", [5, -5]], ["aa_turret", [0, 7]]],
		"veterans": [["seraph", [4, 4]], ["faraday", [6, 5]],
			["arc_templar", [2, 5]], ["arc_templar", [4, 6]],
			["lance_warden", [3, 7]]],
	},
}

var main: Node = null
var mission := 0
var active := false
var obj_done: Array = []
var survive_left := 0.0
var mission_t := 0.0
var _waves: Array = []
var _drive_t := 0.0
var debug_fast := false


# --- progression ------------------------------------------------------------------

static func act_of(mid: int) -> int:
	if not MISSIONS.has(mid):
		return 1
	var cfg: Dictionary = MISSIONS[mid]
	return int(cfg.get("act", 1))


static func act_missions(act: int) -> Array:
	var a: Dictionary = ACTS[act]
	return a["missions"]


static func unlocked(act := 1) -> int:
	# Act I opens at its first mission; later acts stay sealed (0) until the act
	# before them is finished and unlock() writes their first id.
	var ms: Array = act_missions(act)
	var floor_id: int = int(ms[0]) if act == 1 else 0
	var cfg := ConfigFile.new()
	if cfg.load("user://campaign.cfg") != OK:
		return floor_id
	var a: Dictionary = ACTS[act]
	return int(cfg.get_value(String(a["cfg"]), "unlocked", floor_id))


static func unlock(m: int) -> void:
	if not MISSIONS.has(m):
		return                       # finishing the last mission of the last act
	var act: int = act_of(m)
	if m <= unlocked(act):
		return
	var cfg := ConfigFile.new()
	cfg.load("user://campaign.cfg")
	var a: Dictionary = ACTS[act]
	cfg.set_value(String(a["cfg"]), "unlocked", m)
	cfg.save("user://campaign.cfg")


static func act_open(act: int) -> bool:
	return unlocked(act) > 0


# --- setup ------------------------------------------------------------------------

func begin(mid: int, m: Node) -> void:
	main = m
	mission = mid
	active = true
	mission_t = 0.0
	var cfg: Dictionary = MISSIONS[mid]
	var goals: Array = cfg["goals"]
	obj_done = []
	for _g in goals:
		obj_done.append(false)

	survive_left = 0.0
	for g in goals:
		var gd: Dictionary = g
		if gd["type"] == "survive":
			survive_left = float(gd["t"])
	_waves = []
	for w in cfg.get("waves", []):
		_waves.append([w[0], w[1], w[2]])
	if debug_fast:
		# the compressed run used by --mission2: same shape, seconds not minutes
		if survive_left > 0.0:
			survive_left = 25.0
		_waves = [[4.0, "N", [["conscript", 3]]], [12.0, "E", [["rat", 2]]]]

	# --- data-driven mission hooks ---
	if cfg.has("ai_tech_limit"):
		main.ai.tech_limit = String(cfg["ai_tech_limit"])
	if bool(cfg.get("ai_off", false)):
		main.ai.set_process(false)
	if cfg.has("grant"):
		var pf: int = main.player_fac
		main.economy.credits[pf] = main.economy.credits.get(pf, 0) + int(cfg["grant"])
	var s: Vector2i = main.world.faction_start(main.player_fac)
	for entry in cfg.get("prebuild", []):
		var e: Array = entry
		var off: Array = e[1]
		_prebuild(String(e[0]), main.player_fac,
			s + Vector2i(int(off[0]), int(off[1])))
	# missions may also fortify the ENEMY — mission 5's flak line is the point of
	# the mission, and the AI's own build logic would never raise it in time
	var es: Vector2i = main.world.faction_start(main.ai_fac)
	for entry3 in cfg.get("prebuild_enemy", []):
		var e3: Array = entry3
		var off3: Array = e3[1]
		_prebuild(String(e3[0]), main.ai_fac,
			es + Vector2i(int(off3[0]), int(off3[1])))
	for entry2 in cfg.get("veterans", []):
		var e2: Array = entry2
		var off2: Array = e2[1]
		main.army.spawn(String(e2[0]), main.player_fac,
			s + Vector2i(int(off2[0]), int(off2[1])))
	_push_objectives()


# Place a mission's prebuilt structure near an offset, searching outward for a
# spot that is legal for its WHOLE footprint. buildings._create does no checking
# of its own — it stamps tiles, blocks cells and registers over the full
# size x size area — so validating only the origin tile let a size-3 airfield
# land half inside the start refinery (reassigning shared cells in cell_map) or
# on top of emberstone (converting the tiles and orphaning their credits).
func _prebuild(id: String, faction: int, base: Vector2i) -> void:
	var sz: int = int(main.buildings.DEFS[id]["size"])
	for ring in range(0, 10):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c: Vector2i = base + Vector2i(dx, dy)
				if _footprint_clear(c, sz):
					main.buildings._create(id, faction, c)
					return


func _footprint_clear(origin: Vector2i, sz: int) -> bool:
	for dy in range(sz):
		for dx in range(sz):
			var c: Vector2i = origin + Vector2i(dx, dy)
			if not main.world.is_buildable(c.x, c.y):
				return false
			if main.buildings.cell_map.has(c):
				return false
	return true


# --- the running mission ----------------------------------------------------------

func tick(dt: float) -> String:
	if not active:
		return ""
	mission_t += dt
	var cfg: Dictionary = MISSIONS[mission]
	var goals: Array = cfg["goals"]

	# The timer has to run BEFORE the goals are judged. Judging first meant any
	# goal gated on the timer could never latch: the same tick that expires the
	# clock also returns "win", after which active is false and tick never runs
	# again — so the mission ended showing every objective unticked.
	var timed := false
	for g0 in goals:
		var g0d: Dictionary = g0
		if g0d["type"] == "survive":
			timed = true
	if timed:
		survive_left = maxf(0.0, survive_left - dt)
		_spawn_due_waves()
		if bool(cfg.get("drive_tide", false)):
			_drive_t -= dt
			if _drive_t <= 0.0:
				_drive_t = 3.0
				_drive_tide()

	for i in range(goals.size()):
		var g: Dictionary = goals[i]
		match String(g["type"]):
			"own":
				var all := true
				for id in g["ids"]:
					if not main.buildings._owns(main.player_fac, String(id)):
						all = false
				_check(i, all)
			"muster":
				var n := 0
				for u in main.army.units:
					if u.kind == String(g["kind"]) and u.faction == main.player_fac \
							and u.hp > 0:
						n += 1
				_check(i, n >= int(g["n"]))
			"kill_hq":
				var hq: int = main._hq_enemy
				_check(i, hq >= 0 and main.buildings.list[hq]["hp"] <= 0)
			"razed_all":
				# latched, so an AI rebuild later cannot un-complete it
				var left := 0
				for b in main.buildings.list:
					var bd: Dictionary = b
					if bd["type"] == String(g["id"]) and bd["faction"] == main.ai_fac \
							and bd["hp"] > 0:
						left += 1
				_check(i, left == 0 and mission_t > 3.0)
			"hold_hq":
				var php: int = main._hq_player
				_check(i, php >= 0 and main.buildings.list[php]["hp"] > 0
					and survive_left <= 0.0)
			"survive":
				_check(i, survive_left <= 0.0)

	if timed:
		_push_objectives()
		if survive_left <= 0.0:
			return "win"
	return ""


func _check(i: int, v: bool) -> void:
	if v and not obj_done[i]:
		obj_done[i] = true
		main.ui.announce("OBJECTIVE COMPLETE", Color(0.55, 0.85, 0.5))
		if main.audio:
			main.audio.play_ui("ready_chime", -4.0)
		_push_objectives()


func _push_objectives() -> void:
	var lines := []
	var cfg: Dictionary = MISSIONS[mission]
	var goals: Array = cfg["goals"]
	for i in range(cfg["objectives"].size()):
		var text: String = cfg["objectives"][i]
		if i < goals.size():
			var g: Dictionary = goals[i]
			if g.has("fmt"):
				var t: float = maxf(0.0, survive_left)
				text = String(g["fmt"]) % [int(t) / 60, int(t) % 60]
		lines.append({"text": text, "done": obj_done[i]})
	main.ui.set_objectives(lines)


# --- scripted waves ---------------------------------------------------------------

func _spawn_due_waves() -> void:
	var cfg: Dictionary = MISSIONS[mission]
	var total: float = 25.0 if debug_fast else float(cfg.get("survive_total", 360.0))
	for g in cfg["goals"]:
		var gd: Dictionary = g
		if gd["type"] == "survive" and not debug_fast:
			total = float(gd["t"])
	var elapsed: float = total - survive_left
	for k in range(_waves.size() - 1, -1, -1):
		var w: Array = _waves[k]
		if elapsed >= float(w[0]):
			_waves.remove_at(k)
			_spawn_wave(String(w[1]), w[2])
			main.ui.announce("THE TIDE RISES — CONTACT %s" %
				{"N": "NORTH", "E": "EAST", "W": "WEST", "S": "SOUTH"}[String(w[1])],
				Color(0.95, 0.25, 0.2))
			if main.audio:
				main.audio.play_ui("sw_klaxon", -8.0)


func _spawn_wave(edge: String, spec: Array) -> void:
	var s: Vector2i = main.world.faction_start(main.player_fac)
	var w: int = main.world.w
	var h: int = main.world.h
	var at := Vector2i(s.x, 3)
	if edge == "E":
		at = Vector2i(w - 4, s.y)
	elif edge == "W":
		at = Vector2i(3, s.y)
	elif edge == "S":
		at = Vector2i(s.x, h - 4)
	var i := 0
	var hq := Vector3((s.x + 0.5) * EFWorld.T, 0, (s.y + 0.5) * EFWorld.T)
	var efac: int = int(MISSIONS[mission]["efac"])
	for entry in spec:
		for n in range(int(entry[1])):
			var u: EFUnit = main.army.spawn(String(entry[0]), efac,
				at + Vector2i((i % 5) - 2, i / 5))
			main.army.path_single(u, hq, i)
			i += 1


func _drive_tide() -> void:
	# stragglers re-aim at the Command Post; close ones gnaw on it
	var hq_idx: int = main._hq_player
	if hq_idx < 0:
		return
	var s: Vector2i = main.world.faction_start(main.player_fac)
	var hq := Vector3((s.x + 0.5) * EFWorld.T, 0, (s.y + 0.5) * EFWorld.T)
	var efac: int = int(MISSIONS[mission]["efac"])
	for u in main.army.units:
		if u.faction != efac or u.hp <= 0 or u.weapon.is_empty():
			continue
		if u.tgt_unit == null and u.tgt_building < 0 and u.path.is_empty():
			if Vector2(u.global_position.x - hq.x,
					u.global_position.z - hq.z).length() < 18.0:
				u.tgt_building = hq_idx
				u.auto_tgt = false
			else:
				main.army.path_single(u, hq, 0)

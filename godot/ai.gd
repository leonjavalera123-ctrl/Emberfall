# EMBERFALL: 1940 — ai.gd
# The enemy commander (GAME_DESIGN.md §11): a state machine, same pattern
# as the harvester but bigger.
#
#   OPENING  — scripted build order (boiler -> barracks -> vehicle works)
#   ECONOMY  — keep power positive, rebuild losses, run 2 harvesters
#   MUSTER   — train a mixed force until army strength >= muster_size
#   ATTACK   — send the wave at the player's HQ; stragglers re-aimed
#   DEFEND   — interrupt: intruders near the base pull the army home
#
# The AI pays real credits from its own treasury and obeys the same tech
# tree; it just skips the sidebar (its queue is a timer, not a UI).

class_name EFAI
extends Node

const THINK := 0.5
const DEFEND_RADIUS := 30.0

var muster_size := 10
var wave_cooldown := 25.0
var allow_sw := true
var tech_limit := ""        # "infantry" caps the camp at barracks-grade war


func set_difficulty(d: int) -> void:
	match d:
		1:      # EASY — smaller waves, long breathers, no doomsday
			muster_size = 8
			wave_cooldown = 40.0
			allow_sw = false
		3:      # BRUTAL — big waves, short breathers
			muster_size = 14
			wave_cooldown = 15.0
		_:
			pass

var world: EFWorld
var army: EFArmy
var economy: EFEconomy
var buildings: EFBuildings
var fac := 2
var enemy_fac := 1           # the CURRENT hunt target
var foe_pool: Array[int] = []   # every hostile faction; retarget draws from here
var known: Array[int] = []      # foes actually SEEN — a commander starts blind
var _scan_t := 0.0
var _site_picked := false       # has this commander chosen where to found its base?
var _site_t := 0.0              # travel budget before it must plant regardless
const SIGHT := 22.0             # how far this commander's forces notice a foe
var hq_tile := Vector2i.ZERO
var hq_pos := Vector3.ZERO

var state := "OPENING"
var build_q: Array = ["boiler", "barracks", "vehicle_works"]
var cur_build := {}          # {id, t}
var cur_train := {}          # {id, t}
var wave: Array = []
var attack_cd := 0.0
var _think := 0.0
var _defend_pulse := 0.0
var _train_i := 0

var _inf_pool: Array = ["conscript", "conscript", "sapper", "vulture"]
var _veh_pool: Array = ["rat", "warpig", "stovepipe"]
var _harv_kind := "magpie"
var _air_kind := "duster"
var _super_kind := "ashworm"
var _lift_kind := ""         # air transport; "" = this faction fields none

var _lift: EFUnit = null
var _lift_troops: Array = []
var _lift_state := "idle"    # idle / loading / inbound / returning
var _lift_t := 0.0           # sortie watchdog


func setup(w: EFWorld, a: EFArmy, eco: EFEconomy, bld: EFBuildings, faction: int,
		foe: int, foes: Array = []) -> void:
	world = w
	army = a
	economy = eco
	buildings = bld
	fac = faction
	enemy_fac = foe
	foe_pool.assign(foes if not foes.is_empty() else [foe])
	hq_tile = world.faction_start(fac)
	hq_pos = Vector3((hq_tile.x + 0.5) * EFWorld.T, 0, (hq_tile.y + 0.5) * EFWorld.T)
	known = []
	# The caller hands over the foe list with the player at the front. Taking
	# foes[0] as the opening target meant every commander in a free-for-all
	# marched at the human first. Choose by distance instead.
	enemy_fac = _pick_target()
	if fac == 1:
		_inf_pool = ["iron_guard", "iron_guard", "grenadier"]
		_veh_pool = ["outrider", "bastion", "sperrwagen"]
		_harv_kind = "mule"
		_air_kind = "kondor"
		_super_kind = "juggernaut"
	elif fac == 3:
		_inf_pool = ["sky_marine", "sky_marine", "rocketeer"]
		_veh_pool = ["dart", "pavise", "zephyr"]
		_harv_kind = "dray"
		_air_kind = "sparrowhawk"
		_super_kind = "leviathan"
		_lift_kind = "pelican"
	elif fac == 4:
		_inf_pool = ["arc_templar", "arc_templar", "lance_warden"]
		_veh_pool = ["glimmer", "faraday", "ion_carriage"]
		_harv_kind = "collector"
		_air_kind = "seraph"
		_super_kind = "cathedral"


func _process(dt: float) -> void:
	attack_cd = maxf(0.0, attack_cd - dt)
	_defend_pulse = maxf(0.0, _defend_pulse - dt)
	_lift_t = maxf(0.0, _lift_t - dt)
	_advance_jobs(dt)
	_site_t = maxf(0.0, _site_t - dt)
	_discover_tick(dt)
	_think -= dt
	if _think > 0.0:
		return
	_think = THINK

	# a fallen foe is no foe: hunt the nearest survivor (FFA elimination order)
	if _foe_dead(enemy_fac) and not _retarget():
		return          # every enemy is beaten; main is about to end the game

	if allow_sw and buildings.sw_ready(fac):
		# no hesitation, no mercy: the weapon fires the moment it is ready
		buildings.fire_superweapon(fac, _enemy_hq_pos()
			+ Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0)))

	_deploy_tick()
	if buildings.count_posts(fac) == 0:
		return          # nothing else is possible until the base is founded
	_defend_check()
	_airlift_tick()
	match state:
		"OPENING":
			if cur_build.is_empty():
				if build_q.is_empty():
					state = "ECONOMY"
				elif _start_build(build_q[0]):
					build_q.pop_front()
		"ECONOMY":
			if cur_build.is_empty() and buildings.low_power(fac):
				_start_build("boiler")
			elif cur_build.is_empty() and not buildings._owns(fac, "refinery") 					and buildings.prereq_ok("refinery", fac):
				_start_build("refinery")
			elif cur_build.is_empty() and not buildings._owns(fac, "barracks"):
				_start_build("barracks")
			elif tech_limit != "infantry" and cur_build.is_empty() \
					and not buildings._owns(fac, "vehicle_works") \
					and buildings.prereq_ok("vehicle_works", fac):
				_start_build("vehicle_works")
			elif cur_build.is_empty() and not buildings._owns(fac, "airfield") \
					and buildings.prereq_ok("airfield", fac) \
					and economy.credits.get(fac, 0) >= 1400:
				_start_build("airfield")
			elif cur_build.is_empty() and _count_type("aa_turret") < 2 \
					and buildings.prereq_ok("aa_turret", fac) \
					and economy.credits.get(fac, 0) >= 1400:
				_start_build("aa_turret")
			elif cur_build.is_empty() and allow_sw \
					and not buildings._owns(fac, "doomworks") \
					and buildings.prereq_ok("doomworks", fac) \
					and economy.credits.get(fac, 0) >= 3300:
				_start_build("doomworks")
			elif _harvester_count() < 2 and cur_train.is_empty() \
					and buildings._owns(fac, "vehicle_works"):
				_start_train(_harv_kind)
			else:
				state = "MUSTER"
		"MUSTER":
			var mil := _military()
			if mil.size() >= muster_size and attack_cd <= 0.0:
				state = "ATTACK"
			elif cur_train.is_empty():
				var id: String
				if tech_limit == "infantry":
					id = _inf_pool[_train_i % _inf_pool.size()]
				elif buildings._owns(fac, "doomworks") and _train_i % 6 == 5 						and economy.credits.get(fac, 0) >= 3900:
					id = _super_kind
				elif _train_i % 4 == 3 and buildings._owns(fac, "airfield"):
					id = _lift_kind if _wants_lift() else _air_kind
				elif _train_i % 3 == 2:
					id = _veh_pool[_train_i % _veh_pool.size()]
				else:
					id = _inf_pool[_train_i % _inf_pool.size()]
				if _start_train(id):
					_train_i += 1
				elif buildings.low_power(fac):
					state = "ECONOMY"
		"ATTACK":
			# every wave picks its own quarry: whoever we have seen and is
			# nearest NOW, not whoever we happened to aim at on turn one
			enemy_fac = _pick_target()
			_load_lift()
			wave = _military()
			for lu in _lift_troops:
				wave.erase(lu)              # they ride in; the ground wave walks
			var tgt := _enemy_hq_pos()
			for i in range(wave.size()):
				var u: EFUnit = wave[i]
				u.clear_targets()
				army.path_single(u, tgt, i)
			state = "WAVE"
		"WAVE":
			var alive := []
			for u in wave:
				if is_instance_valid(u) and u.hp > 0:
					alive.append(u)
			wave = alive
			if alive.is_empty():
				attack_cd = wave_cooldown
				state = "ECONOMY"
			else:
				var hq_idx := _enemy_hq_idx()
				if hq_idx < 0:
					# this foe's post is down — swing the live wave onto the
					# next survivor instead of marching home
					if _retarget():
						hq_idx = _enemy_hq_idx()
					if hq_idx < 0:
						state = "ECONOMY"   # war's genuinely over
						return
				var tgt2 := _enemy_hq_pos()
				for u in alive:
					if u.tgt_unit == null and u.tgt_building < 0 and u.path.is_empty():
						if Vector2(u.global_position.x - tgt2.x,
								u.global_position.z - tgt2.z).length() < 16.0:
							u.tgt_building = hq_idx
						else:
							army.path_single(u, tgt2, 0)


# --- jobs (build/train timers — the AI's "queue") ------------------------------

func _advance_jobs(dt: float) -> void:
	if not cur_build.is_empty():
		cur_build["t"] -= dt
		if cur_build["t"] <= 0.0:
			if buildings.ai_place_near(cur_build["id"], fac, hq_tile):
				cur_build = {}
			else:
				cur_build["t"] = 2.0        # no room right now — retry shortly
	if not cur_train.is_empty():
		cur_train["t"] -= dt
		if cur_train["t"] <= 0.0:
			buildings.train_spawn(cur_train["id"], fac)
			cur_train = {}


func _start_build(id: String) -> bool:
	var cost := buildings._cost_of(id)
	if economy.credits.get(fac, 0) < cost or not buildings.prereq_ok(id, fac):
		return false
	economy.credits[fac] = economy.credits.get(fac, 0) - int(cost)
	cur_build = {"id": id, "t": cost / 100.0}
	return true


func _start_train(id: String) -> bool:
	var cost := buildings._cost_of(id)
	if economy.credits.get(fac, 0) < cost or not buildings.prereq_ok(id, fac):
		return false
	economy.credits[fac] = economy.credits.get(fac, 0) - int(cost)
	cur_train = {"id": id, "t": cost / 100.0}
	return true


# --- situational awareness ------------------------------------------------------

func _military() -> Array:
	var out := []
	for u in army.units:
		if u.faction == fac and u.hp > 0 and not u.weapon.is_empty() \
				and not u.is_harvester() and u.garrisoned_in < 0:
			out.append(u)
	return out


func _harvester_count() -> int:
	var n := 0
	for u in army.units:
		if u.faction == fac and u.hp > 0 and u.is_harvester():
			n += 1
	return n


func _defend_check() -> void:
	if _defend_pulse > 0.0 or state == "WAVE":
		return
	var threatened := false
	for u in army.units:
		if u.faction != fac and u.faction in foe_pool and u.hp > 0 \
				and not u.weapon.is_empty() \
				and u.global_position.distance_to(hq_pos) < DEFEND_RADIUS:
			threatened = true
			break
	if not threatened:
		return
	_defend_pulse = 3.0
	var i := 0
	for u in _military():
		if u.tgt_unit == null and u.tgt_building < 0 \
				and u.global_position.distance_to(hq_pos) > 18.0:
			army.path_single(u, hq_pos, i)
			i += 1


# --- the air bridge -------------------------------------------------------------
# A passenger leaves army.units the moment it boards, so the hold is only ever
# filled AFTER muster_size has been banked and the wave committed — loading any
# earlier starves the AI's own attack trigger and it never launches.

func _wants_lift() -> bool:
	return _lift_kind != "" and tech_limit != "infantry" \
		and _find_lift() == null and economy.credits.get(fac, 0) >= 1800


func _find_lift() -> EFUnit:
	for u: EFUnit in army.units:
		if u.faction == fac and u.hp > 0 and u.kind == _lift_kind:
			return u
	return null


func _live(list: Array) -> Array:
	var out := []
	for u in list:
		if is_instance_valid(u) and u.hp > 0:
			out.append(u)
	return out


func _load_lift() -> void:
	if _lift == null or _lift_state != "idle" or not _lift.cargo_units.is_empty():
		return
	var mil := _military()
	var room: int = mini(EFUnit.CARGO_SLOTS, mil.size() / 2)
	var picked := []
	for u: EFUnit in mil:
		if picked.size() >= room:
			break
		if u.is_infantry() and u.garrisoned_in < 0:
			picked.append(u)
	if picked.size() < 2:
		return                              # too few boots to be worth the sortie
	# a transport left to itself idles in a 6.5 m orbit over the base, and the
	# troops can only path to open ground under it — so send it to them first
	var c := Vector3.ZERO
	for u3: EFUnit in picked:
		c += u3.global_position
	var rally := _open_point(c / float(picked.size()))
	army.path_single(_lift, rally, 0)
	# a standing march order survives clear_targets(), and the transport tick
	# only re-paths a passenger whose path has run out — so overwrite it here or
	# a wave veteran walks to the enemy HQ instead of to the ramp
	var li := 0
	for u2: EFUnit in picked:
		u2.clear_targets()
		u2.garrison_target = -1
		u2.load_target = _lift
		army.path_single(u2, rally, li)
		li += 1
	_lift_troops = picked
	_lift_state = "loading"
	_lift_t = 35.0


func _launch_lift() -> void:
	var drop := _drop_point()
	_lift.unload_at = drop
	army.path_single(_lift, drop, 0)
	_lift_state = "inbound"
	_lift_t = 45.0


func _open_point(p: Vector3) -> Vector3:
	var cell: Vector2i = army._nearest_open(
		Vector2i(int(p.x / EFWorld.T), int(p.z / EFWorld.T)))
	return Vector3((cell.x + 0.5) * EFWorld.T, 0, (cell.y + 0.5) * EFWorld.T)


func _drop_point() -> Vector3:
	# short of the HQ on the AI's own side, so the troops land on open ground
	# instead of inside the building footprint
	var e := _enemy_hq_pos()
	var back := hq_pos - e
	back.y = 0.0
	if back.length() < 0.001:
		back = Vector3(1, 0, 0)
	return _open_point(e + back.normalized() * 10.0)


func _airlift_tick() -> void:
	if _lift_kind == "":
		return
	_lift = _find_lift()
	if _lift == null:
		_lift_troops.clear()                # shot down, riders and all
		_lift_state = "idle"
		return
	match _lift_state:
		"loading":
			_lift_troops = _live(_lift_troops)
			var waiting := 0
			for u: EFUnit in _lift_troops:
				if not u.stowed:
					waiting += 1
			if _lift_troops.is_empty() and _lift.cargo_units.is_empty():
				_lift_state = "idle"
			elif waiting == 0 or (_lift_t <= 0.0 and not _lift.cargo_units.is_empty()):
				_launch_lift()
			elif _lift_t <= 0.0:
				for u2: EFUnit in _lift_troops:
					u2.load_target = null
				_lift_troops.clear()
				_lift_state = "idle"
		"inbound":
			if _lift.cargo_units.is_empty():
				_disembark()
			elif _lift_t <= 0.0:
				# the doors never opened: put them down where it stands rather
				# than circle the enemy base forever with a full hold
				_lift.unload_at = Vector3(_lift.global_position.x, 0,
					_lift.global_position.z)
				_lift.path.clear()
				_lift_t = 8.0
		"returning":
			if _lift.path.is_empty():
				_lift_state = "idle"


func _disembark() -> void:
	var tgt := _enemy_hq_pos()
	var i := 0
	for u: EFUnit in _live(_lift_troops):
		u.clear_targets()
		army.path_single(u, tgt, i)
		if not wave.has(u):
			wave.append(u)                  # so WAVE re-aims them like the rest
		i += 1
	_lift_troops.clear()
	army.path_single(_lift, hq_pos, 0)
	_lift_state = "returning"
	_lift_t = 60.0


func _enemy_hq_idx() -> int:
	for k in range(buildings.list.size()):
		var b: Dictionary = buildings.list[k]
		if b["type"] == "command_post" and b["faction"] == enemy_fac and b["hp"] > 0:
			return k
	return -1


# --- multi-foe support: FFA and 2v2 give an AI several enemies -------------------

func _foe_dead(f: int) -> bool:
	# must mirror main._is_beaten exactly: no post AND no crawler left
	for b in buildings.list:
		if b["type"] == "command_post" and b["faction"] == f and b["hp"] > 0:
			return false
	for u in army.units:
		if u.faction == f and u.role == "mcv" and u.hp > 0:
			return false
	return true


func _retarget() -> bool:
	# drop the fallen, then re-decide. This used to KEEP the current quarry
	# whenever it was still breathing, which — combined with every commander
	# being handed the player as its opening target — turned a free-for-all
	# into three armies queueing up on the human.
	var alive: Array[int] = []
	for f in foe_pool:
		if not _foe_dead(f):
			alive.append(f)
	foe_pool = alive
	if foe_pool.is_empty():
		return false
	enemy_fac = _pick_target()
	return true


func _pick_target() -> int:
	# Prefer someone we have actually LAID EYES ON; if we have met nobody yet,
	# probe toward the nearest instead — a commander who has met no one still
	# has to march somewhere, and standing still reads as broken.
	var pool: Array[int] = []
	for f in known:
		if f in foe_pool and not _foe_dead(f):
			pool.append(f)
	if pool.is_empty():
		for f2 in foe_pool:
			if not _foe_dead(f2):
				pool.append(f2)
	if pool.is_empty():
		return enemy_fac
	var own := _own_hq_pos()
	var best: int = pool[0]
	var bd := 1e18
	for f3 in pool:
		var keep := enemy_fac
		enemy_fac = f3
		var p := _enemy_hq_pos()
		enemy_fac = keep
		var d := Vector2(p.x - own.x, p.z - own.z).length_squared()
		if d < bd:
			bd = d
			best = f3
	return best


func _discover_tick(dt: float) -> void:
	# The commander starts blind. A faction becomes a candidate target only once
	# something of ours has seen something of theirs.
	#
	# The NEGATIVE case is the common one — three commanders spread across a big
	# map see nobody for minutes — so this walks the unit list ONCE per scan and
	# tests every unknown foe in the same pass. Rebuilding the eye list per foe
	# cost ~60 FPS in a four-way match.
	_scan_t -= dt
	if _scan_t > 0.0:
		return
	_scan_t = 1.0
	var hunting: Array[int] = []
	for f in foe_pool:
		if not (f in known) and not _foe_dead(f):
			hunting.append(f)
	if hunting.is_empty():
		return

	var eyes: Array[Vector2] = []
	for u in army.units:
		if u.faction == fac and u.hp > 0:
			eyes.append(Vector2(u.global_position.x, u.global_position.z))
	for b in buildings.list:
		if b["faction"] == fac and b["hp"] > 0:
			var o: Vector2i = b["origin"]
			eyes.append(Vector2((o.x + 0.5) * EFWorld.T, (o.y + 0.5) * EFWorld.T))
	if eyes.is_empty():
		return

	var r2 := SIGHT * SIGHT
	var spotted: Array[int] = []
	for u2 in army.units:
		if u2.hp <= 0 or not (u2.faction in hunting) or u2.faction in spotted:
			continue
		var p := Vector2(u2.global_position.x, u2.global_position.z)
		for e in eyes:
			if p.distance_squared_to(e) < r2:
				spotted.append(u2.faction)
				break
	for b2 in buildings.list:
		if b2["hp"] <= 0 or not (b2["faction"] in hunting) or b2["faction"] in spotted:
			continue
		var o2: Vector2i = b2["origin"]
		var bp := Vector2((o2.x + 0.5) * EFWorld.T, (o2.y + 0.5) * EFWorld.T)
		for e2 in eyes:
			if bp.distance_squared_to(e2) < r2:
				spotted.append(int(b2["faction"]))
				break

	for s in spotted:
		known.append(s)
	if not spotted.is_empty() and state != "ATTACK" and state != "WAVE":
		# someone we just bumped into may be far closer than whoever we were
		# vaguely marching at — reconsider, unless a wave is already committed
		enemy_fac = _pick_target()


func _count_type(type: String) -> int:
	var n := 0
	for b in buildings.list:
		if b["faction"] == fac and b["type"] == type and b["hp"] > 0:
			n += 1
	return n


func _enemy_hq_pos() -> Vector3:
	# Aim at where the enemy ACTUALLY is. This used to return the map's start
	# tile, which was fine when a base could never move — with crawlers the
	# enemy may have founded their base somewhere else entirely, and the AI
	# would have kept throwing waves at empty ground.
	var idx := _enemy_hq_idx()
	if idx >= 0:
		var o: Vector2i = buildings.list[idx]["origin"]
		return Vector3((o.x + 1.5) * EFWorld.T, 0, (o.y + 1.5) * EFWorld.T)
	# no post standing: go for their crawler, else fall back to the start tile
	for u in army.units:
		if u.faction == enemy_fac and u.role == "mcv" and u.hp > 0:
			return u.global_position
	var s: Vector2i = world.faction_start(enemy_fac)
	return Vector3((s.x + 0.5) * EFWorld.T, 0, (s.y + 0.5) * EFWorld.T)


func _own_hq_pos() -> Vector3:
	# and the AI's own anchor follows its real base rather than the map start
	for b in buildings.list:
		if b["type"] == "command_post" and b["faction"] == fac and b["hp"] > 0:
			var o: Vector2i = b["origin"]
			return Vector3((o.x + 1.5) * EFWorld.T, 0, (o.y + 1.5) * EFWorld.T)
	return hq_pos


func _deploy_tick() -> void:
	"""Get the starting crawler unfolded fast — with no post the AI cannot
	build anything at all, so a stalled crawler means a dead opponent."""
	if buildings.count_posts(fac) > 0:
		return
	for u in army.units:
		if u.faction != fac or u.role != "mcv" or u.hp <= 0:
			continue
		# Drive somewhere of its own choosing first, so a crawler landing does
		# not simply rebuild the map's start tile every match. _site_t gives it
		# a few seconds of travel, and a watchdog forces a deploy rather than
		# risk a commander that wanders forever with no base.
		if not _site_picked:
			_site_picked = true
			_site_t = 7.0
			var s0: Vector2i = world.faction_start(fac)
			var ang := randf() * TAU
			var rad := randf_range(4.0, 9.0)
			var dest := Vector2i(s0.x + int(cos(ang) * rad), s0.y + int(sin(ang) * rad))
			dest.x = clampi(dest.x, 3, world.w - 4)
			dest.y = clampi(dest.y, 3, world.h - 4)
			army.path_single(u, Vector3((dest.x + 0.5) * EFWorld.T, 0,
				(dest.y + 0.5) * EFWorld.T), 0)
			return
		if _site_t > 0.0 and not u.path.is_empty():
			return                  # still driving to the chosen site
		if bool(buildings.can_deploy(u)["ok"]):
			if buildings.deploy_mcv(u):
				var o: Vector2i = world.faction_start(fac)
				for b in buildings.list:
					if b["type"] == "command_post" and b["faction"] == fac \
							and b["hp"] > 0:
						o = b["origin"] + Vector2i(1, 1)
				hq_tile = o
				hq_pos = Vector3((o.x + 0.5) * EFWorld.T, 0, (o.y + 0.5) * EFWorld.T)
			return
		# blocked where it stands: shuffle a few tiles and try again next think
		if u.path.is_empty():
			army.path_single(u, u.global_position
				+ Vector3(randf_range(-8.0, 8.0), 0, randf_range(-8.0, 8.0)), 0)
		return

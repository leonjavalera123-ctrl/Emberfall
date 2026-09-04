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

# --- forward expansion -------------------------------------------------------
# A commander that only ever mines its opening field loses the long game. From
# STANDARD upward it eventually buys a crawler, escorts it to a rich deposit it
# does not already own, and founds a second front there.
const EXPAND_DRIVE_TIMEOUT := 90.0   # seconds to reach the site before aborting
const EXPAND_QUEUE_TIMEOUT := 45.0   # seconds to wait for a crawler that may never come
const EXPAND_SITE_RETRIES := 3       # failures before this map is declared hopeless
const EXPAND_COOLDOWN := 60.0        # base backoff, multiplied by the failure count
const EXPAND_CLUSTER_GAP := 3        # tiles apart that still count as one deposit

var muster_size := 10
var wave_cooldown := 25.0
var allow_sw := true
var tech_limit := ""        # "infantry" caps the camp at barracks-grade war


var diff_lvl := 2               # kept so behaviour ticks can gate on difficulty


func set_difficulty(d: int) -> void:
	diff_lvl = d
	match d:
		1:      # EASY — smaller waves, long breathers, no doomsday, one base
			muster_size = 8
			wave_cooldown = 40.0
			allow_sw = false
			expand_max = 0
		3:      # BRUTAL — big waves, short breathers, and it SPREADS
			muster_size = 14
			wave_cooldown = 15.0
			expand_max = 2          # saturates the three-post cap
			expand_after = 180.0
			expand_reach = 80
			expand_escort = 5
			expand_credits = 2800
			expand_army = 6
			_exp_q = ["refinery", "gun_turret", "gun_turret", "gun_turret",
				"barracks", "boiler"]
		_:      # STANDARD — must be written out, not left to fall through: the
				# 2v2 ally is constructed with set_difficulty(2)
			expand_max = 1
			expand_after = 300.0
			expand_reach = 55
			expand_escort = 4
			expand_credits = 3200
			expand_army = 8
			_exp_q = ["refinery", "gun_turret", "gun_turret"]

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

# expansion state
var expand_max := 1          # extra posts beyond the capital; 0 = never expands
var expand_after := 300.0    # game seconds before the first attempt
var expand_reach := 55       # furthest candidate field, in tiles
var expand_escort := 4
var expand_credits := 3200
var expand_army := 8
var _age := 0.0
var _exp_state := "idle"     # idle / queued / driving / building
var _exp_mcv: EFUnit = null
var _exp_site := Vector2i(-1, -1)
var _exp_alts: Array = []    # fallback origins at the same field
var _exp_anchor := Vector2i(-1, -1)
var _exp_escort_units: Array = []
var _exp_t := 0.0
var _exp_cd := 0.0
var _exp_fails := 0
var _exp_pulse := 0.0
var _exp_q: Array = []       # what the forward base builds once founded
var _exp_built := 0
var _fields: Array = []      # [{tiles, center}] clustered ember deposits


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
	_build_field_cache()


func _process(dt: float) -> void:
	attack_cd = maxf(0.0, attack_cd - dt)
	_defend_pulse = maxf(0.0, _defend_pulse - dt)
	_lift_t = maxf(0.0, _lift_t - dt)
	_advance_jobs(dt)
	_site_t = maxf(0.0, _site_t - dt)
	_age += dt
	_exp_cd = maxf(0.0, _exp_cd - dt)
	_exp_t = maxf(0.0, _exp_t - dt)
	_exp_pulse = maxf(0.0, _exp_pulse - dt)
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
	# survival outranks ambition: _deploy_tick and the guard above run first
	_expand_tick(dt)
	_stance_tick()
	_defend_check()
	_airlift_tick()
	match state:
		"OPENING":
			if cur_build.is_empty():
				if build_q.is_empty():
					state = "ECONOMY"
				elif _start_build(String(build_q[0])):
					build_q.pop_front()
				elif not buildings.prereq_ok(String(build_q[0]), fac):
					# An item whose prereq cannot be met from here would pin the
					# opening forever: the queue only ever popped what it managed
					# to START. On a crawler landing there is no free refinery,
					# so "vehicle_works" sat at the head failing every tick — and
					# the refinery that would unblock it is only built in
					# ECONOMY, which OPENING never reached. The whole brain
					# deadlocked: no economy, no troops, for the entire match.
					# Skip it and let ECONOMY pick it up once the tech exists.
					build_q.pop_front()
		"ECONOMY":
			if cur_build.is_empty() and _exp_state == "building" \
					and not _exp_q.is_empty() \
					and economy.credits.get(fac, 0) >= 1500:
				# the new front gets its refinery and guns before the capital
				# spends its surplus on a doomworks
				_expand_build()
			elif cur_build.is_empty() and buildings.low_power(fac):
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
				# stand the garrison up before the march: dug-in infantry are
				# PINNED, and recruiting them into a wave without mobilizing
				# left them rooted at home while the wave died short-handed
				_mobilize_all()
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
			# a forward base builds around ITSELF, not around the capital
			var anchor: Vector2i = cur_build.get("at", hq_tile)
			if buildings.ai_place_near(String(cur_build["id"]), fac, anchor):
				cur_build = {}
			else:
				# do not retry forever: a walled-in anchor would otherwise pin
				# the whole build queue for the rest of the match
				var tries: int = int(cur_build.get("tries", 0)) + 1
				if tries > 8:
					economy.credits[fac] = economy.credits.get(fac, 0) \
						+ int(buildings._cost_of(String(cur_build["id"])))
					cur_build = {}      # refund and move on
				else:
					cur_build["tries"] = tries
					cur_build["t"] = 2.0
	if not cur_train.is_empty():
		cur_train["t"] -= dt
		if cur_train["t"] <= 0.0:
			buildings.train_spawn(cur_train["id"], fac)
			cur_train = {}


func _start_build(id: String, at := Vector2i(-1, -1)) -> bool:
	var cost := buildings._cost_of(id)
	if economy.credits.get(fac, 0) < cost or not buildings.prereq_ok(id, fac):
		return false
	economy.credits[fac] = economy.credits.get(fac, 0) - int(cost)
	cur_build = {"id": id, "t": cost / 100.0,
		"at": at if at.x >= 0 else hq_tile, "tries": 0}
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
	var was := enemy_fac
	enemy_fac = _pick_target()
	if enemy_fac != was:
		# a rooted gun line aimed at the old target cannot march to the new
		# one — pack up the vehicles, but leave the home forts standing
		for u in army.units:
			if u.faction == fac and u.hp > 0 and not u.is_infantry() \
					and not u.flying and u.stance != 0:
				u.set_stance(0)
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


# --- stances: the AI fights with the same postures the player has ------------

const STANCE_FORT_CAP := 6


func _stance_tick() -> void:
	if diff_lvl <= 1:
		return                  # the EASY commander keeps it simple
	if state != "ATTACK" and state != "WAVE":
		# between waves, home-guard infantry dig in around the posts
		var forts := 0
		for u in army.units:
			if u.faction == fac and u.hp > 0 and u.fort_ref >= 0:
				forts += 1
		if forts >= STANCE_FORT_CAP:
			return
		for u2 in army.units:
			if forts >= STANCE_FORT_CAP:
				break
			if u2.faction != fac or u2.hp <= 0 or not u2.is_infantry():
				continue
			if u2.stance != 0 or u2.fort_ref >= 0 or u2.garrisoned_in >= 0:
				continue
			if not u2.path.is_empty() or u2.tgt_unit != null:
				continue
			var d := u2.global_position.distance_to(hq_pos)
			if d < DEFEND_RADIUS * 0.8 and d > 6.0:
				u2.set_stance(2)
				u2.path.clear()
				army._make_fort(u2)
				forts += 1
	elif diff_lvl >= 3 and state == "WAVE":
		# the BRUTAL gun line: cannon vehicles already inside their deployed
		# reach of the target base root themselves for the range/damage bonus
		var hq := _enemy_hq_pos()
		for u3 in army.units:
			if u3.faction != fac or u3.hp <= 0 or u3.flying or u3.is_infantry():
				continue
			if u3.role != "tank" and u3.role != "smalltank":
				continue
			if u3.stance != 0 or u3.weapon.is_empty():
				continue
			var rng: float = u3.weapon.get("range", 8.0)
			var d2 := u3.global_position.distance_to(hq)
			if d2 < rng * 1.8 and d2 > rng * 0.7:
				u3.set_stance(1)


func _mobilize_all() -> void:
	# forts dropped, artillery packed up: everyone can march again
	for u in army.units:
		if u.faction != fac or u.hp <= 0:
			continue
		if u.fort_ref >= 0:
			army._drop_fort(u.fort_ref, false)
		if u.stance != 0:
			u.set_stance(0)


func _count_type(type: String) -> int:
	var n := 0
	for b in buildings.list:
		if b["faction"] == fac and b["type"] == type and b["hp"] > 0:
			n += 1
	return n


# ============================ FORWARD EXPANSION ===============================

func _build_field_cache() -> void:
	# one flood fill over the map's ember tiles, grouping anything within
	# EXPAND_CLUSTER_GAP into a single deposit worth founding a base beside
	_fields = []
	var seen := {}
	for t in world.ember_tiles:
		if seen.has(t):
			continue
		var group: Array = []
		var queue: Array = [t]
		seen[t] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			group.append(c)
			for o in world.ember_tiles:
				if seen.has(o):
					continue
				if maxi(absi(o.x - c.x), absi(o.y - c.y)) <= EXPAND_CLUSTER_GAP:
					seen[o] = true
					queue.append(o)
		var cx := 0
		var cy := 0
		for g in group:
			cx += g.x
			cy += g.y
		_fields.append({"tiles": group,
			"center": Vector2i(cx / group.size(), cy / group.size())})


func _posts() -> Array:
	var out: Array = []
	for b in buildings.list:
		if b["type"] == "command_post" and b["faction"] == fac and b["hp"] > 0:
			out.append(b["origin"])
	return out


func _field_value(f: Dictionary) -> float:
	var total := 0.0
	for t in f["tiles"]:
		total += float(economy.reserves.get(t, 0.0))
	return total


func _score_field(f: Dictionary) -> float:
	var reserve := _field_value(f)
	if reserve <= 0.0:
		return -INF                     # mined out; nothing to come for
	var center: Vector2i = f["center"]
	var own := _posts()
	var own_d := 9999
	for p in own:
		own_d = mini(own_d, maxi(absi(center.x - p.x), absi(center.y - p.y)))
	if own_d > expand_reach:
		return -INF                     # too far to escort a crawler safely
	var foe_d := 999
	for b in buildings.list:
		if b["hp"] <= 0 or not world.is_hostile(fac, int(b["faction"])):
			continue
		if not (int(b["faction"]) in known):
			continue                    # we have not met them; we cannot fear them
		var bo: Vector2i = b["origin"]
		foe_d = mini(foe_d, maxi(absi(center.x - bo.x), absi(center.y - bo.y)))
	var mine := 0.0
	var theirs := 0.0
	for b2 in buildings.list:
		if b2["hp"] <= 0:
			continue
		var o2: Vector2i = b2["origin"]
		if maxi(absi(center.x - o2.x), absi(center.y - o2.y)) > 8:
			continue
		if int(b2["faction"]) == fac:
			mine = 1.0
		elif world.is_hostile(fac, int(b2["faction"])):
			theirs = 1.0
	var score := reserve / 1500.0
	score -= 0.10 * float(own_d)        # every tile is a longer supply line
	score += 0.06 * float(foe_d)        # but do not found it in their lap
	score -= 6.0 * theirs               # someone already lives here
	score -= 3.0 * mine                 # we already drain this one
	if own_d < EFBuildings.MCV_SPACING + 6:
		score -= 2.5                    # too close to be a real second front
	return score


func _pick_expand_site() -> Array:
	if _fields.is_empty():
		return []
	var best: Dictionary = {}
	var best_score := -INF
	for f in _fields:
		var s := _score_field(f)
		if s > best_score:
			best_score = s
			best = f
	if best.is_empty() or best_score == -INF:
		return []
	var center: Vector2i = best["center"]
	var found: Array = []
	# The post can never stand ON the field ('E' is not buildable, and a mined
	# tile becomes ',' which is not either) — so ring outward far enough to
	# clear the whole deposit.
	for ring in range(1, 7):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var origin: Vector2i = center + Vector2i(dx, dy) - Vector2i(1, 1)
				if not buildings.can_place("command_post", origin, fac, null, true):
					continue
				var ok := true
				for p in _posts():
					if maxi(absi(p.x - origin.x), absi(p.y - origin.y)) \
							< EFBuildings.MCV_SPACING:
						ok = false
				if ok:
					found.append(origin)
			if found.size() >= 3:
				break
	return found


func _threatened(p: Vector3, r: float) -> bool:
	for u in army.units:
		if u.hp <= 0 or not world.is_hostile(fac, u.faction):
			continue
		if u.global_position.distance_to(p) < r:
			return true
	return false


func _find_free_mcv() -> EFUnit:
	for u in army.units:
		if u.faction == fac and u.role == "mcv" and u.hp > 0:
			return u
	return null


func _want_expand() -> bool:
	if expand_max <= 0 or _exp_state != "idle" or _exp_cd > 0.0:
		return false
	if _exp_built >= expand_max:
		return false
	if buildings.count_posts(fac) >= EFBuildings.MAX_POSTS:
		return false
	if _age < expand_after or state == "ATTACK":
		return false
	if not buildings._owns(fac, "refinery") or not buildings._owns(fac, "vehicle_works"):
		return false
	if buildings.low_power(fac):
		return false
	if economy.credits.get(fac, 0) < expand_credits:
		return false
	if _military().size() < expand_army:
		return false
	if _defend_pulse > 0.0:
		return false
	for p in _posts():
		var pp := Vector3((p.x + 1.5) * EFWorld.T, 0, (p.y + 1.5) * EFWorld.T)
		if _threatened(pp, DEFEND_RADIUS):
			return false                # never expand while the house is burning
	return true


func _pick_escort(n: int) -> Array:
	var out: Array = []
	for u in _military():
		if out.size() >= n:
			break
		if u in wave:
			continue                    # do not strip a committed attack
		out.append(u)
	return out


func _exp_fail(reason: String) -> void:
	_exp_fails += 1
	_exp_cd = EXPAND_COOLDOWN * float(_exp_fails)
	_exp_state = "idle"
	_exp_mcv = null
	_exp_escort_units = []
	_exp_site = Vector2i(-1, -1)
	_exp_alts = []
	if _exp_fails >= EXPAND_SITE_RETRIES:
		expand_max = 0                  # this map will not take a second front
	print("[ai %d] expansion aborted: %s" % [fac, reason])


func _expand_tick(dt: float) -> void:
	match _exp_state:
		"idle":
			var orphan := _find_free_mcv()
			if orphan != null and _age > expand_after:
				# a crawler already exists (post-load, or bought and forgotten):
				# adopt it rather than buying another
				var sites := _pick_expand_site()
				if not sites.is_empty():
					_exp_mcv = orphan
					_exp_site = sites[0]
					_exp_alts = sites.slice(1)
					_exp_escort_units = _pick_escort(expand_escort)
					_exp_state = "driving"
					_exp_t = EXPAND_DRIVE_TIMEOUT
				return
			if not _want_expand():
				return
			var sites2 := _pick_expand_site()
			if sites2.is_empty():
				_exp_cd = EXPAND_COOLDOWN
				return
			if not cur_train.is_empty():
				return
			if _start_train(EFBuildings.mcv_for(fac)):
				_exp_site = sites2[0]
				_exp_alts = sites2.slice(1)
				_exp_state = "queued"
				_exp_t = EXPAND_QUEUE_TIMEOUT
		"queued":
			var u := _find_free_mcv()
			if u != null:
				_exp_mcv = u
				_exp_escort_units = _pick_escort(expand_escort)
				_exp_state = "driving"
				_exp_t = EXPAND_DRIVE_TIMEOUT
			elif _exp_t <= 0.0:
				_exp_fail("no crawler arrived")
		"driving":
			if _exp_mcv == null or not is_instance_valid(_exp_mcv) or _exp_mcv.hp <= 0:
				_exp_fail("crawler lost on the road")
				return
			if _exp_t <= 0.0:
				_exp_fail("crawler never reached the site")
				return
			var dest := Vector3((_exp_site.x + 1.5) * EFWorld.T, 0,
				(_exp_site.y + 1.5) * EFWorld.T)
			if _exp_pulse <= 0.0:
				_exp_pulse = 3.0
				if _exp_mcv.path.is_empty():
					army.path_single(_exp_mcv, dest, 0)
				for i in range(_exp_escort_units.size()):
					var e: EFUnit = _exp_escort_units[i]
					if is_instance_valid(e) and e.hp > 0 and e.path.is_empty() \
							and e.tgt_unit == null:
						army.path_single(e, dest, i + 1)
			if _exp_mcv.global_position.distance_to(dest) < 4.0:
				var chk := buildings.can_deploy(_exp_mcv)
				if bool(chk["ok"]):
					if buildings.deploy_mcv(_exp_mcv):
						_exp_anchor = _exp_site + Vector2i(1, 1)
						_exp_built += 1
						_exp_state = "building"
						_exp_mcv = null
						print("[ai %d] forward base founded at %s" % [fac, _exp_site])
				elif not _exp_alts.is_empty():
					_exp_site = _exp_alts.pop_front()   # try the next legal spot
					_exp_t = maxf(_exp_t, 20.0)
				else:
					_exp_fail("site refused: %s" % chk["why"])
		"building":
			if _exp_q.is_empty():
				_exp_state = "idle"
				_exp_cd = EXPAND_COOLDOWN


func _expand_build() -> void:
	# drain the forward base's own build order, anchored at the new post
	if _exp_q.is_empty() or _exp_anchor.x < 0 or not cur_build.is_empty():
		return
	var id := String(_exp_q[0])
	if not buildings.prereq_ok(id, fac):
		_exp_q.pop_front()          # cannot have it here; skip rather than jam
		return
	if _start_build(id, _exp_anchor):
		_exp_q.pop_front()


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

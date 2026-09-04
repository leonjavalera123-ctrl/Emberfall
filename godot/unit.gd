# EMBERFALL: 1940 — unit.gd
# One unit on the field: procedural 3D body (Blender .glb swaps come later,
# same as the HQs), waypoint-following movement with terrain collision,
# smooth turning, a walk bob, and a selection ring.
#
# Movement model (GAME_DESIGN.md §10): units are POINTS WITH A RADIUS, not
# tile-occupiers. The army hands us a waypoint path; we steer along it and
# the army's push-apart pass keeps crowds from stacking.

class_name EFUnit
extends Node3D

var kind := "iron_guard"
var role := "inf"                     # inf / tank / smalltank / scout / harvester
var display_name := "Iron Guard"
var faction := 1
var speed := 3.7
var radius := 0.34
var turn_speed := 12.0

var vel := Vector3.ZERO
var path: Array[Vector3] = []
var goal_cell := Vector2i(-1, -1)
var stuck_time := 0.0
var slot_point := Vector3.INF   # this unit's OWN destination, not the group's
var repath_tries := 0           # give-up counter for the stuck watchdog
# Crowd-stall detection. stuck_time only counts TERRAIN blockage, so a unit
# being shoved around by its own side never trips it — it just oscillates
# toward its slot forever. These track actual ground covered instead.
var stall_t := 0.0
var stall_ref := Vector3.INF
var stall_count := 0

var garrisoned_in := -1               # index into structures.garrisons, -1 = outside
var home_refinery := -1               # harvesters: the refinery they serve

# the sky (Phase 6)
const ALT := 8.0                      # cruising altitude in meters
var flying := false                   # planes ignore terrain and never stop
var orbit_anchor := Vector3.INF       # where an idle plane circles
var _orbit_a := 0.0
var _roll := 0.0
var _prop: MeshInstance3D
var _props: Array[MeshInstance3D] = []    # pipeline aircraft: every disc spins
var _insig_mi: MeshInstance3D             # the roundel quads, for the lineup dump
var _shadow: MeshInstance3D
var garrison_target := -1             # heading to garrison this structure

# air transport (Phase 11): a stowed passenger is OFF THE FIELD — hidden, pathless
# and removed from army.units, so every system that walks army.units skips it
const CARGO_SLOTS := 5
var stowed := false
var cargo_units: Array[EFUnit] = []
var load_target: EFUnit = null
var unload_at := Vector3.INF
var hovering := false

# combat (Phase 5) — damage = weapon dmg x armor multiplier (GAME_DESIGN.md §7)
var hp := 55.0
var max_hp := 55.0
var shield := 0.0
var max_shield := 0.0
var armor := "INF"                    # INF / LIGHT / HEAVY
var weapon := {}                      # {class, dmg, rof, range}; empty = unarmed
var cd := 0.0                         # weapon cooldown
var scan_t := 0.0                     # auto-acquire throttle
var repath_t := 0.0                   # chase repath throttle
var body_height := 1.0                # health bar anchor
var tgt_unit: EFUnit = null
var tgt_building := -1
var tgt_garrison := -1
var auto_tgt := false                 # true = self-acquired; dropped if it flees range
var salv_ref := {}                    # vulture crews: the wreck being stripped
var salv_t := 0.0
var since_hit := 999.0                # seconds since last wound (field healing)

# --- stance -------------------------------------------------------------------
# Index 0 is always today's behaviour, so nothing about the existing balance,
# the AI or the selftests shifts until a player deliberately changes posture.
const STANCES := {
	"inf": ["STEADY", "LIGHT FEET", "DIG IN"],
	"tank": ["MOBILE", "ARTILLERY"],
	"smalltank": ["MOBILE", "ARTILLERY"],
	"scout": ["MOBILE", "ARTILLERY"],
	"plane": ["LOITER", "PATROL"],
	"harvester": ["STEADY"],
	"mcv": ["STEADY"],          # its one trick is deploying, not posture
}
const MOBILE := 0
const ARTILLERY := 1
const DEPLOY_TIME := 1.6
const UNDEPLOY_TIME := 1.2

var stance := 0
var deploy_t := 0.0                   # > 0 while packing up or setting up
var fort_ref := -1                    # DIG IN: index into army.forts


func stance_options() -> Array:
	var o: Array = STANCES.get(role, ["STEADY"])
	return o


func stance_name() -> String:
	var o: Array = stance_options()
	return String(o[stance]) if stance < o.size() else "STEADY"


func set_stance(s: int) -> void:
	var o: Array = stance_options()
	if o.size() < 2 or s == stance or s >= o.size():
		return
	# leaving a posture always costs the setup time, so the swap is a decision
	if not flying:
		deploy_t = UNDEPLOY_TIME if stance == ARTILLERY else DEPLOY_TIME
	stance = s


func is_deployed() -> bool:
	return role != "inf" and not flying and stance == ARTILLERY


func is_pinned() -> bool:
	# artillery holds its ground; so does anyone mid-transition
	return is_deployed() or deploy_t > 0.0 or fort_ref >= 0


func is_patrolling() -> bool:
	return flying and stance == 1


func range_mult() -> float:
	if is_deployed():
		return 2.0
	return 1.35 if fort_ref >= 0 else 1.0


func dmg_mult() -> float:
	return 1.6 if is_deployed() else 1.0


func incoming_mult() -> float:
	if fort_ref >= 0:
		return 0.45
	return 1.15 if (role == "inf" and stance == 1) else 1.0


func move_speed() -> float:
	return speed * (1.28 if (role == "inf" and stance == 1) else 1.0)


func orbit_radius() -> float:
	return 26.0 if is_patrolling() else 6.5


func clear_targets() -> void:
	tgt_unit = null
	tgt_building = -1
	tgt_garrison = -1

# harvester state (kind == "harvester" only) — the FSM from GAME_DESIGN.md §5
const CAPACITY := 400.0
const MINE_RATE := 50.0               # credits/second while mining
const UNLOAD_TIME := 3.0
var h_state := "idle"                 # idle / to_field / mining / to_refinery / unloading
var cargo := 0.0
var target_field := Vector2i(-1, -1)
var unload_t := 0.0
var h_watch := 0.0                    # no-progress watchdog
var h_last := Vector3.ZERO
var _cargo: MeshInstance3D

var selected := false:
	set(v):
		selected = v
		if _ring:
			_ring.visible = v

var _ring: MeshInstance3D
var _body: Node3D
var _anim_t := 0.0
var _prev_speed := 0.0       # suspension lean: frame-to-frame deltas
var _prev_yaw := 0.0
var recoil_v := 0.0          # set by army on firing; decays as the hull settles
var _track_phase := 0.0      # scrolling tread position, metres travelled
var _merged: MeshInstance3D = null   # the baked hull (holds the track shader)


func setup(k: String, stats: Dictionary, fac: int, col: Color) -> void:
	kind = k
	role = stats["kind"]
	display_name = stats["name"]
	faction = fac
	speed = stats["speed"]
	radius = stats["radius"]
	turn_speed = stats["turn"]
	hp = stats.get("hp", 55.0)
	max_hp = hp
	armor = stats.get("armor", "INF")
	var wpn = stats.get("weapon")
	weapon = wpn if wpn != null else {}
	max_shield = stats.get("shield", 0.0)
	shield = max_shield
	flying = stats.get("flying", false)
	body_height = 1.2 if role == "inf" else (1.7 if role == "harvester" else 1.4)
	_body = Node3D.new()
	add_child(_body)
	if role == "inf":
		# infantry come as a section of six, not one man
		_build_squad(col)
		_build_ring()
		return
	if _try_glb(col):
		_dress()
		_build_ring()
		return
	match kind:
		"juggernaut":
			_build_juggernaut(col)
			_dress()
			_build_ring()
			return
		"ashworm":
			_build_ashworm(col)
			_dress()
			_build_ring()
			return
		"leviathan", "cathedral":
			_build_zeppelin(col, kind == "cathedral")
			_dress()
			_build_ring()
			return
	match stats["kind"]:
		"inf":
			_build_infantry(col)
		"tank":
			_build_tank(col, 1.0)
		"smalltank":
			_build_tank(col, 0.62)
		"scout":
			_build_scout(col)
		"harvester":
			_build_harvester(col)
		"mcv":
			_build_mcv(col)
		"plane":
			_build_plane(col)
	_dress()
	_build_ring()


func _aim_step(dt: float) -> void:
	# a rooted unit still tracks its target; ground units have no separate turret
	# node, so the hull does the swivelling
	var aim := Vector3.INF
	if tgt_unit != null and is_instance_valid(tgt_unit) and tgt_unit.hp > 0:
		aim = tgt_unit.global_position
	if aim == Vector3.INF:
		return
	var d := aim - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return
	var look := global_transform.looking_at(global_position + d.normalized(), Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(
		look.basis, minf(turn_speed * 0.5 * dt, 1.0)).orthonormalized()


func is_infantry() -> bool:
	return role == "inf"


func is_harvester() -> bool:
	return role == "harvester"


# --- per-frame movement (called by the army) ----------------------------------

func step(dt: float, world: EFWorld) -> void:
	if flying:
		_fly_step(dt)
		return
	if is_pinned():
		# Deployed, digging in, or mid-transition: hold the ground and swivel.
		# The path is deliberately KEPT — an order given while packing up would
		# otherwise be thrown away every frame until the transition finished,
		# and the unit would just stand there having visibly accepted it.
		vel = vel.move_toward(Vector3.ZERO, speed * 6.0 * dt)
		deploy_t = maxf(0.0, deploy_t - dt)
		_aim_step(dt)
		return
	var mspeed := move_speed()
	if not path.is_empty():
		var to := path[0] - global_position
		to.y = 0.0
		# The FINAL waypoint gets a tolerance scaled to the unit's own size.
		# A fixed 0.28 m meant a bastion — which the crowd push-apart displaces
		# by most of a body width — could never register as arrived, so it
		# re-approached and got shoved again forever.
		var arrive := 0.28 if path.size() > 1 else maxf(0.28, radius * 1.15)
		if to.length() < arrive:
			path.pop_front()
			if path.is_empty():
				slot_point = Vector3.INF
				repath_tries = 0
		else:
			vel = vel.move_toward(to.normalized() * mspeed, mspeed * 5.0 * dt)
	else:
		vel = vel.move_toward(Vector3.ZERO, mspeed * 6.0 * dt)

	if vel.length_squared() > 0.0004:
		var nxt := global_position + vel * dt
		# unstick rule: if we're ALREADY somewhere illegal (wedged between
		# structures), movement is always allowed so we can walk free
		var cur_ok := world.clear_at(global_position.x, global_position.z, radius * 0.8)
		if not cur_ok or world.clear_at(nxt.x, nxt.z, radius * 0.8):
			global_position = nxt
			stuck_time = 0.0
		else:
			# slide along whichever axis is still open
			var nx := global_position + Vector3(vel.x, 0, 0) * dt
			var nz := global_position + Vector3(0, 0, vel.z) * dt
			if world.clear_at(nx.x, nx.z, radius * 0.8):
				global_position = nx
			elif world.clear_at(nz.x, nz.z, radius * 0.8):
				global_position = nz
			elif not path.is_empty():
				stuck_time += dt
		if vel.length() > 0.5:
			var look := global_transform.looking_at(global_position + vel.normalized(), Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(
				look.basis, minf(turn_speed * dt, 1.0)).orthonormalized()

	# Vehicles don't hop — they LEAN. The old vertical sine made every truck
	# bounce like a toy with no wheels. Suspension lean instead: squat on
	# acceleration, nose-dip on braking, roll into turns, all from the frame-
	# to-frame speed and heading deltas. Infantry sections animate per man in
	# squad_tick, so the whole-body term skips them entirely.
	_anim_t += dt * (vel.length() * 2.0 + 1.0)
	if role != "inf":
		var sp_now := vel.length()
		var yaw_now := global_transform.basis.get_euler().y
		var d_speed := (sp_now - _prev_speed) / maxf(dt, 0.001)
		var d_yaw := wrapf(yaw_now - _prev_yaw, -PI, PI) / maxf(dt, 0.001)
		_prev_speed = sp_now
		_prev_yaw = yaw_now
		var k := minf(8.0 * dt, 1.0)
		# accel -> tail squat (pitch back), brake -> nose dip; firing rocks the
		# hull back on its suspension the same way (recoil_v decays to rest)
		recoil_v = maxf(0.0, recoil_v - 0.5 * dt)
		_body.rotation.x = lerpf(_body.rotation.x,
			-clampf(d_speed * 0.022, -0.085, 0.085) + recoil_v * 1.4, k)
		_body.position.z = lerpf(_body.position.z, recoil_v * 0.8, minf(14.0 * dt, 1.0))
		# turn -> lean out of the corner, scaled by how fast we're going
		_body.rotation.z = lerpf(_body.rotation.z,
			clampf(d_yaw * sp_now * 0.012, -0.10, 0.10), k)
		_body.position.y = 0.0
		# treads scroll with the ground actually covered — distance, not time
		if _merged != null:
			_track_phase += sp_now * dt
			_merged.set_instance_shader_parameter("track_scroll", _track_phase)
	if _cargo:
		_cargo.visible = cargo > 120.0


# --- the harvester's working life (state machine, GAME_DESIGN.md §5) -----------

func harvest_tick(dt: float, army: EFArmy) -> void:
	# watchdog: a hauler that stops making progress clears its path and
	# lets its state re-plan (cures wedged-between-buildings paralysis)
	if h_state == "to_field" or h_state == "to_refinery":
		h_watch += dt
		if h_watch > 3.0:
			if global_position.distance_to(h_last) < 0.6:
				path.clear()
			h_watch = 0.0
			h_last = global_position
	else:
		h_watch = 0.0
		h_last = global_position
	match h_state:
		"idle":
			var f: Vector2i = army.economy.nearest_field(global_position)
			if f.x >= 0:
				target_field = f
				army.path_single(self, _field_pos(f), 0)
				h_state = "to_field"
		"to_field":
			if path.is_empty():
				if not army.economy.has_reserves(target_field):
					h_state = "to_refinery" if cargo > 0.0 else "idle"
					if h_state == "to_refinery":
						_head_home(army)
				elif global_position.distance_to(_field_pos(target_field)) < 2.4:
					h_state = "mining"
				else:
					army.path_single(self, _field_pos(target_field), 0)
		"mining":
			if not army.economy.has_reserves(target_field):
				var f2: Vector2i = army.economy.nearest_field(global_position)
				if f2.x >= 0 and cargo < CAPACITY:
					target_field = f2
					army.path_single(self, _field_pos(f2), 0)
					h_state = "to_field"
				else:
					_head_home(army)
				return
			cargo += army.economy.mine(target_field, MINE_RATE * dt)
			if cargo >= CAPACITY:
				cargo = CAPACITY
				_head_home(army)
		"to_refinery":
			if path.is_empty():
				var dock: Vector3 = army.buildings.dock_for(self)
				if dock == Vector3.INF:
					h_state = "idle"
				elif global_position.distance_to(dock) < 2.8:
					h_state = "unloading"
					unload_t = 0.0
				else:
					army.path_single(self, dock, 0)
		"unloading":
			unload_t += dt
			if unload_t >= UNLOAD_TIME:
				army.economy.deposit(faction, cargo)
				cargo = 0.0
				h_state = "idle"


func force_harvest(tile: Vector2i, army: EFArmy) -> void:
	target_field = tile
	army.path_single(self, _field_pos(tile), 0)
	h_state = "to_field"


func _head_home(army: EFArmy) -> void:
	var dock: Vector3 = army.buildings.dock_for(self)
	if dock == Vector3.INF:
		h_state = "idle"
		return
	army.path_single(self, dock, 0)
	h_state = "to_refinery"


func _field_pos(tile: Vector2i) -> Vector3:
	return Vector3((tile.x + 0.5) * EFWorld.T, 0, (tile.y + 0.5) * EFWorld.T)


# --- procedural bodies ----------------------------------------------------------

func _mat(col: Color, rough := 0.8, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _mesh(mesh: Mesh, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	(parent if parent else _body).add_child(mi)
	return mi


func _build_infantry(col: Color) -> void:
	var uniform := _mat(col.darkened(0.25), 0.9, 0.0)
	var dark := _mat(Color(0.12, 0.115, 0.12), 0.8, 0.3)
	var skin := _mat(Color(0.5, 0.4, 0.32), 0.9, 0.0)

	var torso := CapsuleMesh.new()
	torso.radius = 0.17
	torso.height = 0.62
	_mesh(torso, uniform, Vector3(0, 0.5, 0))

	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.22
	_mesh(head, skin, Vector3(0, 0.88, 0))

	var helmet := SphereMesh.new()
	helmet.radius = 0.135
	helmet.height = 0.16
	_mesh(helmet, dark, Vector3(0, 0.95, 0))

	var pack := BoxMesh.new()
	pack.size = Vector3(0.22, 0.28, 0.12)
	_mesh(pack, dark, Vector3(0, 0.55, 0.19))

	var rifle := BoxMesh.new()
	rifle.size = Vector3(0.05, 0.05, 0.55)
	var r := _mesh(rifle, dark, Vector3(0.16, 0.52, -0.05))
	r.rotation_degrees = Vector3(-18, 0, 0)


func _build_tank(col: Color, s: float) -> void:
	var hull_m := _mat(col.darkened(0.3), 0.6, 0.5)
	var dark := _mat(Color(0.1, 0.095, 0.1), 0.7, 0.4)
	var steel := _mat(Color(0.3, 0.3, 0.33), 0.5, 0.7)

	var hull := BoxMesh.new()
	hull.size = Vector3(1.5, 0.5, 2.2) * s
	_mesh(hull, hull_m, Vector3(0, 0.5 * s, 0))

	var glacis := BoxMesh.new()
	glacis.size = Vector3(1.3, 0.3, 0.5) * s
	var gl := _mesh(glacis, hull_m, Vector3(0, 0.62 * s, -1.05 * s))
	gl.rotation_degrees = Vector3(-24, 0, 0)

	for tx in [-0.82 * s, 0.82 * s]:
		var track := BoxMesh.new()
		track.size = Vector3(0.34, 0.42, 2.35) * s
		_mesh(track, dark, Vector3(tx, 0.32 * s, 0))

	var turret := BoxMesh.new()
	turret.size = Vector3(0.95, 0.42, 1.15) * s
	_mesh(turret, hull_m, Vector3(0, 0.92 * s, 0.1 * s))

	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.07 * s
	barrel.bottom_radius = 0.09 * s
	barrel.height = 1.5 * s
	var b := _mesh(barrel, steel, Vector3(0, 0.95 * s, -1.0 * s))
	b.rotation_degrees = Vector3(90, 0, 0)

	var stack := CylinderMesh.new()
	stack.top_radius = 0.06 * s
	stack.bottom_radius = 0.08 * s
	stack.height = 0.4 * s
	_mesh(stack, dark, Vector3(-0.5 * s, 0.9 * s, 0.95 * s))


func _build_scout(col: Color) -> void:
	var body_m := _mat(col.darkened(0.2), 0.55, 0.45)
	var dark := _mat(Color(0.1, 0.095, 0.1), 0.8, 0.3)

	var hull := BoxMesh.new()
	hull.size = Vector3(0.9, 0.4, 1.7)
	_mesh(hull, body_m, Vector3(0, 0.52, 0))

	var cab := BoxMesh.new()
	cab.size = Vector3(0.8, 0.3, 0.7)
	_mesh(cab, body_m, Vector3(0, 0.85, 0.25))

	# the Dynamo Wagon is an unarmed support truck — it gets a tesla coil from
	# the dress pass instead of a gun it cannot fire
	if kind != "dynamo":
		var gun := BoxMesh.new()
		gun.size = Vector3(0.06, 0.06, 0.7)
		var gm := _mesh(gun, dark, Vector3(0, 1.08, -0.1))
		gm.rotation_degrees = Vector3(-8, 0, 0)

	for wz in [-0.55, 0.55]:
		for wx in [-0.52, 0.52]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.24
			wheel.bottom_radius = 0.24
			wheel.height = 0.16
			var w := _mesh(wheel, dark, Vector3(wx, 0.24, wz))
			w.rotation_degrees = Vector3(0, 0, 90)


func _build_mcv(col: Color) -> void:
	# A base folded up for travel: a long flatbed carrying a shrouded structure,
	# tracked, unarmed, and obviously too big for the road it is on.
	var body_m := _mat(col.darkened(0.3), 0.65, 0.4)
	var dark := _mat(Color(0.11, 0.105, 0.11), 0.85, 0.3)
	var tarp := _mat(Color(0.34, 0.32, 0.28), 0.95, 0.05)

	var hull := BoxMesh.new()
	hull.size = Vector3(1.85, 0.6, 3.4)
	_mesh(hull, body_m, Vector3(0, 0.6, 0))

	var deck := BoxMesh.new()
	deck.size = Vector3(1.95, 0.16, 3.5)
	_mesh(deck, dark, Vector3(0, 0.94, 0))

	# the folded command post under its tarp — the payload
	var load1 := BoxMesh.new()
	load1.size = Vector3(1.5, 0.85, 1.9)
	_mesh(load1, tarp, Vector3(0, 1.42, 0.25))
	var load2 := BoxMesh.new()
	load2.size = Vector3(1.15, 0.5, 1.2)
	_mesh(load2, tarp, Vector3(0, 2.05, 0.35))
	# a stub of the mast that will raise when it deploys
	var mast := CylinderMesh.new()
	mast.top_radius = 0.07
	mast.bottom_radius = 0.09
	mast.height = 1.0
	mast.radial_segments = 8
	_mesh(mast, dark, Vector3(0.45, 2.5, 0.1))

	var cab := BoxMesh.new()
	cab.size = Vector3(1.3, 0.72, 0.95)
	_mesh(cab, body_m, Vector3(0, 1.28, -1.42))
	var glass := BoxMesh.new()
	glass.size = Vector3(1.15, 0.34, 0.1)
	_mesh(glass, _mat(Color(0.18, 0.24, 0.3), 0.25, 0.6), Vector3(0, 1.36, -1.92))

	# heavy tracks
	for tx in [-0.95, 0.95]:
		var track := BoxMesh.new()
		track.size = Vector3(0.42, 0.62, 3.5)
		_mesh(track, dark, Vector3(tx, 0.42, 0))
		for wz in [-1.25, -0.42, 0.42, 1.25]:
			var w := CylinderMesh.new()
			w.top_radius = 0.3
			w.bottom_radius = 0.3
			w.height = 0.3
			w.radial_segments = 10
			var wm := _mesh(w, dark, Vector3(tx, 0.34, wz))
			wm.rotation_degrees = Vector3(0, 0, 90)


func _build_harvester(col: Color) -> void:
	var body_m := _mat(col.darkened(0.25), 0.6, 0.45)
	var dark := _mat(Color(0.1, 0.095, 0.1), 0.8, 0.3)

	var hull := BoxMesh.new()
	hull.size = Vector3(1.3, 0.55, 2.3)
	_mesh(hull, body_m, Vector3(0, 0.55, 0))

	var cab := BoxMesh.new()
	cab.size = Vector3(1.1, 0.6, 0.7)
	_mesh(cab, body_m, Vector3(0, 1.05, -0.75))

	var hopper := BoxMesh.new()
	hopper.size = Vector3(1.2, 0.55, 1.25)
	_mesh(hopper, dark, Vector3(0, 1.0, 0.45))

	# the glowing ore pile — only visible when loaded
	var pile := BoxMesh.new()
	pile.size = Vector3(0.95, 0.3, 1.0)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.55, 0.2)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.15)
	glow.emission_energy_multiplier = 1.8
	_cargo = _mesh(pile, glow, Vector3(0, 1.3, 0.45))
	_cargo.visible = false

	for wz in [-0.8, 0.0, 0.8]:
		for wx in [-0.72, 0.72]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.3
			wheel.bottom_radius = 0.3
			wheel.height = 0.2
			var wm := _mesh(wheel, dark, Vector3(wx, 0.3, wz))
			wm.rotation_degrees = Vector3(0, 0, 90)


func _build_ring() -> void:
	var ring := TorusMesh.new()
	ring.rings = 12
	ring.ring_segments = 8
	# a section needs a ring wide enough to hold six men, but `radius` itself
	# must not change — it drives separation, pathing clearance, formation
	# pitch and click tolerance across the whole game
	ring.inner_radius = 0.62 if role == "inf" else radius + 0.18
	ring.outer_radius = 0.70 if role == "inf" else radius + 0.26
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 1.0, 0.55)
	m.emission_enabled = true
	m.emission = Color(0.35, 1.0, 0.4)
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring = MeshInstance3D.new()
	_ring.mesh = ring
	_ring.material_override = m
	_ring.position = Vector3(0, 0.06, 0)
	_ring.visible = false
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


# --- flight (Phase 6) --------------------------------------------------------------
# Planes are simple and honest: straight lines to wherever they're sent,
# lazy circles once they arrive, banking into every turn. No pathfinding,
# no collision — the sky belongs to whoever holds it.

func _fly_step(dt: float) -> void:
	if not path.is_empty():
		var tgt: Vector3 = path[0]
		var to := Vector3(tgt.x - global_position.x, 0, tgt.z - global_position.z)
		if to.length() < 3.0:
			orbit_anchor = Vector3(tgt.x, 0, tgt.z)
			path.pop_front()
		else:
			vel = vel.move_toward(to.normalized() * speed, speed * 1.5 * dt)
	elif hovering:
		# a transport waiting on passengers must come to a full stop: the 6.5 m
		# idle orbit runs at ~0.72x speed, faster than the infantry chasing it
		vel = vel.move_toward(Vector3.ZERO, speed * 2.0 * dt)
	else:
		if orbit_anchor == Vector3.INF:
			orbit_anchor = Vector3(global_position.x, 0, global_position.z)
		# PATROL widens the circle so the plane sweeps ground for you
		var orad := orbit_radius()
		_orbit_a += dt * 0.09 * speed * (6.5 / orad)
		var op := orbit_anchor + Vector3(cos(_orbit_a) * orad, 0, sin(_orbit_a) * orad)
		var to2 := Vector3(op.x - global_position.x, 0, op.z - global_position.z)
		if to2.length() > 0.3:
			vel = vel.move_toward(to2.normalized() * speed * 0.72, speed * 1.6 * dt)

	global_position += Vector3(vel.x, 0, vel.z) * dt
	global_position.y = move_toward(global_position.y, 3.0 if hovering else ALT, 6.5 * dt)

	if vel.length() > 1.0:
		var prev := global_transform.basis
		var look := global_transform.looking_at(
			global_position + Vector3(vel.x, 0, vel.z).normalized(), Vector3.UP)
		global_transform.basis = prev.slerp(
			look.basis, minf(turn_speed * dt, 1.0)).orthonormalized()
		var turned := wrapf(prev.get_euler().y - global_transform.basis.get_euler().y,
			-PI, PI)
		_roll = lerpf(_roll, clampf(turned * 14.0, -0.85, 0.85), 5.0 * dt)
		_body.rotation.z = _roll
	if _prop:
		_prop.rotate_object_local(Vector3.UP, dt * 50.0)
	for p in _props:
		p.rotate_object_local(Vector3.UP, dt * 50.0)
	if _shadow:
		_shadow.global_position = Vector3(global_position.x, 0.06, global_position.z)
		_shadow.global_rotation = Vector3.ZERO
	_anim_t += dt


func _build_plane(col: Color) -> void:
	var hull := _mat(col.darkened(0.2), 0.65, 0.45)
	var dark := _mat(Color(0.11, 0.105, 0.11), 0.7, 0.35)
	var canvas := _mat(col.lightened(0.12), 0.9, 0.05)

	if kind == "kondor":
		# Karvath armored gunship: a flying slab with engine pods
		var fus := BoxMesh.new()
		fus.size = Vector3(0.9, 0.62, 2.6)
		_mesh(fus, hull, Vector3(0, 0, 0))
		var wing := BoxMesh.new()
		wing.size = Vector3(3.4, 0.1, 0.95)
		_mesh(wing, hull, Vector3(0, 0.16, 0.1))
		for wx in [-1.15, 1.15]:
			var pod := CapsuleMesh.new()
			pod.radius = 0.16
			pod.height = 0.85
			var p := _mesh(pod, dark, Vector3(wx, 0.02, -0.15))
			p.rotation_degrees = Vector3(90, 0, 0)
		var tail := BoxMesh.new()
		tail.size = Vector3(1.3, 0.08, 0.5)
		_mesh(tail, hull, Vector3(0, 0.2, 1.25))
		var fin := BoxMesh.new()
		fin.size = Vector3(0.08, 0.55, 0.5)
		_mesh(fin, hull, Vector3(0, 0.42, 1.25))
		var gun := CylinderMesh.new()
		gun.top_radius = 0.06
		gun.bottom_radius = 0.07
		gun.height = 0.8
		var g := _mesh(gun, dark, Vector3(0, -0.24, -1.35))
		g.rotation_degrees = Vector3(90, 0, 0)
	elif kind == "duster":
		# Ashfall crop-duster gone to war: skinny, patched, fixed gear
		var fus := BoxMesh.new()
		fus.size = Vector3(0.5, 0.5, 2.3)
		_mesh(fus, canvas, Vector3(0, 0.05, 0))
		var wing := BoxMesh.new()
		wing.size = Vector3(3.0, 0.07, 0.8)
		_mesh(wing, canvas, Vector3(0, -0.1, -0.2))
		var fin := BoxMesh.new()
		fin.size = Vector3(0.07, 0.5, 0.45)
		_mesh(fin, canvas, Vector3(0, 0.3, 1.1))
		for gx in [-0.4, 0.4]:
			var leg := CylinderMesh.new()
			leg.top_radius = 0.03
			leg.bottom_radius = 0.03
			leg.height = 0.4
			_mesh(leg, dark, Vector3(gx, -0.42, -0.5))
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.12
			wheel.bottom_radius = 0.12
			wheel.height = 0.08
			var wh := _mesh(wheel, dark, Vector3(gx, -0.62, -0.5))
			wh.rotation_degrees = Vector3(0, 0, 90)
	elif kind == "pelican":
		# Aurelian Pelican: unarmed air bridge — fat high-wing hauler, twin pods
		var fus := BoxMesh.new()
		fus.size = Vector3(1.05, 0.9, 3.0)
		_mesh(fus, hull, Vector3(0, 0.15, 0))
		var nose := CapsuleMesh.new()
		nose.radius = 0.5
		nose.height = 1.2
		var n := _mesh(nose, hull, Vector3(0, 0.15, -1.35))
		n.rotation_degrees = Vector3(90, 0, 0)
		var bay := BoxMesh.new()
		bay.size = Vector3(1.5, 0.62, 2.0)
		_mesh(bay, canvas, Vector3(0, -0.34, 0.1))
		var ramp := BoxMesh.new()
		ramp.size = Vector3(1.15, 0.08, 0.9)
		var rp := _mesh(ramp, dark, Vector3(0, -0.5, 1.2))
		rp.rotation_degrees = Vector3(25, 0, 0)
		# the RTS pitch flattens height onto depth: a tail over the rear fuselage
		# hides inside it, so the boom carries it far enough back to clear
		var boom := BoxMesh.new()
		boom.size = Vector3(0.62, 0.55, 1.2)
		_mesh(boom, hull, Vector3(0, 0.3, 2.05))
		var wing := BoxMesh.new()
		wing.size = Vector3(4.6, 0.14, 1.1)
		_mesh(wing, hull, Vector3(0, 0.66, -0.1))
		# the disc at -1.3 is the shared _prop; this material only dresses its twin
		var blur := _mat(Color(0.25, 0.24, 0.23, 0.55), 0.9, 0.0)
		blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for px in [-1.3, 1.3]:
			var pod := CapsuleMesh.new()
			pod.radius = 0.22
			pod.height = 1.3
			var p := _mesh(pod, dark, Vector3(px, 0.5, -0.45))
			p.rotation_degrees = Vector3(90, 0, 0)
			if px > 0.0:
				var disc := CylinderMesh.new()
				disc.top_radius = 0.5
				disc.bottom_radius = 0.5
				disc.height = 0.04
				var d := _mesh(disc, blur, Vector3(px, 0.5, -1.15))
				d.rotation_degrees = Vector3(90, 0, 0)
				d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fin3 := BoxMesh.new()
		fin3.size = Vector3(0.14, 1.3, 0.8)
		_mesh(fin3, hull, Vector3(0, 1.1, 2.25))
		var tail3 := BoxMesh.new()
		tail3.size = Vector3(2.0, 0.1, 0.62)
		_mesh(tail3, canvas, Vector3(0, 1.68, 2.3))
	elif kind == "wasp":
		# Aurelian Gyrocopter: stubby fuselage under a big horizontal rotor —
		# it used to render as a leftover biplane with wings it never had
		var fus_w := CapsuleMesh.new()
		fus_w.radius = 0.3
		fus_w.height = 1.7
		var fw := _mesh(fus_w, hull, Vector3(0, 0, 0.05))
		fw.rotation_degrees = Vector3(90, 0, 0)
		var mast := BoxMesh.new()
		mast.size = Vector3(0.08, 0.5, 0.08)
		_mesh(mast, dark, Vector3(0, 0.45, 0))
		var rotor := CylinderMesh.new()
		rotor.top_radius = 1.35
		rotor.bottom_radius = 1.35
		rotor.height = 0.03
		rotor.radial_segments = 24
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.25, 0.24, 0.23, 0.4)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var rot_mi := MeshInstance3D.new()
		rot_mi.mesh = rotor
		rot_mi.material_override = rm
		rot_mi.position = Vector3(0, 0.72, 0)
		rot_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(rot_mi)
		var boom := BoxMesh.new()
		boom.size = Vector3(0.1, 0.1, 1.1)
		_mesh(boom, hull, Vector3(0, 0.1, 1.0))
		var fin_w := BoxMesh.new()
		fin_w.size = Vector3(0.06, 0.4, 0.35)
		_mesh(fin_w, hull, Vector3(0, 0.32, 1.45))
	elif kind == "seraph":
		# Luminar Seraph: clean monoplane, violet canopy, wingtip arc orbs
		var fus_s := CapsuleMesh.new()
		fus_s.radius = 0.26
		fus_s.height = 2.3
		var fs := _mesh(fus_s, hull, Vector3(0, 0, 0.1))
		fs.rotation_degrees = Vector3(90, 0, 0)
		var wing_s := BoxMesh.new()
		wing_s.size = Vector3(2.6, 0.06, 0.7)
		_mesh(wing_s, hull, Vector3(0, 0.18, -0.2))
		var fin_s := BoxMesh.new()
		fin_s.size = Vector3(0.07, 0.5, 0.42)
		_mesh(fin_s, hull, Vector3(0, 0.3, 1.2))
		var canopy := SphereMesh.new()
		canopy.radius = 0.17
		canopy.height = 0.26
		canopy.radial_segments = 10
		canopy.rings = 5
		_mesh(canopy, _mat(Color(0.55, 0.42, 0.85), 0.2, 0.6), Vector3(0, 0.24, -0.35))
		for ox in [-1.32, 1.32]:
			_add_piece("orb", _kit_mat("arc"), Vector3(ox, 0.18, -0.2))
	else:
		# Aurelian Sparrowhawk fallback: sleek biplane (glb normally wins)
		var fus := CapsuleMesh.new()
		fus.radius = 0.26
		fus.height = 2.2
		var f := _mesh(fus, hull, Vector3(0, 0, 0.1))
		f.rotation_degrees = Vector3(90, 0, 0)
		for wy in [-0.12, 0.42]:
			var wing := BoxMesh.new()
			wing.size = Vector3(2.7, 0.06, 0.72)
			_mesh(wing, canvas, Vector3(0, wy, -0.25))
		for sx in [-1.0, 1.0]:
			var strut := BoxMesh.new()
			strut.size = Vector3(0.05, 0.55, 0.05)
			_mesh(strut, dark, Vector3(sx, 0.15, -0.25))
		var fin2 := BoxMesh.new()
		fin2.size = Vector3(0.07, 0.45, 0.4)
		_mesh(fin2, hull, Vector3(0, 0.28, 1.15))
		var tail2 := BoxMesh.new()
		tail2.size = Vector3(1.0, 0.06, 0.4)
		_mesh(tail2, hull, Vector3(0, 0.08, 1.15))

	# shared: cockpit, spinning prop disc, ground shadow
	var pit_pos := Vector3(0, 0.28, -0.3)
	var prop_pos := Vector3(0, 0, -1.45)
	var sh_size := Vector2(1.9, 2.3)
	if kind == "kondor":
		pit_pos = Vector3(0, 0.4, -0.7)
		prop_pos = Vector3(0, 0, -1.5)
	elif kind == "pelican":
		# _prop rides the port pod; the starboard disc is a static twin
		pit_pos = Vector3(0, 0.62, -1.2)
		prop_pos = Vector3(-1.3, 0.5, -1.15)
		sh_size = Vector2(3.4, 4.0)
	elif kind == "wasp":
		# a gyro pushes: the prop sits behind the cabin, not floating off the nose
		prop_pos = Vector3(0, 0.05, 0.98)

	# the seraph's violet canopy IS its cockpit — the default dark pit sphere
	# sat 0.06 m away and swallowed it
	if kind != "seraph":
		var pit := SphereMesh.new()
		pit.radius = 0.16
		pit.height = 0.24
		_mesh(pit, dark, pit_pos)
	var prop_mesh := CylinderMesh.new()
	prop_mesh.top_radius = 0.5
	prop_mesh.bottom_radius = 0.5
	prop_mesh.height = 0.04
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.25, 0.24, 0.23, 0.55)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_prop = MeshInstance3D.new()
	_prop.mesh = prop_mesh
	_prop.material_override = pm
	_prop.rotation_degrees = Vector3(90, 0, 0)
	_prop.position = prop_pos
	_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_prop)

	var sh_mesh := PlaneMesh.new()
	sh_mesh.size = sh_size
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.3)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow = MeshInstance3D.new()
	_shadow.mesh = sh_mesh
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)


# --- Phase 9: the superunits --------------------------------------------------------

func _build_juggernaut(col: Color) -> void:
	body_height = 2.6
	var hull_m := _mat(col.darkened(0.3), 0.55, 0.55)
	var dark := _mat(Color(0.1, 0.095, 0.1), 0.7, 0.4)
	var steel := _mat(Color(0.32, 0.32, 0.35), 0.45, 0.75)

	var hull := BoxMesh.new()
	hull.size = Vector3(2.8, 1.1, 4.4)
	_mesh(hull, hull_m, Vector3(0, 0.85, 0))
	for tx in [-1.55, 1.55]:
		var track := BoxMesh.new()
		track.size = Vector3(0.55, 0.8, 4.6)
		_mesh(track, dark, Vector3(tx, 0.45, 0))
	for tz in [-0.9, 0.9]:
		var tur := BoxMesh.new()
		tur.size = Vector3(1.5, 0.6, 1.7)
		_mesh(tur, hull_m, Vector3(0, 1.7, tz))
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.1
		barrel.bottom_radius = 0.13
		barrel.height = 2.2
		var bmi := _mesh(barrel, steel, Vector3(0, 1.78, tz - 1.7))
		bmi.rotation_degrees = Vector3(90, 0, 0)
	for sx in [-0.9, 0.9]:
		var stack := CylinderMesh.new()
		stack.top_radius = 0.1
		stack.bottom_radius = 0.14
		stack.height = 0.9
		_mesh(stack, dark, Vector3(sx, 1.8, 1.9))


func _build_ashworm(col: Color) -> void:
	body_height = 2.2
	var scrap := _mat(col.darkened(0.25), 0.85, 0.3)
	var dark := _mat(Color(0.11, 0.1, 0.1), 0.8, 0.3)
	var rust := _mat(Color(0.38, 0.22, 0.13), 0.85, 0.2)

	var z := -1.7
	for i in range(3):
		var car := BoxMesh.new()
		car.size = Vector3(1.6, 1.2 if i == 0 else 1.0, 1.5)
		_mesh(car, scrap if i != 0 else rust, Vector3(0, 0.85, z))
		for wx in [-0.9, 0.9]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.32
			wheel.bottom_radius = 0.32
			wheel.height = 0.2
			var wmi := _mesh(wheel, dark, Vector3(wx, 0.35, z))
			wmi.rotation_degrees = Vector3(0, 0, 90)
		if i > 0:
			var link := BoxMesh.new()
			link.size = Vector3(0.3, 0.25, 0.5)
			_mesh(link, dark, Vector3(0, 0.7, z + 0.95))
		z += 1.75
	var gun := CylinderMesh.new()
	gun.top_radius = 0.11
	gun.bottom_radius = 0.14
	gun.height = 1.6
	var g := _mesh(gun, dark, Vector3(0, 1.7, -2.4))
	g.rotation_degrees = Vector3(75, 0, 0)
	var stack := CylinderMesh.new()
	stack.top_radius = 0.12
	stack.bottom_radius = 0.16
	stack.height = 1.0
	_mesh(stack, dark, Vector3(0.4, 1.9, -1.7))


func _build_zeppelin(col: Color, holy: bool) -> void:
	body_height = 2.4
	var skin := _mat(Color(0.78, 0.78, 0.82) if holy else col.darkened(0.1), 0.6, 0.2)
	var dark := _mat(Color(0.13, 0.125, 0.13), 0.7, 0.35)

	var env_mesh := CapsuleMesh.new()
	env_mesh.radius = 1.1
	env_mesh.height = 5.6
	var env := _mesh(env_mesh, skin, Vector3(0, 0.6, 0))
	env.rotation_degrees = Vector3(90, 0, 0)

	var gondola := BoxMesh.new()
	gondola.size = Vector3(0.8, 0.6, 2.2)
	_mesh(gondola, dark, Vector3(0, -0.7, 0.2))

	for fz in [[0.06, 0.9, 1.0], [0.9, 0.06, 1.0]]:
		var fin := BoxMesh.new()
		fin.size = Vector3(fz[0] * 2.2, fz[1] * 2.2, 0.8)
		_mesh(fin, skin, Vector3(0, 0.6, 2.6))

	for px in [-1.3, 1.3]:
		var pod := CapsuleMesh.new()
		pod.radius = 0.18
		pod.height = 0.9
		var p := _mesh(pod, dark, Vector3(px, -0.1, -0.4))
		p.rotation_degrees = Vector3(90, 0, 0)

	if holy:
		var arc_mat := _mat(Color(0.66, 0.5, 1.0), 0.4, 0.1)
		arc_mat.emission_enabled = true
		arc_mat.emission = Color(0.6, 0.42, 1.0)
		arc_mat.emission_energy_multiplier = 2.4
		for sz in [-1.4, 0.0, 1.4]:
			var spire := CylinderMesh.new()
			spire.top_radius = 0.03
			spire.bottom_radius = 0.1
			spire.height = 0.9
			_mesh(spire, dark, Vector3(0, 1.9, sz))
			var orb := SphereMesh.new()
			orb.radius = 0.14
			orb.height = 0.28
			_mesh(orb, arc_mat, Vector3(0, 2.4, sz))


# --- the Blender model pass ---------------------------------------------------------
# One master .glb per battlefield role; every faction wears its own color on
# the same silhouette via the "unit_tint" material (named so in Blender).

const GLB_KINDS := {
	"bastion": "tank", "warpig": "tank", "pavise": "tank",
	"iron_guard": "soldier", "conscript": "soldier", "sky_marine": "soldier",
	"arc_templar": "soldier", "grenadier": "soldier", "sapper": "soldier",
	"rocketeer": "soldier", "lance_warden": "soldier", "vulture": "soldier",
	"mule": "harvester", "magpie": "harvester", "dray": "harvester",
	"collector": "harvester",
	"sparrowhawk": "biplane",
	"outrider": "scout", "dart": "scout", "rat": "scout",
}


var custom_model := false    # a per-kind Hunyuan model: skip procedural dress


# A pipeline hull carries no "Prop" child, so the first Hunyuan aircraft flew
# with a dead nose while the old procedural planes kept spinning. These rebuild
# the discs from the baked hull's OWN bounds: each entry is a position given as
# a fraction of that AABB — so it tracks the model instead of a fixed guess that
# would drift the moment a mesh is re-carved — plus a radius in metres and
# whether the disc lies flat (rotorcraft) or stands upright (tractor/pusher).
# The two fractions that position the disc ACROSS the airframe are given here;
# the third is solved against the mesh, because a disc placed by guesswork ends
# up buried inside the engine pod it is supposed to sit in front of.
#   "front" = tractor, disc stands upright ahead of the nose/nacelle
#   "rear"  = pusher, upright behind the tail/pod
#   "top"   = rotor, disc lies flat above the cabin
const CUSTOM_PROPS := {
	"sparrowhawk": [[Vector3(0.50, 0.52, 0.0), 0.46, "front"]],
	"pelican": [[Vector3(0.24, 0.66, 0.0), 0.42, "front"],
		[Vector3(0.76, 0.66, 0.0), 0.42, "front"]],
	"kondor": [[Vector3(0.50, 0.45, 0.0), 0.50, "front"]],
	"duster": [[Vector3(0.50, 0.45, 0.0), 0.50, "front"]],
	"seraph": [[Vector3(0.50, 0.40, 0.0), 0.34, "rear"]],
	"wasp": [[Vector3(0.50, 0.0, 0.40), 1.30, "top"]],
	"leviathan": [[Vector3(0.16, 0.26, 0.0), 0.34, "rear"],
		[Vector3(0.84, 0.26, 0.0), 0.34, "rear"]],
}


# Widen the search until real geometry turns up. A fixed box is a silent
# failure mode: the Pelican's wing simply was not where the first guess looked,
# and both its roundels vanished with no error to explain it.
#
# Returns the WINNING VERTEX, not just its picked coordinate. Returning the
# coordinate alone was the subtler version of the same bug — once the box had
# to widen, the caller kept its original target and pinned the quad beside the
# wing at the wing's height, which is how the roundels ended up hovering over
# open ground next to the aircraft.
static func _probe(verts: PackedVector3Array, ua: float, ub: float,
		axis_a: int, axis_b: int, pick: int, want_max: bool) -> Vector3:
	for grow: float in [1.0, 2.0, 4.0]:
		var span: float = 0.28 * grow
		var best := -INF
		var win := Vector3.INF
		for v in verts:
			if absf(v[axis_a] - ua) <= span and absf(v[axis_b] - ub) <= span:
				var s: float = v[pick] * (1.0 if want_max else -1.0)
				if s > best:
					best = s
					win = v
		if best > -INF:
			return win
	return Vector3.INF


func _custom_prop(hull: AABB, verts: PackedVector3Array) -> void:
	var spec: Array = CUSTOM_PROPS.get(kind, [])
	if spec.is_empty() or verts.is_empty():
		return
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.22, 0.21, 0.20, 0.62)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for entry in spec:
		var frac: Vector3 = entry[0]
		var mode := String(entry[2])
		var px: float = hull.position.x + hull.size.x * frac.x
		var pos := Vector3.ZERO
		if mode == "top":
			var tz: float = hull.position.z + hull.size.z * frac.z
			var top := _probe(verts, px, tz, 0, 2, 1, true)
			if top == Vector3.INF:
				continue
			pos = top + Vector3(0, 0.12, 0)
		else:
			var ty: float = hull.position.y + hull.size.y * frac.y
			var fwd := mode == "front"
			var edge := _probe(verts, px, ty, 0, 1, 2, not fwd)
			if edge == Vector3.INF:
				continue
			pos = edge + Vector3(0, 0, -0.05 if fwd else 0.05)
		var disc := CylinderMesh.new()
		disc.top_radius = float(entry[1])
		disc.bottom_radius = float(entry[1])
		disc.height = 0.04
		disc.radial_segments = 20
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = pm
		mi.position = pos
		if mode != "top":
			mi.rotation_degrees = Vector3(90, 0, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(mi)
		_props.append(mi)


func _try_glb(col: Color) -> bool:
	# A model named for the KIND beats the shared class chassis: this is the
	# hook the Crownhold-pipeline upgrade drops assets into, one unit at a
	# time, without touching the units that still share the old models.
	var model: String = GLB_KINDS.get(kind, "")
	var path := "res://models/unit_%s.glb" % kind
	if ResourceLoader.exists(path):
		model = kind
		custom_model = true
	else:
		if model == "":
			return false
		path = "res://models/unit_%s.glb" % model
		if not ResourceLoader.exists(path):
			return false
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	_body.add_child(inst)
	# Merge the hull into ONE mesh grouped by material: these models are ~30-45
	# separate MeshInstance3Ds, and each was its own draw call on every unit.
	# The baked node is parented to the glb root so it inherits the same
	# axis-conversion transform the originals had.
	var baked := _bake_vehicle_mesh(model, faction, inst, custom_model)
	if baked != null:
		var merged := MeshInstance3D.new()
		merged.mesh = baked
		_merged = merged        # step() feeds the track shader through this
		inst.add_child(merged)
		for child in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi != merged and _bakeable(String(mi.name)):
				mi.queue_free()          # its geometry now lives in the merge
		if flying:
			_prop = inst.find_child("Prop", true, false) as MeshInstance3D
			var sh := Vector2(1.9, 2.3)
			if custom_model:
				# the fixed patch was sized for the old shared chassis — a
				# Leviathan would otherwise cast a fighter's shadow
				var hull := inst.transform * baked.get_aabb()
				_custom_prop(hull, _hull_verts())
				sh = Vector2(hull.size.x, hull.size.z) * 0.85
			_make_shadow(sh)
		return true
	_apply_tint(inst, col)
	if flying:
		_prop = inst.find_child("Prop", true, false) as MeshInstance3D
		_make_shadow()
	return true


static var _tint_cache := {}          # "%d|%d" % [src material id, faction] -> Material
static var _relief_cache := {}        # same key -> a material wearing scanned plate
static var _squad_tint_cache := {}    # plain tints for the baked infantry mesh
static var _squad_walk_cache := {}    # source material id -> gait ShaderMaterial


# Buildings have worn scanned Poly Haven plate since the texture round; units
# never did, so an army of flat-colour hulls sat in front of buildings covered
# in rivets and corrugation. This borrows the same normal/roughness maps.
#
# OBJECT-space triplanar, not world: a world-space projection is right for
# terrain and buildings because they never move, but on a driving tank the
# grain would swim across the hull as it crosses the map.
static func _unit_relief(src: BaseMaterial3D, faction: int) -> BaseMaterial3D:
	var key := "%d|%d" % [src.get_instance_id(), faction]
	if _relief_cache.has(key):
		return _relief_cache[key]
	var plate: String = EFBuildings.FAC_PLATE.get(faction, "rusty_metal_02")
	var npath := "res://textures/%s_nor_gl.jpg" % plate
	var rpath := "res://textures/%s_Rough.jpg" % plate
	if not ResourceLoader.exists(npath):
		# still honour baked AO even without a plate texture to add
		var plain: BaseMaterial3D = src.duplicate()
		plain.vertex_color_use_as_albedo = true
		_relief_cache[key] = plain
		return plain
	var d: BaseMaterial3D = src.duplicate()
	# Pipeline models carry ambient occlusion baked into COLOR_0. Without this
	# the flat faction tint swallows every panel line and rivet the concept art
	# carved, and the unit reads as one coloured blob from the RTS camera.
	d.vertex_color_use_as_albedo = true
	d.normal_enabled = true
	d.normal_texture = load(npath)
	d.normal_scale = 0.55             # gentler than a building: these are small
	if ResourceLoader.exists(rpath):
		d.roughness_texture = load(rpath)
	d.uv1_triplanar = true
	d.uv1_world_triplanar = false
	d.uv1_scale = Vector3(3.0, 3.0, 3.0)
	_relief_cache[key] = d
	return d


# Called on every scene (re)load: the cache keys are source-material instance
# ids, which are NOT stable across reloads — a stale entry could even collide
# with a recycled id and hand a unit the wrong faction's paint.
static func reset_visual_caches() -> void:
	_tint_cache.clear()
	_squad_mesh_cache.clear()
	_relief_cache.clear()
	_squad_tint_cache.clear()
	_veh_mesh_cache.clear()


# ============================ SQUAD INFANTRY ==================================
# An infantry "unit" is a section of six men that lives and dies as one. The men
# are cosmetic — one hp pool, one weapon, one rate of fire — but the section
# visibly thins as it takes losses and re-forms as it heals at base.
#
# The trick that makes this CHEAPER than the single soldier it replaces: the
# soldier .glb is 27 separate MeshInstance3Ds, so it was costing 27 draws per
# man. Bake those into ONE mesh grouped by material (9 surfaces), hand it to a
# MultiMesh, and six men cost 9 instanced draws instead of 162.

const SQUAD_N := 6
# Widened ~1.4x from the original huddle: six 1.75 m men stood inside a
# 0.6 m circle, which read as penguins jostling on one spot. The section now
# occupies ~1.0 m — still overflowing its collision radius on purpose (a squad
# IS a crowd), with _separate giving inf pairs extra room so two sections
# no longer merge into a single mass on the march.
const SQUAD_OFFS: Array[Vector2] = [
	Vector2(0.0, -0.48), Vector2(-0.42, -0.20), Vector2(0.42, -0.20),
	Vector2(-0.21, 0.20), Vector2(0.21, 0.20), Vector2(0.0, 0.52),
]

static var _squad_mesh_cache := {}

var _squad_mm: MultiMeshInstance3D = null
const STRIDE_LEN := 0.62        # metres of ground per leg swing
var _gait := 0.0                # gait phase, advanced by distance travelled
var _gait_amt := 0.0            # 0 standing, 1 striding — eased so halts settle
var _squad_order: Array[int] = []       # which slot dies first — stable per unit
var _squad_fall: Array[float] = []      # 0 = standing, 1 = fallen
var _squad_jitter: Array[Vector3] = []  # x, z, yaw wobble so six men differ
var _squad_phase: Array[float] = []     # bob phase per man
var _squad_alive := SQUAD_N
var _squad_spread := 1.0
var _squad_t := 0.0
var _fire_kick := 0.0                   # 1 at the muzzle flash, gone in ~0.3 s


func squad_alive() -> int:
	return _squad_alive


func squad_fire_kick() -> void:
	_fire_kick = 1.0


# The walk lives in squad_walk.gdshader, driven by UV limb tags and
# INSTANCE_CUSTOM — so a section is only animated if its surfaces actually RUN
# that shader. The bake used to hand out plain StandardMaterial3Ds, which is
# why a marching section stayed rigid: the gait pipeline existed end to end,
# and no material ever executed it.
static func _squad_walk_wrap(src: Material) -> Material:
	var key := src.get_instance_id()
	if _squad_walk_cache.has(key):
		return _squad_walk_cache[key]
	var sh := load("res://squad_walk.gdshader") as Shader
	if sh == null or not (src is BaseMaterial3D):
		return src
	var b := src as BaseMaterial3D
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", b.albedo_color)
	m.set_shader_parameter("rough", b.roughness)
	m.set_shader_parameter("metal", b.metallic)
	if b.emission_enabled:
		m.set_shader_parameter("emission_col", b.emission)
		m.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
	_squad_walk_cache[key] = m
	return m


static var _squad_role_cache := {}


# The helmet/boots/kit materials for pipeline soldiers. The helmet wears the
# faction ACCENT — Aurelia's brass, Luminar's pale enamel — which is what makes
# a 27-px figure read as belonging to its concept instead of being one flat
# colour poured over a statue.
static func _squad_role_mat(role: String, fac: int) -> Material:
	var key := "%s|%d" % [role, fac]
	if _squad_role_cache.has(key):
		return _squad_role_cache[key]
	var f: Dictionary = EFWorld.FACTIONS.get(fac, EFWorld.FACTIONS[1])
	var m := StandardMaterial3D.new()
	match role:
		"trim":
			m.albedo_color = f.get("accent", Color(0.6, 0.6, 0.6))
			# half the vehicle trim's metal: a helmet is painted steel, not
			# polished brightwork, and full mirror flashed white at squad size
			m.metallic = float(f.get("acc_metal", 0.6)) * 0.5
			m.roughness = maxf(0.5, float(f.get("acc_rough", 0.5)))
		"boot":
			m.albedo_color = Color(0.11, 0.10, 0.095)
			m.roughness = 0.9
		_:
			m.albedo_color = Color(0.22, 0.22, 0.23)
			m.metallic = 0.55
			m.roughness = 0.5
	_squad_role_cache[key] = m
	return m


static func _bake_squad_mesh(fac: int, variant: String) -> ArrayMesh:
	"""Merge the soldier glb's many nodes into one mesh, grouped by material,
	with the faction dress pieces baked in so squad men keep their identity."""
	var key := "%d|%s" % [fac, variant]
	if _squad_mesh_cache.has(key):
		return _squad_mesh_cache[key]
	# A per-faction pipeline soldier wins over the shared hand-built one. Its
	# limbs are already tagged in UV2 by the prep script (a Hunyuan mesh is a
	# single object, so there are no SD_Leg / SD_Arm node names to read), and
	# _append_limb honours that tagging instead of overwriting it.
	var fac_name: String = String(EFWorld.FACTIONS[fac]["name"]).to_lower()
	var path := "res://models/unit_soldier_%s.glb" % fac_name
	var pre_tagged := ResourceLoader.exists(path)
	if not pre_tagged:
		path = "res://models/unit_soldier.glb"
	if not ResourceLoader.exists(path):
		return null
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var col: Color = EFWorld.hull_of(fac)

	# group every surface by the material it uses, carrying its node transform
	var groups := {}                     # Material -> Array[[Mesh, surf, xform]]
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(si)
			if mat == null:
				continue
			var lname := mat.resource_name.to_lower()
			if pre_tagged and lname == "" and si < CUSTOM_SLOT_ROLE.size():
				# the importer drops names on these glbs (seen on vehicles:
				# 'u_track' arrived as '') — fall back to the slot convention
				lname = ("u_" + CUSTOM_SLOT_ROLE[si]) if si > 0 else "unit_tint"
			var use_mat: Material = mat
			if "tint" in lname:
				# A SEPARATE cache from _tint_cache on purpose. That one now
				# carries normal-mapped relief for vehicles, and a normal map
				# needs TANGENTS — which SurfaceTool.append_from + commit does
				# not generate. Feeding it in here rendered every section as
				# Godot's magenta/white missing-texture checkerboard.
				var tkey := "%d|%d" % [mat.get_instance_id(), fac]
				if not _squad_tint_cache.has(tkey):
					var dup: Material = mat.duplicate()
					if dup is BaseMaterial3D:
						(dup as BaseMaterial3D).albedo_color = col.darkened(0.12)
					_squad_tint_cache[tkey] = dup
				use_mat = _squad_tint_cache[tkey]
			elif pre_tagged and lname.begins_with("u_trim"):
				use_mat = _squad_role_mat("trim", fac)
			elif pre_tagged and lname.begins_with("u_track"):
				use_mat = _squad_role_mat("boot", fac)
			elif pre_tagged and lname.begins_with("u_steel"):
				use_mat = _squad_role_mat("steel", fac)
			else:
				# Pull the pale kit down and lift the near-black helmet. A man is
				# only ~27 px tall from the RTS camera, and that much contrast
				# inside one figure hard-edges into blocks at that size.
				var ckey := "sq|%s|%d" % [mat.resource_name, fac]
				if not _squad_tint_cache.has(ckey):
					var cd: Material = mat.duplicate()
					if cd is BaseMaterial3D:
						var bm := cd as BaseMaterial3D
						var a := bm.albedo_color
						var lum := a.r * 0.30 + a.g * 0.59 + a.b * 0.11
						# pull every shade toward mid grey, keeping its hue
						var t := 0.34 if lum > 0.5 else 0.26
						bm.albedo_color = a.lerp(Color(0.42, 0.40, 0.38), t)
					_squad_tint_cache[ckey] = cd
				use_mat = _squad_tint_cache[ckey]
			# the lance warden's rifle glows instead of a runtime find_child
			if variant == "lance_warden" and "rifle" in String(mi.name).to_lower():
				use_mat = _kit_mat("arc")
			# a plain material would leave this surface rigid mid-march
			if pre_tagged:
				use_mat = _squad_walk_wrap(use_mat)
			if not groups.has(use_mat):
				groups[use_mat] = []
			groups[use_mat].append([mi.mesh, si, mi.transform, mi.name])

	var out := ArrayMesh.new()
	for mat2 in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry in groups[mat2]:
			var e: Array = entry
			# append_from, NOT the hand-rolled limb walker below: emitting the
			# vertices manually to stamp UV2 limb tags rendered every section as
			# a black-and-white checkerboard, and four different fixes (normals,
			# winding, buffer layout, material conversion) all failed to explain
			# it. Reverted to the known-good path until that is understood; the
			# gait shader and _append_limb are left in place for that work.
			st.append_from(e[0] as Mesh, int(e[1]), e[2] as Transform3D)
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat2 as Material)
	inst.queue_free()
	_squad_mesh_cache[key] = out
	return out


# Which limb a part belongs to, from its node name, and the height it pivots
# about. Grouping by MATERIAL alone could never carry this — the legs and the
# helmet share u_dark — so it has to travel per-vertex, in UV2.
const HIP_Y := 0.565
const SHOULDER_Y := 0.95


static func _limb_of(node_name: String, xform: Transform3D) -> Vector2:
	var n := node_name.to_lower()
	var left: bool = xform.origin.x < 0.0
	if n.begins_with("sd_leg") or n.begins_with("sd_boot") or n.begins_with("sd_puttee"):
		return Vector2(1.0 if left else 2.0, HIP_Y)
	if n.begins_with("sd_arm") or n.begins_with("sd_hand") or n.begins_with("sd_rifle"):
		# the rifle is carried, so it must swing with the arms or it detaches
		return Vector2(3.0 if left else 4.0, SHOULDER_Y)
	return Vector2(0.0, 0.0)


static var _veh_mesh_cache := {}      # "model|faction" -> baked ArrayMesh
static var _track_shader_mat: ShaderMaterial = null


static func _track_mat() -> Material:
	# one shared material for every tracked hull; per-unit motion comes from
	# the track_scroll INSTANCE uniform, so sharing costs nothing
	if _track_shader_mat == null:
		var sh := load("res://track_scroll.gdshader") as Shader
		if sh == null:
			return null
		_track_shader_mat = ShaderMaterial.new()
		_track_shader_mat.shader = sh
	return _track_shader_mat

# Nodes that MOVE independently and therefore cannot be baked into the hull:
# a propeller has to spin, so it stays its own MeshInstance3D.
const NO_BAKE := ["prop", "rotor", "blade"]


static func _bakeable(node_name: String) -> bool:
	var n := node_name.to_lower()
	for s in NO_BAKE:
		if s in n:
			return false
	return true


# The same merge the infantry already use, generalised to the vehicle models.
# A tank .glb is ~45 separate MeshInstance3Ds, so every tank on the field cost
# 45 draw calls; grouped by material it is 6-9. The propeller is left alone.
# Per-kind pipeline models carry no UVs and their material names can be lost
# by the importer — but their PREP SCRIPT guarantees the slot order, so role
# is derived from the surface index instead of the name.
const CUSTOM_SLOT_ROLE := ["tint", "track", "steel", "trim"]


static var _gunmetal: StandardMaterial3D


# Slot 2 is the gun barrel, and a barrel is dark oiled steel on every banner's
# concept art — it is NOT the faction accent. Keeping it neutral is what lets
# the brass in slot 3 actually read as trim.
static func _gunmetal_mat() -> StandardMaterial3D:
	if _gunmetal == null:
		_gunmetal = StandardMaterial3D.new()
		_gunmetal.albedo_color = Color(0.19, 0.19, 0.20)
		_gunmetal.metallic = 0.80
		_gunmetal.roughness = 0.42
		_gunmetal.vertex_color_use_as_albedo = true
	return _gunmetal


static var _accent_cache := {}


# The steel slot used to inherit Blender's generic grey, identical on all four
# banners — so Aurelia's brass, the single most recognisable thing in its
# concept art, existed nowhere in the game. Each faction now gets its own metal.
static func _accent_mat(fac: int) -> StandardMaterial3D:
	if _accent_cache.has(fac):
		return _accent_cache[fac]
	var f: Dictionary = EFWorld.FACTIONS.get(fac, EFWorld.FACTIONS[1])
	var m := StandardMaterial3D.new()
	m.albedo_color = f.get("accent", Color(0.32, 0.32, 0.34))
	m.metallic = float(f.get("acc_metal", 0.7))
	m.roughness = float(f.get("acc_rough", 0.45))
	m.metallic_specular = 0.75
	# vertex colours carry the baked AO; without this the trim ignores every
	# crevice the AO pass darkened and floats off the hull
	m.vertex_color_use_as_albedo = true
	if fac == 4:
		# arc-tech: the Covenant's trim is powered, not just polished
		m.emission_enabled = true
		m.emission = f.get("accent", Color.WHITE)
		m.emission_energy_multiplier = 0.35
	_accent_cache[fac] = m
	return m


static func _bake_vehicle_mesh(model: String, fac: int, src_root: Node3D,
		custom := false) -> ArrayMesh:
	var key := "%s|%d" % [model, fac]
	if _veh_mesh_cache.has(key):
		return _veh_mesh_cache[key]
	var col: Color = EFWorld.hull_of(fac)
	var groups := {}
	for child in src_root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null or not _bakeable(String(mi.name)):
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(si)
			if mat == null:
				continue
			var use_mat: Material = mat
			if mat is BaseMaterial3D:
				var lname := mat.resource_name.to_lower()
				if custom and lname == "" and si < CUSTOM_SLOT_ROLE.size():
					# Godot's import dropped the name (observed: 'u_track'
					# arrived as '') — fall back to the slot convention
					lname = "u_" + CUSTOM_SLOT_ROLE[si]
					if si == 0:
						lname = "unit_tint"
				if "tint" in lname:
					var tkey := "veh|%d|%d" % [mat.get_instance_id(), fac]
					if not _tint_cache.has(tkey):
						var dup: Material = mat.duplicate()
						(dup as BaseMaterial3D).albedo_color = col.darkened(0.12)
						_tint_cache[tkey] = _unit_relief(dup as BaseMaterial3D, fac)
					use_mat = _tint_cache[tkey]
				elif lname.begins_with("u_track"):
					var tm := _track_mat()
					use_mat = tm if tm != null \
						else _unit_relief(mat as BaseMaterial3D, fac)
				elif lname.begins_with("u_trim"):
					use_mat = _accent_mat(fac)
				elif lname.begins_with("u_steel") or lname.begins_with("u_dark"):
					use_mat = _gunmetal_mat()
				# -v only: this fires once per distinct (model, faction) pair and
				# is how the stale-import bug was caught — the game was loading a
				# 3-surface cache of a 4-surface file, so every visual A/B before
				# it was comparing meshes that had never reached the renderer.
				if custom and OS.is_stdout_verbose():
					var alb := "n/a"
					if use_mat is BaseMaterial3D:
						alb = str((use_mat as BaseMaterial3D).albedo_color)
					print("[slot %s] surf %d raw '%s' lname '%s' -> albedo %s"
						% [key, si, mat.resource_name, lname, alb])
			if not groups.has(use_mat):
				groups[use_mat] = []
			groups[use_mat].append([mi.mesh, si, mi.transform])
	if custom and OS.is_stdout_verbose() == false:
		print("[bake %s] groups=%d nodes_walked=%d" % [key, groups.size(),
			src_root.find_children("*", "MeshInstance3D", true, false).size()])
	if groups.is_empty():
		return null
	var out := ArrayMesh.new()
	for mat2 in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var has_uv := true
		for entry in groups[mat2]:
			var e: Array = entry
			st.append_from(e[0] as Mesh, int(e[1]), e[2] as Transform3D)
			var arrs: Array = (e[0] as Mesh).surface_get_arrays(int(e[1]))
			if arrs[Mesh.ARRAY_TEX_UV] == null:
				has_uv = false
		# Normal maps without tangents render as garbage, so tangents are
		# generated — but ONLY when the source has UVs to derive them from.
		# Hunyuan meshes ship POSITION+NORMAL only, and calling this on them
		# throws, which silently aborted the whole bake: the pilot tank fell
		# back to flat tint and the region materials never appeared. Their
		# relief is object-space triplanar, which needs neither UVs nor
		# tangents, so skipping is correct, not a compromise.
		if has_uv:
			st.generate_tangents()
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat2 as Material)
	_veh_mesh_cache[key] = out
	return out


static func _append_limb(st: SurfaceTool, mesh: Mesh, surf: int, xform: Transform3D,
		node_name: String) -> void:
	# SurfaceTool.append_from cannot inject an attribute the source lacks, so the
	# arrays are walked by hand to stamp UV2 with the limb tag.
	var arrays := mesh.surface_get_arrays(surf)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return
	# these three are null, not empty, on a surface that lacks the attribute —
	# assigning null straight into a typed Packed*Array is a runtime error
	var norms := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		norms = arrays[Mesh.ARRAY_NORMAL]
	var uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	var tag := _limb_of(node_name, xform)
	var basis := xform.basis
	var order: PackedInt32Array = idx
	if order.is_empty():
		order = PackedInt32Array()
		for i in range(verts.size()):
			order.append(i)
	# A mirrored part (the left boot, arm, puttee...) has a negative-determinant
	# basis, which REVERSES triangle winding. SurfaceTool.append_from fixes that
	# for you; emitting vertices by hand does not, so those parts rendered
	# inside-out under cull_back and the whole section looked like a black and
	# white checkerboard.
	var flip: bool = basis.determinant() < 0.0
	var tris := order.size() / 3
	for t in range(tris):
		for c in range(3):
			var vi: int = order[t * 3 + (2 - c if flip else c)]
			if norms.size() > vi:
				st.set_normal((basis * norms[vi]).normalized())
			if uvs.size() > vi:
				st.set_uv(uvs[vi])
			st.set_uv2(tag)
			st.add_vertex(xform * verts[vi])


static var _walk_mat_cache := {}


static func _walk_mat(src: Material) -> Material:
	# A MultiMeshInstance3D has no per-surface override, so the gait cannot live
	# in a material_override without flattening every colour on the model. Each
	# surface material becomes a ShaderMaterial instead, carrying its own colour
	# into the shared walk shader.
	var key := str(src.get_instance_id())
	if _walk_mat_cache.has(key):
		return _walk_mat_cache[key]
	var sh: Shader = load("res://squad_walk.gdshader")
	if sh == null or not (src is BaseMaterial3D):
		push_warning("squad walk shader missing — falling back to flat materials")
		return src
	var b := src as BaseMaterial3D
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", b.albedo_color)
	m.set_shader_parameter("rough", b.roughness)
	m.set_shader_parameter("metal", b.metallic)
	if b.emission_enabled:
		m.set_shader_parameter("emission_col", b.emission)
		m.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
	_walk_mat_cache[key] = m
	return m


func _build_squad(col: Color) -> void:
	var mesh := _bake_squad_mesh(faction, kind if kind == "lance_warden" else "")
	if mesh == null:
		_build_infantry(col)          # no model on disk: fall back to primitives
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true       # carries each man's own gait phase
	mm.mesh = mesh
	mm.instance_count = SQUAD_N
	_squad_mm = MultiMeshInstance3D.new()
	_squad_mm.multimesh = mm
	# fixed bounds: without this Godot recomputes the AABB from moving instances
	_squad_mm.custom_aabb = AABB(Vector3(-0.9, -0.4, -0.9), Vector3(1.8, 2.2, 1.8))
	_body.add_child(_squad_mm)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	_squad_order = []
	for i in range(SQUAD_N):
		_squad_order.append(i)
	# who falls first is fixed per section, so survivors keep their own places
	# instead of every man teleporting each time the count changes
	for i in range(SQUAD_N - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = _squad_order[i]
		_squad_order[i] = _squad_order[j]
		_squad_order[j] = tmp
	_squad_fall = []
	_squad_jitter = []
	_squad_phase = []
	for i in range(SQUAD_N):
		_squad_fall.append(0.0)
		# Enough scatter to actually break the rows. At +-0.07 against 0.30 m
		# offsets the six men still stood in a tidy grid, and a grid of small
		# high-contrast figures at ~27 px on screen reads as a checkerboard.
		_squad_jitter.append(Vector3(rng.randf_range(-0.20, 0.20),
			rng.randf_range(-0.6, 0.6), rng.randf_range(-0.17, 0.17)))
		_squad_phase.append(rng.randf() * TAU)
	_squad_alive = SQUAD_N
	_squad_write()


func squad_tick(dt: float) -> void:
	if _squad_mm == null:
		return
	_squad_t += dt
	var want := clampi(int(ceil(hp / maxf(max_hp, 0.001) * float(SQUAD_N))),
		1, SQUAD_N)
	if hp <= 0.0:
		want = 0
	if want != _squad_alive:
		_squad_alive = want
	# the section closes up as it thins, so the last man stands on the unit
	# origin where the selection ring and health bar already are
	var target_spread := float(maxi(_squad_alive - 1, 0)) / float(SQUAD_N - 1)
	if fort_ref >= 0:
		target_spread *= 0.7                  # hunkered in the hole
	elif role == "inf" and stance == 1:
		target_spread *= 1.15                 # light feet: looser order
	_squad_spread = lerpf(_squad_spread, target_spread, minf(dt * 2.4, 1.0))

	# The gait advances with GROUND COVERED, not with time — driving it off TIME
	# is exactly what makes feet skate along underneath a walking man.
	var sp := vel.length()
	_gait += (sp * dt) / STRIDE_LEN * PI
	if _gait > TAU:
		_gait -= TAU
	var want_amt := 1.0 if sp > 0.30 else 0.0
	var prev_amt := _gait_amt
	_gait_amt = move_toward(_gait_amt, want_amt, dt * 3.5)

	var moving := not is_equal_approx(prev_amt, _gait_amt) or _gait_amt > 0.001
	if _fire_kick > 0.0:
		_fire_kick = maxf(0.0, _fire_kick - dt * 3.2)
		moving = true
	for i in range(SQUAD_N):
		var slot: int = _squad_order.find(i)
		var down := slot >= _squad_alive
		var tgt := 1.0 if down else 0.0
		if not is_equal_approx(_squad_fall[i], tgt):
			var rate := dt / (0.7 if down else 0.5)
			_squad_fall[i] = move_toward(_squad_fall[i], tgt, rate)
			moving = true
	if moving or vel.length_squared() > 0.0004 or not is_equal_approx(
			_squad_spread, target_spread):
		_squad_write()


func _squad_write() -> void:
	if _squad_mm == null:
		return
	var mm := _squad_mm.multimesh
	for i in range(SQUAD_N):
		var off: Vector2 = SQUAD_OFFS[i] * _squad_spread
		var j: Vector3 = _squad_jitter[i]
		var pos := Vector3(off.x + j.x * _squad_spread, 0.0,
			off.y + j.z * _squad_spread)
		if fort_ref >= 0:
			pos.y -= 0.12
		var fall: float = _squad_fall[i]
		# a lost man pitches forward and sinks; healing runs it in reverse
		var basis := Basis(Vector3.UP, j.y * 0.5)
		if fall > 0.001:
			basis = basis * Basis(Vector3.RIGHT, -fall * 1.4)
			pos.y -= fall * 0.10
			basis = basis.scaled(Vector3.ONE * maxf(1.0 - fall, 0.02))
		# the vertical bob now lives in the shader, at twice stride frequency
		# and a fraction of the amplitude — the old whole-body hop on a single
		# sine is what made a marching section look like bouncing toys
		# Written through the explicit setters rather than by packing mm.buffer
		# by hand: the raw per-instance layout interleaves transform, colour and
		# custom data, and guessing that order wrong put the gait phase into the
		# colour slot, which tinted every man by a different large number and
		# rendered a section as a bright/dark checkerboard.
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, Color(1, 1, 1, 1))
		# gait phase, gait amount, per-man brightness jitter
		var fallen: float = 0.0 if fall > 0.001 else _gait_amt
		mm.set_instance_custom_data(i, Color(
			_gait + _squad_phase[i], fallen,
			fposmod(float(i) * 0.37 + _squad_phase[i], 1.0), _fire_kick))


func _apply_tint(root: Node3D, col: Color) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var m := mi.get_active_material(i)
			if m == null or not (m is BaseMaterial3D):
				continue
			var lname := m.resource_name.to_lower()
			if "tint" in lname:
				# cached per (source material, faction): the glb PackedScene is
				# resource-cached so sources are shared, meaning a whole army
				# shares a handful of materials instead of one per surface per
				# unit — the renderer batches same-faction units again
				var key := "%d|%d" % [m.get_instance_id(), faction]
				if not _tint_cache.has(key):
					var dup: Material = m.duplicate()
					if dup is BaseMaterial3D:
						(dup as BaseMaterial3D).albedo_color = col.darkened(0.12)
						_tint_cache[key] = _unit_relief(dup as BaseMaterial3D, faction)
					else:
						_tint_cache[key] = dup
				mi.set_surface_override_material(i, _tint_cache[key])
			elif lname.begins_with("u_steel") or lname.begins_with("u_dark") \
					or lname.begins_with("u_track"):
				# the hull's unpainted metalwork gets the grain too — it is the
				# bulk of what the eye reads on a tank from above
				mi.set_surface_override_material(i,
					_unit_relief(m as BaseMaterial3D, faction))


# ============================ THE FACTION KIT =================================
# Shared, lazily-built materials and meshes for the per-faction dress pass.
# NOTHING in here may be allocated per unit: materials come from _kit_mat,
# meshes from _piece, and both are static caches handed to every instance.

static var _kit_mats := {}
static var _piece_meshes := {}
static var _insig_mats := {}
static var _insig_meshes := {}


static func _kit_mat(name: String, fac: int = 0) -> StandardMaterial3D:
	var key := "%s|%d" % [name, fac]
	if _kit_mats.has(key):
		return _kit_mats[key]
	var m := StandardMaterial3D.new()
	match name:
		"iron":            # Karvath dark riveted iron
			m.albedo_color = Color(0.16, 0.15, 0.16)
			m.roughness = 0.62
			m.metallic = 0.55
		"rust":            # Ashfall welded scrap (ashworm's recipe, shared now)
			m.albedo_color = Color(0.38, 0.22, 0.13)
			m.roughness = 0.93
		"brass":           # Aurelian trim (world.gd's brass recipe)
			m.albedo_color = Color(0.55, 0.42, 0.22)
			m.roughness = 0.45
			m.metallic = 0.7
		"arc":             # Luminar emissive coil glow
			m.albedo_color = Color(0.66, 0.5, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.6, 0.42, 1.0)
			m.emission_energy_multiplier = 2.2
		"canvas":          # pale sandbag / strap cloth
			m.albedo_color = Color(0.52, 0.47, 0.38)
			m.roughness = 1.0
		"bluehull":        # Aurelian streamlining panels
			m.albedo_color = Color(0.28, 0.52, 0.73).darkened(0.2)
			m.roughness = 0.5
			m.metallic = 0.5
		"ember":           # smokestack mouths
			m.albedo_color = Color(0.9, 0.4, 0.15)
			m.emission_enabled = true
			m.emission = Color(0.9, 0.35, 0.1)
			m.emission_energy_multiplier = 1.6
	_kit_mats[key] = m
	return m


static func _piece(name: String) -> Mesh:
	if _piece_meshes.has(name):
		return _piece_meshes[name]
	var mesh: Mesh = null
	match name:
		"stack":           # smokestack
			var c := CylinderMesh.new()
			c.top_radius = 0.055
			c.bottom_radius = 0.075
			c.height = 0.8
			c.radial_segments = 8
			mesh = c
		"stack_lip":
			var c2 := CylinderMesh.new()
			c2.top_radius = 0.07
			c2.bottom_radius = 0.07
			c2.height = 0.06
			c2.radial_segments = 8
			mesh = c2
		"slab":            # armor skirt / applique plate
			var b := BoxMesh.new()
			b.size = Vector3(0.06, 0.3, 0.8)
			mesh = b
		"plate":           # small welded patch
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.34, 0.05, 0.42)
			mesh = b2
		"sandbag":
			var s := SphereMesh.new()
			s.radius = 0.16
			s.height = 0.14
			s.radial_segments = 8
			s.rings = 4
			mesh = s
		"rivet":
			var s2 := SphereMesh.new()
			s2.radius = 0.028
			s2.height = 0.056
			s2.radial_segments = 6
			s2.rings = 3
			mesh = s2
		"orb":
			var s3 := SphereMesh.new()
			s3.radius = 0.09
			s3.height = 0.18
			s3.radial_segments = 10
			s3.rings = 5
			mesh = s3
		"coil_rod":
			var c3 := CylinderMesh.new()
			c3.top_radius = 0.035
			c3.bottom_radius = 0.05
			c3.height = 0.5
			c3.radial_segments = 8
			mesh = c3
		"coil_ring":
			var t := TorusMesh.new()
			t.inner_radius = 0.07
			t.outer_radius = 0.12
			t.rings = 10
			t.ring_segments = 6
			mesh = t
		"trim":            # brass / emissive edge strip
			var b3 := BoxMesh.new()
			b3.size = Vector3(0.05, 0.04, 1.1)
			mesh = b3
		"wedge":           # streamlined nose
			var p := PrismMesh.new()
			p.size = Vector3(0.7, 0.35, 0.6)
			mesh = p
		"barrel":          # extra flak barrel
			var c4 := CylinderMesh.new()
			c4.top_radius = 0.03
			c4.bottom_radius = 0.035
			c4.height = 0.85
			c4.radial_segments = 6
			mesh = c4
		"spike":
			var c5 := CylinderMesh.new()
			c5.top_radius = 0.0
			c5.bottom_radius = 0.045
			c5.height = 0.16
			c5.radial_segments = 6
			mesh = c5
		"pauldron":
			var b4 := BoxMesh.new()
			b4.size = Vector3(0.16, 0.09, 0.18)
			mesh = b4
		"mortar":
			var c6 := CylinderMesh.new()
			c6.top_radius = 0.09
			c6.bottom_radius = 0.075
			c6.height = 0.5
			c6.radial_segments = 8
			mesh = c6
	_piece_meshes[name] = mesh
	return mesh


static func insignia_mat(fac: int) -> StandardMaterial3D:
	if _insig_mats.has(fac):
		return _insig_mats[fac]
	var m := StandardMaterial3D.new()
	var tex_path := "res://textures/insignia_f%d.png" % fac
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
	# ALPHA_SCISSOR keeps insignia in the opaque pass: no sort fights with the
	# alpha-blended prop disc or ground shadow, and no per-pixel blend cost
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	if fac == 4:               # Luminar insignia glow like their arc tech
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission = Color(0.5, 0.35, 0.8)
		m.emission_energy_multiplier = 1.1
	_insig_mats[fac] = m
	return m


# One single-surface mesh per plane kind: every roundel quad baked into the
# vertices, so the whole insignia set is ONE extra draw call per aircraft.
const INSIG_QUADS := {
	# kind: [[pos, size, axis], ...]  axis "y" = flat on wing, "x" = fin side
	# every coordinate here was checked against the measured extents of the mesh
	# it decorates — a quad on the centre plane of a fin is INVISIBLE (buried in
	# the fin's thickness), and one floating off the wing reads as a glitch
	"kondor": [[Vector3(-1.15, 0.24, 0.1), 0.5, "y"], [Vector3(1.15, 0.24, 0.1), 0.5, "y"]],
	"duster": [[Vector3(-1.05, -0.055, -0.2), 0.44, "y"],
		[Vector3(1.05, -0.055, -0.2), 0.44, "y"]],
	"sparrowhawk": [[Vector3(-1.1, 0.515, -0.25), 0.42, "y"],
		[Vector3(1.1, 0.515, -0.25), 0.42, "y"],
		[Vector3(-0.045, 0.32, 1.2), 0.26, "x"], [Vector3(0.045, 0.32, 1.2), 0.26, "x"]],
	"pelican": [[Vector3(-1.9, 0.75, -0.1), 0.55, "y"], [Vector3(1.9, 0.75, -0.1), 0.55, "y"],
		[Vector3(-0.078, 1.2, 2.25), 0.34, "x"], [Vector3(0.078, 1.2, 2.25), 0.34, "x"]],
	"wasp": [[Vector3(-0.045, 0.38, 1.45), 0.26, "x"], [Vector3(0.045, 0.38, 1.45), 0.26, "x"]],
	"seraph": [[Vector3(-0.85, 0.215, -0.2), 0.4, "y"], [Vector3(0.85, 0.215, -0.2), 0.4, "y"]],
	"leviathan": [[Vector3(-1.115, 0.6, 0.0), 0.5, "x"], [Vector3(1.115, 0.6, 0.0), 0.5, "x"]],
	# ground vehicles wear ownership where the RTS camera can see it: the roof
	"pavise": [[Vector3(0.17, 1.545, -0.12), 0.34, "y"]],
	"zephyr": [[Vector3(0.0, 1.005, 0.25), 0.3, "y"]],
}


# The table above is hand-measured against a specific mesh, which is exactly
# why it breaks on pipeline models: re-carving a hull moves every surface it
# was measured from, and the roundels end up hovering beside the wing or buried
# inside it. These entries give a target as a FRACTION of the hull's bounding
# box; the quad is then snapped onto the nearest real surface at that spot, so
# it lands on the skin no matter what the mesh turns out to be.
#   "y" = flat on the upper surface, frac reads (x, -, z)
#   "x" = on the flank, frac reads (-, y, z), mirrored to both sides
const CUSTOM_INSIG := {
	"sparrowhawk": [[Vector3(0.22, 0.0, 0.48), 0.42, "y"],
		[Vector3(0.78, 0.0, 0.48), 0.42, "y"]],
	"pelican": [[Vector3(0.17, 0.0, 0.46), 0.55, "y"],
		[Vector3(0.83, 0.0, 0.46), 0.55, "y"]],
	"kondor": [[Vector3(0.18, 0.0, 0.50), 0.50, "y"],
		[Vector3(0.82, 0.0, 0.50), 0.50, "y"]],
	"duster": [[Vector3(0.18, 0.0, 0.45), 0.44, "y"],
		[Vector3(0.82, 0.0, 0.45), 0.44, "y"]],
	# these two wear it on the upper surface, not the flank: the RTS camera
	# looks down at 52 degrees, and a quad on the side of an airship hull is
	# edge-on to it — present in the mesh, invisible in the game
	"wasp": [[Vector3(0.5, 0.0, 0.78), 0.24, "y"]],
	"leviathan": [[Vector3(0.5, 0.0, 0.38), 0.80, "y"]],
	# ground vehicles wear it on the roof, where the RTS camera can see it
	"pavise": [[Vector3(0.5, 0.0, 0.62), 0.34, "y"]],
	"zephyr": [[Vector3(0.5, 0.0, 0.35), 0.30, "y"]],
	"dart": [[Vector3(0.5, 0.0, 0.55), 0.30, "y"]],
	"dray": [[Vector3(0.5, 0.0, 0.30), 0.32, "y"]],
	"keelwright": [[Vector3(0.5, 0.0, 0.60), 0.50, "y"]],
	# Luminar wear it on their heavy hulls only. Faction 4's insignia material
	# emits (see insignia_mat), so this doubles as their arc-light signature —
	# putting one on every truck as well would turn a signature into wallpaper.
	"faraday": [[Vector3(0.5, 0.0, 0.45), 0.34, "y"]],
	"ark_carriage": [[Vector3(0.5, 0.0, 0.55), 0.50, "y"]],
	"cathedral": [[Vector3(0.5, 0.0, 0.40), 0.70, "y"]],
	"seraph": [[Vector3(0.26, 0.0, 0.58), 0.34, "y"],
		[Vector3(0.74, 0.0, 0.58), 0.34, "y"]],
}

static var _fit_insig_meshes := {}


# Snap each fractional target onto the hull's actual skin. A quad is accepted
# only if real geometry sits under it — a target that misses the mesh is
# dropped rather than left floating in air.
static func _fit_quads(verts: PackedVector3Array, hull: AABB, spec: Array) -> Array:
	var out: Array = []
	for q in spec:
		var f: Vector3 = q[0]
		var size: float = q[1]
		var half: float = size * 0.5
		if String(q[2]) == "y":
			var tx: float = hull.position.x + hull.size.x * f.x
			var tz: float = hull.position.z + hull.size.z * f.z
			var top := _probe(verts, tx, tz, 0, 2, 1, true)
			if top == Vector3.INF:
				continue
			out.append([top + Vector3(0, 0.03, 0), size, "y"])
		else:
			var ty: float = hull.position.y + hull.size.y * f.y
			var tz2: float = hull.position.z + hull.size.z * f.z
			var flank := 0.0
			for v in verts:
				if absf(v.y - ty) <= half and absf(v.z - tz2) <= half:
					flank = maxf(flank, absf(v.x))
			if flank <= 0.0:
				continue
			out.append([Vector3(flank + 0.03, ty, tz2), size, "x"])
			out.append([Vector3(-flank - 0.03, ty, tz2), size, "x"])

	# A mirrored pair has to sit at the same height. On the Kondor's twin tail
	# the starboard probe latched onto a fin top — "highest geometry here" is
	# the right rule for a roof and the wrong one when something sticks up out
	# of the wing — and left that roundel hanging above the airframe. Levelling
	# every "y" quad in a spec to its LOWEST hit picks the wing in that case and
	# changes nothing for a spec that only has one.
	var flat: Array = []
	for q in out:
		if String(q[2]) == "y":
			flat.append(q)
	if flat.size() > 1:
		var low := INF
		for q in flat:
			low = minf(low, float(q[0].y))
		for q in flat:
			q[0] = Vector3(q[0].x, low, q[0].z)
	return out


# The baked mesh hangs under the glb root's axis-conversion transform, so its
# vertices need walking back up into the body's own space before anything can
# be positioned against them.
static var _hull_vert_cache := {}


func _hull_verts() -> PackedVector3Array:
	# cached per kind: every unit of a kind loads the same glb under the same
	# node tree, and the Cathedral alone is 60k vertices to walk on every spawn
	if _hull_vert_cache.has(kind):
		return _hull_vert_cache[kind]
	var verts := PackedVector3Array()
	if _merged == null or _merged.mesh == null:
		return verts
	var xf := Transform3D.IDENTITY
	var n: Node3D = _merged
	while n != null and n != _body:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	for si in range(_merged.mesh.get_surface_count()):
		var arr: Array = _merged.mesh.surface_get_arrays(si)
		for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			verts.append(xf * v)
	_hull_vert_cache[kind] = verts
	return verts


func _hull_box(verts: PackedVector3Array) -> AABB:
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box


# A Luminar hull with no arc light is just a violet truck. The procedural coils
# in _dress() are positioned against the meshes they were built for, so pipeline
# models skip them and take this instead: one emissive orb snapped onto the real
# hull, which survives any re-carve.
const CUSTOM_GLOW := {
	"glimmer": [Vector3(0.5, 0.0, 0.30), 0.13],
	"faraday": [Vector3(0.5, 0.0, 0.70), 0.16],
	"ion_carriage": [Vector3(0.5, 0.0, 0.62), 0.14],
	"collector": [Vector3(0.5, 0.0, 0.66), 0.16],
	"dynamo": [Vector3(0.5, 0.0, 0.64), 0.20],
	"ark_carriage": [Vector3(0.5, 0.0, 0.26), 0.20],
	"seraph": [Vector3(0.5, 0.0, 0.84), 0.13],
	"cathedral": [Vector3(0.5, 0.0, 0.78), 0.26],
}


func _add_custom_glow() -> void:
	if not custom_model or not CUSTOM_GLOW.has(kind):
		return
	var verts := _hull_verts()
	if verts.is_empty():
		return
	var hull := _hull_box(verts)
	var spec: Array = CUSTOM_GLOW[kind]
	var f: Vector3 = spec[0]
	var r: float = spec[1]
	var top := _probe(verts, hull.position.x + hull.size.x * f.x,
		hull.position.z + hull.size.z * f.z, 0, 2, 1, true)
	if top == Vector3.INF:
		return
	var orb := SphereMesh.new()
	orb.radius = r
	orb.height = r * 2.0
	orb.radial_segments = 12
	orb.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = orb
	mi.material_override = _kit_mat("arc")
	mi.position = top + Vector3(0, r * 0.55, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)


func _fitted_insignia() -> ArrayMesh:
	if _fit_insig_meshes.has(kind):
		return _fit_insig_meshes[kind]
	var verts := _hull_verts()
	if verts.is_empty():
		return null
	var hull := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		hull = hull.expand(v)
	var quads := _fit_quads(verts, _hull_box(verts), CUSTOM_INSIG[kind])
	if quads.is_empty():
		return null
	var mesh := _build_insig_mesh(quads)
	_fit_insig_meshes[kind] = mesh
	return mesh


static func _insignia_mesh(kind_key: String) -> ArrayMesh:
	if _insig_meshes.has(kind_key):
		return _insig_meshes[kind_key]
	var mesh := _build_insig_mesh(INSIG_QUADS[kind_key])
	_insig_meshes[kind_key] = mesh
	return mesh


static func _build_insig_mesh(quads: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in quads:
		var c: Vector3 = q[0]
		var h: float = q[1] * 0.5
		var corners: Array[Vector3] = []
		if q[2] == "y":            # flat, facing up; texture top toward the nose (-Z)
			corners = [Vector3(c.x - h, c.y, c.z - h), Vector3(c.x + h, c.y, c.z - h),
				Vector3(c.x + h, c.y, c.z + h), Vector3(c.x - h, c.y, c.z + h)]
		else:                      # vertical, on the fin plane (cull off serves both sides)
			corners = [Vector3(c.x, c.y + h, c.z - h), Vector3(c.x, c.y + h, c.z + h),
				Vector3(c.x, c.y - h, c.z + h), Vector3(c.x, c.y - h, c.z - h)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				st.set_uv(uvs[idx])
				st.set_normal(Vector3.UP if q[2] == "y" else Vector3.RIGHT)
				st.add_vertex(corners[idx])
	return st.commit()


func _add_piece(mesh_name: String, mat: Material, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _piece(mesh_name)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)
	return mi


func _add_insignia() -> void:
	var mesh: ArrayMesh = null
	if custom_model and CUSTOM_INSIG.has(kind):
		mesh = _fitted_insignia()
	elif INSIG_QUADS.has(kind):
		mesh = _insignia_mesh(kind)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	_insig_mi = mi
	mi.mesh = mesh
	mi.material_override = insignia_mat(faction)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)


# ============================ THE DRESS PASS ==================================
# Per-faction identity beyond the tint: silhouette pieces, insignia, glow.
# Karvath = riveted iron + smokestacks · Ashfall = asymmetric welded scrap ·
# Aurelia = brass trim + roundels · Luminar = clean lines + arc light.
# Everything here uses the shared kit — no per-unit materials, no shadows on
# small pieces, and at most ~7 extra meshes per unit (sperrwagen is the ceiling).

func _dress() -> void:
	_add_insignia()
	_add_custom_glow()
	if custom_model:
		# a per-kind pipeline model carries its own stacks/plates/detail —
		# the procedural pieces below would float through its silhouette
		return
	var iron := _kit_mat("iron")
	var rust := _kit_mat("rust")
	var brass := _kit_mat("brass")
	var arc := _kit_mat("arc")
	match kind:
		# ----- KARVATH: the slow hammer
		"bastion":
			for sz in [0.85, 1.08]:
				_add_piece("stack", iron, Vector3(0.5, 1.45, sz))
				_add_piece("stack_lip", _kit_mat("ember"), Vector3(0.5, 1.86, sz))
		"sperrwagen":
			for sx in [-0.62, 0.62]:
				_add_piece("slab", iron, Vector3(sx, 0.45, 0.0),
					Vector3.ZERO, Vector3(1.0, 1.0, 1.6))
				for rz in [-0.35, 0.35]:
					_add_piece("rivet", iron, Vector3(sx * 1.06, 0.62, rz))
			_add_piece("stack", iron, Vector3(-0.3, 1.1, 0.6))
		"hammerfall":
			# no longer Faraday's twin: blast shield, mortar sleeve, second stack
			_add_piece("plate", iron, Vector3(0, 1.15, -0.75),
				Vector3(-65, 0, 0), Vector3(2.6, 1.0, 1.6))
			_add_piece("mortar", iron, Vector3(0, 1.12, -1.15), Vector3(-78, 0, 0))
			_add_piece("stack", iron, Vector3(0.5, 1.35, 0.95))
			_add_piece("stack_lip", _kit_mat("ember"), Vector3(0.5, 1.76, 0.95))
		# ----- ASHFALL: the thousand cuts
		"rat":
			_add_piece("plate", rust, Vector3(-0.45, 0.78, -0.3), Vector3(0, 12, 0))
			_add_piece("stack", rust, Vector3(0.35, 0.95, 0.55), Vector3(0, 0, -14))
		"warpig":
			_add_piece("plate", rust, Vector3(0.7, 0.95, 0.3), Vector3(0, 8, 90))
			_add_piece("plate", rust, Vector3(-0.68, 0.85, -0.55), Vector3(0, -15, 90))
			for si in range(3):
				# rear deck (TK_Rear) tops out at y 0.908 — bags SIT on it
				_add_piece("sandbag", _kit_mat("canvas"),
					Vector3(-0.25 + si * 0.25, 0.98, 1.05))
		"stovepipe":
			_add_piece("stack", rust, Vector3(0.3, 1.25, 0.55), Vector3(0, 0, -10),
				Vector3(1.4, 1.5, 1.4))
			_add_piece("plate", rust, Vector3(-0.4, 0.78, 0.2), Vector3(0, 5, 0))
		"duster":
			# the wing sits at y -0.1 (top -0.065): the patch lies ON it
			_add_piece("plate", rust, Vector3(0.7, -0.05, -0.2),
				Vector3.ZERO, Vector3(1.6, 0.6, 1.3))
		# ----- AURELIA: the thousand sails
		"pavise":
			for sx in [-1.02, 1.02]:
				_add_piece("trim", brass, Vector3(sx, 0.78, 0.0))
		"zephyr":
			_add_piece("wedge", _kit_mat("bluehull"),
				Vector3(0, 0.55, -1.05), Vector3(-90, 0, 0))
			for bx in [-0.08, 0.08]:
				_add_piece("barrel", _kit_mat("iron"), Vector3(bx, 1.1, -0.15),
					Vector3(-82, 0, 0))
		# ----- LUMINAR: the second sun
		"faraday":
			_add_piece("coil_rod", iron, Vector3(-0.5, 1.3, 0.95))
			_add_piece("coil_ring", arc, Vector3(-0.5, 1.45, 0.95))
			_add_piece("orb", arc, Vector3(-0.5, 1.62, 0.95))
			_add_piece("orb", arc, Vector3(0, 1.05, -1.9))
		"dynamo":
			_add_piece("coil_rod", iron, Vector3(0, 0.95, 0.35),
				Vector3.ZERO, Vector3(1.6, 1.3, 1.6))
			for ry in [1.3, 1.5]:
				_add_piece("coil_ring", arc, Vector3(0, ry, 0.35))
			_add_piece("orb", arc, Vector3(0, 1.72, 0.35), Vector3.ZERO,
				Vector3(1.4, 1.4, 1.4))
		"glimmer":
			# raised off the cab roof (top face y 1.0) and shortened to the cab
			# span so it neither z-fights the roof nor floats over the bow
			_add_piece("trim", arc, Vector3(0, 1.01, 0.25), Vector3.ZERO,
				Vector3(1.0, 1.0, 0.63))
			_add_piece("orb", arc, Vector3(0, 1.1, 0.45), Vector3.ZERO,
				Vector3(0.7, 0.7, 0.7))
		"ion_carriage":
			for bx2 in [-0.14, 0.14]:
				_add_piece("coil_rod", iron, Vector3(bx2, 1.05, -0.2),
					Vector3.ZERO, Vector3(0.7, 0.8, 0.7))
				_add_piece("orb", arc, Vector3(bx2, 1.32, -0.2), Vector3.ZERO,
					Vector3(0.6, 0.6, 0.6))
		"leviathan":
			_add_piece("trim", brass, Vector3(0, -0.62, 0.0), Vector3.ZERO,
				Vector3(1.0, 1.0, 2.2))
	# faction-wide infantry identity (all four rosters share one soldier glb)
	if role == "inf":
		match faction:
			1:
				_add_piece("pauldron", iron, Vector3(-0.23, 0.95, -0.05))
				_add_piece("spike", iron, Vector3(0, 1.32, -0.02))
				if kind == "grenadier":
					_add_piece("mortar", iron, Vector3(0.2, 0.62, 0.16),
						Vector3(-20, 0, 0), Vector3(0.7, 0.8, 0.7))
			2:
				_add_piece("plate", rust, Vector3(0.2, 0.98, -0.02),
					Vector3(0, 0, 74), Vector3(0.5, 0.8, 0.4))
			3:
				_add_piece("pauldron", brass, Vector3(-0.23, 0.95, -0.05),
					Vector3.ZERO, Vector3(0.8, 0.6, 0.8))
			4:
				# clear of SD_Pack (z 0.145-0.275) and SD_Bedroll — proud of the
				# pack's rear face so the glow actually reads
				_add_piece("orb", arc, Vector3(0, 0.88, 0.33),
					Vector3.ZERO, Vector3(0.55, 0.55, 0.55))
				if kind == "lance_warden":
					var lance := find_child("SD_RifleBarrel", true, false)
					if lance is MeshInstance3D:
						(lance as MeshInstance3D).material_override = arc


func _make_shadow(sz := Vector2(1.9, 2.3)) -> void:
	var sh_mesh := PlaneMesh.new()
	sh_mesh.size = sz
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.3)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow = MeshInstance3D.new()
	_shadow.mesh = sh_mesh
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)

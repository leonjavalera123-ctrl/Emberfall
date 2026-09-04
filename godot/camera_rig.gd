# EMBERFALL: 1940 — camera_rig.gd
# Classic RTS camera: the rig slides on the ground plane, an angled arm
# holds the camera above it. Pan (WASD/arrows/screen edge), rotate (Q/E),
# zoom (mouse wheel). Screen = what the camera sees; no offsets to math out.

class_name CameraRig
extends Node3D

const T := 2.0
const EDGE := 20.0
const PAN_BASE := 30.0        # meters/sec at default zoom (scales with zoom)
const ROT_SPEED := 1.7        # radians/sec
const DIST_MIN := 14.0
const DIST_MAX := 70.0        # the standard map is big — let the eye climb

var arm: Node3D
var cam: Camera3D
var dist := 30.0
var target_dist := 30.0
var bounds_max := Vector2(128, 96)
var s_blocked := false      # true while units are selected: S = stop order, not pan
var wheel_blocked := false  # true while the formation preview is cycling shapes
var _shake_t := 0.0
var _shake_mag := 0.0

# --- follow-the-march ---------------------------------------------------------
# Opt-in escort camera: after a move order the view trails the group. It is a
# COURTESY, not a lock — the first time the player pans, rotates, edge-scrolls
# or clicks elsewhere, it lets go and hands the camera straight back.
var follow_on := false            # the setting, toggled by the player
var edge_pan_on := true           # selftests disable this: with no real mouse the
                                  # pointer sits in a window corner and edge-scrolls
                                  # forever, which cancels any follow being measured
var follow_units: Array = []      # who we are trailing right now
var _follow_active := false
var _last_mouse := Vector2(-1e9, -1e9)
var _mouse_moved := false


func follow_group(list: Array) -> void:
	if not follow_on:
		return
	follow_units = list.duplicate()
	_follow_active = not follow_units.is_empty()
	# a pointer parked at an edge must not instantly cancel the follow it just
	# started; it has to move first to count as the player taking over
	_mouse_moved = false


func release_follow() -> void:
	_follow_active = false
	follow_units = []


func _follow_step(dt: float) -> void:
	# Centre on the LEADING edge of the group, not its centroid: a march with
	# one wounded straggler should keep the fighting in frame, so the faster
	# units are weighted far more heavily than the slow ones.
	var best := Vector3.ZERO
	var wsum := 0.0
	var alive := 0
	for u in follow_units:
		if not is_instance_valid(u) or u.hp <= 0:
			continue
		alive += 1
		# weight by speed, and heavily favour anyone still actually moving
		var w: float = maxf(u.speed, 0.1)
		if not u.path.is_empty():
			w *= 3.0
		best += u.global_position * w
		wsum += w
	if alive == 0 or wsum <= 0.0:
		release_follow()
		return
	var aim := best / wsum
	# ease rather than snap, so the camera glides instead of jerking each frame
	var to := Vector2(aim.x - position.x, aim.z - position.z)
	if to.length() < 0.35:
		return
	var step := minf(3.0 * dt, 1.0)
	position.x += to.x * step
	position.z += to.y * step
	_clamp()


func shake(mag: float, dur: float) -> void:
	_shake_mag = mag
	_shake_t = dur


func setup(world: EFWorld) -> void:
	bounds_max = Vector2(world.w * T, world.h * T)
	arm = Node3D.new()
	arm.rotation_degrees = Vector3(-52, 0, 0)
	add_child(arm)
	cam = Camera3D.new()
	cam.position = Vector3(0, 0, dist)
	cam.fov = 55.0
	arm.add_child(cam)
	cam.current = true


func _unhandled_input(ev: InputEvent) -> void:
	if wheel_blocked:
		return          # the formation preview owns the wheel while it is up
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_dist = clamp(target_dist - 3.5, DIST_MIN, DIST_MAX)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_dist = clamp(target_dist + 3.5, DIST_MIN, DIST_MAX)


func _process(dt: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if (Input.is_key_pressed(KEY_S) and not s_blocked) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1

	var edge_pan := false
	if edge_pan_on and get_window().has_focus():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		if mp.x < EDGE:
			dir.x -= 1
			edge_pan = true
		elif mp.x > vs.x - EDGE:
			dir.x += 1
			edge_pan = true
		if mp.y < EDGE:
			dir.y -= 1
			edge_pan = true
		elif mp.y > vs.y - EDGE:
			dir.y += 1
			edge_pan = true
		# A pointer left sitting near an edge is not the player asking for the
		# camera — only count edge-scroll as deliberate once the mouse has
		# actually moved, or a follow would die the instant it began.
		# The first observation has no previous position to compare against.
		# Seeding _last_mouse with a sentinel made frame one measure a movement
		# of ~1e9 pixels, so a follow begun with the pointer anywhere near an
		# edge cancelled itself immediately.
		if _last_mouse.x < -1e8:
			_last_mouse = mp
		elif mp.distance_to(_last_mouse) > 1.0:
			_mouse_moved = true
		_last_mouse = mp

	var rotating := Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E)
	if Input.is_key_pressed(KEY_Q):
		rotate_y(ROT_SPEED * dt)
	if Input.is_key_pressed(KEY_E):
		rotate_y(-ROT_SPEED * dt)

	# Any DELIBERATE camera input hands control straight back to the player.
	# Keyboard pan and rotate always count; edge-scroll only once the pointer
	# has actually moved (see above).
	var keyed := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) \
		or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) \
		or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) \
		or (Input.is_key_pressed(KEY_S) and not s_blocked) \
		or Input.is_key_pressed(KEY_DOWN)
	if _follow_active and (keyed or rotating or (edge_pan and _mouse_moved)):
		release_follow()

	if _follow_active:
		_follow_step(dt)

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var speed := PAN_BASE * (dist / 30.0)      # pan faster when zoomed out
		position += (right * dir.x + fwd * -dir.y) * speed * dt
		_clamp()

	dist = lerp(dist, target_dist, minf(9.0 * dt, 1.0))
	cam.position = Vector3(0, 0, dist)
	if _shake_t > 0.0:
		_shake_t = maxf(0.0, _shake_t - dt)
		var f := _shake_t * _shake_mag
		cam.h_offset = randf_range(-f, f)
		cam.v_offset = randf_range(-f, f)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func center_on(wx: float, wz: float) -> void:
	position = Vector3(wx, 0.0, wz)
	_clamp()


func _clamp() -> void:
	position.x = clamp(position.x, 0.0, bounds_max.x)
	position.z = clamp(position.z, 0.0, bounds_max.y)
	position.y = 0.0

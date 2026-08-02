# EMBERFALL: 1940 — ui.gd
# The Phase 4 command sidebar: minimap, live treasury + power grid, BUILD
# TABS with RA-style queue buttons (progress bar fills as credits drain,
# READY flashes when a building awaits placement), a combined context panel
# (selection or survey), compact hints, and an F1 field-manual overlay.

class_name EFUI
extends CanvasLayer

const VIEW_W := 1060
const SB_X := 1060
const SB_W := 220

const COL_BG := Color(0.094, 0.102, 0.118)
const COL_PANEL := Color(0.129, 0.141, 0.165)
const COL_PANEL_HI := Color(0.165, 0.18, 0.21)
const COL_EDGE := Color(0.25, 0.275, 0.31)
const COL_TEXT := Color(0.81, 0.8, 0.76)
const COL_DIM := Color(0.5, 0.49, 0.47)
const COL_ACCENT := Color(0.89, 0.58, 0.23)
const COL_GOOD := Color(0.55, 0.85, 0.5)
const COL_BAD := Color(0.9, 0.4, 0.32)

const MM_COLORS := {
	".": Color(0.38, 0.36, 0.33), ",": Color(0.30, 0.29, 0.26),
	"#": Color(0.16, 0.16, 0.17), "~": Color(0.17, 0.29, 0.34),
	"E": Color(0.93, 0.57, 0.20), "B": Color(0.52, 0.48, 0.42),
	"R": Color(0.72, 0.6, 0.42), "C": Color(0.62, 0.55, 0.48),
	"W": Color(0.66, 0.66, 0.7),
}

var world: EFWorld
var rig: CameraRig
var economy: EFEconomy
var buildings: EFBuildings
var mm_scale := 1

var credits_label: Label
var power_label: Label
var context_lines: Array[Label] = []
var fps_label: Label
var minimap_rect: TextureRect
var mm_dragging := false
var band: RubberBand
var manual_panel: Panel
var _mm_img: Image
var _tab_buttons := {}
var _item_buttons := {}        # tab -> Array of {btn, bar, id}
var active_tab := "BASE"
var _force_counts := {}
var _survey := []
var _sel_bld := -1
signal stance_picked(stance: String)
signal anthem_pressed()

var demolish_btn: Button
var stance_a_btn: Button
var stance_b_btn: Button
var _stance_opts: Array = []          # empty = hide the row
var _stance_cur := ""
var _stance_mixed := false
var _stance_stale := true
var _pick_a := ""                     # what button A actually emits — must match its label
var _pick_b := ""
var _form_shape := ""
var _form_n := 0
var _form_label: Label
var sw_btn: Button
var anthem_btn: Button
var repair_btn: Button
var pause_layer: ColorRect
var announce_label: Label
var _announce_t := 0.0
var _sw_was_ready := false


class RubberBand extends Control:
	var rect := Rect2()

	func _draw() -> void:
		if rect.size != Vector2.ZERO:
			draw_rect(rect, Color(0.45, 1.0, 0.55, 0.07), true)
			draw_rect(rect, Color(0.5, 1.0, 0.6, 0.9), false, 1.0)


class MiniCamRect extends Control:
	var rig: CameraRig
	var world_size := Vector2(384, 256)

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if rig == null:
			return
		var c := Vector2(rig.position.x / world_size.x, rig.position.z / world_size.y) * size
		var half := Vector2(rig.dist * 0.72, rig.dist * 0.52) / world_size * size
		draw_rect(Rect2(c - half, half * 2.0), Color(1, 1, 1, 0.9), false, 1.0)


class HealthBars extends Control:
	# one overlay draws every bar: units (hurt or selected) and damaged buildings
	var army: EFArmy
	var buildings: EFBuildings
	var rig: CameraRig

	func _process(_dt: float) -> void:
		queue_redraw()

	func _bar(sp: Vector2, w: float, frac: float) -> void:
		frac = clampf(frac, 0.0, 1.0)
		var col := Color(0.35, 0.85, 0.35) if frac > 0.6 else \
			(Color(0.9, 0.75, 0.25) if frac > 0.3 else Color(0.9, 0.3, 0.25))
		draw_rect(Rect2(sp.x - w / 2 - 1, sp.y - 1, w + 2, 5), Color(0, 0, 0, 0.65))
		draw_rect(Rect2(sp.x - w / 2, sp.y, w * frac, 3), col)

	func _draw() -> void:
		if army == null:
			return
		var cam := rig.cam
		for u in army.units:
			if u.garrisoned_in >= 0 or u.hp <= 0:
				continue
			if not u.selected and u.hp >= u.max_hp and u.shield >= u.max_shield:
				continue
			if u.faction != army.player_faction and not army.world.is_explored(
					int(u.global_position.x / EFWorld.T),
					int(u.global_position.z / EFWorld.T)):
				continue
			var wp: Vector3 = u.global_position + Vector3(0, u.body_height + 0.6, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			if sp.x < 0 or sp.x > 1060 or sp.y < 0 or sp.y > 720:
				continue
			_bar(sp, 26.0, u.hp / u.max_hp)
			if u.max_shield > 0.0:
				draw_rect(Rect2(sp.x - 14, sp.y - 4, 28, 2), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(sp.x - 13, sp.y - 4, 26.0 * u.shield / u.max_shield, 2),
					Color(0.66, 0.5, 1.0))
		for b in buildings.list:
			if b["hp"] <= 0:
				continue
			var max_hp: float = EFBuildings.DEFS[b["type"]]["hp"]
			if b["hp"] >= max_hp:
				continue
			var size: int = EFBuildings.DEFS[b["type"]]["size"]
			var wp2 := Vector3((b["origin"].x + size * 0.5) * EFWorld.T, 3.4,
				(b["origin"].y + size * 0.5) * EFWorld.T)
			if cam.is_position_behind(wp2):
				continue
			var sp2 := cam.unproject_position(wp2)
			if sp2.x < 0 or sp2.x > 1060 or sp2.y < 0 or sp2.y > 720:
				continue
			_bar(sp2, 38.0, b["hp"] / max_hp)


func setup(w: EFWorld, r: CameraRig, eco: EFEconomy, bld: EFBuildings) -> void:
	world = w
	rig = r
	economy = eco
	buildings = bld
	world.tiles_revealed.connect(_on_revealed)
	mm_scale = maxi(1, int(192.0 / world.w))

	band = RubberBand.new()
	band.position = Vector2.ZERO
	band.size = Vector2(VIEW_W, 720)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	var hb := HealthBars.new()
	hb.army = r.get_parent().army if r.get_parent().get("army") else null
	hb.buildings = bld
	hb.rig = r
	hb.position = Vector2.ZERO
	hb.size = Vector2(VIEW_W, 720)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)

	_rect(Rect2(SB_X, 0, SB_W, 720), COL_BG)
	_rect(Rect2(SB_X, 0, 2, 720), COL_EDGE)
	var x := SB_X + 10

	_label("EMBERFALL: 1940", Vector2(x, 8), 19, COL_ACCENT)
	_label("PHASE 11 · THE LONG WAR", Vector2(x, 32), 10, COL_DIM)

	# --- minimap ---
	var mm_size := Vector2(world.w * mm_scale, world.h * mm_scale)
	_panel(Rect2(x, 50, 200, mm_size.y + 10))
	minimap_rect = TextureRect.new()
	minimap_rect.texture = ImageTexture.create_from_image(_minimap_image())
	minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	minimap_rect.position = Vector2(x + (200 - mm_size.x) / 2.0, 55)
	minimap_rect.size = mm_size
	minimap_rect.gui_input.connect(_on_minimap_input)
	add_child(minimap_rect)
	var mc := MiniCamRect.new()
	mc.rig = rig
	mc.world_size = Vector2(world.w * EFWorld.T, world.h * EFWorld.T)
	mc.position = minimap_rect.position
	mc.size = mm_size
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mc)

	var y := 50 + int(mm_size.y) + 18

	# --- treasury ---
	_panel(Rect2(x, y, 200, 52), "TREASURY")
	credits_label = _label("CREDITS", Vector2(x + 8, y + 17), 13, COL_ACCENT)
	power_label = _label("POWER", Vector2(x + 8, y + 33), 13, COL_DIM)
	y += 60

	sw_btn = Button.new()
	sw_btn.position = Vector2(x, y)
	sw_btn.size = Vector2(200, 22)
	_style_button(sw_btn, 10)
	sw_btn.visible = false
	sw_btn.pressed.connect(func():
		if buildings.sw_ready(buildings.player_faction):
			buildings.sw_targeting = true)
	add_child(sw_btn)
	y += 26

	# The anthem shares the superweapon's row rather than taking one of its own:
	# everything below here is already packed down to the hint strip, and adding
	# a row would push the context panel into it.
	sw_btn.size = Vector2(126, 22)
	anthem_btn = Button.new()
	anthem_btn.position = Vector2(x + 130, sw_btn.position.y)
	anthem_btn.size = Vector2(70, 22)
	anthem_btn.text = "ANTHEM"
	_style_button(anthem_btn, 10)
	anthem_btn.pressed.connect(func(): anthem_pressed.emit())
	add_child(anthem_btn)

	# --- build tabs + grid ---
	var tab_names := ["BASE", "INF", "VEH", "AIR"]
	for i in range(4):
		var tb := Button.new()
		tb.text = tab_names[i]
		tb.position = Vector2(x + i * 51, y)
		tb.size = Vector2(48, 22)
		_style_button(tb, 11)
		tb.pressed.connect(_set_tab.bind(tab_names[i]))
		add_child(tb)
		_tab_buttons[tab_names[i]] = tb
	y += 26

	for tab in ["BASE", "INF", "VEH", "AIR"]:
		var arr := []
		var items: Array = bld.tab_items(tab)
		for i in range(items.size()):
			var id: String = items[i]
			var btn := Button.new()
			btn.position = Vector2(x + (i % 2) * 103, y + (i / 2) * 44)
			btn.size = Vector2(97, 40)
			_style_button(btn, 10)
			btn.pressed.connect(_on_item.bind(tab, id))
			btn.gui_input.connect(_on_item_rmb.bind(tab, id))
			add_child(btn)
			var bar := ColorRect.new()
			bar.color = COL_ACCENT
			bar.position = btn.position + Vector2(2, 36)
			bar.size = Vector2(0, 2)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(bar)
			arr.append({"btn": btn, "bar": bar, "id": id})
		_item_buttons[tab] = arr
	_set_tab("BASE")
	y += 5 * 44 + 6

	# --- context (selection or survey) ---
	_panel(Rect2(x, y, 200, 96), "CONTEXT")
	for i in range(4):
		context_lines.append(_label("", Vector2(x + 8, y + 16 + i * 18), 11, COL_TEXT))
	repair_btn = Button.new()
	repair_btn.text = "REPAIR"
	repair_btn.position = Vector2(x + 2, y + 66)
	repair_btn.size = Vector2(92, 22)
	_style_button(repair_btn, 10)
	repair_btn.add_theme_color_override("font_color", COL_GOOD)
	repair_btn.visible = false
	repair_btn.pressed.connect(func():
		if _sel_bld >= 0:
			buildings.toggle_repair(_sel_bld))
	add_child(repair_btn)

	demolish_btn = Button.new()
	demolish_btn.text = "DEMOLISH  +50%"
	demolish_btn.position = Vector2(x + 98, y + 66)
	demolish_btn.size = Vector2(94, 22)
	_style_button(demolish_btn, 10)
	demolish_btn.add_theme_color_override("font_color", COL_BAD)
	demolish_btn.visible = false
	demolish_btn.pressed.connect(func():
		if _sel_bld >= 0:
			buildings.sell(_sel_bld))
	add_child(demolish_btn)

	# The stance row reuses the repair/demolish rect: building selection and unit
	# selection are mutually exclusive, so the two can never want it at once.
	stance_a_btn = Button.new()
	stance_a_btn.position = Vector2(x + 2, y + 66)
	stance_a_btn.size = Vector2(92, 22)
	_style_button(stance_a_btn, 10)
	stance_a_btn.visible = false
	stance_a_btn.pressed.connect(func():
		if get_tree().paused or _pick_a == "":
			return
		stance_picked.emit(_pick_a))
	add_child(stance_a_btn)

	stance_b_btn = Button.new()
	stance_b_btn.position = Vector2(x + 98, y + 66)
	stance_b_btn.size = Vector2(94, 22)
	_style_button(stance_b_btn, 10)
	stance_b_btn.visible = false
	stance_b_btn.pressed.connect(func():
		if get_tree().paused or _pick_b == "":
			return
		stance_picked.emit(_pick_b))
	add_child(stance_b_btn)
	y += 104

	# --- hints ---
	_panel(Rect2(x, y, 200, 70))
	_label("RMB move·attack·harvest·garrison", Vector2(x + 8, y + 6), 10, COL_DIM)
	_label("S stop · ESC cancel · F5/F9 save/load", Vector2(x + 8, y + 22), 10, COL_DIM)
	_label("Z stance · X unfold crawler", Vector2(x + 8, y + 38), 10, COL_DIM)
	_label("F1 manual · F11 fullscreen", Vector2(x + 8, y + 52), 10, COL_ACCENT)

	# formation readout, centred under the battlefield while right-click is held
	_form_label = Label.new()
	_form_label.position = Vector2(0, 646)
	_form_label.size = Vector2(VIEW_W, 20)
	_form_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_form_label.add_theme_font_size_override("font_size", 13)
	_form_label.add_theme_color_override("font_color", COL_ACCENT)
	_form_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_label.visible = false
	add_child(_form_label)

	pause_layer = ColorRect.new()
	pause_layer.color = Color(0, 0, 0, 0.5)
	pause_layer.size = Vector2(1280, 720)
	pause_layer.visible = false
	add_child(pause_layer)
	var pl := Label.new()
	pl.text = "— PAUSED —\n\nP or ESC to resume"
	pl.position = Vector2(0, 300)
	pl.size = Vector2(1280, 120)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.add_theme_font_size_override("font_size", 30)
	pl.add_theme_color_override("font_color", COL_ACCENT)
	pause_layer.add_child(pl)

	fps_label = _label("", Vector2(SB_X + 116, 700), 11, COL_DIM)
	announce_label = Label.new()
	announce_label.position = Vector2(130, 40)
	announce_label.size = Vector2(800, 40)
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.add_theme_font_size_override("font_size", 22)
	announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(announce_label)
	_build_manual_overlay()


# --- per-frame refresh ----------------------------------------------------------

func _process(_dt: float) -> void:
	fps_label.text = "%4.0f FPS · v1.3" % Engine.get_frames_per_second()
	if economy:
		var cr: int = economy.credits.get(buildings.player_faction, 0)
		credits_label.text = "CREDITS  %7d" % cr
		var stalled := false
		if cr <= 0 and buildings:
			for tq in buildings.queues.values():
				if tq != null and not tq["ready"]:
					stalled = true
		if stalled and int(Time.get_ticks_msec() / 400.0) % 2 == 0:
			credits_label.add_theme_color_override("font_color", COL_BAD)
			credits_label.text += "  NO FUNDS"
		else:
			credits_label.add_theme_color_override("font_color", COL_ACCENT)
	if buildings:
		var p := buildings.power_report(buildings.player_faction)
		power_label.text = "POWER    %d / %d" % [p.y, p.x]
		var low := p.y > p.x
		power_label.add_theme_color_override("font_color", COL_BAD if low else COL_GOOD)
		if low:
			power_label.text += "  LOW!"
		_refresh_build_buttons()
		_refresh_sw_button()
	_refresh_context()
	# separate from _refresh_context, which early-returns on the building branch
	_refresh_stance()
	if _announce_t > 0.0:
		_announce_t -= get_process_delta_time()
		announce_label.modulate.a = clampf(_announce_t / 1.5, 0.0, 1.0)
		if _announce_t <= 0.0:
			announce_label.text = ""


func _refresh_build_buttons() -> void:
	for tab in _item_buttons:
		var q = buildings.queues[tab]
		for e in _item_buttons[tab]:
			var btn: Button = e["btn"]
			var bar: ColorRect = e["bar"]
			var id: String = e["id"]
			var cost := int(buildings._cost_of(id))
			var ok := buildings.prereq_ok(id)
			btn.disabled = not ok
			bar.size.x = 0
			# how many of this unit are stacked (active + backlog)?
			var qcount := 0
			if EFBuildings.TRAIN.has(id):
				if q != null and q["id"] == id:
					qcount += 1
				if buildings.backlog.has(tab):
					for bid in buildings.backlog[tab]:
						if bid == id:
							qcount += 1
			var suffix := "  x%d" % qcount if qcount > 1 else ""
			if q != null and q["id"] == id:
				if q["ready"]:
					var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
					btn.text = "%s\nPLACE >" % EFBuildings.DEFS[id]["name"]
					btn.add_theme_color_override("font_color",
						COL_ACCENT.lerp(Color.WHITE, flash))
				else:
					btn.text = "%s\n%d%%%s" % [_name_of(id),
						int(q["paid"] / q["cost"] * 100.0), suffix]
					bar.size.x = 93.0 * q["paid"] / q["cost"]
			else:
				var wait := "  x%d" % qcount if qcount > 0 else ""
				if ok:
					btn.text = "%s\n$%d%s" % [_name_of(id), cost, wait]
				else:
					btn.text = "%s\nneeds %s" % [_name_of(id), buildings.missing_prereq(id)]
				btn.add_theme_color_override("font_color", COL_TEXT if ok else COL_DIM)
			if buildings.pending_place == id:
				btn.text = "%s\nPLACING" % _name_of(id)


func _name_of(id: String) -> String:
	if id == "doomworks":
		return buildings.display_name(id, buildings.player_faction)
	return EFBuildings.DEFS[id]["name"] if EFBuildings.DEFS.has(id) else \
		EFArmy.KINDS[id]["name"]


func _refresh_context() -> void:
	for l in context_lines:
		l.text = ""
	demolish_btn.visible = _sel_bld >= 0
	repair_btn.visible = _sel_bld >= 0
	if _sel_bld >= 0 and _sel_bld < buildings.list.size():
		var b: Dictionary = buildings.list[_sel_bld]
		var d: Dictionary = EFBuildings.DEFS[b["type"]]
		var full: bool = b["hp"] >= float(d["hp"])
		repair_btn.disabled = full
		repair_btn.text = "REPAIRING..." if buildings.repairing.has(_sel_bld) \
			and not full else "REPAIR"
		context_lines[0].text = String(d["name"])
		context_lines[0].add_theme_color_override("font_color", COL_ACCENT)
		context_lines[1].text = "HP %d / %d" % [int(b["hp"]), int(d["hp"])]
		context_lines[1].add_theme_color_override("font_color", COL_TEXT)
		var prod: Array = buildings.produces(b["type"])
		if not prod.is_empty():
			var names := []
			for pid in prod:
				names.append(EFArmy.KINDS[pid]["name"])
			context_lines[2].text = "recruits: " + ", ".join(PackedStringArray(names))
			context_lines[2].add_theme_color_override("font_color", COL_GOOD)
			context_lines[3].text = "use the highlighted tab above"
			context_lines[3].add_theme_color_override("font_color", COL_DIM)
		return
	if not _force_counts.is_empty():
		var names := _force_counts.keys()
		names.sort()
		var i := 0
		for n in names:
			if i >= 3:
				break
			context_lines[i].text = "%dx %s" % [_force_counts[n], n]
			context_lines[i].add_theme_color_override("font_color", COL_TEXT)
			i += 1
		if _harvest_hint:
			context_lines[3].text = "RMB — harvest this field"
			context_lines[3].add_theme_color_override("font_color", COL_ACCENT)
	elif not _survey.is_empty():
		context_lines[0].text = str(_survey[0])
		context_lines[1].text = "tile (%d, %d)" % [_survey[1], _survey[2]]
		context_lines[1].add_theme_color_override("font_color", COL_DIM)
		if _survey.size() > 3 and str(_survey[3]) != "":
			context_lines[2].text = str(_survey[3])
			context_lines[2].add_theme_color_override("font_color", COL_ACCENT)
	else:
		context_lines[0].text = "--"


func set_survey(hover: Array) -> void:
	_survey = hover


var _harvest_hint := false
var _objective_labels: Array[Label] = []


func set_objectives(lines: Array) -> void:
	for l in _objective_labels:
		l.queue_free()
	_objective_labels = []
	for i in range(lines.size()):
		var entry: Dictionary = lines[i]
		var l := Label.new()
		l.text = ("[X]  " if entry["done"] else "[ ]  ") + String(entry["text"])
		l.position = Vector2(14, 84 + i * 20)
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color",
			Color(0.55, 0.85, 0.5) if entry["done"] else COL_TEXT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_objective_labels.append(l)

func set_harvest_hint(v: bool) -> void:
	_harvest_hint = v


func set_force(counts: Dictionary) -> void:
	_force_counts = counts


func needs_stance_refresh() -> bool:
	return _stance_stale


func set_stance(options: Array, current: String, mixed: bool) -> void:
	_stance_opts = options
	_stance_cur = current
	_stance_mixed = mixed
	_stance_stale = false
	_refresh_stance()


func _refresh_stance() -> void:
	if stance_a_btn == null:
		return
	var show: bool = _sel_bld < 0 and _stance_opts.size() >= 2
	stance_a_btn.visible = show
	stance_b_btn.visible = show
	if not show:
		return
	# The label and the value the button emits MUST come from the same place. A
	# three-option infantry row shows the middle option on button A, and emitting
	# _stance_opts[0] instead made that button read LIGHT FEET and set STEADY,
	# leaving LIGHT FEET unreachable from the sidebar entirely.
	_pick_a = String(_stance_opts[1]) if _stance_opts.size() > 2 else String(_stance_opts[0])
	_pick_b = String(_stance_opts[_stance_opts.size() - 1])
	stance_a_btn.text = _pick_a
	stance_b_btn.text = _pick_b
	var a: String = _pick_a
	var b: String = _pick_b
	var pick_a: String = _pick_a
	if _stance_mixed:
		stance_a_btn.add_theme_color_override("font_color", COL_DIM)
		stance_b_btn.add_theme_color_override("font_color", COL_DIM)
	else:
		stance_a_btn.add_theme_color_override("font_color",
			COL_ACCENT if _stance_cur == pick_a else COL_TEXT)
		stance_b_btn.add_theme_color_override("font_color",
			COL_ACCENT if _stance_cur == b else COL_TEXT)


func set_formation_hint(shape: String, n: int) -> void:
	_form_shape = shape
	_form_n = n
	if _form_label == null:
		return
	_form_label.visible = shape != ""
	if shape != "":
		_form_label.text = "%s  ·  %d units  ·  wheel to change · drag to aim" % [shape, n]


func set_building(idx: int) -> void:
	_sel_bld = idx


func jump_tab(tab: String) -> void:
	_set_tab(tab)


func _set_tab(tab: String) -> void:
	active_tab = tab
	for t in _item_buttons:
		var vis: bool = t == tab
		for e in _item_buttons[t]:
			e["btn"].visible = vis
			e["bar"].visible = vis
	for t in _tab_buttons:
		var tb: Button = _tab_buttons[t]
		tb.add_theme_color_override("font_color", COL_ACCENT if t == tab else COL_DIM)


func show_pause(on: bool) -> void:
	pause_layer.visible = on


func _on_item(tab: String, id: String) -> void:
	if get_tree().paused:
		return
	buildings.click_item(tab, id)


func _on_item_rmb(e: InputEvent, tab: String, id: String) -> void:
	if e is InputEventMouseButton and e.pressed \
			and e.button_index == MOUSE_BUTTON_RIGHT:
		buildings.cancel_item(tab, id)


func _refresh_sw_button() -> void:
	var fac: int = buildings.player_faction
	var owns := false
	for b in buildings.list:
		if b["faction"] == fac and b["type"] == "doomworks" and b["hp"] > 0:
			owns = true
	sw_btn.visible = owns
	if not owns:
		_sw_was_ready = false
		return
	if buildings.sw_targeting:
		sw_btn.text = "%s: CLICK THE MAP" % buildings.sw_name(fac)
		sw_btn.add_theme_color_override("font_color", COL_BAD)
	elif buildings.sw_ready(fac):
		var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		sw_btn.text = "%s READY — SELECT TARGET" % buildings.sw_name(fac)
		sw_btn.add_theme_color_override("font_color",
			COL_BAD.lerp(Color.WHITE, flash))
		if not _sw_was_ready:
			_sw_was_ready = true
			announce("%s IS READY" % buildings.sw_name(fac), COL_ACCENT)
	else:
		_sw_was_ready = false
		sw_btn.text = "%s CHARGING  %d%%" % [buildings.sw_name(fac),
			int(buildings.sw_charge.get(fac, 0.0) / buildings.SW_TIME * 100.0)]
		sw_btn.add_theme_color_override("font_color", COL_DIM)


func announce(text: String, col: Color) -> void:
	announce_label.text = text
	announce_label.add_theme_color_override("font_color", col)
	announce_label.modulate.a = 1.0
	_announce_t = 4.0


func set_drag_rect(r: Rect2) -> void:
	band.rect = r
	band.queue_redraw()


func toggle_manual() -> void:
	manual_panel.visible = not manual_panel.visible


func show_game_over(win: bool, title_text := "", sub_text := "") -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(1280, 720)
	add_child(dim)
	var p := Panel.new()
	p.position = Vector2(360, 240)
	p.size = Vector2(560, 220)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.97)
	sb.border_color = COL_ACCENT if win else COL_BAD
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	var title := Label.new()
	title.text = title_text if title_text != "" else ("VICTORY" if win else "DEFEAT")
	title.position = Vector2(0, 40)
	title.size = Vector2(560, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", COL_ACCENT if win else COL_BAD)
	p.add_child(title)
	var sub := Label.new()
	if sub_text != "":
		sub.text = sub_text
	else:
		sub.text = "The enemy Command Post has fallen. The Cradle is yours." if win else "Your Command Post has fallen. The ash claims another army."
	sub.position = Vector2(0, 110)
	sub.size = Vector2(560, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", COL_TEXT)
	p.add_child(sub)
	var hint := Label.new()
	hint.text = "press  R  to return to command"
	hint.position = Vector2(0, 160)
	hint.size = Vector2(560, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_DIM)
	p.add_child(hint)


# --- minimap -------------------------------------------------------------------

const MM_DARK := Color(0.045, 0.05, 0.06)


func _minimap_image() -> Image:
	var img := Image.create_empty(world.w, world.h, false, Image.FORMAT_RGB8)
	for ty in range(world.h):
		for tx in range(world.w):
			img.set_pixel(tx, ty, MM_COLORS[world.tile_char(tx, ty)]
				if world.is_explored(tx, ty) else MM_DARK)
	for num in world.starts:
		var s: Vector2i = world.starts[num]
		if not world.is_explored(s.x, s.y):
			continue                    # enemy bases appear when scouted
		var col: Color = EFWorld.FACTIONS[world.slot_faction.get(num, num)]["color"]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px := s.x + dx
				var py := s.y + dy
				if px >= 0 and px < world.w and py >= 0 and py < world.h:
					img.set_pixel(px, py, col)
	_mm_img = img
	return img


func _on_revealed(cells: Array) -> void:
	if _mm_img == null:
		return
	for c in cells:
		_mm_img.set_pixel(c.x, c.y, MM_COLORS[world.tile_char(c.x, c.y)])
	for num in world.starts:
		var s: Vector2i = world.starts[num]
		if world.is_explored(s.x, s.y):
			var col: Color = EFWorld.FACTIONS[world.slot_faction.get(num, num)]["color"]
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px := s.x + dx
					var py := s.y + dy
					if px >= 0 and px < world.w and py >= 0 and py < world.h:
						_mm_img.set_pixel(px, py, col)
	minimap_rect.texture = ImageTexture.create_from_image(_mm_img)


func restore_pixel(tile: Vector2i) -> void:
	if _mm_img == null or not world.is_explored(tile.x, tile.y):
		return
	_mm_img.set_pixel(tile.x, tile.y, MM_COLORS["E"])
	minimap_rect.texture = ImageTexture.create_from_image(_mm_img)


func deplete_pixel(tile: Vector2i) -> void:
	if _mm_img:
		_mm_img.set_pixel(tile.x, tile.y, MM_COLORS[","])
		(minimap_rect.texture as ImageTexture).update(_mm_img)


func refresh_tiles(cells: Array) -> void:
	if _mm_img == null:
		return
	for c in cells:
		_mm_img.set_pixel(c.x, c.y, MM_COLORS[world.tile_char(c.x, c.y)])
	(minimap_rect.texture as ImageTexture).update(_mm_img)


func _on_minimap_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		mm_dragging = ev.pressed
		if ev.pressed:
			_mm_jump(ev.position)
	elif ev is InputEventMouseMotion and mm_dragging:
		_mm_jump(ev.position)


func _mm_jump(local: Vector2) -> void:
	var frac := (local / minimap_rect.size).clamp(Vector2.ZERO, Vector2.ONE)
	rig.center_on(frac.x * world.w * EFWorld.T, frac.y * world.h * EFWorld.T)


# --- the F1 field manual ---------------------------------------------------------

func _build_manual_overlay() -> void:
	manual_panel = Panel.new()
	manual_panel.position = Vector2(270, 130)
	manual_panel.size = Vector2(520, 400)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	sb.border_color = COL_ACCENT
	sb.set_border_width_all(2)
	manual_panel.add_theme_stylebox_override("panel", sb)
	manual_panel.visible = false
	add_child(manual_panel)
	var lines := [
		["FIELD MANUAL", COL_ACCENT],
		["", COL_TEXT],
		["CAMERA   WASD / arrows / screen edge pan", COL_TEXT],
		["         Q / E rotate · wheel zoom · minimap jump", COL_TEXT],
		["", COL_TEXT],
		["SELECT   LMB click · LMB drag box · SHIFT add", COL_TEXT],
		["         click a ruin your troops hold = garrison", COL_TEXT],
		["", COL_TEXT],
		["ORDERS   RMB move · RMB ember field = harvest", COL_TEXT],
		["         RMB ruin = garrison infantry · S stop", COL_TEXT],
		["         garrison selected + RMB ground = unload", COL_TEXT],
		["", COL_TEXT],
		["BUILD    pick a tab, click an item to start it", COL_TEXT],
		["         buildings: click PLACE, then click the map", COL_TEXT],
		["         walls keep placing until ESC / RMB", COL_TEXT],
		["         everything must touch your base (4 tiles)", COL_TEXT],
		["", COL_TEXT],
		["CRAWLER  drive it somewhere good, then press X", COL_TEXT],
		["         it unfolds INTO a Command Post — one use", COL_TEXT],
		["         three posts is the limit, six tiles apart", COL_TEXT],
		["", COL_TEXT],
		["STANCE   Z cycles the selected units' posture", COL_TEXT],
		["         infantry: light feet / dig in", COL_TEXT],
		["         vehicles: mobile / artillery (rooted, far)", COL_TEXT],
		["         aircraft: loiter / wide patrol", COL_TEXT],
		["", COL_TEXT],
		["F1 closes this manual", COL_DIM],
	]
	for i in range(lines.size()):
		var l := Label.new()
		l.text = lines[i][0]
		l.position = Vector2(24, 16 + i * 20)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", lines[i][1])
		manual_panel.add_child(l)


# --- tiny UI helpers -------------------------------------------------------------

func _style_button(btn: Button, font_size: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_EDGE
	sb.set_border_width_all(1)
	var sbh := sb.duplicate()
	sbh.bg_color = COL_PANEL_HI
	var sbd := sb.duplicate()
	sbd.bg_color = Color(0.1, 0.108, 0.124)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	btn.add_theme_stylebox_override("disabled", sbd)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_disabled_color", COL_DIM)


func _rect(r: Rect2, col: Color) -> void:
	var c := ColorRect.new()
	c.position = r.position
	c.size = r.size
	c.color = col
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _panel(r: Rect2, title: String = "") -> void:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_EDGE
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	if title != "":
		_label(title, r.position + Vector2(8, 3), 10, COL_DIM)


func _label(text: String, pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

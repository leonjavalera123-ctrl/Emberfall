# EMBERFALL: 1940 — settings_panel.gd
#
# One settings screen, mounted in two places: the title hall (menu.gd's
# _show_settings) and the pause overlay (main, mid-battle). It is a plain
# Control rather than a CanvasLayer precisely so it can be added to either —
# menu.gd and ui.gd are both CanvasLayers already, and nesting one inside
# another buys nothing.
#
# It carries its own palette instead of reaching into EFMenu's or EFUI's. Those
# two are near-identical copies of each other, and a third reference would make
# this screen depend on whichever host it happened to be inside — the one thing
# a screen with two hosts must not do.
#
# Nothing here stores state. Every control reads EFSettings when it is built and
# writes back through EFSettings when it moves; that is what makes the mid-match
# screen and the menu screen the same screen rather than two that agree.

class_name EFSettingsPanel
extends Control

signal closed()

const COL_PANEL := Color(0.11, 0.12, 0.14)
const COL_EDGE := Color(0.25, 0.275, 0.31)
const COL_TEXT := Color(0.81, 0.8, 0.76)
const COL_DIM := Color(0.5, 0.49, 0.47)
const COL_ACCENT := Color(0.89, 0.58, 0.23)

const ROWS := [
	["MASTER", EFSettings.BUS_MASTER, "everything at once"],
	["MUSIC", EFSettings.BUS_MUSIC, "the score and the anthem"],
	["SFX", EFSettings.BUS_SFX, "guns, engines, klaxons"],
]

var _value_labels := {}                  # bus name -> its percentage Label
var _res_buttons: Array[Button] = []
var _full_btn: Button
var _intro_btn: Button
var _shown_fullscreen := false           # what the FULLSCREEN row currently reads

# How hard to black out whatever is behind. The menu wants its own background
# art to survive, the way every other room leaves it showing; a battle wants to
# be gone. Set before add_child(), because _ready() builds the scrim.
var scrim_alpha := 0.94


func _ready() -> void:
	# The pause overlay is the whole reason this exists mid-match, so it must
	# keep processing while the tree is paused or its sliders would not move.
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	# STOP, so a click aimed at a slider cannot fall through to the battlefield
	# underneath and order the army somewhere.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.034, 0.042, scrim_alpha)
	scrim.size = Vector2(1280, 720)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# The box starts below y 110 so that in the menu it clears the EMBERFALL
	# title and its strapline, and the screen reads as one more room rather than
	# a slab dropped over the front page.
	var box := Panel.new()
	box.position = Vector2(330, 138)
	box.size = Vector2(620, 518)   # +48 for the PLAY INTRO row
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.09, 0.105, 0.98)
	sb.border_color = COL_EDGE
	sb.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_centred("SETTINGS", 110, 22, COL_ACCENT)
	_text("AUDIO", Vector2(366, 162), 12, COL_DIM)

	for i in range(ROWS.size()):
		var row: Array = ROWS[i]
		_volume_row(String(row[0]), String(row[1]), String(row[2]), 190 + i * 48)

	_text("VIDEO", Vector2(366, 336), 12, COL_DIM)

	_full_btn = Button.new()
	_full_btn.position = Vector2(366, 358)
	_full_btn.size = Vector2(548, 36)
	_style(_full_btn, 13)
	_full_btn.pressed.connect(func():
		EFSettings.set_fullscreen(not EFSettings.fullscreen)
		refresh())
	add_child(_full_btn)

	# Paired tight under FULLSCREEN rather than given its own block: both are
	# one-line VIDEO toggles, and the 8 px gap reads as "these two go together".
	_intro_btn = Button.new()
	_intro_btn.position = Vector2(366, 402)
	_intro_btn.size = Vector2(548, 36)
	_style(_intro_btn, 13)
	_intro_btn.pressed.connect(func():
		EFSettings.set_play_intro(not EFSettings.play_intro)
		refresh())
	add_child(_intro_btn)

	_text("SCREEN SIZE", Vector2(366, 458), 12, COL_DIM)
	for i in range(EFSettings.RESOLUTIONS.size()):
		var r: Array = EFSettings.RESOLUTIONS[i]
		var rb := Button.new()
		rb.position = Vector2(366 + i * 138, 480)
		rb.size = Vector2(132, 36)
		rb.text = "%d x %d" % [int(r[0]), int(r[1])]
		_style(rb, 12)
		rb.pressed.connect(func():
			EFSettings.set_res_index(i)
			refresh())
		add_child(rb)
		_res_buttons.append(rb)

	_text("Screen size applies in windowed mode. F11 toggles fullscreen at any time.",
		Vector2(366, 530), 11, COL_DIM)
	_text("Changes take effect immediately and are remembered for next time.",
		Vector2(366, 548), 11, COL_DIM)

	var back := Button.new()
	back.position = Vector2(490, 580)
	back.size = Vector2(300, 44)
	back.text = "< BACK"
	_style(back, 15)
	back.pressed.connect(func(): closed.emit())
	add_child(back)

	refresh()


func _volume_row(label: String, bus: String, blurb: String, y: int) -> void:
	_text(label, Vector2(366, y), 14, COL_TEXT)
	_text(blurb, Vector2(366, y + 18), 10, COL_DIM)

	var s := HSlider.new()
	s.position = Vector2(520, y + 2)
	s.size = Vector2(300, 20)
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = EFSettings.volume_of(bus)

	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.06, 0.065, 0.08)
	groove.border_color = COL_EDGE
	groove.set_border_width_all(1)
	groove.content_margin_top = 5
	groove.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_ACCENT
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	# AC-7: applied on the way past, not on BACK — the point of dragging a volume
	# slider is hearing what it did while you are still holding it.
	s.value_changed.connect(func(v: float):
		EFSettings.set_volume(bus, v)
		_set_value_label(bus, v))
	add_child(s)

	var vl := _text("", Vector2(838, y + 2), 13, COL_ACCENT)
	_value_labels[bus] = vl
	_set_value_label(bus, s.value)


func _set_value_label(bus: String, v: float) -> void:
	var l: Label = _value_labels.get(bus)
	if l == null:
		return
	# "MUTED" rather than "0%": the one value where the player most needs to be
	# sure of what they did is the one a percentage describes worst.
	l.text = "MUTED" if v <= 0.0 else "%d%%" % int(round(v * 100.0))
	l.add_theme_color_override("font_color", COL_DIM if v <= 0.0 else COL_ACCENT)


func _process(_dt: float) -> void:
	# F11 toggles fullscreen from anywhere, including from on top of this screen.
	# Rather than make every caller remember to tell us, notice: one bool compare
	# a frame beats a refresh() call that someone will eventually forget.
	if _shown_fullscreen != EFSettings.fullscreen:
		refresh()


func refresh() -> void:
	_shown_fullscreen = EFSettings.fullscreen
	_full_btn.text = "FULLSCREEN:  %s" % ("ON" if EFSettings.fullscreen else "OFF")
	_full_btn.add_theme_color_override("font_color",
		COL_ACCENT if EFSettings.fullscreen else COL_TEXT)
	# No _shown_ mirror for this one: F11 can change fullscreen behind the panel's
	# back, but nothing outside this button ever touches play_intro.
	_intro_btn.text = "PLAY INTRO:  %s" % ("ON" if EFSettings.play_intro else "OFF")
	_intro_btn.add_theme_color_override("font_color",
		COL_ACCENT if EFSettings.play_intro else COL_TEXT)
	for i in range(_res_buttons.size()):
		# Greyed while fullscreen, because in fullscreen the choice does nothing
		# and a control that silently does nothing is worse than one that says so.
		_res_buttons[i].disabled = EFSettings.fullscreen
		_res_buttons[i].add_theme_color_override("font_color",
			COL_ACCENT if i == EFSettings.res_index and not EFSettings.fullscreen
			else (COL_DIM if EFSettings.fullscreen else COL_TEXT))


# --- tiny builders ----------------------------------------------------------------

func _style(btn: Button, font_size: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_EDGE
	sb.set_border_width_all(1)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.16, 0.175, 0.2)
	sbh.border_color = COL_ACCENT
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", COL_TEXT)


func _text(s: String, pos: Vector2, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _centred(s: String, y: int, font_size: int, col: Color) -> void:
	var l := Label.new()
	l.text = s
	l.position = Vector2(0, y)
	l.size = Vector2(1280, font_size + 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)

# EMBERFALL: 1940 — menu.gd
# Three rooms: the title hall (CAMPAIGN / SKIRMISH / CONTINUE), the war
# chronicle (Act I missions with briefings), and the skirmish table.

class_name EFMenu
extends CanvasLayer

signal start_requested(faction: int, foe: int, map_path: String, difficulty: int,
	mcv_start: bool, mode: String, ally: int)

const MODES := [["1v1", "SKIRMISH", "one enemy, one front"],
	["ffa", "FREE FOR ALL", "all four banners, no friends"],
	["2v2", "ALLIED", "two against two"]]
signal campaign_requested(mission: int)
signal load_requested()

const COL_BG := Color(0.055, 0.06, 0.075)
const COL_PANEL := Color(0.11, 0.12, 0.14)
const COL_EDGE := Color(0.25, 0.275, 0.31)
const COL_TEXT := Color(0.81, 0.8, 0.76)
const COL_DIM := Color(0.5, 0.49, 0.47)
const COL_ACCENT := Color(0.89, 0.58, 0.23)

const FACTIONS := [
	[1, "KARVATH IRON CONCORD", "heavy armor · iron walls · the slow hammer",
		Color(0.72, 0.25, 0.18)],
	[2, "ASHFALL COMPACT", "cheap swarms · scrap tanks · the thousand cuts",
		Color(0.5, 0.52, 0.3)],
	[3, "AURELIAN LEAGUE", "sky power · fast strikes · the thousand sails",
		Color(0.28, 0.52, 0.73)],
	[4, "LUMINAR COVENANT", "arc lightning · shields · the second sun",
		Color(0.66, 0.51, 0.88)],
]
const MAPS := [
	["ASHFALL PLAIN", "192 x 128 · the standard battlefield",
		"res://maps/ashfall_plain.txt", 2],
	["THE CRADLE", "96 x 64 · tight and vicious", "res://maps/the_cradle.txt", 2],
	["CRADLE GATE", "64 x 48 · a knife fight", "res://maps/cradle_gate.txt", 2],
	["CRADLE LANDING", "64 x 48 · ridge and passes",
		"res://maps/cradle_landing.txt", 2],
	["GREYFEN REDOUBT", "96 x 64 · a ring in the open ash",
		"res://maps/greyfen_redoubt.txt", 2],
	["SAILWRIGHT REACH", "96 x 64 · a canal and three crossings",
		"res://maps/sailwright_reach.txt", 2],
	["THE FLAK COAST", "96 x 64 · an escarpment, two gaps",
		"res://maps/the_flak_coast.txt", 2],
	["THE CRADLE CROWN", "192 x 128 · four powers, one prize",
		"res://maps/the_cradle_crown.txt", 4],
	["EMBER SEA", "192 x 128 · islands of fire in the ash",
		"res://maps/ember_sea.txt", 4],
	["GREYFEN EXPANSE", "192 x 128 · the open waste, no mercy",
		"res://maps/greyfen_expanse.txt", 4],
]


func _map_starts(path: String) -> int:
	for m in MAPS:
		if String(m[2]) == path:
			return int(m[3])
	return 2
const DIFFS := [[1, "EASY", "a patient enemy, no superweapon"],
	[2, "STANDARD", "the war as designed"],
	[3, "BRUTAL", "big waves, short mercy"]]

var faction := 1
var foe := 2
var mode := "1v1"
var ally := 0                       # 2v2 partner; 0 until chosen
var _mode_buttons: Array[Button] = []
var difficulty := 2
var map_path: String = MAPS[0][2]
var sel_mission := 1
var sel_lore := 0
const BG_PATH := "res://textures/menu_bg.png"
const BG_VIDEO_PATH := "res://video/menu_bg.ogv"
static var _bg_tex: Texture2D = null
var _bg_layer: CanvasLayer = null
var _bg_video_ok := false


func _ensure_bg() -> void:
	# Build the animated background ONCE, on a layer beneath the menu's own
	# (this CanvasLayer sits on the engine default of 1). _clear() only frees
	# the menu's direct children — the bg layer is one of those, so it is
	# explicitly skipped there by name.
	if _bg_layer != null:
		return
	if not ResourceLoader.exists(BG_VIDEO_PATH):
		return
	var stream := load(BG_VIDEO_PATH) as VideoStream
	if stream == null:
		return
	_bg_layer = CanvasLayer.new()
	_bg_layer.name = "BGVideoLayer"
	_bg_layer.layer = 0
	add_child(_bg_layer)
	var vp := VideoStreamPlayer.new()
	vp.stream = stream
	# anchors, never a one-shot size: the intro taught us the engine resizes
	# this control to the video's native size when the first frame decodes
	vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.expand = true
	vp.loop = true                  # ambient loop; nothing awaits `finished`
	vp.bus = EFSettings.BUS_MUSIC   # muted with the music, as art should be
	vp.volume_db = -80.0            # the clip is silent, but belt and braces
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(vp)
	vp.play()
	_bg_video_ok = true
var _lore_buttons: Array[Button] = []
var sel_act := 1
var _room_missions: Array = []      # global mission ids shown in the current room
var _fac_buttons: Array[Button] = []
var _foe_buttons: Array[Button] = []
var _diff_buttons: Array[Button] = []
var _map_buttons: Array[Button] = []
var _mission_buttons: Array[Button] = []
var _start_buttons: Array[Button] = []
var mcv_start := false


func _ready() -> void:
	_show_root()


func _clear() -> void:
	for c in get_children():
		if c == _bg_layer:
			continue        # the animated background survives room changes
		c.queue_free()
	_fac_buttons = []
	_foe_buttons = []
	_diff_buttons = []
	_map_buttons = []
	_mission_buttons = []
	_start_buttons = []
	_room_missions = []
	_lore_buttons = []
	# The ANIMATED background lives on its own layer below the menu precisely so
	# it is NOT rebuilt per room — recreating a VideoStreamPlayer would restart
	# the loop on every button press. It must be decided BEFORE the base coat:
	# the coat is opaque and sits on the higher layer, so painting it over an
	# active video hides the video completely (observed: pitch-black menu).
	_ensure_bg()
	if not _bg_video_ok:
		var bg := ColorRect.new()
		bg.color = COL_BG
		bg.size = Vector2(1280, 720)
		add_child(bg)
	if _bg_video_ok:
		# the video layer is behind us; a scrim keeps the panels readable
		var scrim := ColorRect.new()
		scrim.color = Color(0.04, 0.045, 0.055, 0.55)
		scrim.size = Vector2(1280, 720)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scrim)
	else:
		if _bg_tex == null and ResourceLoader.exists(BG_PATH):
			_bg_tex = load(BG_PATH)
		if _bg_tex != null:
			var pic := TextureRect.new()
			pic.texture = _bg_tex
			pic.size = Vector2(1280, 720)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(pic)
			# a scrim so the panels and text keep their contrast over the art
			var scrim2 := ColorRect.new()
			scrim2.color = Color(0.04, 0.045, 0.055, 0.55)
			scrim2.size = Vector2(1280, 720)
			scrim2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(scrim2)
	_label("EMBERFALL: 1940", Vector2(0, 30), 40, COL_ACCENT, true)
	_label("AN ALTERNATE 1940 · THE CRADLE WAR", Vector2(0, 82), 12, COL_DIM, true)


# ============================ ROOT ============================

func _show_root() -> void:
	_clear()
	var entries := [
		["CAMPAIGN", "The Cradle War — four acts · twelve missions",
			func(): _show_campaign()],
		["SKIRMISH", "1v1, free for all, or allied 2v2",
			func(): _show_skirmish()],
	]
	if FileAccess.file_exists("user://savegame.json"):
		entries.append(["CONTINUE LAST WAR", "resume your saved battle",
			func(): load_requested.emit()])
	entries.append(["THE WORLD BIBLE", "the Emberfall, the four powers, the Cradle",
		func(): _show_lore()])
	entries.append(["SETTINGS", "volume · fullscreen · screen size",
		func(): _show_settings()])
	# There used to be a hard ceiling of four here, because the row was a fixed
	# 84 px on a 104 px pitch and a fifth ran to y 700 into the footer at 620.
	# The block is measured now: five entries (a save on disk plus SETTINGS makes
	# five) tighten to 66 on 84 and end at 592, and four keep the old geometry
	# exactly so the front page a stranger sees first has not moved.
	var n := entries.size()
	var row_h: int = 84 if n <= 4 else 66
	var pitch: int = 104 if n <= 4 else 84
	var y: int = 200 if n <= 4 else 190
	for e in entries:
		var b := Button.new()
		b.position = Vector2(440, y)
		b.size = Vector2(400, row_h)
		b.text = "%s\n%s" % [e[0], e[1]]
		_style(b, 17 if n <= 4 else 15)
		b.pressed.connect(e[2])
		add_child(b)
		y += pitch
	_label("F11 fullscreen · P pauses in battle · F1 field manual",
		Vector2(0, 620), 11, COL_DIM, true)


# ============================ CAMPAIGN ============================

func _show_campaign() -> void:
	_clear()
	# act tabs flank the heading: I and II on the left, III and IV on the right
	var numerals := ["I", "II", "III", "IV"]
	var tab_x := [40, 210, 900, 1070]
	for act in EFCampaign.ACTS.keys():
		var open: bool = EFCampaign.act_open(act)
		var tab := Button.new()
		tab.position = Vector2(tab_x[act - 1], 108)
		tab.size = Vector2(160, 30)
		tab.text = ("ACT %s" % numerals[act - 1]) if open \
			else ("ACT %s — SEALED" % numerals[act - 1])
		_style(tab, 11)
		tab.disabled = not open
		tab.add_theme_color_override("font_color",
			COL_ACCENT if act == sel_act else COL_TEXT)
		tab.pressed.connect(func():
			sel_act = act
			sel_mission = int(EFCampaign.act_missions(act)[0])
			_show_campaign())
		add_child(tab)

	if not EFCampaign.act_open(sel_act):
		sel_act = 1
	var a_cur: Dictionary = EFCampaign.ACTS[sel_act]
	_label("THE CRADLE WAR — %s" % String(a_cur["name"]), Vector2(0, 114), 14,
		COL_ACCENT, true)

	var ms: Array = EFCampaign.act_missions(sel_act)
	var unlocked: int = EFCampaign.unlocked(sel_act)
	if not ms.has(sel_mission):
		sel_mission = int(ms[0])
	for i in range(ms.size()):
		var mid: int = int(ms[i])
		var cfg: Dictionary = EFCampaign.MISSIONS[mid]
		var b := Button.new()
		b.position = Vector2(80 + i * 380, 148)
		b.size = Vector2(360, 54)
		# numbered 1-3 within the act, but keyed by the global mission id
		b.text = ("MISSION %d\n%s" % [i + 1, cfg["title"]]) if mid <= unlocked \
			else ("MISSION %d\n— SEALED ORDERS —" % (i + 1))
		_style(b, 13)
		b.disabled = mid > unlocked
		b.pressed.connect(func():
			sel_mission = mid
			_show_campaign())
		add_child(b)
		_mission_buttons.append(b)
		_room_missions.append(mid)

	# the briefing paper
	var p := Panel.new()
	p.position = Vector2(220, 220)
	p.size = Vector2(840, 336)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.09, 0.105)
	sb.border_color = COL_EDGE
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	var cfg2: Dictionary = EFCampaign.MISSIONS[sel_mission]
	_label(String(cfg2["title"]), Vector2(0, 232), 17, COL_ACCENT, true)
	var brief: Array = cfg2["brief"]
	for i in range(brief.size()):
		_label(String(brief[i]), Vector2(260, 268 + i * 19), 12, COL_TEXT, false)
	var oy := 268 + brief.size() * 19 + 8
	for i in range(cfg2["objectives"].size()):
		_label("□  " + String(cfg2["objectives"][i]),
			Vector2(260, oy + i * 18), 12, COL_DIM, false)

	var go := Button.new()
	go.position = Vector2(480, 578)
	go.size = Vector2(320, 56)
	go.text = "COMMENCE OPERATION"
	_style(go, 17)
	go.add_theme_color_override("font_color", COL_ACCENT)
	go.pressed.connect(func(): campaign_requested.emit(sel_mission))
	add_child(go)
	_back_button()
	_refresh()


# ============================ SKIRMISH ============================

func _show_skirmish() -> void:
	_clear()
	_mode_buttons = []
	_label("THE SHAPE OF THE WAR", Vector2(0, 104), 12, COL_DIM, true)
	for i in range(MODES.size()):
		var md: Array = MODES[i]
		var bm := Button.new()
		bm.position = Vector2(230 + i * 280, 120)
		bm.size = Vector2(270, 38)
		bm.text = "%s — %s" % [md[1], md[2]]
		_style(bm, 10)
		bm.pressed.connect(_pick_mode.bind(String(md[0])))
		add_child(bm)
		_mode_buttons.append(bm)

	_label("CHOOSE YOUR BANNER", Vector2(0, 166), 12, COL_DIM, true)
	for i in range(FACTIONS.size()):
		var f: Array = FACTIONS[i]
		var btn := Button.new()
		btn.position = Vector2(50 + i * 300, 182)
		btn.size = Vector2(290, 62)
		btn.text = "%s\n%s" % [f[1], f[2]]
		_style(btn, 11)
		btn.pressed.connect(_pick_faction.bind(int(f[0])))
		add_child(btn)
		_fac_buttons.append(btn)
		var swatch := ColorRect.new()
		swatch.color = f[3]
		swatch.position = btn.position + Vector2(0, 56)
		swatch.size = Vector2(290, 6)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(swatch)

	# the second row changes meaning with the mode: enemy in 1v1, ally in 2v2,
	# and in free-for-all there is nothing to choose — everyone is coming
	var row2 := "CHOOSE YOUR ENEMY"
	if mode == "2v2":
		row2 = "CHOOSE YOUR ALLY"
	elif mode == "ffa":
		row2 = "ALL BANNERS TAKE THE FIELD"
	_label(row2, Vector2(0, 258), 12, COL_DIM, true)
	for i in range(FACTIONS.size()):
		var f2: Array = FACTIONS[i]
		var btn2 := Button.new()
		btn2.position = Vector2(50 + i * 300, 274)
		btn2.size = Vector2(290, 36)
		btn2.text = String(f2[1])
		_style(btn2, 10)
		btn2.pressed.connect(_pick_foe.bind(int(f2[0])))
		add_child(btn2)
		_foe_buttons.append(btn2)

	_label("CHOOSE THE ODDS", Vector2(0, 322), 12, COL_DIM, true)
	for i in range(DIFFS.size()):
		var d: Array = DIFFS[i]
		var btnd := Button.new()
		btnd.position = Vector2(330 + i * 210, 338)
		btnd.size = Vector2(200, 38)
		btnd.text = "%s\n%s" % [d[1], d[2]]
		_style(btnd, 10)
		btnd.pressed.connect(_pick_diff.bind(int(d[0])))
		add_child(btnd)
		_diff_buttons.append(btnd)

	_label("CHOOSE THE BATTLEFIELD", Vector2(0, 388), 12, COL_DIM, true)
	for i in range(MAPS.size()):
		var m: Array = MAPS[i]
		var btn3 := Button.new()
		# five across now: ten maps must fit in two rows
		btn3.position = Vector2(22 + (i % 5) * 248, 404 + (i / 5) * 56)
		btn3.size = Vector2(238, 50)
		btn3.text = "%s\n%s" % [m[0], m[1]]
		_style(btn3, 9)
		btn3.pressed.connect(_pick_map.bind(String(m[2])))
		add_child(btn3)
		_map_buttons.append(btn3)

	# how the match opens: a standing base, or a crawler you must plant yourself
	_label("HOW YOU ARRIVE", Vector2(0, 522), 12, COL_DIM, true)
	for i in range(2):
		var ob := Button.new()
		ob.position = Vector2(330 + i * 310, 538)
		ob.size = Vector2(300, 36)
		ob.text = ["ESTABLISHED BASE", "CRAWLER LANDING"][i]
		_style(ob, 11)
		ob.pressed.connect(func():
			mcv_start = i == 1
			_refresh())
		add_child(ob)
		_start_buttons.append(ob)

	var start := Button.new()
	start.position = Vector2(480, 590)
	start.size = Vector2(320, 52)
	start.text = "BEGIN THE WAR"
	_style(start, 18)
	start.add_theme_color_override("font_color", COL_ACCENT)
	start.pressed.connect(_emit_start)
	add_child(start)
	_back_button()
	_refresh()


func _emit_start() -> void:
	if mode == "2v2" and ally == 0:
		return                      # no ally picked yet; the row is highlighted
	if mode != "1v1" and _map_starts(map_path) < 4:
		return                      # gated: this battlefield lacks four starts
	var out_foe := foe
	if mode != "1v1":
		# first enemy is just "some hostile faction" — main derives the roster
		for f in [1, 2, 3, 4]:
			if f != faction and f != ally:
				out_foe = f
				break
	start_requested.emit(faction, out_foe, map_path, difficulty, mcv_start,
		mode, ally)


func _pick_mode(m: String) -> void:
	mode = m
	if mode == "2v2":
		if ally == faction or ally == 0:
			ally = 1 if faction != 1 else 2
	else:
		ally = 0
	# multi-side wars need a four-start battlefield: hop to the first one
	if mode != "1v1" and _map_starts(map_path) < 4:
		for mm in MAPS:
			if int(mm[3]) >= 4:
				map_path = String(mm[2])
				break
	_show_skirmish()


# ============================ SETTINGS ============================
# The room itself is EFSettingsPanel, because the pause overlay shows the very
# same screen mid-battle (AC-10) and two copies of a volume slider is two
# chances for them to disagree.

func _show_settings() -> void:
	_clear()
	var p := EFSettingsPanel.new()
	p.scrim_alpha = 0.55        # let the background art through, like every room
	p.closed.connect(func(): _show_root())
	add_child(p)


# ============================ LORE ============================

func _show_lore() -> void:
	_clear()
	# page selector: 0 is the world, 1-4 are the factions in id order
	for i in range(EFLore.PAGES.size()):
		var page: Dictionary = EFLore.PAGES[i]
		var b := Button.new()
		b.position = Vector2(40 + i * 242, 118)
		b.size = Vector2(232, 44)
		b.text = String(page["title"])
		_style(b, 11)
		b.add_theme_color_override("font_color",
			COL_ACCENT if i == sel_lore else COL_TEXT)
		b.pressed.connect(func():
			sel_lore = i
			_show_lore())
		add_child(b)
		_lore_buttons.append(b)
		if i >= 1:
			var sw := ColorRect.new()
			sw.color = FACTIONS[i - 1][3]
			sw.position = b.position + Vector2(0, 38)
			sw.size = Vector2(232, 6)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(sw)

	# the page itself, on an opaque panel so the background art cannot wash it out
	var p := Panel.new()
	p.position = Vector2(100, 176)
	p.size = Vector2(1080, 440)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.08, 0.095, 0.96)
	sb.border_color = COL_EDGE
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)

	var cur: Dictionary = EFLore.PAGES[sel_lore]
	var rt := RichTextLabel.new()
	rt.position = Vector2(124, 196)
	rt.size = Vector2(1032, 400)
	rt.bbcode_enabled = true
	rt.fit_content = false       # must stay false or it grows past the panel
	rt.scroll_active = true      # and the scrollbar never appears
	rt.scroll_following = false
	# RichTextLabel ignores "font_size" — these are the keys it actually reads
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_font_size_override("bold_font_size", 13)
	rt.add_theme_font_size_override("italics_font_size", 13)
	rt.add_theme_color_override("default_color", COL_TEXT)
	rt.text = String(cur["body"])
	add_child(rt)               # mouse_filter left alone: IGNORE kills wheel scroll

	_label("scroll for more", Vector2(0, 622), 11, COL_DIM, true)
	_back_button()


func _back_button() -> void:
	var b := Button.new()
	b.position = Vector2(40, 640)
	b.size = Vector2(140, 40)
	b.text = "< BACK"
	_style(b, 13)
	b.pressed.connect(func(): _show_root())
	add_child(b)


func _pick_faction(f: int) -> void:
	faction = f
	if foe == faction:
		foe = 1 if faction != 1 else 2
	if ally == faction:
		ally = 1 if faction != 1 else 2
	_refresh()


func _pick_foe(f: int) -> void:
	if f == faction:
		return
	if mode == "2v2":
		ally = f          # in the allied room this row picks your partner
	else:
		foe = f
	_refresh()


func _pick_map(m: String) -> void:
	map_path = m
	_refresh()


func _pick_diff(d: int) -> void:
	difficulty = d
	_refresh()


func _refresh() -> void:
	for i in range(_mode_buttons.size()):
		_mode_buttons[i].add_theme_color_override("font_color",
			COL_ACCENT if String(MODES[i][0]) == mode else COL_TEXT)
	for i in range(_fac_buttons.size()):
		_fac_buttons[i].add_theme_color_override("font_color",
			COL_ACCENT if int(FACTIONS[i][0]) == faction else COL_TEXT)
	for i in range(_foe_buttons.size()):
		var fid: int = int(FACTIONS[i][0])
		_foe_buttons[i].disabled = fid == faction or mode == "ffa"
		var lit := fid == (ally if mode == "2v2" else foe) and mode != "ffa"
		_foe_buttons[i].add_theme_color_override("font_color",
			COL_ACCENT if lit else (COL_DIM if fid == faction or mode == "ffa"
				else COL_TEXT))
	for i in range(_diff_buttons.size()):
		_diff_buttons[i].add_theme_color_override("font_color",
			COL_ACCENT if int(DIFFS[i][0]) == difficulty else COL_TEXT)
	for i in range(_map_buttons.size()):
		var lacks := mode != "1v1" and int(MAPS[i][3]) < 4
		_map_buttons[i].disabled = lacks
		_map_buttons[i].add_theme_color_override("font_color",
			COL_ACCENT if String(MAPS[i][2]) == map_path else
			(COL_DIM if lacks else COL_TEXT))
	for i in range(_start_buttons.size()):
		_start_buttons[i].add_theme_color_override("font_color",
			COL_ACCENT if (i == 1) == mcv_start else COL_TEXT)
	for i in range(_mission_buttons.size()):
		if not _mission_buttons[i].disabled and i < _room_missions.size():
			_mission_buttons[i].add_theme_color_override("font_color",
				COL_ACCENT if int(_room_missions[i]) == sel_mission else COL_TEXT)


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


func _label(text: String, pos: Vector2, size: int, col: Color, center: bool) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if center:
		l.position = Vector2(0, pos.y)
		l.size = Vector2(1280, size + 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)

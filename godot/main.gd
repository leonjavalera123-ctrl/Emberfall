# EMBERFALL: 1940 — main.gd
# Phase 7: the full game loop. Skirmish menu (faction + map) -> the war
# (economy, building, combat, an AI commander) -> victory or defeat when a
# Command Post falls. R returns to the menu.
#
# Dev screenshots (menu is bypassed, defaults: Karvath on Ashfall Plain):
#   ... -- --selftest shot.png [--start N] [--march] [--garrison]
#   ... -- --selftest shot.png --econ | --build | --war
#   ... -- --selftest shot.png --ai        (watch the enemy commander think)
#   ... -- --selftest shot.png --gameover  (prove the defeat path)
#
# The vertical slice (VERTICAL_SLICE.md) adds five, all of which quit on their
# own and none of which need the --selftest harness:
#   ... -- --onboard              M1's teaching prompts, in order, once each
#   ... -- --onboard-off N        the same triggers on mission N: silence
#   ... -- --settings             volumes/fullscreen/resolution round-trip
#   ... -- --busvol               a zeroed fader is -inf AT THE BUS
#   ... -- --settingsshot out.png [--in-game]  how the screen actually looks
#   ... -- --intro out.png        the studio logo plays, advances, and skips

extends Node3D

const T := 2.0
const VIEW_W := 1060.0

var world: EFWorld
var rig: CameraRig
var ui: EFUI
var army: EFArmy
var economy: EFEconomy
var structures: EFStructures
var buildings: EFBuildings
var ais: Array[EFAI] = []
var ai: EFAI:                   # compat alias: campaign + selftests poke main.ai
	get:
		return ais[0] if ais.size() > 0 else null
var audio: EFAudio
var music: EFMusic
var campaign: EFCampaign
var menu: EFMenu
var intro: EFIntro

# The studio logo plays ONCE per process. _quit_to_menu(), and the F9 and R
# branches of _unhandled_input(), all call reload_current_scene(), which destroys
# this node and re-runs _ready() from the top with identical argv — an instance
# var would reset with it and the logo would replay on every death. A static
# survives the reload; that statics do is the whole reason EFUnit.reset_visual_
# caches() has to be called by hand up in _ready().
static var _intro_played := false

var player_fac := 1
var ai_fac := 2                 # primary enemy (campaign / selftest alias)
var enemy_facs: Array[int] = [2]
var ally_fac := 0               # 0 = fighting alone
var cur_mode := "1v1"           # "1v1" | "ffa" | "2v2"
var cur_difficulty := 2
var cur_mcv_start := false      # match began with crawlers instead of bases
var cur_map := "res://maps/ashfall_plain.txt"
var game_over := false
var victory := false
var _hq_player := -1
var _hq_enemy := -1
var _fallen := {}               # faction -> true once eliminated (announced)

var _dragging := false
var _drag_start := Vector2.ZERO
var _hover_tile := Vector2i(-1, -1)
var _ghost: MeshInstance3D
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _harvest_marker: MeshInstance3D
var sel_building := -1
var _bld_marker: MeshInstance3D
var _groups := {}       # Ctrl+1..9 stores a control group; 1..9 recalls it

const DBL_MS := 350
const DBL_PX := 12.0
const RMB_HOLD_MS := 220
var _last_click_ms: int = 0
var _last_click_pos := Vector2(-1e9, -1e9)
var _rmb_down := false
var _rmb_ms: int = 0
var _rmb_pos := Vector2.ZERO
var _rmb_preview := false
var _shape_i := 0                       # index into EFArmy.SHAPES
var _ghost_pool: Array[MeshInstance3D] = []
var _face_ghost: MeshInstance3D = null  # arrow showing which way the line faces
var _form_rot := -1.0                   # wheel-aimed facing in radians; <0 = auto
var _settings_panel: EFSettingsPanel = null   # non-null while it is up mid-battle
# Has the player ever right-clicked an order to anyone? AC-2's prompt teaches
# exactly that gesture, so having used it once is proof the lesson is not needed.
var player_ordered := false


func _ready() -> void:
	# main stays awake through tree-pause so P can unpause; the game systems
	# below are explicitly pausable
	process_mode = Node.PROCESS_MODE_ALWAYS
	EFUnit.reset_visual_caches()      # material ids are not stable across reloads

	# AC-9: the player's settings are back in force before anything can be heard.
	# Audio always — the buses exist whatever we booted for. The WINDOW only on a
	# real launch: a dev flag inheriting somebody's 2560x1440 fullscreen would
	# report an FPS number that cannot be compared with the baseline, and would
	# save its screenshot from a viewport nobody asked for.
	EFSettings.load_settings()
	EFSettings.apply_audio()
	if OS.get_cmdline_user_args().is_empty():
		EFSettings.apply_video()

	_setup_sky_and_light()

	# The score lives here, on main, and is deliberately left out of the
	# PAUSABLE list below so it plays over the pause overlay (ducked).
	music = EFMusic.new()
	add_child(music)

	var uargs := OS.get_cmdline_user_args()
	if uargs.has("--settingsshot"):
		# The settings screen has two hosts and they must look like one screen.
		# Pass --in-game to shoot the one that opens over a paused battle.
		var spath := "user://settings.png"
		var sshot := uargs.find("--settingsshot")
		if sshot + 1 < uargs.size() and not uargs[sshot + 1].begins_with("--"):
			spath = uargs[sshot + 1]
		if uargs.has("--in-game"):
			_on_campaign_start(1)
			for i in range(30):
				await get_tree().process_frame
			_toggle_pause()
			# The overlay is the other half of AC-10. It is the door; shoot it
			# before walking through, or the picture only proves the room exists
			# and says nothing about whether anyone can find it.
			for i in range(10):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var ppath := spath.get_basename() + "_pause.png"
			get_viewport().get_texture().get_image().save_png(ppath)
			print("pause overlay screenshot -> %s" % ppath)
			_open_settings()
		else:
			menu = EFMenu.new()
			add_child(menu)
			menu._show_settings()
		for i in range(20):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(spath)
		print("settings screenshot -> %s (in_game=%s)" % [spath, uargs.has("--in-game")])
		get_tree().quit()
		return
	if uargs.has("--intro"):
		# Four claims, because three of them can pass while the logo is broken:
		# the stream loads and plays; it ADVANCES (a decoder frozen on frame zero
		# still reports is_playing); it is actually ON SCREEN (a black frame would
		# satisfy everything above); and a keypress through the real handler
		# kills it. Engine.time_scale stays 1.0 throughout — _wait_seconds counts
		# scaled delta but Theora decode does not ride that clock, so every
		# measurement below is wall-clock.
		var ipath := "user://intro.png"
		var ii := uargs.find("--intro")
		if ii + 1 < uargs.size() and not uargs[ii + 1].begins_with("--"):
			ipath = uargs[ii + 1]
		var iv := EFIntro.new()
		add_child(iv)
		# Grace window first: an event landing in the opening milliseconds — the
		# Enter that launched the game from a shortcut — must NOT eat the logo.
		var early := InputEventKey.new()
		early.keycode = KEY_ESCAPE
		early.pressed = true
		iv._input(early)
		var grace_held := not iv.is_done
		print("intro: keypress inside the %d ms grace — survived=%s (must be true)"
			% [EFIntro.INPUT_GRACE_MS, grace_held])
		await _wait_seconds(0.5)
		if iv.player == null:
			print("intro: VERDICT FAIL — nothing loaded from %s" % EFIntro.VIDEO_PATH)
			get_tree().quit()
			return
		var vp: VideoStreamPlayer = iv.player
		print("intro: load=%d ms length=%.2f s playing=%s bus=%s (playing must be true, bus must be Music)"
			% [iv.load_ms, vp.get_stream_length(), vp.is_playing(), vp.bus])
		var w0 := Time.get_ticks_msec()
		var p0 := vp.stream_position
		await _wait_seconds(1.0)
		var wall := Time.get_ticks_msec() - w0
		var p1 := vp.stream_position
		var advanced := p1 > p0
		print("intro: stream_position %.2f -> %.2f over %d ms wall — ratio %.2f (must rise; ratio near 1.00 means the decoder keeps up)"
			% [p0, p1, wall, (p1 - p0) / maxf(wall / 1000.0, 0.001)])
		for i in range(10):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ipath)
		var luma := 0.0
		for y in range(0, img.get_height(), 16):
			for x in range(0, img.get_width(), 16):
				luma = maxf(luma, img.get_pixel(x, y).get_luminance())
		var lit := luma > 0.05
		print("intro screenshot -> %s  max_luma=%.3f (must exceed 0.05 — a black PNG proves nothing)"
			% [ipath, luma])
		# The hold contract: input through the REAL handler must be ignored
		# before SHOW_MIN_MS — the wordmark lands late and the studio name must
		# always be seen — and after the hold a keypress starts the FADE, never
		# a hard cut.
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		iv._input(esc)
		await _wait_seconds(0.3)
		var held_early := vp.is_playing() and not iv.fading and not iv.is_done
		print("intro: ESC at ~2s — still playing=%s fading=%s (must be true / false: the 14 s hold)"
			% [vp.is_playing(), iv.fading])
		# wait out the hold, then the same key must begin the fade
		var hold_end: int = iv._t0 + EFIntro.SHOW_MIN_MS
		await _wait_until(func(): return Time.get_ticks_msec() >= hold_end, 16.0)
		var esc2 := InputEventKey.new()
		esc2.keycode = KEY_ESCAPE
		esc2.pressed = true
		iv._input(esc2)
		await _wait_seconds(0.2)
		var fade_began := iv.fading and not iv.is_done
		var veil_rising := iv._fade_rect != null and iv._fade_rect.color.a > 0.0
		print("intro: ESC after the hold — fading=%s veil alpha=%.2f (fade must be underway, not a cut)"
			% [iv.fading, iv._fade_rect.color.a if iv._fade_rect != null else -1.0])
		var t_done := Time.get_ticks_msec()
		if not iv.is_done:
			await iv.done
		var fade_took := (Time.get_ticks_msec() - t_done) / 1000.0
		var shown_s := (Time.get_ticks_msec() - iv._t0) / 1000.0
		print("intro: done after %.1f s on screen, fade ran %.2f s (shown must be >= 14, fade ~%.1f)"
			% [shown_s, fade_took, EFIntro.FADE_S])
		var held_14 := shown_s >= 14.0
		iv.queue_free()
		await get_tree().process_frame
		var gone := not is_instance_valid(iv)
		print("intro: overlay freed=%s (must be true)" % [gone])
		print("intro: VERDICT %s"
			% ["PASS" if grace_held and advanced and lit and held_early
				and fade_began and veil_rising and held_14 and gone
				else "FAIL"])
		get_tree().quit()
		return
	if uargs.has("--menushot"):
		menu = EFMenu.new()
		add_child(menu)
		if uargs.has("--room-campaign"):
			menu._show_campaign()
		elif uargs.has("--room-act2"):
			menu.sel_act = 2
			menu.sel_mission = int(EFCampaign.act_missions(2)[0])
			menu._show_campaign()
		elif uargs.has("--room-skirmish"):
			menu._show_skirmish()
		elif uargs.has("--room-lore"):
			var li := uargs.find("--lore-page")
			if li != -1 and li + 1 < uargs.size():
				menu.sel_lore = int(uargs[li + 1])
			menu._show_lore()
		_menushot(uargs)
		return
	if uargs.has("--missionshot"):
		var mi := uargs.find("--missionshot")
		var mmid := int(uargs[mi + 1])
		var mpath := String(uargs[mi + 2])
		_on_campaign_start(mmid)
		for i in range(40):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(mpath)
		print("mission %d screenshot -> %s" % [mmid, mpath])
		get_tree().quit()
		return
	if uargs.has("--unlockcheck"):
		# the progression backbone: if this is wrong, Act II is unreachable.
		# The player's REAL progress is stashed and restored — this harness used
		# to delete campaign.cfg outright and leave its own unlocks behind, so
		# running the dev suite wiped a genuine playthrough.
		var d := DirAccess.open("user://")
		var stash := ""
		if d != null and d.file_exists("campaign.cfg"):
			var fh := FileAccess.open("user://campaign.cfg", FileAccess.READ)
			if fh != null:
				stash = fh.get_as_text()
				fh.close()
			d.remove("campaign.cfg")
		print("fresh: act1 unlocked=%d act2 unlocked=%d act2_open=%s"
			% [EFCampaign.unlocked(1), EFCampaign.unlocked(2),
				EFCampaign.act_open(2)])
		EFCampaign.unlock(2)
		EFCampaign.unlock(3)
		print("after winning 1 and 2: act1=%d act2_open=%s"
			% [EFCampaign.unlocked(1), EFCampaign.act_open(2)])
		EFCampaign.unlock(4)                      # finishing mission 3 of act I
		print("after winning act I: act1=%d act2=%d act2_open=%s"
			% [EFCampaign.unlocked(1), EFCampaign.unlocked(2),
				EFCampaign.act_open(2)])
		EFCampaign.unlock(5)
		EFCampaign.unlock(6)
		EFCampaign.unlock(7)                      # act II done -> act III opens
		print("after winning act II: act2=%d act3_open=%s"
			% [EFCampaign.unlocked(2), EFCampaign.act_open(3)])
		for m in range(8, 13):
			EFCampaign.unlock(m)
		# 13 is now the past-the-end case (missions run 1..12), not 7
		EFCampaign.unlock(13)
		print("after winning all four acts: act4=%d (13 must not stick) has_13=%s"
			% [EFCampaign.unlocked(4), EFCampaign.MISSIONS.has(13)])
		print("act_of: 1->%d 4->%d 7->%d 10->%d 12->%d" % [EFCampaign.act_of(1),
			EFCampaign.act_of(4), EFCampaign.act_of(7), EFCampaign.act_of(10),
			EFCampaign.act_of(12)])
		# put the player's own progress back exactly as it was
		if stash != "":
			var fw := FileAccess.open("user://campaign.cfg", FileAccess.WRITE)
			if fw != null:
				fw.store_string(stash)
				fw.close()
		elif d != null and d.file_exists("campaign.cfg"):
			d.remove("campaign.cfg")
		print("unlockcheck: player progress restored=%s" % [stash != ""])
		get_tree().quit()
		return

	if uargs.has("--busvol"):
		# AC-11: prove silence at the MIXER. A slider that reads 0% while the bus
		# sits at 0 dB is exactly the bug this flag exists to catch, so nothing
		# here reads a UI value.
		var probe := EFAudio.new()
		add_child(probe)
		await get_tree().process_frame
		var bnames := []
		for bi in range(AudioServer.get_bus_count()):
			bnames.append(AudioServer.get_bus_name(bi))
		print("busvol: buses=%s (must be Master, Music, SFX)" % [bnames])
		var m_idx := AudioServer.get_bus_index(EFSettings.BUS_MUSIC)
		var s_idx := AudioServer.get_bus_index(EFSettings.BUS_SFX)
		print("busvol: Music=%d -> '%s' | SFX=%d -> '%s' (both must send to Master)"
			% [m_idx, AudioServer.get_bus_send(m_idx) if m_idx >= 0 else "?",
				s_idx, AudioServer.get_bus_send(s_idx) if s_idx >= 0 else "?"])
		print("busvol: routing — music bed='%s' war='%s' | sfx 3d='%s' ui='%s'"
			% [music.bed.bus if music.bed != null else "?",
				music.war.bus if music.war != null else "?",
				probe._pool[0].bus, probe._ui_pool[0].bus])
		var st_bv := _stash_user_file("settings.cfg")
		EFSettings.reset_to_defaults()
		EFSettings.apply_audio()
		print("busvol: at full — Music %.2f dB SFX %.2f dB (both must be 0)"
			% [AudioServer.get_bus_volume_db(m_idx),
				AudioServer.get_bus_volume_db(s_idx)])
		EFSettings.set_volume(EFSettings.BUS_SFX, 0.0)
		var sfx_zero := AudioServer.get_bus_volume_db(s_idx)
		print("busvol: SFX slider to zero — bus %.2f dB is_inf=%s SILENT=%s"
			% [sfx_zero, is_inf(sfx_zero), sfx_zero == -INF])
		print("busvol: ...and Music was not touched by it — %.2f dB (must be 0)"
			% AudioServer.get_bus_volume_db(m_idx))
		EFSettings.set_volume(EFSettings.BUS_MUSIC, 0.0)
		var mus_zero := AudioServer.get_bus_volume_db(m_idx)
		print("busvol: Music slider to zero — bus %.2f dB SILENT=%s"
			% [mus_zero, mus_zero == -INF])
		EFSettings.set_volume(EFSettings.BUS_SFX, 0.5)
		print("busvol: SFX back to 50%% — bus %.2f dB (linear_to_db(0.5)=%.2f)"
			% [AudioServer.get_bus_volume_db(s_idx), linear_to_db(0.5)])
		EFSettings.set_volume(EFSettings.BUS_MASTER, 0.0)
		print("busvol: Master to zero — bus %.2f dB SILENT=%s (kills everything)"
			% [AudioServer.get_bus_volume_db(AudioServer.get_bus_index(
				EFSettings.BUS_MASTER)),
				AudioServer.get_bus_volume_db(AudioServer.get_bus_index(
					EFSettings.BUS_MASTER)) == -INF])
		EFSettings.reset_to_defaults()
		EFSettings.apply_audio()
		_restore_user_file("settings.cfg", st_bv)
		print("busvol: player settings restored=%s" % [st_bv != ""])
		get_tree().quit()
		return

	if uargs.has("--settings"):
		# AC-7/AC-8/AC-9: set every value, save, throw memory away, reload — the
		# reload is the "next launch" path, run for real rather than simulated.
		var st_set := _stash_user_file("settings.cfg")
		EFSettings.reset_to_defaults()
		print("settings: defaults master=%.2f music=%.2f sfx=%.2f fullscreen=%s res=%s"
			% [EFSettings.master, EFSettings.music, EFSettings.sfx,
				EFSettings.fullscreen, EFSettings.resolution()])
		EFSettings.set_volume(EFSettings.BUS_MASTER, 0.42)
		EFSettings.set_volume(EFSettings.BUS_MUSIC, 0.0)
		EFSettings.set_volume(EFSettings.BUS_SFX, 0.75)
		EFSettings.set_fullscreen(true)
		EFSettings.set_res_index(2)
		# false, because the default is true — a round trip that writes the
		# default proves nothing about whether the value survived the disk.
		EFSettings.set_play_intro(false)
		print("settings: wrote  master=%.2f music=%.2f sfx=%.2f fullscreen=%s res=%s"
			% [EFSettings.master, EFSettings.music, EFSettings.sfx,
				EFSettings.fullscreen, EFSettings.resolution()])
		print("settings: %s exists=%s" % [EFSettings.PATH,
			FileAccess.file_exists(EFSettings.PATH)])
		EFSettings.reset_to_defaults()
		print("settings: memory wiped   master=%.2f sfx=%.2f fullscreen=%s res=%s"
			% [EFSettings.master, EFSettings.sfx, EFSettings.fullscreen,
				EFSettings.resolution()])
		EFSettings.load_settings()
		var ok_rt: bool = is_equal_approx(EFSettings.master, 0.42) \
			and EFSettings.music == 0.0 and is_equal_approx(EFSettings.sfx, 0.75) \
			and EFSettings.fullscreen and EFSettings.res_index == 2 \
			and not EFSettings.play_intro
		print("settings: reloaded master=%.2f music=%.2f sfx=%.2f fullscreen=%s res=%s intro=%s"
			% [EFSettings.master, EFSettings.music, EFSettings.sfx,
				EFSettings.fullscreen, EFSettings.resolution(),
				EFSettings.play_intro])
		print("settings: ROUND TRIP=%s (must be true)" % ok_rt)
		EFSettings.apply_audio()
		var si2 := AudioServer.get_bus_index(EFSettings.BUS_SFX)
		var mi2 := AudioServer.get_bus_index(EFSettings.BUS_MUSIC)
		print("settings: mixer followed the reload — SFX %.2f dB Music %.2f dB (Music must be -inf)"
			% [AudioServer.get_bus_volume_db(si2),
				AudioServer.get_bus_volume_db(mi2)])
		# an out-of-range index on disk must not be able to crash a later launch
		var bad := ConfigFile.new()
		bad.set_value("video", "res_index", 99)
		bad.save(EFSettings.PATH)
		EFSettings.load_settings()
		print("settings: res_index 99 from disk clamps to %d -> %s"
			% [EFSettings.res_index, EFSettings.resolution()])
		# leave the machine exactly as it was found
		EFSettings.reset_to_defaults()
		EFSettings.apply_video()
		EFSettings.apply_audio()
		_restore_user_file("settings.cfg", st_set)
		print("settings: player settings restored=%s" % [st_set != ""])
		get_tree().quit()
		return

	if uargs.has("--onboard"):
		# AC-1..AC-6, end to end. Every prompt is reached through the trigger a
		# player would reach it through — nothing calls show_hint() directly —
		# and in the order a player would meet them.
		_on_campaign_start(1)
		rig.set_process(false)
		rig.set_process_unhandled_input(false)
		# The 20 s idle clock is real; it just runs faster. mission_t accumulates
		# the same scaled delta _wait_seconds counts, so the two stay honest.
		Engine.time_scale = 4.0
		for i in range(10):
			await get_tree().process_frame

		await _wait_until(func(): return ui.hints_shown.size() >= 1, 10.0)
		print("onboard AC-1 [M1 begins] %s" % _hint_at(0))

		# AC-2: issue nothing at all, and let the mission clock run past 20 s
		await _wait_until(func(): return ui.hints_shown.size() >= 2, 60.0)
		print("onboard AC-2 [no order by t=%.0fs, player_ordered=%s] %s"
			% [campaign.mission_t, player_ordered, _hint_at(1)])

		# AC-3a: a click on a DISABLED tab item, through ui's real handler
		var lmb := InputEventMouseButton.new()
		lmb.button_index = MOUSE_BUTTON_LEFT
		lmb.pressed = true
		print("onboard AC-3a: airfield prereq_ok=%s (must be false — it is greyed out)"
			% buildings.prereq_ok("airfield"))
		ui._on_item_gui_input(lmb, "BASE", "airfield")
		await _wait_until(func(): return ui.hints_shown.size() >= 3, 15.0)
		print("onboard AC-3a [clicked a disabled AIRFIELD] %s" % _hint_at(2))

		# AC-3b: an item that is unlocked but unaffordable
		economy.credits[player_fac] = 50
		buildings.click_item("BASE", "boiler")
		await _wait_until(func(): return ui.hints_shown.size() >= 4, 15.0)
		print("onboard AC-3b [BOILER HOUSE on $50] %s" % _hint_at(3))

		# AC-4: finish goal 0 for real and watch it name goal 1
		economy.credits[player_fac] = 3000
		var s_ob: Vector2i = world.faction_start(player_fac)
		campaign._prebuild("boiler", player_fac, s_ob + Vector2i(-5, -5))
		campaign._prebuild("barracks", player_fac, s_ob + Vector2i(5, -5))
		await _wait_until(func(): return ui.hints_shown.size() >= 5, 15.0)
		print("onboard AC-4 [goal 0 done, objectives %s] %s"
			% [campaign.obj_done, _hint_at(4)])
		print("onboard AC-4: names the next objective=%s (must be true)"
			% _hint_at(4).contains(String(EFCampaign.MISSIONS[1]["objectives"][1])))

		# AC-5: overdraw the grid until the turrets would hold fire
		var pw0 := buildings.power_report(player_fac)
		for k in range(9):
			campaign._prebuild("gun_turret", player_fac,
				s_ob + Vector2i(-8 + k * 2, 7))
		var pw1 := buildings.power_report(player_fac)
		print("onboard AC-5: power made %d->%d drawn %d->%d low_power=%s"
			% [pw0.x, pw1.x, pw0.y, pw1.y, buildings.low_power(player_fac)])
		await _wait_until(func(): return ui.hints_shown.size() >= 6, 15.0)
		print("onboard AC-5 [grid overdrawn] %s" % _hint_at(5))

		# AC-6: pull every trigger again. Note that NONE of the conditions have
		# been cleared — the clock is still past 20 s, no order has been given,
		# goal 0 is still done and the grid is still overdrawn — so the only
		# thing that can hold these back is the once-per-mission guard itself.
		var before_n := ui.hints_shown.size()
		buildings.queues["BASE"] = null
		economy.credits[player_fac] = 10
		ui._on_item_gui_input(lmb, "BASE", "airfield")
		buildings.click_item("BASE", "barracks")
		await _wait_seconds(30.0)
		print("onboard AC-6: %d prompts before re-triggering, %d after (must match)"
			% [before_n, ui.hints_shown.size()])
		print("onboard AC-6: %d of M1's %d prompts have fired; the one still held back is the goal-1 prompt, and goal 1 is not done"
			% [campaign._hints_fired.size(), campaign._hints.size()])
		for hi in range(ui.hints_shown.size()):
			print("   %d. %s" % [hi + 1, ui.hints_shown[hi]])
		Engine.time_scale = 1.0
		get_tree().quit()
		return

	if uargs.has("--onboard-off"):
		# AC-14: the same triggers, on a mission that never asked to teach.
		var oi := uargs.find("--onboard-off")
		var omid := 2
		if oi + 1 < uargs.size() and not uargs[oi + 1].begins_with("--"):
			omid = int(uargs[oi + 1])
		_on_campaign_start(omid)
		rig.set_process(false)
		rig.set_process_unhandled_input(false)
		Engine.time_scale = 4.0
		for i in range(10):
			await get_tree().process_frame
		var olmb := InputEventMouseButton.new()
		olmb.button_index = MOUSE_BUTTON_LEFT
		olmb.pressed = true
		ui._on_item_gui_input(olmb, "BASE", "airfield")
		economy.credits[player_fac] = 5
		buildings.click_item("BASE", "boiler")
		# well past M1's 20 s idle prompt, with no order ever issued
		await _wait_seconds(40.0)
		var ocfg: Dictionary = EFCampaign.MISSIONS[omid]
		print("onboard-off: mission %d [%s] has_hints_key=%s"
			% [omid, String(ocfg["title"]), ocfg.has("hints")])
		print("onboard-off: t=%.0fs player_ordered=%s deny_pending=%s low_power=%s"
			% [campaign.mission_t, player_ordered, not buildings.last_deny.is_empty(),
				buildings.low_power(player_fac)])
		print("onboard-off: prompts shown=%d %s (must be 0 and empty)"
			% [ui.hints_shown.size(), ui.hints_shown])
		print("onboard-off: mission still live=%s objectives=%s"
			% [campaign.active, campaign.obj_done])
		Engine.time_scale = 1.0
		get_tree().quit()
		return

	if uargs.has("--missioncheck"):
		# boot one mission and report what its data-driven hooks actually did
		var ci := uargs.find("--missioncheck")
		var cmid := int(uargs[ci + 1])
		_on_campaign_start(cmid)
		for i in range(20):
			await get_tree().process_frame
		var cfg: Dictionary = EFCampaign.MISSIONS[cmid]
		var blds := 0
		for b in buildings.list:
			var bd: Dictionary = b
			if bd["faction"] == player_fac and bd["hp"] > 0:
				blds += 1
		var mine := 0
		var air := 0
		for u in army.units:
			if u.faction == player_fac and u.hp > 0:
				mine += 1
				if u.flying:
					air += 1
		print("mission %d [%s] act=%d map=%s pfac=%d efac=%d diff=%d"
			% [cmid, String(cfg["title"]), EFCampaign.act_of(cmid),
				String(cfg["map"]).get_file(), player_fac, ai_fac, cur_difficulty])
		print("   credits=%d buildings=%d units=%d (flying %d) objectives=%d ai_limit='%s'"
			% [economy.credits.get(player_fac, 0), blds, mine, air,
				campaign.obj_done.size(), ai.tech_limit])
		var foe_aa := 0
		for b2 in buildings.list:
			var bd2: Dictionary = b2
			if bd2["faction"] == ai_fac and bd2["type"] == "aa_turret" and bd2["hp"] > 0:
				foe_aa += 1
		print("   hq_player=%d hq_enemy=%d active=%s enemy_aa=%d objectives_done=%s" %
			[_hq_player, _hq_enemy, campaign.active, foe_aa, campaign.obj_done])
		# start pads must match the sides actually playing: a 4-start map used
		# for a 2-side mission once raised fully dressed phantom bases on the
		# unused slots, one of them in the player's own colours
		print("   map starts=%d sides=%d start pads built=%d (pads must equal sides)"
			% [world.starts.size(), world.slot_faction.size(),
				world.start_nodes.size()])
		get_tree().quit()
		return

	if uargs.find("--selftest") != -1 and uargs.has("--killhq"):
		# a kill_hq mission taken to victory: proves the objective actually
		# latches instead of the game ending before the campaign is ticked
		_on_campaign_start(3)
		_maybe_selftest()
		return
	if uargs.find("--selftest") != -1 and uargs.has("--mission2"):
		_on_campaign_start(2, true)
		_maybe_selftest()
		return
	if uargs.find("--selftest") != -1 and uargs.has("--loadcheck"):
		_load_game()
		_maybe_selftest()
		return
	if uargs.find("--selftest") != -1:
		var pfac := 1
		var efac := 2
		if uargs.has("--pelican"):
			pfac = 3            # the Pelican is an Aurelian League airframe
		if uargs.has("--airlift"):
			efac = 3            # ...so the AI has to be Aurelian to fly one
		var pi := uargs.find("--pfac")
		if pi != -1 and pi + 1 < uargs.size():
			pfac = int(uargs[pi + 1])
		var ei := uargs.find("--efac")
		if ei != -1 and ei + 1 < uargs.size():
			efac = int(uargs[ei + 1])
		var st_mode := "1v1"
		var st_ally := 0
		var st_map := "res://maps/ashfall_plain.txt"
		var mi2 := uargs.find("--mapfile")
		if mi2 != -1 and mi2 + 1 < uargs.size():
			st_map = "res://maps/%s.txt" % String(uargs[mi2 + 1])
		if uargs.has("--ffa"):
			st_mode = "ffa"
			st_map = "res://maps/the_cradle_crown.txt"
		elif uargs.has("--allied"):
			st_mode = "2v2"
			st_ally = 3 if pfac != 3 else 4
			st_map = "res://maps/the_cradle_crown.txt"
		# --crawlstart begins the match with crawlers WITHOUT running the --mcv
		# selftest block, which razes the player's posts and ends the game (and
		# with it stops every AI) — useless for watching an AI develop.
		_start_game(pfac, efac, st_map, 2, false,
			uargs.has("--mcv") or uargs.has("--crawlstart"), st_mode, st_ally)
		_maybe_selftest()
		return
	if FileAccess.file_exists("user://load.flag"):
		DirAccess.open("user://").remove("load.flag")
		_load_game()
		return
	# --- VANTA CORE -----------------------------------------------------------
	# Below the load.flag return ON PURPOSE. F9 quickload reloads the scene with
	# the same (empty) argv a real launch has, so it is position — not the argv
	# test — that keeps the logo out of a resume. The argv test is the same
	# real-launch idiom _ready() already uses to decide whether to apply_video(),
	# repeated because an orphan dev flag (a bare --march, --norelief) falls
	# through to here with a NON-empty argv, and nobody debugging a unit test
	# wants to sit through fifteen seconds of logo.
	var did_intro := false
	if not _intro_played:
		# Latch FIRST, and whether or not we actually play. "Has this process
		# already decided about the logo" is a different question from "did the
		# logo run", and conflating them costs you this: boot with PLAY INTRO
		# off (so the latch never sets), turn it on from the pause menu
		# mid-match, then QUIT TO MENU — the reload finds the flag true and the
		# latch false, and the studio logo plays in the middle of the session.
		_intro_played = true
		if EFSettings.play_intro and OS.get_cmdline_user_args().is_empty():
			did_intro = true
			await _play_intro()
	menu = EFMenu.new()
	add_child(menu)
	if did_intro:
		# the logo faded to black; the title hall now fades IN from that same
		# black instead of popping — the two halves of one smooth handoff
		var veil := CanvasLayer.new()
		veil.layer = 101
		add_child(veil)
		var vr := ColorRect.new()
		vr.color = Color(0, 0, 0, 1)
		vr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		veil.add_child(vr)
		var tw := create_tween()
		tw.tween_property(vr, "color:a", 0.0, 0.6)
		tw.tween_callback(veil.queue_free)
	if music != null:
		music.play_menu()
	menu.start_requested.connect(_on_menu_start)
	menu.campaign_requested.connect(_on_campaign_start)
	menu.load_requested.connect(func():
		menu.queue_free()
		menu = null
		_load_game())


func _menushot(uargs: PackedStringArray) -> void:
	var idx := uargs.find("--menushot")
	var path := "user://menu.png"
	if idx + 1 < uargs.size():
		path = uargs[idx + 1]
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("menu screenshot -> ", path)
	get_tree().quit()


func _play_intro() -> void:
	intro = EFIntro.new()
	add_child(intro)
	# is_done BEFORE the await, not after: a missing video finishes via
	# call_deferred, which can land before we get here — awaiting a signal that
	# already fired would stall the boot forever on a black screen.
	if not intro.is_done:
		await intro.done
	intro.queue_free()
	intro = null
	await get_tree().process_frame     # let layer 100 actually leave before the
	                                   # title hall paints its first frame


func _on_menu_start(fac: int, foe: int, map_path: String, difficulty: int,
		mcv_start := false, mode := "1v1", ally := 0) -> void:
	menu.queue_free()
	menu = null
	_start_game(fac, foe, map_path, difficulty, false, mcv_start, mode, ally)


func _on_campaign_start(mid: int, fast := false) -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	var cfg: Dictionary = EFCampaign.MISSIONS[mid]
	_start_game(int(cfg["pfac"]), int(cfg["efac"]), String(cfg["map"]),
		int(cfg["diff"]))
	# debug_fast must be set BEFORE begin(): begin() applies the mission's
	# prebuilt structures, veterans and credit grant, so calling it twice would
	# double all three
	campaign.debug_fast = fast
	campaign.begin(mid, self)
	ui.announce(String(cfg["title"]), Color(0.89, 0.58, 0.23))


func _start_game(p_fac: int, e_fac: int, map_path: String, difficulty := 2,
		restoring := false, mcv_start := false, mode := "1v1", ally := 0) -> void:
	player_fac = p_fac
	ai_fac = e_fac
	cur_mode = mode
	ally_fac = ally
	_fallen = {}
	# roster: which factions fight, and who is on whose team
	match mode:
		"ffa":
			enemy_facs = []
			for f in [1, 2, 3, 4]:
				if f != p_fac:
					enemy_facs.append(f)
		"2v2":
			enemy_facs = []
			for f2 in [1, 2, 3, 4]:
				if f2 != p_fac and f2 != ally:
					enemy_facs.append(f2)
		_:
			enemy_facs = [e_fac]
	if not enemy_facs.is_empty():
		ai_fac = enemy_facs[0]
	cur_difficulty = difficulty
	cur_mcv_start = mcv_start
	cur_map = map_path
	if audio:
		audio.announcer_fac = p_fac

	world = EFWorld.new()
	# slots 1..N on the map, player first, ally (if any) second
	var roster: Array[int] = [p_fac]
	if ally > 0:
		roster.append(ally)
	roster.append_array(enemy_facs)
	world.slot_faction = {}
	for i in range(roster.size()):
		world.slot_faction[i + 1] = roster[i]
	# teams: distinct everywhere except 2v2's two pairs
	world.team_of = {}
	for f3 in roster:
		world.team_of[f3] = f3
	if mode == "2v2":
		world.team_of[ally] = p_fac
		world.team_of[enemy_facs[1]] = enemy_facs[0]
	add_child(world)
	world.show_start_pads = not mcv_start
	world.build(map_path)

	rig = CameraRig.new()
	add_child(rig)
	rig.setup(world)
	_add_ash_motes()
	var s: Vector2i = world.faction_start(player_fac)
	rig.center_on((s.x + 0.5) * T, (s.y + 0.5) * T)

	audio = EFAudio.new()
	add_child(audio)

	army = EFArmy.new()
	add_child(army)
	army.setup(world)
	army.player_faction = player_fac
	army.audio = audio

	economy = EFEconomy.new()
	add_child(economy)
	economy.setup(world)

	structures = EFStructures.new()
	add_child(structures)
	structures.setup(world, army)

	buildings = EFBuildings.new()
	add_child(buildings)
	buildings.setup(world, army, economy)
	buildings.player_faction = player_fac
	buildings.audio = audio
	buildings.relief_on = not OS.get_cmdline_user_args().has("--norelief")

	army.economy = economy
	army.structures = structures
	army.buildings = buildings
	army.music = music
	buildings.music = music
	if music != null:
		music.start_battle()

	if not restoring:
		# iterate the slots WE configured, not the map's raw starts — a 4-start
		# map in a 1v1 simply leaves two slots empty
		for num in world.slot_faction:
			if not world.starts.has(num):
				continue
			var sfac: int = world.slot_faction[num]
			if mcv_start:
				# no base: each side gets a crawler and has to found one
				var mk := EFBuildings.mcv_for(sfac)
				army.spawn(mk, sfac, world.starts[num])
			else:
				buildings.register_start_base(sfac, world.starts[num])
		world.reveal(world.faction_start(player_fac), 14)
		world.shroud_flush()
		army.spawn_start_forces()
		for ef in enemy_facs:
			_place_enemy_turrets(world.faction_start(ef), ef)
			_pre_garrison_enemy(ef)

	campaign = EFCampaign.new()
	add_child(campaign)

	# one commander per non-player faction; the 2v2 ally is just an EFAI whose
	# foes are the enemy team
	ais = []
	var ai_rosters: Array = []
	for ef2 in enemy_facs:
		var foes_e: Array = [player_fac]
		if ally_fac > 0:
			foes_e.append(ally_fac)
		if cur_mode == "ffa":
			foes_e = []
			for f4 in roster:
				if f4 != ef2:
					foes_e.append(f4)
		ai_rosters.append([ef2, foes_e, true])
	if ally_fac > 0:
		ai_rosters.append([ally_fac, enemy_facs.duplicate(), false])
	for i2 in range(ai_rosters.size()):
		var entry: Array = ai_rosters[i2]
		var a := EFAI.new()
		add_child(a)
		a.setup(world, army, economy, buildings, int(entry[0]),
			int(entry[1][0]), entry[1])
		# the ally fights at standard settings — difficulty shapes the ENEMY
		a.set_difficulty(difficulty if bool(entry[2]) else 2)
		if bool(entry[2]):
			economy.income_mult[entry[0]] = {1: 0.75, 2: 1.0, 3: 1.3}[difficulty]
			if difficulty == 3:
				economy.credits[entry[0]] = economy.credits.get(entry[0], 0) + 1500
		# stagger think ticks so three AIs never pathfind on the same frame
		a._think = float(i2) * EFAI.THINK / maxf(float(ai_rosters.size()), 1.0)
		ais.append(a)

	var pausables: Array = [world, rig, army, economy, structures, buildings, audio]
	pausables.append_array(ais)
	for node in pausables:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE

	_hq_player = _find_hq(player_fac)
	_hq_enemy = _find_hq(ai_fac)

	ui = EFUI.new()
	add_child(ui)
	ui.setup(world, rig, economy, buildings)
	ui.stance_picked.connect(func(s: String):
		army.set_stance_selected(s)
		ui.announce(s, Color(0.72, 0.86, 1.0)))
	ui.anthem_pressed.connect(_toggle_anthem)
	ui.settings_pressed.connect(_open_settings)
	ui.quit_to_menu_pressed.connect(_quit_to_menu)
	economy.field_depleted.connect(ui.deplete_pixel)
	economy.field_regrown.connect(ui.restore_pixel)
	buildings.placed.connect(ui.refresh_tiles)
	army.selection_cleared.connect(rig.release_follow)
	army.superweapon_launched.connect(func(fac: int, _pos: Vector3):
		if fac == player_fac:
			ui.announce("%s LAUNCHED" % buildings.sw_name(fac), Color(0.89, 0.58, 0.23))
		elif world.is_ally(player_fac, fac):
			ui.announce("ALLIED %s LAUNCHED" % buildings.sw_name(fac),
				Color(0.4, 0.8, 0.5))
		else:
			ui.announce("ENEMY %s INBOUND — TAKE COVER" % buildings.sw_name(fac),
				Color(0.95, 0.25, 0.2)))
	army.superweapon_impact.connect(func(_pos: Vector3):
		rig.shake(0.5, 0.7))

	_make_ghost()


func _add_ash_motes() -> void:
	# drifting ash, always in the air wherever the commander looks
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 8.0
	p.preprocess = 6.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-220, -20, -220), Vector3(440, 60, 440))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(42.0, 10.0, 32.0)
	pm.direction = Vector3(1, -0.1, 0.4)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.1, -0.02, 0.05)
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.7, 0.62, 0.16)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = m
	p.draw_pass_1 = quad
	p.position = Vector3(0, 9.0, 0)
	rig.add_child(p)


func _find_hq(fac: int) -> int:
	# The FIRST LIVING post. With crawlers a side can hold up to three, and the
	# old version cached one index with no hp test — so destroying whichever
	# post happened to be registered first ended the game while two still stood,
	# and afterwards the index pointed at a corpse.
	for k in range(buildings.list.size()):
		var b: Dictionary = buildings.list[k]
		if b["type"] == "command_post" and b["faction"] == fac and b["hp"] > 0:
			return k
	return -1


func _deploy_selected() -> void:
	# Try EVERY selected crawler before giving up: bailing on the first one meant
	# a mixed selection could refuse while a perfectly placeable crawler stood
	# beside it. And always say something — silence reads as a broken key.
	var crawlers := 0
	var refusal := ""
	for u in army.selection.duplicate():
		if u.role != "mcv" or u.hp <= 0:
			continue
		crawlers += 1
		var chk := buildings.can_deploy(u)
		if bool(chk["ok"]):
			var was := buildings.count_posts(u.faction)
			if buildings.deploy_mcv(u):
				army.selection_dirty = true
				ui.announce("COMMAND POST %d ESTABLISHED" % (was + 1),
					Color(0.55, 0.85, 0.5))
				_hq_player = _find_hq(player_fac)
			return
		if refusal == "" and String(chk["why"]) != "":
			refusal = String(chk["why"])
	if crawlers == 0:
		ui.announce("SELECT A CRAWLER TO UNFOLD IT", Color(0.95, 0.55, 0.2))
	elif refusal != "":
		ui.announce(refusal, Color(0.95, 0.55, 0.2))


func _has_mcv(fac: int) -> bool:
	for u in army.units:
		if u.faction == fac and u.role == "mcv" and u.hp > 0:
			return true
	return false


func _is_beaten(fac: int) -> bool:
	# A side is out when it holds no command post AND has no crawler left to
	# found one. Starting without a base is now legal, so "no post" alone can
	# no longer mean defeat.
	return buildings.count_posts(fac) == 0 and not _has_mcv(fac)


func _pre_garrison_enemy(fac := -1) -> void:
	# this enemy already holds two ruins near its side of the map
	if fac < 0:
		fac = ai_fac
	if structures.garrisons.is_empty():
		return
	var s2: Vector2i = world.faction_start(fac)
	var s2_pos := Vector3((s2.x + 0.5) * T, 0, (s2.y + 0.5) * T)
	var by_dist := range(structures.garrisons.size())
	by_dist.sort_custom(func(a, b):
		return structures.garrisons[a]["center"].distance_squared_to(s2_pos) < \
			structures.garrisons[b]["center"].distance_squared_to(s2_pos))
	var inf_kind := "conscript"
	if fac == 1:
		inf_kind = "iron_guard"
	elif fac == 3:
		inf_kind = "sky_marine"
	elif fac == 4:
		inf_kind = "arc_templar"
	# Only ruins genuinely on this side of the map get seeded. The big 4-start
	# maps carry exactly four ruins, all of them central and contested — without
	# a distance cap the AI sides simply owned every one of them from frame one,
	# which on a 2v2 handed the enemy team all four before a shot was fired.
	var reach: float = maxf(world.w, world.h) * T * 0.22
	var taken := 0
	for idx in by_dist:
		if taken >= 2:
			break
		if not structures.garrisons[idx]["occupants"].is_empty():
			continue
		if structures.garrisons[idx]["center"].distance_to(s2_pos) > reach:
			break                 # sorted by distance: everything after is further
		for n in range(2):
			var u := army.spawn(inf_kind, fac, structures.garrisons[idx]["door"])
			structures.enter(u, idx)
		taken += 1


func _place_enemy_turrets(s2: Vector2i, fac := -1) -> void:
	if fac < 0:
		fac = ai_fac
	var found := 0
	for ring in range(4, 9):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				if (found == 0 and dx > 0) or (found == 1 and dx <= 0):
					continue
				var c := s2 + Vector2i(dx, dy)
				# is_buildable ignores units standing on the tile, and start
				# forces spawn before this runs — so a turret could be raised on
				# top of the enemy's own first soldier and block the cell it
				# stood in, trapping it until the turret died. can_place would
				# catch it but also demands base adjacency, which would shrink
				# these rings, so test occupancy directly.
				var kind := "aa_turret" if found == 1 else "gun_turret"
				if world.is_buildable(c.x, c.y) and not _unit_on_tile(c):
					buildings._create(kind, fac, c)
					found += 1
					if found >= 2:
						return


func _unit_on_tile(c: Vector2i) -> bool:
	for u in army.units:
		if u.garrisoned_in >= 0 or u.hp <= 0:
			continue
		if Vector2i(int(u.global_position.x / T), int(u.global_position.z / T)) == c:
			return true
	return false


func _count_faction(fac: int) -> int:
	var n := 0
	for u in army.units:
		if u.faction == fac and u.hp > 0:
			n += 1
	return n


# --- the frame loop -------------------------------------------------------------

func _process(_dt: float) -> void:
	if world == null or get_tree().paused:
		return
	rig.s_blocked = army.has_selection()

	if not game_over:
		# The campaign ticks BEFORE the HQ checks. In an elif chain after them,
		# an enemy-HQ death ended the game on the same frame and tick() was never
		# reached again — which made every "kill_hq" objective unreachable, so
		# missions finished with their main objective still showing unticked.
		if campaign != null and campaign.active:
			var verdict := campaign.tick(get_process_delta_time())
			if verdict == "win":
				_end_game(true)
			elif verdict == "lose":
				_end_game(false)
	if not game_over:
		# keep the cached indices pointing at a LIVING post as bases come and go
		if _hq_player < 0 or buildings.list[_hq_player]["hp"] <= 0:
			_hq_player = _find_hq(player_fac)
		if _hq_enemy < 0 or buildings.list[_hq_enemy]["hp"] <= 0:
			_hq_enemy = _find_hq(ai_fac)
		# eliminations: announce each fallen faction once, then last team standing
		for f in world.slot_faction.values():
			if f != player_fac and not _fallen.has(f) and _is_beaten(f):
				_fallen[f] = true
				var col: Color = EFWorld.FACTIONS[f]["color"]
				ui.announce("%s HAS FALLEN" % EFWorld.FACTIONS[f]["name"].to_upper(), col)
				if world.start_nodes.has(f):
					world.start_nodes[f].visible = false
		if _is_beaten(player_fac):
			# classic rule: the commander's own defeat ends it, ally or no ally
			_end_game(false)
		else:
			var all_enemies_down := true
			for ef in enemy_facs:
				if not _is_beaten(ef):
					all_enemies_down = false
					break
			if all_enemies_down:
				_end_game(true)

	if structures.selected >= 0:
		ui.set_force(structures.garrison_summary(structures.selected))
	elif army.selection_dirty:
		army.selection_dirty = false
		ui.set_force(army.get_selection_summary())

	# above the unexplored-tile early return below, or the silhouettes freeze
	# the moment the cursor crosses into unscouted ground
	_formation_preview_tick()
	# Unconditional: selection_dirty is consumed a few lines above in the SAME
	# frame, so gating on it meant the row was computed once at startup with an
	# empty selection and never again.
	var st := army.stance_summary()
	ui.set_stance(st[0], String(st[1]), bool(st[2]))

	# survey + hover tracking (the ghost uses the same hovered tile)
	var hover := []
	_hover_tile = Vector2i(-1, -1)
	var mp := get_viewport().get_mouse_position()
	if mp.x < VIEW_W:
		var hit := army.ground_point(mp, rig.cam)
		if hit != Vector3.INF:
			var tx := int(floor(hit.x / T))
			var ty := int(floor(hit.z / T))
			if tx >= 0 and tx < world.w and ty >= 0 and ty < world.h:
				_hover_tile = Vector2i(tx, ty)
				if not world.is_explored(tx, ty):
					ui.set_survey(["Unscouted Territory", tx, ty, ""])
					ui.set_harvest_hint(false)
					if _harvest_marker:
						_harvest_marker.visible = false
					return
				var ch := world.tile_char(tx, ty)
				var tile_name: String = EFWorld.TILE_DEFS[ch]["name"]
				var extra := ""
				var b := buildings.building_at(Vector2i(tx, ty))
				if not b.is_empty():
					tile_name = EFBuildings.DEFS[b["type"]]["name"]
					extra = "%s · %d HP" % [EFWorld.FACTIONS[b["faction"]]["name"],
						int(b["hp"])]
				elif ch == "B":
					var gi := structures.garrison_at(Vector2i(tx, ty))
					if gi >= 0:
						var g: Dictionary = structures.garrisons[gi]
						tile_name = g["kind_name"]
						extra = "GARRISON %d/%d" % [g["occupants"].size(), g["capacity"]]
						if not g["occupants"].is_empty():
							extra += " · " + EFWorld.FACTIONS[g["occupants"][0].faction]["name"]
				elif ch == "E":
					var tile := Vector2i(tx, ty)
					if economy.reserves.has(tile):
						extra = "%d credits in the ground" % int(economy.reserves[tile])
				hover = [tile_name, tx, ty, extra]
	ui.set_survey(hover)

	# the placement ghost
	if buildings.pending_place != "" and _hover_tile.x >= 0:
		var size: int = EFBuildings.DEFS[buildings.pending_place]["size"]
		var origin := _ghost_origin()
		_ghost.visible = true
		_ghost.scale = Vector3(size * T, 0.7, size * T)
		_ghost.position = Vector3((origin.x + size * 0.5) * T, 0.35,
			(origin.y + size * 0.5) * T)
		_ghost.material_override = _ghost_ok \
			if buildings.can_place(buildings.pending_place, origin) else _ghost_bad
	elif _ghost:
		_ghost.visible = false

	# harvest hint: collector selected + hovering (near) an ember field
	var show_harvest := false
	if buildings.pending_place == "" and _hover_tile.x >= 0 and not game_over:
		var has_harv := false
		for u in army.selection:
			if u.is_harvester():
				has_harv = true
				break
		if has_harv:
			var ht := army.nearest_field_tile(_hover_tile, 2)
			if ht.x >= 0:
				show_harvest = true
				_harvest_marker.position = Vector3((ht.x + 0.5) * T, 0.06, (ht.y + 0.5) * T)
	if _harvest_marker:
		_harvest_marker.visible = show_harvest
	ui.set_harvest_hint(show_harvest)

	# selected-building highlight + context
	if sel_building >= 0 and (sel_building >= buildings.list.size()
			or buildings.list[sel_building]["hp"] <= 0):
		sel_building = -1
	if sel_building >= 0:
		var sb: Dictionary = buildings.list[sel_building]
		var ssize: int = EFBuildings.DEFS[sb["type"]]["size"]
		_bld_marker.visible = true
		_bld_marker.scale = Vector3(ssize * T, 1.0, ssize * T)
		_bld_marker.position = Vector3((sb["origin"].x + ssize * 0.5) * T, 0.1,
			(sb["origin"].y + ssize * 0.5) * T)
	else:
		_bld_marker.visible = false
	ui.set_building(sel_building)
	buildings.show_rally_for(sel_building)


func _end_game(win: bool) -> void:
	game_over = true
	if audio:
		audio.play_ui("victory" if win else "defeat", 0.0)
		audio.announce("victory" if win else "defeat", true)
	victory = win
	army.set_process(false)
	for a in ais:
		a.set_process(false)
	buildings.set_process(false)
	if not win and world.start_nodes.has(player_fac):
		world.start_nodes[player_fac].visible = false
	elif win:
		for ef in enemy_facs:
			if world.start_nodes.has(ef):
				world.start_nodes[ef].visible = false
	if campaign != null and campaign.active:
		campaign.active = false
		if win:
			EFCampaign.unlock(campaign.mission + 1)
			ui.show_game_over(true, "MISSION COMPLETE", _campaign_outro())
		else:
			ui.show_game_over(false, "MISSION FAILED",
				"The ash keeps its secrets. Press R to try again.")
	else:
		ui.show_game_over(win)
	print("game over: victory=%s" % win)


func _campaign_outro() -> String:
	# the act's closing line if this was its last mission, else a nudge onward
	var act: int = EFCampaign.act_of(campaign.mission)
	var ms: Array = EFCampaign.act_missions(act)
	if campaign.mission == int(ms[ms.size() - 1]):
		var a: Dictionary = EFCampaign.ACTS[act]
		return String(a["outro"])
	return "The next operation is unsealed."


# --- input -----------------------------------------------------------------------

func _toggle_anthem() -> void:
	if music == null:
		return
	if music.anthem_on:
		music.cancel_anthem()
		ui.announce("ANTHEM SILENCED", Color(0.6, 0.62, 0.66))
		return
	if not music.anthem_ready():
		ui.announce("THE BAND IS STILL CATCHING ITS BREATH",
			Color(0.6, 0.62, 0.66))
		return
	if music.play_anthem(player_fac):
		ui.announce(music.anthem_title(player_fac), Color(0.89, 0.58, 0.23))


func _toggle_pause() -> void:
	# a held right-click never delivers its release across these transitions,
	# so the hold state has to be released by hand or it latches forever
	_rmb_down = false
	_hide_formation_preview()
	get_tree().paused = not get_tree().paused
	ui.show_pause(get_tree().paused)


# --- settings, mid-battle (AC-10) -------------------------------------------------

func _open_settings() -> void:
	if _settings_panel != null:
		return
	_settings_panel = EFSettingsPanel.new()
	_settings_panel.closed.connect(_close_settings)
	# Added to ui, not to main: ui is the CanvasLayer the pause overlay lives on,
	# and going in after it is what puts this in front of it.
	ui.add_child(_settings_panel)


func _close_settings() -> void:
	if _settings_panel == null:
		return
	_settings_panel.queue_free()
	_settings_panel = null


func _quit_to_menu() -> void:
	# The road R already takes from the game-over screen. Reload the scene and
	# let _ready() raise the title hall from nothing; anything subtler would have
	# to unpick a world, an army, an economy and three AI commanders by hand, and
	# every one of those is a leak waiting to be found by the fifth stranger.
	get_tree().paused = false
	get_tree().reload_current_scene()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F11:
		var wm := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
			if wm == DisplayServer.WINDOW_MODE_FULLSCREEN
			else DisplayServer.WINDOW_MODE_FULLSCREEN)
		# F11 predates the settings screen and still works from anywhere, so it
		# is the one thing that can make the stored setting a lie. Tell it.
		EFSettings.sync_from_window()
		return
	# The settings screen owns ESC while it is up. Closing it must not also
	# unpause the battle underneath, and P must not resume behind an open panel.
	if _settings_panel != null:
		if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ESCAPE
				or ev.keycode == KEY_P):
			_close_settings()
		return
	if world == null:
		return
	if not game_over and ev is InputEventKey and ev.pressed and ev.keycode == KEY_F5:
		save_game()
		return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F9:
		if FileAccess.file_exists("user://savegame.json"):
			get_tree().paused = false
			var fl := FileAccess.open("user://load.flag", FileAccess.WRITE)
			fl.store_8(1)
			fl.close()
			get_tree().reload_current_scene()
		else:
			ui.announce("NO SAVED WAR TO LOAD", Color(0.9, 0.4, 0.32))
		return
	if not game_over and ev is InputEventKey and ev.pressed and ev.keycode == KEY_P:
		_toggle_pause()
		return
	if get_tree().paused:
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_toggle_pause()
		return
	if game_over:
		if _rmb_down:
			_rmb_down = false
			_hide_formation_preview()
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if _rmb_preview and ev is InputEventMouseButton and ev.pressed:
		# While the preview is up the wheel AIMS the line — facing was the hard
		# part of laying a formation, not shape, which moves to Shift+wheel.
		# 45-degree snaps: eight compass points are every direction an RTS line
		# actually needs, and snapping is what makes the wheel land exactly.
		var wheel := 0
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel = -1
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel = 1
		if wheel != 0:
			if ev.shift_pressed:
				_shape_i = (_shape_i + (1 if wheel > 0 else EFArmy.SHAPES.size() - 1)) 					% EFArmy.SHAPES.size()
			else:
				if _form_rot < 0.0:
					var mp0 := get_viewport().get_mouse_position()
					var p0 := army.ground_point(mp0, rig.cam)
					var f0 := _formation_facing(p0) if p0 != Vector3.INF 						else Vector2(1, 0)
					_form_rot = atan2(f0.y, f0.x)
				_form_rot = fposmod(round(_form_rot / (PI / 4.0) + float(wheel)) 					* (PI / 4.0), TAU)
			return

	# Both modes below return before the release handler ever runs, so a
	# right-click release that arrives inside them would leave _rmb_down latched
	# true — silhouettes stuck on screen and the next right-click firing a
	# phantom formation order.
	if (buildings.sw_targeting or buildings.pending_place != "") and _rmb_down:
		_rmb_down = false
		_hide_formation_preview()

	# superweapon targeting swallows the mouse until fired or cancelled
	if buildings.sw_targeting:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT and ev.position.x < VIEW_W:
				var swp := army.ground_point(ev.position, rig.cam)
				if swp != Vector3.INF:
					buildings.fire_superweapon(player_fac, swp)
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				buildings.sw_targeting = false
		elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			buildings.sw_targeting = false
		return

	# placement mode swallows the mouse until placed or cancelled
	if buildings.pending_place != "":
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT and _hover_tile.x >= 0:
				buildings.try_place(buildings.pending_place, _ghost_origin())
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				buildings.pending_place = ""
		elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			buildings.pending_place = ""
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F1:
			ui.toggle_manual()
		return

	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				if ev.position.x < VIEW_W:
					_drag_start = ev.position
					_dragging = true
			elif _dragging:
				_dragging = false
				ui.set_drag_rect(Rect2())
				var rect := _norm_rect(_drag_start, ev.position)
				if rect.size.length() < 10.0:
					var now: int = Time.get_ticks_msec()
					var dbl: bool = (now - _last_click_ms) < DBL_MS \
						and ev.position.distance_to(_last_click_pos) < DBL_PX
					_last_click_ms = now
					_last_click_pos = ev.position
					# a double-click that lands on empty ground must still fall
					# through, or double-clicking a building stops selecting it
					if dbl and army.select_same_kind_on_screen(ev.position,
							ev.shift_pressed, rig.cam, VIEW_W,
							get_viewport().get_visible_rect().size.y):
						structures.select_garrison(-1)
						sel_building = -1
					else:
						army.click_select(ev.position, ev.shift_pressed, rig.cam)
						_maybe_select_static(ev.position)
				else:
					army.box_select(rect, ev.shift_pressed, rig.cam)
					structures.select_garrison(-1)
					sel_building = -1
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			# Orders now fire on RELEASE so the press-to-release time can tell a
			# quick click from a hold. Issuing on press and again on release
			# would double-order and snap the units twice.
			if ev.pressed and ev.position.x < VIEW_W:
				_rmb_down = true
				_rmb_ms = Time.get_ticks_msec()
				_rmb_pos = ev.position
			elif not ev.pressed and _rmb_down:
				_rmb_down = false
				var held: bool = _rmb_preview \
					or (Time.get_ticks_msec() - _rmb_ms) >= RMB_HOLD_MS
				_hide_formation_preview()
				_issue_right_click(ev.position, held)
	elif ev is InputEventMouseMotion and _dragging:
		ui.set_drag_rect(_norm_rect(_drag_start, ev.position))
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			army.clear_selection()
			structures.select_garrison(-1)
			sel_building = -1
		elif ev.keycode == KEY_DELETE and sel_building >= 0:
			buildings.sell(sel_building)
			sel_building = -1
		elif ev.keycode == KEY_S and army.has_selection():
			army.stop_selected()
		elif ev.keycode == KEY_M:
			_toggle_anthem()
		elif ev.keycode == KEY_C:
			rig.follow_on = not rig.follow_on
			if not rig.follow_on:
				rig.release_follow()
			elif army.has_selection():
				rig.follow_group(army.selection)
			ui.announce("ESCORT CAMERA %s" % ("ON" if rig.follow_on else "OFF"),
				Color(0.72, 0.86, 1.0))
		elif ev.keycode == KEY_X and army.has_selection():
			_deploy_selected()
		elif ev.keycode == KEY_Z and army.has_selection():
			army.cycle_stance_selected()
			var st := army.stance_summary()
			var opts: Array = st[0]
			if not opts.is_empty():
				ui.announce(String(st[1]), Color(0.72, 0.86, 1.0))
		elif ev.keycode == KEY_F1:
			ui.toggle_manual()
		elif ev.keycode == KEY_F3 and world._shroud_mi != null:
			world._shroud_mi.visible = not world._shroud_mi.visible
		elif ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
			var digit: int = ev.keycode - KEY_0
			if ev.ctrl_pressed:
				if army.has_selection():
					_groups[digit] = army.selection.duplicate()
					ui.announce("GROUP %d ASSIGNED" % digit, Color(0.5, 0.49, 0.47))
			elif _groups.has(digit):
				army.clear_selection()
				for gu in _groups[digit]:
					if is_instance_valid(gu) and gu.hp > 0 and gu.garrisoned_in < 0 \
							and not gu.stowed:
						gu.selected = true
						army.selection.append(gu)
				army.selection_dirty = true


func _issue_right_click(screen_pos: Vector2, held: bool) -> void:
	if screen_pos.x >= VIEW_W:
		return
	var p := army.ground_point(screen_pos, rig.cam)
	if p == Vector3.INF:
		return
	if structures.selected >= 0:
		structures.unload(structures.selected, p)      # unload ignores formations
		army.mark(p)
		player_ordered = true
	elif sel_building >= 0 and buildings.is_factory(sel_building) \
			and int(buildings.list[sel_building]["faction"]) == player_fac:
		# right-click with a factory selected plants its rally point: everything
		# it produces from now on marches there instead of milling at the door
		buildings.set_rally(sel_building, p)
		army.mark(p)
		ui.announce("RALLY POINT SET", Color(0.55, 0.85, 0.5))
		player_ordered = true
	elif army.has_selection():
		if held:
			army.order_formation(_formation_anchor(p), _formation_facing(p),
				EFArmy.SHAPES[_shape_i])
		else:
			army.order_smart(p, structures,
				army.ray_point_at_y(screen_pos, rig.cam, EFUnit.ALT))
		player_ordered = true
		# trail the group they just sent (no-op unless the player enabled it)
		rig.follow_group(army.selection)


# Dragging used to BOTH aim and displace: the formation landed at the point
# the mouse had been dragged TO, so aiming a line north also pushed the whole
# line north — aiming and placing fought over one mouse. While a drag is
# aiming, the line stays planted where the button went DOWN.
func _formation_anchor(point: Vector3) -> Vector3:
	if _form_rot >= 0.0:
		return point
	var press := army.ground_point(_rmb_pos, rig.cam)
	if press != Vector3.INF:
		var drag := Vector2(point.x - press.x, point.z - press.z)
		if drag.length() > 1.5:
			return press
	return point


func _formation_facing(point: Vector3) -> Vector2:
	# the wheel-aimed direction beats everything: the player has stated one
	if _form_rot >= 0.0:
		return Vector2(cos(_form_rot), sin(_form_rot))
	# dragging while held aims the line; otherwise it faces the way they march
	var press := army.ground_point(_rmb_pos, rig.cam)
	if press != Vector3.INF:
		var drag := Vector2(point.x - press.x, point.z - press.z)
		if drag.length() > 1.5:
			return drag
	var c := army.selection_centroid()
	return Vector2(point.x - c.x, point.z - c.z)


# --- formation preview ------------------------------------------------------------
# Driven from _process, not from motion events: motion events stop arriving when
# the mouse is still, and the player can hold the button without moving.

func _formation_preview_tick() -> void:
	if not _rmb_down or not army.has_selection() or structures.selected >= 0:
		if _rmb_preview:
			_hide_formation_preview()
		return
	if not _rmb_preview and Time.get_ticks_msec() - _rmb_ms < RMB_HOLD_MS:
		return
	var mp := get_viewport().get_mouse_position()
	if mp.x >= VIEW_W:
		return
	var p := army.ground_point(mp, rig.cam)
	if p == Vector3.INF:
		return
	_rmb_preview = true
	# the rig is visited before main in unhandled input, so returning from main's
	# wheel branch was not enough — the camera had already zoomed
	rig.wheel_blocked = true
	var list := army.formation_units()
	var fp := _formation_anchor(p)
	var fdir := _formation_facing(p)
	var slots := army.formation_slots(list, fp, fdir,
		EFArmy.SHAPES[_shape_i])
	for i in range(_ghost_pool.size()):
		_ghost_pool[i].visible = false
	while _ghost_pool.size() < slots.size():
		_ghost_pool.append(_make_slot_ghost())
	for i in range(slots.size()):
		var g: MeshInstance3D = _ghost_pool[i]
		var u: EFUnit = list[i]
		g.scale = Vector3(u.radius * 2.2, 1.0, u.radius * 2.2)
		g.position = Vector3(slots[i].x, 0.09, slots[i].z)
		g.visible = true
	ui.set_formation_hint(EFArmy.SHAPES[_shape_i], slots.size())
	# the arrow: none of those discs say which way the men will FACE, and
	# facing is the whole reason the preview exists
	if _face_ghost == null:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.55
		cone.height = 1.5
		cone.radial_segments = 10
		_face_ghost = MeshInstance3D.new()
		_face_ghost.mesh = cone
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(1.0, 0.84, 0.3, 0.55)
		am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_face_ghost.material_override = am
		_face_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_face_ghost)
	var fnorm := fdir.normalized()
	var fext := 1.0
	for sv in slots:
		fext = maxf(fext, Vector2(sv.x - fp.x, sv.z - fp.z).length())
	_face_ghost.position = Vector3(fp.x + fnorm.x * (fext + 1.6), 0.14,
		fp.z + fnorm.y * (fext + 1.6))
	_face_ghost.rotation = Vector3(PI / 2.0, atan2(fnorm.x, fnorm.y), 0.0)
	_face_ghost.visible = true


func _make_slot_ghost() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 0.06
	cyl.radial_segments = 12
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	add_child(m)
	return m


func _hide_formation_preview() -> void:
	_rmb_preview = false
	_form_rot = -1.0
	if _face_ghost != null:
		_face_ghost.visible = false
	if rig != null:
		rig.wheel_blocked = false
	for g in _ghost_pool:
		g.visible = false
	if ui != null:
		ui.set_formation_hint("", 0)


func _maybe_select_static(screen_pos: Vector2) -> void:
	# click priority after units: your garrisons, then your buildings —
	# clicking a production building jumps the sidebar to its recruit tab
	sel_building = -1
	if army.has_selection():
		structures.select_garrison(-1)
		return
	var hit := army.ground_point(screen_pos, rig.cam)
	if hit == Vector3.INF:
		structures.select_garrison(-1)
		return
	var tile := Vector2i(int(hit.x / T), int(hit.z / T))
	var gi := structures.garrison_at(tile)
	if gi >= 0 and not structures.garrisons[gi]["occupants"].is_empty() \
			and structures.garrisons[gi]["occupants"][0].faction == army.player_faction:
		structures.select_garrison(gi)
		return
	structures.select_garrison(-1)
	var bidx: int = buildings.cell_map.get(tile, -1)
	if bidx >= 0 and buildings.list[bidx]["faction"] == player_fac \
			and buildings.list[bidx]["hp"] > 0:
		sel_building = bidx
		var tab := buildings.tab_for_building(buildings.list[bidx]["type"])
		if tab != "":
			ui.jump_tab(tab)


func _norm_rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


func _make_ghost() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	_ghost = MeshInstance3D.new()
	_ghost.mesh = mesh
	_ghost_ok = StandardMaterial3D.new()
	_ghost_ok.albedo_color = Color(0.3, 1.0, 0.4, 0.4)
	_ghost_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_bad = StandardMaterial3D.new()
	_ghost_bad.albedo_color = Color(1.0, 0.3, 0.25, 0.4)
	_ghost_bad.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_bad.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)

	# glowing tile highlight: hover an ember field with a collector selected
	var hm_mesh := PlaneMesh.new()
	hm_mesh.size = Vector2(T * 0.96, T * 0.96)
	_harvest_marker = MeshInstance3D.new()
	_harvest_marker.mesh = hm_mesh
	var hm_mat := StandardMaterial3D.new()
	hm_mat.albedo_color = Color(1.0, 0.65, 0.2, 0.4)
	hm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm_mat.emission_enabled = true
	hm_mat.emission = Color(1.0, 0.55, 0.15)
	hm_mat.emission_energy_multiplier = 1.2
	_harvest_marker.material_override = hm_mat
	_harvest_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_harvest_marker.visible = false
	add_child(_harvest_marker)

	# selected-building outline (a flat glowing frame under the footprint)
	var bm_mesh := PlaneMesh.new()
	bm_mesh.size = Vector2(1.0, 1.0)
	_bld_marker = MeshInstance3D.new()
	_bld_marker.mesh = bm_mesh
	var bm_mat := StandardMaterial3D.new()
	bm_mat.albedo_color = Color(0.5, 1.0, 0.6, 0.22)
	bm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bld_marker.material_override = bm_mat
	_bld_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bld_marker.visible = false
	add_child(_bld_marker)


func _ghost_origin() -> Vector2i:
	var size: int = EFBuildings.DEFS[buildings.pending_place]["size"]
	return _hover_tile - Vector2i((size - 1) / 2, (size - 1) / 2)


# --- the ashen sky of dead Veyre ---------------------------------------------

func _setup_sky_and_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 38, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	# Cascades tuned for a camera that never comes closer than ~24 m: the stock
	# splits spend most of the shadow atlas on ground the RTS view never sees.
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_split_1 = 0.22
	sun.directional_shadow_split_2 = 0.42
	sun.directional_shadow_split_3 = 0.68
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.92
	sun.shadow_normal_bias = 1.2
	add_child(sun)

	sun.light_angular_distance = 1.2       # a real disk, so LIGHT0_SIZE isn't 0
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 215, 0)
	fill.light_color = Color(0.55, 0.6, 0.7)
	fill.light_energy = 0.3
	# LIGHT_ONLY keeps the fill out of the sky shader: otherwise it paints a
	# second, cool sun up there and LIGHT0 is no longer reliably the real sun
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)

	var sky := Sky.new()
	var sky_shader: Shader = load("res://sky.gdshader")
	if sky_shader != null:
		# the ash sky: scrolling cloud decks, a smothered sun, ember-lit horizon
		var sm := ShaderMaterial.new()
		sm.shader = sky_shader
		sky.sky_material = sm
		# clouds move, so the radiance cubemap must refresh — INCREMENTAL
		# spreads that cost over frames instead of paying it all at once
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		sky.radiance_size = Sky.RADIANCE_SIZE_128
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.33, 0.36, 0.42)
		sky_mat.sky_horizon_color = Color(0.63, 0.58, 0.49)
		sky_mat.ground_horizon_color = Color(0.6, 0.55, 0.46)
		sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.17)
		sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	# Glow tuned for a game named after burning stone: SCREEN blending and two
	# wide levels give the ember fields a real halo instead of a thin rim.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.9
	env.glow_strength = 1.05
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.90
	# set_glow_level indexes 0..6; the inspector labels those same levels 1..7.
	# Asking for level 7 was off the end of the array — it raised an error every
	# launch and the widest tier the halo was designed around never applied.
	env.set_glow_level(5, 0.7)
	env.set_glow_level(6, 0.35)
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	# the default 1 m radius is wider than the gap under a tank, so contact
	# darkening never bit at the track line
	env.ssao_radius = 0.45
	env.ssao_detail = 1.0
	env.adjustment_enabled = true              # a touch of grade: richer, deeper
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.12
	env.ssil_enabled = false    # half-res + 4 blur passes for a bounce nobody can
								# see at this camera height; it cost 0.4-0.8 ms and
								# that budget buys the fog and glow work below
	env.fog_enabled = true
	env.fog_light_color = Color(0.56, 0.53, 0.47)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.12       # was 0.25 — it washed out the sky's own contrast
	# The honest substitute for the volumetric fog we had to abandon: ash pools
	# in the low ground, distance takes on the sky's colour, and the sun bleeds
	# through it when you look toward the light.
	env.fog_height = 0.0
	env.fog_height_density = 0.08
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.20
	# (volumetric fog tried and rejected: its froxel grid ends mid-view at
	# RTS camera heights and renders as giant hard-edged slabs)

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# --- save / load -----------------------------------------------------------------
# One quicksave slot: F5 writes user://savegame.json, F9 (or the menu's
# CONTINUE button) brings the war back exactly where it slept.

func save_game() -> void:
	var idx_map := {}
	var blds := []
	for k in range(buildings.list.size()):
		var b: Dictionary = buildings.list[k]
		if b["hp"] <= 0:
			continue
		idx_map[k] = blds.size()
		var entry := {"type": b["type"], "fac": b["faction"],
			"ox": b["origin"].x, "oy": b["origin"].y, "hp": b["hp"],
			"rep": buildings.repairing.has(k)}
		var brp = b.get("rally", null)
		if brp is Vector3:
			entry["rx"] = brp.x
			entry["rz"] = brp.z
		blds.append(entry)
	var units := []
	for u in army.units:
		if u.hp <= 0:
			continue
		# passengers are OUT of army.units, so an unsaved manifest deletes them
		var carrying := []
		for c: EFUnit in u.cargo_units:
			carrying.append(c.kind)
		units.append({"kind": u.kind, "fac": u.faction,
			"x": u.global_position.x, "z": u.global_position.z,
			"hp": u.hp, "sh": u.shield,
			"home": idx_map.get(u.home_refinery, -1),
			"gar": u.garrisoned_in, "hstate": u.h_state, "cargo": u.cargo,
			"carrying": carrying})
	var res := []
	for tile in economy.reserves:
		res.append([tile.x, tile.y, economy.reserves[tile]])
	var regrow := []
	for tile in economy._regrow:
		regrow.append([tile.x, tile.y, economy._regrow[tile]])
	var wrecks := []
	for w in army.wrecks:
		if not w["gone"]:
			wrecks.append([w["pos"].x, w["pos"].z, w["value"], w["ttl"]])
	var queues := {}
	for tab in buildings.queues:
		var q = buildings.queues[tab]
		queues[tab] = null if q == null else {"id": q["id"], "paid": q["paid"]}
	var ai_states := []
	for a in ais:
		ai_states.append({"fac": a.fac, "state": a.state, "ti": a._train_i,
			"cd": a.attack_cd, "bq": a.build_q, "cb": a.cur_build,
			"ct": a.cur_train, "foe": a.enemy_fac})
	var data := {
		"version": 2, "map": cur_map, "player": player_fac, "enemy": ai_fac,
		"difficulty": cur_difficulty,
		"mode": cur_mode, "ally": ally_fac,
		"cam": {"x": rig.position.x, "z": rig.position.z, "dist": rig.target_dist},
		"credits": economy.credits, "reserves": res, "regrow": regrow,
		"explored": Marshalls.raw_to_base64(world.explored),
		"buildings": blds, "queues": queues, "backlog": buildings.backlog,
		"sw": buildings.sw_charge, "units": units, "wrecks": wrecks,
		"ais": ai_states,
		"ai": {"state": ai.state, "ti": ai._train_i, "cd": ai.attack_cd,
			"bq": ai.build_q, "cb": ai.cur_build, "ct": ai.cur_train} \
			if ai != null else {},
	}
	var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	ui.announce("THE WAR IS RECORDED — GAME SAVED", Color(0.55, 0.85, 0.5))
	print("saved: %d buildings, %d units" % [blds.size(), units.size()])


func _load_game() -> void:
	if not FileAccess.file_exists("user://savegame.json"):
		return
	var f := FileAccess.open("user://savegame.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_start_game(int(data["player"]), int(data["enemy"]), String(data["map"]),
		int(data["difficulty"]), true, false,
		String(data.get("mode", "1v1")), int(data.get("ally", 0)))
	_apply_save(data)


func _apply_save(data: Dictionary) -> void:
	# treasury + fields
	economy.credits.clear()
	for k in data["credits"]:
		economy.credits[int(k)] = int(data["credits"][k])
	economy.reserves.clear()
	for r in data["reserves"]:
		economy.reserves[Vector2i(int(r[0]), int(r[1]))] = float(r[2])
	economy._regrow.clear()
	for r in data["regrow"]:
		var tile := Vector2i(int(r[0]), int(r[1]))
		economy._regrow[tile] = float(r[2])
		world.deplete_ember(tile)
	# the remembered map
	world.explored = Marshalls.base64_to_raw(String(data["explored"]))
	world.repaint_explored()
	# the base, wall by wall
	for b in data["buildings"]:
		buildings.restore_building(String(b["type"]), int(b["fac"]),
			Vector2i(int(b["ox"]), int(b["oy"])), float(b["hp"]))
		if b.get("rep", false):
			buildings.repairing[buildings.list.size() - 1] = true
		if b.has("rx"):
			buildings.list[buildings.list.size() - 1]["rally"] = \
				Vector3(float(b["rx"]), 0.0, float(b["rz"]))
	for tab in data["queues"]:
		var q = data["queues"][tab]
		if q != null:
			buildings.queues[tab] = {"id": String(q["id"]), "cost":
				buildings._cost_of(String(q["id"])), "paid": float(q["paid"]),
				"is_unit": EFBuildings.TRAIN.has(String(q["id"])), "ready": false}
	for tab in data["backlog"]:
		buildings.backlog[tab] = []
		for id in data["backlog"][tab]:
			buildings.backlog[tab].append(String(id))
	for k in data["sw"]:
		buildings.sw_charge[int(k)] = float(data["sw"][k])
	# the armies
	for ud in data["units"]:
		var u := army.spawn(String(ud["kind"]), int(ud["fac"]),
			Vector2i(int(float(ud["x"]) / T), int(float(ud["z"]) / T)))
		u.global_position.x = float(ud["x"])
		u.global_position.z = float(ud["z"])
		u.hp = float(ud["hp"])
		u.shield = float(ud["sh"])
		u.home_refinery = int(ud["home"])
		u.cargo = float(ud["cargo"])
		if u.is_harvester():
			u.h_state = "to_refinery" if u.cargo > 250.0 else "idle"
		var gar := int(ud["gar"])
		if gar >= 0 and gar < structures.garrisons.size():
			structures.enter(u, gar)
		# saves written before the air bridge existed have no manifest at all
		for ck in ud.get("carrying", []):
			army.spawn(String(ck), int(ud["fac"]),
				Vector2i(int(float(ud["x"]) / T), int(float(ud["z"]) / T)))
	for w in data["wrecks"]:
		army.restore_wreck(Vector3(float(w[0]), 0.25, float(w[1])),
			int(w[2]), float(w[3]))
	# every commander's train of thought (v2 saves); v1 saves carry just one
	var states: Array = data.get("ais", [])
	if states.is_empty() and data.has("ai") and not (data["ai"] as Dictionary).is_empty():
		var legacy: Dictionary = data["ai"]
		legacy["fac"] = ai_fac
		states = [legacy]
	for ad_v in states:
		var ad: Dictionary = ad_v
		var target: EFAI = null
		for a in ais:
			if a.fac == int(ad.get("fac", -1)):
				target = a
				break
		if target == null:
			continue
		target.state = String(ad["state"])
		target._train_i = int(ad["ti"])
		target.attack_cd = float(ad["cd"])
		target.build_q = []
		for id in ad["bq"]:
			target.build_q.append(String(id))
		target.cur_build = ad["cb"] if ad["cb"] is Dictionary else {}
		target.cur_train = ad["ct"] if ad["ct"] is Dictionary else {}
		var foe_saved := int(ad.get("foe", 0))
		if foe_saved > 0 and foe_saved in target.foe_pool:
			target.enemy_fac = foe_saved
	# the commander's chair
	_hq_player = _find_hq(player_fac)
	_hq_enemy = _find_hq(ai_fac)
	var cam: Dictionary = data["cam"]
	rig.center_on(float(cam["x"]), float(cam["z"]))
	rig.target_dist = float(cam["dist"])
	rig.dist = float(cam["dist"])
	ui.announce("THE WAR RESUMES", Color(0.89, 0.58, 0.23))
	print("loaded: %d buildings, %d units, credits P%d=%d" %
		[buildings.list.size(), army.units.size(), player_fac,
		economy.credits.get(player_fac, 0)])


# --- dev screenshots ------------------------------------------------------------

func _wait_seconds(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _auto_place(id: String) -> bool:
	var start: Vector2i = world.starts[1]
	for ring in range(2, 14):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				if buildings.try_place(id, start + Vector2i(dx, dy)):
					return true
	return false


func _hint_at(i: int) -> String:
	return String(ui.hints_shown[i]) if i < ui.hints_shown.size() else "<NONE SHOWN>"


# A dev flag must not cost the player their own settings. Same contract as the
# campaign.cfg stash in --unlockcheck: take the real file out of the way, run
# the test against a clean slate, put it back byte for byte.
func _stash_user_file(fname: String) -> String:
	var d := DirAccess.open("user://")
	var text := ""
	if d != null and d.file_exists(fname):
		var fh := FileAccess.open("user://" + fname, FileAccess.READ)
		if fh != null:
			text = fh.get_as_text()
			fh.close()
		d.remove(fname)
	return text


func _restore_user_file(fname: String, text: String) -> void:
	var d := DirAccess.open("user://")
	if text != "":
		var fw := FileAccess.open("user://" + fname, FileAccess.WRITE)
		if fw != null:
			fw.store_string(text)
			fw.close()
	elif d != null and d.file_exists(fname):
		d.remove(fname)


func _maybe_selftest() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--selftest")
	if idx == -1:
		return
	var path := "user://selftest.png"
	if idx + 1 < args.size() and not args[idx + 1].begins_with("--"):
		path = args[idx + 1]
	_run_selftest(path)


func _run_selftest(path: String) -> void:
	var args := OS.get_cmdline_user_args()
	var sidx := args.find("--start")
	if sidx != -1 and sidx + 1 < args.size():
		var num := int(args[sidx + 1])
		if world.starts.has(num):
			var s: Vector2i = world.starts[num]
			rig.center_on((s.x + 0.5) * T, (s.y + 0.5) * T)

	rig.set_process(false)
	rig.set_process_unhandled_input(false)
	for i in range(30):
		await get_tree().process_frame

	if args.has("--musiccheck"):
		if music == null or not music.available:
			print("music test: NO PLAYERS (files missing?)")
		else:
			var w: AudioStreamWAV = music.bed.stream
			print("music test: format=%d (1=16bit, 4=QOA) loop_mode=%d (1=FORWARD) loop_end=%d"
				% [w.format, w.loop_mode, w.loop_end])
			print("music test: bed playing=%s war playing=%s" %
				[music.bed.playing, music.war.playing])
			var quiet := music.war.volume_db
			# fake a battle and watch the war layer answer
			for i in range(30):
				music.bump(0.2)
			await _wait_seconds(1.5)
			var loud := music.war.volume_db
			print("music test: war layer %.1f dB -> %.1f dB under fire (rose=%s)" %
				[quiet, loud, loud > quiet + 6.0])
			# drift must be read BEFORE the loop test below, which seeks one stem
			# on purpose and would desync them by definition
			var drift: float = absf(music.bed.get_playback_position()
				- music.war.get_playback_position())
			print("music test: bed/war drift %.4f s after free play (must stay locked)"
				% drift)
			# prove the loop: jump near the end and confirm it wraps and keeps going
			var dur: float = music.bed.stream.get_length()
			music.bed.seek(dur - 0.8)
			var before: float = music.bed.get_playback_position()
			await _wait_seconds(2.0)
			var after: float = music.bed.get_playback_position()
			print("music test: len=%.2fs seek->%.2fs then %.2fs playing=%s LOOPED=%s"
				% [dur, before, after, music.bed.playing,
					music.bed.playing and after < before])

	if args.has("--damagefx"):
		# wounded machines smoke, guns kick, treads scroll, booms pool
		var sd: Vector2i = world.faction_start(player_fac)
		var tank := army.spawn("bastion", player_fac, sd + Vector2i(6, 6))
		await _wait_seconds(0.8)
		# 1) tracks: a clear-lane drive, nothing to shoot along the way
		army.selection = [tank]
		army.order_move(Vector3((sd.x + 13.5) * T, 0, (sd.y + 6.5) * T))
		await _wait_seconds(2.0)
		print("damagefx: track phase %.2f m after a 2s drive (must be > 1)"
			% tank._track_phase)
		# 2) recoil: NOW give it something durable to shell, and poll the PEAK —
		# recoil decays in ~0.2 s, so a late single read can miss a real shot
		var prey := army.spawn("warpig", ai_fac,
			Vector2i(int(tank.global_position.x / T) + 4,
				int(tank.global_position.z / T)))
		await _wait_seconds(0.3)
		army.selection = [tank]
		army.order_smart(prey.global_position, structures, Vector3.INF)
		var peak := 0.0
		var t_end := Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < t_end and peak <= 0.0:
			peak = maxf(peak, tank.recoil_v)
			await get_tree().process_frame
		print("damagefx: peak recoil %.3f after firing (must be > 0)" % peak)
		# 3) wound smoke: hurt the tank below the threshold and count puffs
		army.damage_unit(tank, "CANNON", tank.max_hp * 0.6)
		await _wait_seconds(1.5)
		var live := 0
		for s in army._puffs:
			if bool(s["live"]):
				live += 1
		print("damagefx: %d live smoke puffs while wounded (must be > 0)" % live)
		# 4) booms pool: fire one directly — no victim required
		army._boom(tank.global_position + Vector3(3, 0, 0))
		await _wait_seconds(0.1)
		var booms := 0
		for s2 in army._booms:
			if bool(s2["live"]):
				booms += 1
		print("damagefx: %d live booms in the pool (must be > 0)" % booms)
		if is_instance_valid(prey) and prey.hp > 0:
			army.damage_unit(prey, "BLAST", 9999.0)
		rig.center_on(tank.global_position.x, tank.global_position.z)
		rig.target_dist = 16.0
		rig.dist = 16.0

	if args.has("--soldiercloseup"):
		# a squad at minimum zoom: the only honest way to judge the sculpt
		var sc2: Vector2i = world.faction_start(player_fac)
		var sq := army.spawn("iron_guard", player_fac, sc2 + Vector2i(6, 6))
		await _wait_seconds(1.0)
		rig.center_on(sq.global_position.x, sq.global_position.z)
		rig.dist = 14.0
		rig.target_dist = 14.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(0.6)

	if args.has("--closeup"):
		# full zoom-in on the player's base: the only view where surface detail
		# on a 3 m building is bigger than a pixel
		var cs: Vector2i = world.faction_start(player_fac)
		rig.center_on((cs.x + 2.0) * T, (cs.y + 1.0) * T)
		rig.dist = 15.0
		rig.target_dist = 15.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(1.0)

	if args.has("--skyshot"):
		# tilt up off the RTS pitch so the screenshot actually shows the sky
		rig.arm.rotation_degrees.x = -13.0
		rig.dist = 52.0
		rig.target_dist = 52.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(2.5)      # let the cloud decks scroll off frame zero

	if args.has("--edgeshot"):
		# what the player ACTUALLY sees: normal RTS pitch, parked at the map
		# boundary, so the background beyond the edge fills the top of frame
		rig.center_on(world.w * T * 0.5, 6.0 * T)
		rig.dist = 54.0
		rig.target_dist = 54.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(2.0)

	if args.has("--embershot"):
		# park on the largest ember field (the one nearest map centre) so a glow
		# change is judged on the thing the glow was tuned for
		var ec := Vector2i(int(world.w / 2), int(world.h / 2))
		var best_e := Vector2i(-1, -1)
		var best_d := 1 << 30
		for et in world.ember_tiles:
			var ed: int = absi(et.x - ec.x) + absi(et.y - ec.y)
			if ed < best_d:
				best_d = ed
				best_e = et
		if best_e.x >= 0:
			rig.center_on((best_e.x + 0.5) * T, (best_e.y + 0.5) * T)
			rig.dist = 18.0
			rig.target_dist = 18.0
			rig.cam.position = Vector3(0, 0, rig.dist)
		# the field is deep in unscouted ground: lift the shroud quad or the
		# screenshot is a black rectangle
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		print("embershot: centred on ember tile %s of %d on the map"
			% [best_e, world.ember_tiles.size()])
		await _wait_seconds(1.5)

	if args.has("--aiopen"):
		# A crawler-start commander used to deploy and then freeze forever.
		# Watch a real AI's economy actually come up.
		await _wait_seconds(45.0)
		var afac := ai_fac
		var counts := {}
		for b in buildings.list:
			if b["faction"] == afac and b["hp"] > 0:
				counts[b["type"]] = int(counts.get(b["type"], 0)) + 1
		var harv := 0
		var mil := 0
		for u in army.units:
			if u.faction == afac and u.hp > 0:
				if u.is_harvester():
					harv += 1
				elif not u.weapon.is_empty():
					mil += 1
		var brain: EFAI = null
		for a in ais:
			if a.fac == afac:
				brain = a
		print("aiopen: t=45s state=%s buildings=%s harvesters=%d military=%d credits=%d"
			% [brain.state if brain else "?", counts, harv, mil,
				economy.credits.get(afac, 0)])
		print("aiopen: has refinery=%s (the deadlock left this false forever)"
			% buildings._owns(afac, "refinery"))
		print("aiopen: left OPENING=%s (must be true)"
			% [brain != null and brain.state != "OPENING"])

	if args.has("--vehbake"):
		var s0v: Vector2i = world.faction_start(player_fac)
		var kinds_v := ["bastion", "outrider", "mule", "sparrowhawk"]
		var made: Array[EFUnit] = []
		for i in range(kinds_v.size()):
			made.append(army.spawn(kinds_v[i], player_fac,
				s0v + Vector2i(5 + i * 3, 5)))
		await _wait_seconds(1.0)
		for i in range(made.size()):
			var u: EFUnit = made[i]
			# count real submitted surfaces, not nodes
			var surfaces := 0
			var nodes := 0
			for c in u.find_children("*", "MeshInstance3D", true, false):
				var mi := c as MeshInstance3D
				if mi.mesh == null or not mi.visible:
					continue
				nodes += 1
				surfaces += mi.mesh.get_surface_count()
			print("vehbake: %-12s %d mesh nodes, %d surfaces submitted"
				% [kinds_v[i], nodes, surfaces])
		# a propeller must still exist and still spin
		var plane: EFUnit = made[3]
		# compare the whole basis: the prop spins about its LOCAL up while the
		# node itself is pitched 90 degrees, so no single euler axis is reliable
		var p0 := Basis.IDENTITY
		if plane._prop != null:
			p0 = plane._prop.transform.basis
		await _wait_seconds(0.8)
		var spun := plane._prop != null \
			and not plane._prop.transform.basis.is_equal_approx(p0)
		print("vehbake: sparrowhawk prop present=%s and still spinning=%s (must be true)"
			% [plane._prop != null, spun])
		rig.center_on((s0v.x + 8.5) * T, (s0v.y + 5.5) * T)
		rig.target_dist = 18.0
		rig.dist = 18.0
		await _wait_seconds(0.4)

	if args.has("--aistance"):
		# the AI now uses the player's stances: home guard digs in, and the
		# Brutal gun line roots its cannon vehicles at siege range
		var brain: EFAI = ais[0]
		var ah: Vector2i = world.faction_start(ai_fac)
		for i in range(8):
			army.spawn(["conscript", "sapper"][i % 2], ai_fac,
				ah + Vector2i(-3 + (i % 4) * 2, 5 + (i / 4) * 2))
		await _wait_seconds(4.0)
		var dug := 0
		for u in army.units:
			if u.faction == ai_fac and u.hp > 0 and u.fort_ref >= 0:
				dug += 1
		print("aistance: after 4s the home guard dug in %d forts (must be > 0, cap 6)" % dug)
		brain._mobilize_all()
		await _wait_seconds(0.2)
		var still := 0
		for u2 in army.units:
			if u2.faction == ai_fac and u2.hp > 0 and u2.fort_ref >= 0:
				still += 1
		print("aistance: after mobilize %d remain dug in (must be 0)" % still)
		# brutal artillery: a cannon vehicle at siege range of the player HQ
		brain.diff_lvl = 3
		brain.state = "WAVE"
		var php: Vector2i = world.faction_start(player_fac)
		var gun := army.spawn("bastion", ai_fac, php + Vector2i(6, 0))
		await _wait_seconds(0.1)
		brain._stance_tick()
		print("aistance: brutal bastion at siege range deployed=%s (stance %d, must be 1)"
			% [gun.stance == 1, gun.stance])
		brain.state = "ECONOMY"

	if args.has("--rally"):
		# prove the rally through the REAL production path, not by calling
		# set_rally and reading it back
		var sr: Vector2i = world.faction_start(player_fac)
		var bidx := -1
		for k in range(buildings.list.size()):
			if buildings.list[k]["type"] == "barracks" \
					and buildings.list[k]["faction"] == player_fac:
				bidx = k
		if bidx < 0:
			# raise one next to the start so the test stands alone
			buildings._create("barracks", player_fac, sr + Vector2i(5, 2))
			for k2 in range(buildings.list.size()):
				if buildings.list[k2]["type"] == "barracks":
					bidx = k2
		var rally := Vector3((sr.x + 14.5) * T, 0, (sr.y + 2.5) * T)
		sel_building = bidx
		buildings.set_rally(bidx, rally)
		print("rally: set on barracks %d -> %s | pennant visible=%s"
			% [bidx, rally, buildings._rally_node.visible])
		buildings.train_spawn("iron_guard", player_fac)
		await _wait_seconds(0.3)
		var newest: EFUnit = null
		for u in army.units:
			if u.kind == "iron_guard" and u.faction == player_fac:
				newest = u
		var going := newest != null and not newest.path.is_empty()
		await _wait_seconds(9.0)
		var d := 999.0
		if newest != null:
			d = newest.global_position.distance_to(rally)
		print("rally: fresh recruit pathed=%s, ended %.1f m from the rally (must be < 4)"
			% [going, d])
		sel_building = -1
		buildings.show_rally_for(-1)
		print("rally: pennant hidden after deselect=%s" % [not buildings._rally_node.visible])
		# minimap blips: count what a redraw would draw, through the same rules
		var vis_units := 0
		var hid_units := 0
		for u2 in army.units:
			if u2.hp <= 0 or u2.garrisoned_in >= 0 or u2.stowed:
				continue
			if u2.faction != player_fac and not u2.visible:
				hid_units += 1
			else:
				vis_units += 1
		print("rally: minimap would blip %d units, fog hides %d enemies (hidden must be > 0 on a fresh map)"
			% [vis_units, hid_units])

	if args.has("--facing"):
		# A static lineup cannot reveal a backwards model: only motion can.
		# Drive each pipeline unit east and compare where its NOSE points to
		# where it is actually travelling.
		var fs: Vector2i = world.faction_start(player_fac)
		var subjects: Array[EFUnit] = []
		for i in range(3):
			subjects.append(army.spawn(["bastion", "juggernaut", "outrider"][i],
				player_fac, fs + Vector2i(4, 4 + i * 3)))
		await _wait_seconds(1.0)
		army.selection = subjects
		army.order_move(Vector3((fs.x + 26.5) * T, 0, (fs.y + 7.5) * T))
		await _wait_seconds(4.0)
		for u in subjects:
			# -Z is forward in Godot; compare the hull's facing to its velocity
			var fwd := -u.global_transform.basis.z
			var vel := u.vel
			vel.y = 0.0
			var agree := 0.0
			if vel.length() > 0.3:
				agree = fwd.normalized().dot(vel.normalized())
			print("facing: %-11s nose-vs-travel %+.2f  %s"
				% [u.kind, agree,
					"FORWARD" if agree > 0.5 else
					("BACKWARDS" if agree < -0.5 else "turning/idle")])
		rig.center_on((fs.x + 12.0) * T, (fs.y + 7.5) * T)
		rig.dist = 24.0
		rig.target_dist = 24.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(0.4)

	if args.has("--karvath"):
		# the pipeline batch, lined up beside the units they replace
		var kb: Vector2i = world.faction_start(player_fac)
		# two rows, not one long line: a 40-tile row forced the camera so far
		# back that a reversed nose was unreadable, which is the one thing
		# this lineup exists to catch
		var row := [["pavise", 0, 0], ["dart", 5, 0], ["zephyr", 10, 0],
			["dray", 15, 0], ["keelwright", 21, 0],
			["sky_marine", 0, 8], ["wasp", 5, 8], ["sparrowhawk", 10, 8],
			["pelican", 16, 8], ["leviathan", 23, 8]]
		if player_fac == 1:
			row = [["bastion", 0, 0], ["outrider", 5, 0], ["sperrwagen", 10, 0],
				["mule", 15, 0], ["forge_crawler", 21, 0],
				["iron_guard", 0, 8], ["hammerfall", 5, 8],
				["kondor", 11, 8], ["juggernaut", 18, 8]]
		elif player_fac == 2:
			row = [["rat", 0, 0], ["warpig", 5, 0], ["stovepipe", 10, 0],
				["magpie", 15, 0], ["scrap_hauler", 21, 0],
				["conscript", 0, 8], ["vulture", 4, 8],
				["duster", 11, 8], ["ashworm", 18, 8]]
		elif player_fac == 4:
			row = [["glimmer", 0, 0], ["faraday", 5, 0], ["ion_carriage", 10, 0],
				["collector", 15, 0], ["dynamo", 20, 0],
				["arc_templar", 0, 8], ["lance_warden", 4, 8],
				["ark_carriage", 9, 8], ["seraph", 15, 8], ["cathedral", 22, 8]]
		# --pick KIND spawns that one unit alone and frames it tight: a lineup
		# shot is too small to tell a shading bug from a mesh bug
		var pick := ""
		var qi := args.find("--pick")
		if qi != -1 and qi + 1 < args.size():
			pick = String(args[qi + 1])
		var made: Array[EFUnit] = []
		for e in row:
			if pick != "" and String(e[0]) != pick:
				continue
			var u := army.spawn(String(e[0]), player_fac,
				kb + Vector2i(3 + (0 if pick != "" else int(e[1])),
					4 + (4 if pick != "" else int(e[2]))))
			made.append(u)
		await _wait_seconds(1.2)
		for u2 in made:
			print("karvath: %-11s custom=%s radius=%.2f props=%d"
				% [u2.kind, u2.custom_model, u2.radius,
					u2._props.size() + (1 if u2._prop != null else 0)])
			if not args.has("--dump"):
				continue
			if u2._merged != null and u2._merged.mesh != null:
				var ab: AABB = u2._merged.mesh.get_aabb()
				print("    aabb pos (%.2f, %.2f, %.2f) size (%.2f, %.2f, %.2f)"
					% [ab.position.x, ab.position.y, ab.position.z,
						ab.size.x, ab.size.y, ab.size.z])
				for si in range(u2._merged.mesh.get_surface_count()):
					var m := u2._merged.mesh.surface_get_material(si)
					var mn := "null"
					if m != null:
						mn = "%s '%s'" % [m.get_class(), m.resource_name]
						if m is BaseMaterial3D:
							var t: Texture2D = (m as BaseMaterial3D).albedo_texture
							mn += " tex=%s vc=%s" % [
								"null" if t == null else t.get_class(),
								(m as BaseMaterial3D).vertex_color_use_as_albedo]
					print("    surf %d: %s" % [si, mn])
			for p in u2._props:
				print("    prop @ (%.2f, %.2f, %.2f) r=%.2f"
					% [p.position.x, p.position.y, p.position.z,
						(p.mesh as CylinderMesh).top_radius])
			if u2._insig_mi == null:
				print("    insignia: NONE")
			else:
				var ia: AABB = u2._insig_mi.mesh.get_aabb()
				print("    insignia: %d verts, aabb pos (%.2f, %.2f, %.2f) size (%.2f, %.2f, %.2f) vis=%s"
					% [u2._insig_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
						ia.position.x, ia.position.y, ia.position.z,
						ia.size.x, ia.size.y, ia.size.z, u2._insig_mi.visible])
		rig.center_on((kb.x + (3.0 if pick != "" else 15.0)) * T,
			(kb.y + 8.5) * T)
		rig.dist = 18.0 if pick != "" else 34.0
		rig.target_dist = rig.dist
		rig.cam.position = Vector3(0, 0, rig.dist)
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		await _wait_seconds(0.6)

	if args.has("--bldshow"):
		# One of every structure, laid out on open ground and framed together.
		# The base only ever contains the two or three a match has built by the
		# time a selftest fires, so there was no view that showed the pipeline
		# buildings side by side.
		var sb: Vector2i = world.faction_start(player_fac)
		var lay := [["boiler", 0], ["barracks", 5], ["refinery", 10],
			["vehicle_works", 16], ["airfield", 22], ["doomworks", 28],
			["gun_turret", 34], ["aa_turret", 37]]
		for e in lay:
			buildings._create(String(e[0]), player_fac,
				sb + Vector2i(6 + int(e[1]), 20), true)
		await _wait_seconds(1.2)
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		# --pick <id> frames ONE structure close. At the 62 m group distance a
		# building is about a hundred pixels tall, which is too small to judge
		# whether its trim and relief are landing — the first pipeline batch
		# looked "flat" at group range and the real fault was only visible up close.
		var bpick := ""
		var bpi := args.find("--pick")
		if bpi != -1 and bpi + 1 < args.size():
			bpick = String(args[bpi + 1])
		var bcx := sb.x + 25.0
		var bcy := sb.y + 14.0
		var bdist := 62.0
		for e in lay:
			if String(e[0]) == bpick:
				bcx = sb.x + 6.0 + float(e[1]) + 1.5
				bcy = sb.y + 20.0
				bdist = 14.0
		rig.center_on(bcx * T, bcy * T)
		rig.dist = bdist
		rig.target_dist = bdist
		rig.cam.position = Vector3(0, 0, rig.dist)
		print("bldshow: placed %d structures | framed %s at %.0f m"
			% [lay.size(), bpick if bpick != "" else "all", bdist])
		await _wait_seconds(0.5)

	if args.has("--ruinview"):
		# Frame a background ruin. They sit on fringe rock, scattered across the
		# whole map, so no fixed camera finds one — ask the world which tiles it
		# actually consumed.
		var rk: Array = world._ruin_used.keys()
		if rk.is_empty():
			print("ruinview: no ruins on this map")
		else:
			# the keys are the FOUR tiles of each 2x2 footprint, so step by 4 to
			# land on a different ruin rather than the next corner of this one
			var rn := 0
			var rpi := args.find("--pick")
			if rpi != -1 and rpi + 1 < args.size():
				rn = int(args[rpi + 1])
			var ridx: int = clampi(rn * 4, 0, rk.size() - 1)
			var rt: Vector2i = rk[ridx]
			var rdist := 17.0
			var rdi := args.find("--dist")
			if rdi != -1 and rdi + 1 < args.size():
				rdist = float(args[rdi + 1])
			rig.center_on((rt.x + 0.5) * T, (rt.y + 1.5) * T)
			rig.dist = rdist
			rig.target_dist = rdist
			rig.cam.position = Vector3(0, 0, rdist)
			if world._shroud_mi != null:
				world._shroud_mi.visible = false
			print("ruinview: %d ruin tiles | framing (%d,%d) at %.0f m"
				% [rk.size(), rt.x, rt.y, rdist])
			await _wait_seconds(0.4)

	if args.has("--hqview"):
		# Close on the Command Post: the only structure that flies an ensign,
		# and at base-overview range the flag is a dozen pixels of cloth.
		var hb: Vector2i = world.faction_start(player_fac)
		var hdist := 15.0
		var hi := args.find("--dist")
		if hi != -1 and hi + 1 < args.size():
			hdist = float(args[hi + 1])
		rig.center_on((hb.x + 2.6) * T, (hb.y + 0.2) * T)
		rig.dist = hdist
		rig.target_dist = hdist
		rig.cam.position = Vector3(0, 0, hdist)
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		print("hqview: faction %d post at (%d,%d) | camera %.0f m"
			% [player_fac, hb.x, hb.y, hdist])
		await _wait_seconds(0.5)

	if args.has("--mtnview"):
		# Frame the DEEPEST rock tile on the map — the core of the biggest
		# massif — because that is where the depth-scaled height actually shows.
		# Any fixed camera lands on open ground and reports "no mountains".
		var dep := world.rock_depth()
		var bx := 0
		var by := 0
		var bd := 0
		for ty in range(world.h):
			for tx in range(world.w):
				var v: int = dep[ty * world.w + tx]
				if v > bd:
					bd = v
					bx = tx
					by = ty
		var mdist := 46.0
		var mi3 := args.find("--dist")
		if mi3 != -1 and mi3 + 1 < args.size():
			mdist = float(args[mi3 + 1])
		rig.center_on((bx + 0.5) * T, (by + 6.0) * T)
		rig.dist = mdist
		rig.target_dist = mdist
		rig.cam.position = Vector3(0, 0, mdist)
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		print("mtnview: deepest rock tile (%d,%d) depth %d | camera %.0f m"
			% [bx, by, bd, mdist])
		await _wait_seconds(0.4)

	if args.has("--formshot"):
		# The preview tick runs off _rmb_down state every frame, so the whole
		# formation UX can be driven headless: plant the press, warp the mouse,
		# and photograph what a player would see. Frame A proves the drag AIMS
		# without dragging the line away from the press point; frame B proves the
		# wheel override rotates the arrow to a stated compass point.
		var fsi := args.find("--selftest")
		var fsbase := String(args[fsi + 1]).trim_suffix(".png")
		var fsb: Vector2i = world.faction_start(player_fac)
		var fsl: Array[EFUnit] = []
		for fi in range(6):
			fsl.append(army.spawn("bastion", player_fac,
				fsb + Vector2i(14 + (fi % 3) * 2, 18 + (fi / 3) * 2)))
		await _wait_seconds(0.8)
		army.selection = fsl
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		var fscene := Vector3((fsb.x + 24.0) * T, 0.0, (fsb.y + 19.0) * T)
		rig.center_on(fscene.x, fscene.z)
		rig.dist = 30.0
		rig.target_dist = 30.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await get_tree().process_frame
		await get_tree().process_frame
		# press at the scene centre, drag 6 m north — the line must STAY at the
		# press point and face north
		var press3 := fscene
		var drag3 := fscene + Vector3(0, 0, -6.0)
		_rmb_pos = rig.cam.unproject_position(press3)
		_rmb_down = true
		_rmb_ms = 0
		get_viewport().warp_mouse(rig.cam.unproject_position(drag3))
		await _wait_seconds(0.3)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(fsbase + "_drag.png")
		print("formshot: drag-aim ghosts=%d anchor should be press point (%.0f, %.0f)"
			% [_ghost_pool.size(), press3.x, press3.z])
		# wheel override: face WEST regardless of the mouse
		_form_rot = PI
		await _wait_seconds(0.25)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(fsbase + "_wheel.png")
		print("formshot: wheel-aim rot=%.2f (west)" % _form_rot)
		_rmb_down = false
		_hide_formation_preview()

	if args.has("--gaitshot"):
		# Two frames a third of a stride apart prove the legs actually swing; a
		# third frame catches the rifle kick. No transform test can see any of
		# this — the whole gait lives in the vertex shader, so the only honest
		# witnesses are the limb-tag histogram and the pictures.
		var gsi := args.find("--selftest")
		var gbase := String(args[gsi + 1]).trim_suffix(".png")
		var gb: Vector2i = world.faction_start(player_fac)
		var gu := army.spawn("iron_guard", player_fac, gb + Vector2i(16, 20))
		await _wait_seconds(0.5)
		# ONE man, not six: a full section from 52 degrees up is a blob in which
		# no leg can be judged. Dropping hp to a sixth leaves a single soldier
		# standing on the unit origin where the camera is aimed anyway.
		gu.hp = gu.max_hp / 6.0 - 0.5
		await _wait_seconds(1.2)
		if gu._squad_mm != null:
			var gam := gu._squad_mm.multimesh.mesh as ArrayMesh
			for gs in range(gam.get_surface_count()):
				var garr := gam.surface_get_arrays(gs)
				var guvs: PackedVector2Array = garr[Mesh.ARRAY_TEX_UV]
				var gbuckets := [0, 0, 0, 0, 0]
				for gv in guvs:
					gbuckets[clampi(int(round(gv.x)), 0, 4)] += 1
				print("gaitshot: surface %d mat=%s limbs=%s" % [gs,
					gam.surface_get_material(gs).get_class(), gbuckets])
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		army.selection = [gu]
		army.order_move(Vector3((gb.x + 56.0) * T, 0.0, (gb.y + 20.0) * T))
		await _wait_seconds(1.6)
		rig.center_on(gu.global_position.x + 1.2, gu.global_position.z)
		rig.arm.rotation_degrees.x = -24.0    # low profile: legs in silhouette
		rig.dist = 5.5
		rig.target_dist = 5.5
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(0.12)
		await RenderingServer.frame_post_draw
		var gscr := rig.cam.unproject_position(gu.global_position + Vector3(0, 0.7, 0))
		print("gaitshot: man at screen (%.0f, %.0f) alive=%d hp=%.0f"
			% [gscr.x, gscr.y, gu._squad_alive, gu.hp])
		get_viewport().get_texture().get_image().save_png(gbase + "_a.png")
		await _wait_seconds(0.13)
		rig.center_on(gu.global_position.x + 1.2, gu.global_position.z)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(gbase + "_b.png")
		print("gaitshot: A/B saved  gait=%.2f amt=%.2f speed=%.2f"
			% [gu._gait, gu._gait_amt, gu.vel.length()])
		# halt, then park an enemy section in front of the guns for the kick
		army.order_move(gu.global_position)
		var gtile := Vector2i(int(gu.global_position.x / T) + 3,
			int(gu.global_position.z / T))
		var gef := 2 if player_fac != 2 else 1
		army.spawn("conscript", gef, gtile)
		var gkick := 0.0
		for gwait in range(300):
			await get_tree().process_frame
			if gu._fire_kick > 0.55:
				gkick = gu._fire_kick
				break
		rig.center_on(gu.global_position.x + 1.2, gu.global_position.z)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(gbase + "_fire.png")
		print("gaitshot: fire kick %.2f at capture" % gkick)

	if args.has("--aatest"):
		# Turrets went silent the day the pipeline building models landed: the
		# firing loop gated on a "Head" child the new single-mesh models do not
		# have. This is the regression test — one turret of each type, powered,
		# with one air and one ground enemy parked inside range. PASS = damage.
		var ab2: Vector2i = world.faction_start(player_fac)
		buildings._create("boiler", player_fac, ab2 + Vector2i(6, 2), true)
		buildings._create("aa_turret", player_fac, ab2 + Vector2i(10, 6), true)
		buildings._create("gun_turret", player_fac, ab2 + Vector2i(13, 6), true)
		var afoe := army.spawn("sparrowhawk", ai_fac, ab2 + Vector2i(11, 8))
		var gfoe := army.spawn("bastion", ai_fac, ab2 + Vector2i(14, 9))
		await _wait_seconds(0.5)
		var ah0: float = afoe.hp
		var gh0: float = gfoe.hp
		await _wait_seconds(6.0)
		var ah: float = afoe.hp if is_instance_valid(afoe) else 0.0
		var gh: float = gfoe.hp if is_instance_valid(gfoe) else 0.0
		print("aatest: AA vs air %.0f -> %.0f (%s) | gun vs ground %.0f -> %.0f (%s)"
			% [ah0, ah, "HIT" if ah < ah0 else "UNTOUCHED",
				gh0, gh, "HIT" if gh < gh0 else "UNTOUCHED"])
		rig.center_on((ab2.x + 11.0) * T, (ab2.y + 7.0) * T)
		rig.dist = 26.0
		rig.target_dist = 26.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		await _wait_seconds(0.3)

	if args.has("--fordtest"):
		# A ford that units quietly path AROUND is decoration, not a crossing —
		# and a screenshot cannot tell the difference between wading across and
		# detouring half the map. So: stand a tank on one bank, order it to the
		# far bank, and check where it actually ends up.
		var fx := -1
		var fy := -1
		for ty in range(world.h):
			for tx in range(world.w):
				if world.grid[ty][tx] == "f":
					fx = tx
					fy = ty
					break
			if fx != -1:
				break
		if fx == -1:
			print("fordtest: no ford tiles on this map")
		else:
			var wx := fx
			while wx > 2 and not world.is_walkable(wx - 1, fy):
				wx -= 1
			while wx > 2 and world.grid[fy][wx - 1] == "f":
				wx -= 1
			var ex := fx
			while ex < world.w - 3 and world.grid[fy][ex + 1] in ["f", "~"]:
				ex += 1
			var from_t := Vector2i(maxi(2, wx - 6), fy)
			var to_t := Vector2i(mini(world.w - 3, ex + 6), fy)
			var fu := army.spawn("bastion", player_fac, from_t)
			await _wait_seconds(0.5)
			var start_p := fu.global_position
			var goal := Vector3((to_t.x + 0.5) * T, 0.0, (to_t.y + 0.5) * T)
			army.selection = [fu]
			army.order_move(goal)
			var crossed := false
			for _i in range(140):        # ~14 s at 10 ticks/s of observation
				await _wait_seconds(0.1)
				var tx2 := int(fu.global_position.x / T)
				var ty2 := int(fu.global_position.z / T)
				if world.in_bounds(tx2, ty2) and world.grid[ty2][tx2] == "f":
					crossed = true
				if fu.global_position.distance_to(goal) < 3.0:
					break
			var d := fu.global_position.distance_to(goal)
			print("fordtest: ford at (%d,%d) | from (%d,%d) to (%d,%d)"
				% [fx, fy, from_t.x, from_t.y, to_t.x, to_t.y])
			print("fordtest: travelled %.1f m | %.1f m short of the far bank | ON THE FORD: %s | %s"
				% [start_p.distance_to(fu.global_position), d, crossed,
					"CROSSED" if d < 3.0 else "DID NOT ARRIVE"])
			rig.center_on(float(fx + 1) * T, float(fy) * T)
			rig.dist = 34.0
			rig.target_dist = 34.0
			rig.cam.position = Vector3(0, 0, rig.dist)
			if world._shroud_mi != null:
				world._shroud_mi.visible = false
			await _wait_seconds(0.4)

	if args.has("--rollcall"):
		# Facing was only ever verified on AIRCRAFT. The VEHICLE nose rule —
		# "the thin end of the model is the gun barrel, so that end is the
		# front" — was never checked against the vehicles it actually governs,
		# and the Juggernaut and Hammerfall shipped driving backwards.
		#
		# One unit at a time, driven EAST (+X, which is screen RIGHT under this
		# camera), framed to its own radius and photographed. A whole roster in
		# one process, so the models can be judged from PICTURES rather than
		# from the rule that produced them.
		var rdir := "user://"
		var ri := args.find("--rollcall")
		if ri != -1 and ri + 1 < args.size():
			rdir = String(args[ri + 1])
		var rb: Vector2i = world.faction_start(player_fac)
		var kinds: Array[String] = []
		for k in EFArmy.KINDS.keys():
			if ResourceLoader.exists("res://models/unit_%s.glb" % k):
				kinds.append(String(k))
		kinds.sort()
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		for k in kinds:
			# Do NOT drive them. Driving made the shot depend on pathfinding,
			# and pathfinding promptly routed half the roster around obstacles
			# heading south — the direction under test became a variable. The
			# question is only ever "does the mesh's nose agree with the unit's
			# own forward vector", so the transform is SET and photographed.
			# well clear of the base: the start forces are the SAME faction
			# colour and stood in frame, wrecking any automatic "where is the
			# subject" measurement taken off the screenshot
			var ru := army.spawn(k, player_fac, rb + Vector2i(30, 26))
			await _wait_seconds(1.6)         # let a flyer reach cruise altitude
			# Aim at the MODEL, not the ground point under it. center_on takes a
			# ground target, so a tall hull renders above frame centre and an
			# aircraft at altitude leaves the shot entirely — which is what made
			# the first contact sheet half empty sky. At the rig's ~52 degree
			# pitch, pushing the aim south by altitude/tan(52) re-centres it.
			# NORTH, not south: moving the aim point south puts the subject
			# north of centre, which pushes it UP and off the top of frame —
			# the mistake that emptied the first two contact sheets.
			var ralt: float = ru.global_position.y + maxf(ru.radius, 0.5) * 0.8
			rig.center_on(ru.global_position.x,
				ru.global_position.z - ralt * 0.78)
			# an aircraft cruises 8 m up, so it is 8 m NEARER the camera than the
			# ground plane this distance was sized against — without the
			# altitude term every flyer filled the whole frame
			var rd: float = clampf(ru.radius * 13.0, 11.0, 30.0) \
				+ ru.global_position.y * 1.35
			rig.dist = rd
			rig.target_dist = rd
			rig.cam.position = Vector3(0, 0, rd)
			await _wait_seconds(0.25)
			# Face EAST on the frame we photograph. Basis(UP, -90 deg) maps the
			# engine's forward (-Z) onto +X, so every model in the sheet is
			# nose-east by construction and the sheet can be read with one rule:
			# the nose must point SCREEN RIGHT.
			ru.global_transform.basis = Basis(Vector3.UP, -PI / 2.0)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/rc_%s.png" % [rdir, k])
			var rf := -ru.global_transform.basis.z
			print("rollcall: %-14s fwd (%+.2f, %+.2f) dist %.0f alt %.2f"
				% [k, rf.x, rf.z, rd, ru.global_position.y])
			army.selection = []
			army.units.erase(ru)
			ru.queue_free()
			await _wait_seconds(0.15)
		print("rollcall: %d models photographed | EAST = SCREEN RIGHT" % kinds.size())

	if args.has("--airfacing"):
		# A model reversed INSIDE its own glb is invisible to every transform
		# test: --facing compares the hull basis to velocity and the two agree
		# by construction, because the code is steering correctly and only the
		# MESH is wrong. The only proof is a picture. Fly it east — +X, which
		# is SCREEN RIGHT under this camera — and look at where the nose points.
		var ab: Vector2i = world.faction_start(player_fac)
		var akind := "sparrowhawk"
		var qa := args.find("--pick")
		if qa != -1 and qa + 1 < args.size():
			akind = String(args[qa + 1])
		var au := army.spawn(akind, player_fac, ab + Vector2i(6, 12))
		await _wait_seconds(0.8)
		army.selection = [au]
		# Bounded to the map: the first pass ordered a 60-tile hop, a 15 m/s
		# Sparrowhawk crossed the edge, and the camera's own _clamp() then
		# refused to follow it — the framing loop converged in Y and sat 237 px
		# out in X because the target was somewhere it could never look.
		var adx: float = minf(ab.x + 44.0, world.w - 7.0)
		army.order_move(Vector3(adx * T, 0.0, (ab.y + 12.0) * T))
		await _wait_seconds(2.2)
		var av := au.vel
		av.y = 0.0
		var afwd := -au.global_transform.basis.z
		print("airfacing: %-12s vel (%+.2f, %+.2f) basis-fwd (%+.2f, %+.2f) | EAST = SCREEN RIGHT"
			% [akind, av.x, av.z, afwd.x, afwd.z])
		# Framing this by dead reckoning does not work: the aircraft flies at
		# altitude, which throws it toward the TOP of the frame, and a 15 m/s
		# Sparrowhawk outruns any fixed lead (the first attempt photographed
		# empty ground). Close the loop instead — unproject where it ACTUALLY
		# lands and nudge the rig until it sits in the middle of the playable
		# area. Note the sidebar eats the right ~220 px, so the aim point is
		# not the frame centre. The loop also tracks the aircraft, so it is
		# still framed on the last iteration before the shot.
		rig.dist = 22.0
		rig.target_dist = 22.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		if world._shroud_mi != null:
			world._shroud_mi.visible = false
		var vps := get_viewport().get_visible_rect().size
		var want := Vector2((vps.x - 220.0) * 0.5, vps.y * 0.5)
		rig.center_on(au.global_position.x, au.global_position.z)
		var sp := Vector2.ZERO
		for i in range(16):
			await _wait_seconds(0.05)
			sp = rig.cam.unproject_position(au.global_position)
			var err := sp - want
			if args.has("--dump"):
				print("  frame %d: plane (%.1f, %.1f) rig (%.1f, %.1f) screen (%.0f, %.0f) err (%+.0f, %+.0f) yaw %.1f map %dx%d"
					% [i, au.global_position.x, au.global_position.z,
						rig.position.x, rig.position.z, sp.x, sp.y,
						err.x, err.y, rad_to_deg(rig.rotation.y), world.w, world.h])
			if err.length() < 14.0:
				break
			# Separate gains per axis, and BOTH below critical. One shared 0.035
			# made X oscillate with GROWING amplitude (146 -> 170 -> 189 -> ...
			# -> 266 px) while Y settled, because a 52-degree pitch foreshortens
			# the ground: measured off the trace, 1 px is 0.0202 m along X but
			# 0.0274 m along Z, so a gain tuned for Z over-corrects X by 1.75x.
			# Damped to ~0.85 of measured, plus a feed-forward on the aircraft's
			# own velocity so a 15 m/s Sparrowhawk does not out-run the loop.
			# These are tied to rig.dist = 22 above.
			var fv := au.vel
			rig.center_on(rig.position.x + err.x * 0.017 + fv.x * 0.05,
				rig.position.z + err.y * 0.023 + fv.z * 0.05)
		_shot_subject = au        # hand it to the shutter tracker
		print("airfacing: framed at screen (%.0f, %.0f), aim (%.0f, %.0f)"
			% [sp.x, sp.y, want.x, want.y])

	if args.has("--newtank"):
		# the pipeline pilot: new per-kind Bastion beside the old shared-chassis
		# tank (warpig still uses unit_tank.glb), same camera
		var nt: Vector2i = world.faction_start(player_fac)
		var nb := army.spawn("bastion", player_fac, nt + Vector2i(5, 5))
		var ow := army.spawn("warpig", player_fac, nt + Vector2i(8, 5))
		await _wait_seconds(1.0)
		print("newtank: bastion custom_model=%s | warpig custom_model=%s (must be true/false)"
			% [nb.custom_model, ow.custom_model])
		var mi_n := 0
		for c in nb.find_children("*", "MeshInstance3D", true, false):
			var cmi := c as MeshInstance3D
			if cmi.mesh == null:
				continue
			mi_n += 1
			var mats: Array = []
			for si in range(cmi.mesh.get_surface_count()):
				var m := cmi.mesh.surface_get_material(si)
				var ov := cmi.material_override
				mats.append("%s%s" % [m.resource_name if m else "null",
					"(+override)" if ov else ""])
			print("newtank:   node '%s' surfaces=%d mats=%s"
				% [cmi.name, cmi.mesh.get_surface_count(), mats])
		print("newtank: bastion mesh nodes=%d (baked: expect 1-2)" % mi_n)
		rig.center_on((nt.x + 6.5) * T, (nt.y + 5.5) * T)
		rig.target_dist = 14.0
		rig.dist = 14.0
		# the harness disables rig._process, and dist only reaches the camera
		# inside _process — write the camera transform directly or the shot
		# stays at default zoom (the escort-test lesson, one layer deeper)
		rig.cam.position = Vector3(0, 0, 14.0)
		await _wait_seconds(0.5)

	if args.has("--squadzoom"):
		# The check I owed: do six-man sections still read as a checkerboard at
		# the distance the game is actually played from?
		var sz: Vector2i = world.faction_start(player_fac)
		# each banner's own rifleman, not Karvath's — this flag now doubles as
		# the uniform check (helmet accent, dark boots) for all four factions
		var inf_kind: String = {1: "iron_guard", 2: "conscript",
			3: "sky_marine", 4: "arc_templar"}.get(player_fac, "iron_guard")
		var squads: Array[EFUnit] = []
		for r in range(3):
			for c in range(4):
				squads.append(army.spawn(inf_kind, player_fac,
					sz + Vector2i(4 + c * 3, 4 + r * 3)))
		await _wait_seconds(1.2)
		# converge everyone on one point: the huddle complaint is about squads
		# ON THE MARCH, and spawn-grid spacing proves nothing about that
		army.selection = squads.duplicate()
		army.order_move(Vector3((sz.x + 8.5) * T, 0.0, (sz.y + 7.5) * T))
		await _wait_seconds(3.5)
		var cx2 := (sz.x + 8.5) * T
		var cz2 := (sz.y + 7.5) * T
		rig.center_on(cx2, cz2)
		rig.target_dist = 30.0            # the default play distance
		rig.dist = 30.0
		await _wait_seconds(0.6)
		# measure how scattered the men actually are: the standard deviation of
		# their offsets tells me whether the jitter broke the rows or not
		var xs: Array[float] = []
		var zs: Array[float] = []
		for u in squads:
			for j in u._squad_jitter:
				xs.append(j.x)
				zs.append(j.z)
		var mx := 0.0
		for v in xs:
			mx += absf(v)
		print("squadzoom: %d sections, mean |jitter| = %.3f m against 0.30 m spacing"
			% [squads.size(), mx / maxf(float(xs.size()), 1.0)])
		print("squadzoom: camera at %.0f m — this is the distance the player sees"
			% rig.dist)

	if args.has("--meshdump"):
		# Observation, not theory: compare what the BAKED mesh's surfaces hold
		# against the same materials read straight off the un-baked glb.
		var raw: Node3D = (load("res://models/unit_soldier.glb") as PackedScene).instantiate()
		add_child(raw)
		print("meshdump: --- materials ON THE GLB (these render correctly) ---")
		var seen_raw := {}
		for child in raw.find_children("*", "MeshInstance3D", true, false):
			var rmi := child as MeshInstance3D
			if rmi.mesh == null:
				continue
			for si in range(rmi.mesh.get_surface_count()):
				var rm := rmi.get_active_material(si)
				if rm == null or seen_raw.has(rm.get_instance_id()):
					continue
				seen_raw[rm.get_instance_id()] = true
				var tex_r := "none"
				if rm is BaseMaterial3D:
					var t: Texture2D = (rm as BaseMaterial3D).albedo_texture
					tex_r = "null" if t == null else "%s(%dx%d)" % [
						t.get_class(), t.get_width(), t.get_height()]
				print("  glb mat '%s' class=%s albedo_tex=%s"
					% [rm.resource_name, rm.get_class(), tex_r])
		raw.queue_free()

		print("meshdump: --- surfaces ON THE BAKED MESH (these checkerboard) ---")
		EFUnit.reset_visual_caches()
		var baked: ArrayMesh = EFUnit._bake_squad_mesh(player_fac, "")
		if baked == null:
			print("  BAKE RETURNED NULL")
		else:
			print("  surfaces=%d" % baked.get_surface_count())
			for i in range(baked.get_surface_count()):
				var bm := baked.surface_get_material(i)
				var desc := "NULL MATERIAL"
				if bm != null:
					var tex_b := "n/a"
					if bm is BaseMaterial3D:
						var bt: Texture2D = (bm as BaseMaterial3D).albedo_texture
						tex_b = "null" if bt == null else "%s(%dx%d)" % [
							bt.get_class(), bt.get_width(), bt.get_height()]
						tex_b += " shaded=%d" % (bm as BaseMaterial3D).shading_mode
					desc = "'%s' class=%s albedo_tex=%s" % [
						bm.resource_name, bm.get_class(), tex_b]
				# what the geometry itself carries
				var arr: Array = baked.surface_get_arrays(i)
				var verts: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var has_norm: bool = arr[Mesh.ARRAY_NORMAL] != null
				var has_tan: bool = arr[Mesh.ARRAY_TANGENT] != null
				var has_uv: bool = arr[Mesh.ARRAY_TEX_UV] != null
				var has_col: bool = arr[Mesh.ARRAY_COLOR] != null
				print("  surf %d: %s" % [i, desc])
				print("          verts=%d normal=%s tangent=%s uv=%s color=%s"
					% [verts, has_norm, has_tan, has_uv, has_col])
		# ISOLATION: the SAME baked mesh rendered three ways, side by side.
		# Whichever one checkerboards is the culprit, and it is no longer a guess.
		if baked != null:
			var s0: Vector2i = world.faction_start(player_fac)
			var base := Vector3((s0.x + 6.5) * T, 0, (s0.y + 6.5) * T)

			# (a) plain MeshInstance3D — no MultiMesh at all
			var plain := MeshInstance3D.new()
			plain.mesh = baked
			plain.position = base
			plain.scale = Vector3(3, 3, 3)
			add_child(plain)

			# (b) MultiMesh with colours + custom data, exactly as the squad does
			var mmA := MultiMesh.new()
			mmA.transform_format = MultiMesh.TRANSFORM_3D
			mmA.use_colors = true
			mmA.use_custom_data = true
			mmA.mesh = baked
			mmA.instance_count = 1
			mmA.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(3, 3, 3)),
				base + Vector3(4, 0, 0)))
			mmA.set_instance_color(0, Color(1, 1, 1, 1))
			mmA.set_instance_custom_data(0, Color(0, 0, 0, 0))
			var miA := MultiMeshInstance3D.new()
			miA.multimesh = mmA
			add_child(miA)

			# (c) MultiMesh with NEITHER colours nor custom data
			var mmB := MultiMesh.new()
			mmB.transform_format = MultiMesh.TRANSFORM_3D
			mmB.mesh = baked
			mmB.instance_count = 1
			mmB.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(3, 3, 3)),
				base + Vector3(8, 0, 0)))
			var miB := MultiMeshInstance3D.new()
			miB.multimesh = mmB
			add_child(miB)

			print("meshdump: left=plain MeshInstance | middle=MultiMesh+colors+custom | right=MultiMesh bare")
			rig.center_on(base.x + 4.0, base.z)
			rig.target_dist = 16.0
			rig.dist = 16.0
			await _wait_seconds(0.6)
		print("meshdump: done")

	if args.has("--battle"):
		# Every other timing window measures a quiet base. The frame cost that
		# actually matters is 40v40 shooting, where the effect code allocates.
		var sb: Vector2i = world.faction_start(player_fac)
		var mid := Vector2i(sb.x + 14, sb.y + 14)
		var mine: Array[EFUnit] = []
		var theirs: Array[EFUnit] = []
		for i in range(40):
			mine.append(army.spawn(["iron_guard", "bastion", "outrider"][i % 3],
				player_fac, mid + Vector2i(-6 + (i % 6), -6 + (i / 6))))
			theirs.append(army.spawn(["conscript", "warpig", "rat"][i % 3],
				ai_fac, mid + Vector2i(4 + (i % 6), 4 + (i / 6))))
		await _wait_seconds(1.0)
		army.selection = mine
		army.order_move(Vector3((mid.x + 6.5) * T, 0, (mid.y + 6.5) * T))
		# wait for the shooting to actually start before timing anything
		await _wait_until(func():
			for u in mine:
				if is_instance_valid(u) and u.tgt_unit != null:
					return true
			return false, 30.0)
		await _wait_seconds(1.5)
		var t0 := Time.get_ticks_usec()
		var frames := 0
		while frames < 120:
			await get_tree().process_frame
			frames += 1
		var dur := float(Time.get_ticks_usec() - t0) / 1000000.0
		var alive_a := 0
		var alive_b := 0
		for u in mine:
			if is_instance_valid(u) and u.hp > 0:
				alive_a += 1
		for u in theirs:
			if is_instance_valid(u) and u.hp > 0:
				alive_b += 1
		print("battle: %d v %d fighting | %.1f FPS over %d frames IN COMBAT"
			% [alive_a, alive_b, float(frames) / maxf(dur, 0.001), frames])
		print("battle: draw calls=%d | fx nodes=%d"
			% [RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				army.get_child_count()])
		# smoke: every puff on the map should now cost ONE draw call between them
		var live_puffs := 0
		for s in army._puffs:
			if bool(s["live"]):
				live_puffs += 1
		print("battle: %d puffs of smoke alive, sharing %d MultiMesh (pool %d)"
			% [live_puffs, 1 if army._puff_mm != null else 0, EFArmy.PUFF_POOL])
		rig.center_on((mid.x + 0.5) * T, (mid.y + 0.5) * T)
		rig.target_dist = 30.0
		rig.dist = 30.0

	if args.has("--expand"):
		# A BRUTAL commander should not sit on one deposit all game. Compress the
		# clock so a 3-minute-plus behaviour is observable in a selftest.
		var brain: EFAI = null
		for a in ais:
			if a.fac == ai_fac:
				brain = a
		if brain == null:
			print("expand: NO AI FOUND")
		else:
			brain.set_difficulty(3)
			brain.expand_after = 8.0          # compressed from 180s
			brain.expand_credits = 1500
			brain.expand_army = 1
			economy.credits[ai_fac] = 12000   # give it the means, not the decision
			print("expand: fields clustered on this map=%d | expand_max=%d reach=%d"
				% [brain._fields.size(), brain.expand_max, brain.expand_reach])
			var posts0 := buildings.count_posts(ai_fac)
			var won := await _wait_until(func():
				return buildings.count_posts(ai_fac) > posts0, 150.0)
			var posts1 := buildings.count_posts(ai_fac)
			print("expand: posts %d -> %d within 150s (must grow) state=%s built=%d"
				% [posts0, posts1, brain._exp_state, brain._exp_built])
			# where did it plant it, and is it actually near ember?
			var far := 0
			var near_ember := false
			for b in buildings.list:
				if b["type"] == "command_post" and b["faction"] == ai_fac \
						and b["hp"] > 0:
					var o: Vector2i = b["origin"]
					var d := maxi(absi(o.x - brain.hq_tile.x), absi(o.y - brain.hq_tile.y))
					far = maxi(far, d)
					for t in world.ember_tiles:
						if maxi(absi(t.x - o.x), absi(t.y - o.y)) <= 8:
							near_ember = true
			print("expand: furthest post is %d tiles from the capital (spacing min %d)"
				% [far, EFBuildings.MCV_SPACING])
			print("expand: a post sits within 8 tiles of ember=%s (that is the point)"
				% near_ember)
			print("expand: reached=%s" % won)

	if args.has("--escort"):
		# The harness switches the rig's _process OFF above so screenshots are
		# deterministic — which also switches off the escort camera. Measuring
		# the follow with it disabled reported the feature as broken when it was
		# the test that was broken. Turn it back on for this one test.
		rig.set_process(true)
		rig.edge_pan_on = false
		var se: Vector2i = world.faction_start(player_fac)
		var fast := army.spawn("outrider", player_fac, se + Vector2i(4, 4))
		var slow := army.spawn("bastion", player_fac, se + Vector2i(5, 4))
		await _wait_seconds(0.5)
		rig.follow_on = true
		army.selection = [fast, slow]
		var cam0 := Vector2(rig.position.x, rig.position.z)
		var dest := Vector3((se.x + 30.5) * T, 0, (se.y + 4.5) * T)
		army.order_move(dest)
		rig.follow_group(army.selection)
		print("escort: after follow_group active=%s units=%d follow_on=%s"
			% [rig._follow_active, rig.follow_units.size(), rig.follow_on])
		print("escort: rig processing=%s (must be true or nothing can follow)"
			% rig.is_processing())
		await _wait_seconds(1.0)
		print("escort: 1s later active=%s cam=(%.1f,%.1f) fast at (%.1f,%.1f)"
			% [rig._follow_active, rig.position.x, rig.position.z,
				fast.global_position.x, fast.global_position.z])
		await _wait_seconds(3.0)
		var cam1 := Vector2(rig.position.x, rig.position.z)
		var fastp := Vector2(fast.global_position.x, fast.global_position.z)
		var slowp := Vector2(slow.global_position.x, slow.global_position.z)
		print("escort: camera moved %.1f m with the group (must be > 5)"
			% cam0.distance_to(cam1))
		print("escort: camera is %.1f m from the fast unit, %.1f m from the slow one (must favour the fast)"
			% [cam1.distance_to(fastp), cam1.distance_to(slowp)])
		# the release: a manual pan must hand control straight back
		var before := Vector2(rig.position.x, rig.position.z)
		rig.release_follow()
		await _wait_seconds(2.0)
		var after := Vector2(rig.position.x, rig.position.z)
		print("escort: after release the camera moved %.2f m while the group kept marching (must be ~0)"
			% before.distance_to(after))
		# and clicking off the units must release it too
		rig.follow_group(army.selection)
		army.clear_selection()
		print("escort: deselecting released the follow=%s (must be true)"
			% [not rig._follow_active])
		rig.follow_on = false

	if args.has("--walk"):
		# the gait must be driven by GROUND COVERED, not by time, or the feet
		# skate; and it must actually reach the shader as custom data
		var sw: Vector2i = world.faction_start(player_fac)
		var sol := army.spawn("iron_guard", player_fac, sw + Vector2i(5, 5))
		await _wait_seconds(0.6)
		var mmw: MultiMesh = sol._squad_mm.multimesh
		print("walk: custom data enabled=%s | colours=%s | instances=%d"
			% [mmw.use_custom_data, mmw.use_colors, mmw.instance_count])
		# limb tagging: how many of the baked verts are legs vs arms vs body
		var bm: ArrayMesh = mmw.mesh
		var tally := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
		for si in range(bm.get_surface_count()):
			var arr := bm.surface_get_arrays(si)
			if arr[Mesh.ARRAY_TEX_UV2] == null:
				continue
			var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
			for v in u2:
				var lid := int(round(v.x))
				tally[lid] = int(tally.get(lid, 0)) + 1
		print("walk: limb tags body=%d Lleg=%d Rleg=%d Larm=%d Rarm=%d (legs+arms must be > 0)"
			% [tally[0], tally[1], tally[2], tally[3], tally[4]])
		# stand still: gait must settle to zero
		await _wait_seconds(1.4)
		var idle_amt: float = mmw.get_instance_custom_data(0).g
		# now march and sample the phase twice
		army.selection = [sol]
		army.order_move(Vector3((sw.x + 22.5) * T, 0, (sw.y + 5.5) * T))
		await _wait_seconds(1.2)
		var p1: float = mmw.get_instance_custom_data(0).r
		var amt1: float = mmw.get_instance_custom_data(0).g
		var pos1 := sol.global_position
		await _wait_seconds(1.2)
		var p2: float = mmw.get_instance_custom_data(0).r
		var dist := sol.global_position.distance_to(pos1)
		print("walk: idle gait amount %.2f (must be ~0) -> walking %.2f (must be ~1)"
			% [idle_amt, amt1])
		print("walk: phase advanced %.2f rad over %.2f m travelled -> %.2f rad/m (stride %.2f m)"
			% [fposmod(p2 - p1, TAU), dist,
				fposmod(p2 - p1, TAU) / maxf(dist, 0.001), EFUnit.STRIDE_LEN])
		# six men, each on his own phase, so a section is not one animal
		var phases: Array = []
		for i in range(6):
			phases.append("%.2f" % mmw.get_instance_custom_data(i).r)
		print("walk: per-man phases %s (must differ)" % [phases])
		# report what the bake actually produced, per surface
		for si2 in range(bm.get_surface_count()):
			var a2 := bm.surface_get_arrays(si2)
			var vv: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
			var mn := Vector3(1e9, 1e9, 1e9)
			var mx := Vector3(-1e9, -1e9, -1e9)
			for v3 in vv:
				mn = Vector3(minf(mn.x, v3.x), minf(mn.y, v3.y), minf(mn.z, v3.z))
				mx = Vector3(maxf(mx.x, v3.x), maxf(mx.y, v3.y), maxf(mx.z, v3.z))
			var mt := bm.surface_get_material(si2)
			print("walk: surf %d verts=%d normals=%s uv=%s bounds y %.2f..%.2f mat=%s"
				% [si2, vv.size(), a2[Mesh.ARRAY_NORMAL] != null,
					a2[Mesh.ARRAY_TEX_UV] != null, mn.y, mx.y,
					mt.get_class() if mt != null else "NULL"])
		rig.center_on(sol.global_position.x, sol.global_position.z)
		rig.target_dist = 6.0
		rig.dist = 6.0
		await _wait_seconds(0.6)

	if args.has("--wide"):
		# the Juggernaut is 1.5 m of radius on a 2 m grid: the ordinary A* grid
		# routed it through gaps it physically cannot enter, and it jammed
		var s0w: Vector2i = world.faction_start(player_fac)
		var jug := army.spawn("juggernaut", player_fac, s0w + Vector2i(4, 4))
		var ref := army.spawn("bastion", player_fac, s0w + Vector2i(6, 4))
		await _wait_seconds(0.8)
		var legal := world.clear_at(jug.global_position.x, jug.global_position.z,
			jug.radius * 0.8)
		print("wide: juggernaut r=%.2f spawned on a legal tile=%s (must be true)"
			% [jug.radius, legal])
		# count how much of the map each grid considers passable
		var open_n := 0
		var open_w := 0
		for ty in range(world.h):
			for tx in range(world.w):
				if world.is_walkable(tx, ty):
					open_n += 1
					if not army.astar_wide.is_point_solid(Vector2i(tx, ty)):
						open_w += 1
		print("wide: walkable tiles %d | legal for a wide hull %d (%.1f%%)"
			% [open_n, open_w, 100.0 * float(open_w) / maxf(float(open_n), 1.0)])
		# send both across the map and see who actually arrives
		var far := Vector3((world.w - 8) * T, 0, (world.h - 8) * T)
		army.selection = [jug, ref]
		army.order_move(far)
		var start_j := jug.global_position
		var start_b := ref.global_position
		await _wait_seconds(30.0)
		var moved_j := jug.global_position.distance_to(start_j)
		var moved_b := ref.global_position.distance_to(start_b)
		var jug_legal := world.clear_at(jug.global_position.x,
			jug.global_position.z, jug.radius * 0.8)
		print("wide: after 30s juggernaut travelled %.1f m (bastion %.1f m), still on legal ground=%s"
			% [moved_j, moved_b, jug_legal])
		print("wide: juggernaut still has a path=%s stuck_time=%.2f (must not be wedged)"
			% [not jug.path.is_empty(), jug.stuck_time])
		rig.center_on(jug.global_position.x, jug.global_position.z)
		rig.target_dist = 22.0
		rig.dist = 22.0
		await _wait_seconds(0.5)

	if args.has("--squad"):
		# a section of six that thins as it bleeds and re-forms as it heals
		var s0: Vector2i = world.faction_start(player_fac)
		var sq := army.spawn("iron_guard", player_fac, s0 + Vector2i(5, 5))
		await _wait_seconds(0.6)
		print("squad: %s spawned with %d men (hp %d/%d), draw surfaces %d"
			% [sq.kind, sq.squad_alive(), int(sq.hp), int(sq.max_hp),
				sq._squad_mm.multimesh.mesh.get_surface_count()
					if sq._squad_mm != null else -1])
		var seen: Array = []
		for frac in [0.80, 0.60, 0.40, 0.20, 0.08]:
			sq.hp = sq.max_hp * frac
			await _wait_seconds(0.35)
			seen.append("%d%%->%d" % [int(frac * 100), sq.squad_alive()])
		print("squad: thinning %s (must fall 5,4,3,2,1)" % [seen])
		sq.hp = sq.max_hp
		await _wait_seconds(0.5)
		print("squad: healed to full -> %d men back up" % sq.squad_alive())
		# and one section must still count as ONE unit everywhere it matters
		var inf_units := 0
		for u in army.units:
			if u.faction == player_fac and u.is_infantry():
				inf_units += 1
		print("squad: %d infantry UNITS on the field (six men each, but one unit apiece)"
			% inf_units)
		# drop a second section beside it at half strength so the screenshot
		# shows a full six and a mauled one side by side
		var sq2 := army.spawn("grenadier", player_fac, s0 + Vector2i(7, 5))
		await _wait_seconds(0.4)
		sq2.hp = sq2.max_hp * 0.45
		await _wait_seconds(0.8)
		print("squad: neighbour section at 45%% hp shows %d men" % sq2.squad_alive())
		# prove the six men are real geometry in six DIFFERENT places, and that
		# the fallen are scaled away rather than left standing
		var mmv: MultiMesh = sq2._squad_mm.multimesh
		var verts := 0
		for si in range(mmv.mesh.get_surface_count()):
			verts += mmv.mesh.surface_get_array_len(si)
		var spots: Array = []
		var standing := 0
		for ii in range(mmv.instance_count):
			var tr := mmv.get_instance_transform(ii)
			var sc := tr.basis.get_scale().x
			if sc > 0.5:
				standing += 1
				spots.append("(%.2f,%.2f)" % [tr.origin.x, tr.origin.z])
		print("squad: baked mesh %d verts across %d surfaces | %d standing at %s"
			% [verts, mmv.mesh.get_surface_count(), standing, spots])
		rig.center_on((s0.x + 6.0) * T, (s0.y + 5.2) * T)
		rig.target_dist = 8.0
		rig.dist = 8.0
		await _wait_seconds(0.8)

	if args.has("--ffa"):
		# four sides, three commanders: everyone hostile, elimination retargets
		print("ffa: sides %s | teams %s | ais %d" % [world.slot_faction,
			world.team_of, ais.size()])
		var hostile_pairs := 0
		for fa in [1, 2, 3, 4]:
			for fb in [1, 2, 3, 4]:
				if fa < fb and world.is_hostile(fa, fb):
					hostile_pairs += 1
		print("ffa: hostile pairs %d (must be 6 — everyone fights everyone)"
			% hostile_pairs)
		# THE 3v1 CHECK: every commander used to open aimed at the player,
		# because main hands over the foe list with the human at the front.
		var aim0 := []
		var on_player0 := 0
		for a0 in ais:
			aim0.append("%d->%d" % [a0.fac, a0.enemy_fac])
			if a0.enemy_fac == player_fac:
				on_player0 += 1
		print("ffa: opening targets %s | aimed at player %d of %d (must NOT be all)"
			% [aim0, on_player0, ais.size()])
		# and each should pick the neighbour actually nearest its own base
		var nearest_ok := 0
		for a1 in ais:
			var own: Vector2i = world.faction_start(a1.fac)
			var best_f := -1
			var best_d := 1e18
			for f5 in [1, 2, 3, 4]:
				if f5 == a1.fac:
					continue
				var s5: Vector2i = world.faction_start(f5)
				var d5 := Vector2(s5.x - own.x, s5.y - own.y).length_squared()
				if d5 < best_d:
					best_d = d5
					best_f = f5
			if a1.enemy_fac == best_f:
				nearest_ok += 1
		print("ffa: commanders aimed at their NEAREST neighbour: %d of %d"
			% [nearest_ok, ais.size()])
		await _wait_seconds(20.0)
		var aim1 := []
		for a2 in ais:
			aim1.append("%d->%d(seen %s)" % [a2.fac, a2.enemy_fac, a2.known])
		print("ffa: after 20s targets %s" % [aim1])
		var counts := {}
		for u in army.units:
			counts[u.faction] = counts.get(u.faction, 0) + 1
		print("ffa: after 20s units per faction %s | posts %s" % [counts,
			[buildings.count_posts(1), buildings.count_posts(2),
			buildings.count_posts(3), buildings.count_posts(4)]])
		# kill enemy #1's post: its hunters must retarget, not go home
		var vic := ais[0].fac
		for bi in range(buildings.list.size()):
			var b: Dictionary = buildings.list[bi]
			if b["type"] == "command_post" and b["faction"] == vic:
				buildings.take_damage(bi, "BLAST", 99999.0)
		for u2 in army.units.duplicate():
			if u2.faction == vic:
				army.damage_unit(u2, "BLAST", 99999.0)
		await _wait_seconds(3.0)
		var retargeted := true
		for a2 in ais:
			if a2.fac != vic and a2.enemy_fac == vic:
				retargeted = false
		print("ffa: killed faction %d -> fallen announced=%s, others retargeted=%s"
			% [vic, _fallen.has(vic), retargeted])

	if args.has("--allied"):
		# the ally must never be targeted, must share vision, and the win needs
		# BOTH enemies down
		print("allied: player %d + ally %d vs %s | teams %s" % [player_fac,
			ally_fac, enemy_facs, world.team_of])
		print("allied: is_hostile(p,ally)=%s (must be false) | is_ally=%s (must be true)"
			% [world.is_hostile(player_fac, ally_fac),
				world.is_ally(player_fac, ally_fac)])
		# park an allied unit beside the player's troops and wait: nobody fires
		var mine: EFUnit = null
		var theirs: EFUnit = null
		for u in army.units:
			if u.faction == player_fac and not u.weapon.is_empty() and mine == null:
				mine = u
			if u.faction == ally_fac and not u.weapon.is_empty() and theirs == null:
				theirs = u
		if mine != null and theirs != null:
			theirs.global_position = mine.global_position + Vector3(2, 0, 0)
			await _wait_seconds(8.0)
			print("allied: ceasefire held after 8s side by side: mine hp %d/%d, ally hp %d/%d (both must be full)"
				% [int(mine.hp), int(mine.max_hp), int(theirs.hp), int(theirs.max_hp)])
		var tgt_check := army._nearest_enemy(player_fac,
			(mine.global_position if mine != null else Vector3.ZERO), 30.0)
		print("allied: nearest_enemy from player ignores ally: %s" %
			("PASS" if tgt_check == null or tgt_check.faction != ally_fac else "FAIL"))
		# ally down does NOT end the game; both enemies down does
		print("allied: win requires both %s beaten — currently beaten: [%s, %s]"
			% [enemy_facs, _is_beaten(enemy_facs[0]), _is_beaten(enemy_facs[1])])

	if args.has("--mcv"):
		# the whole crawler lifecycle: start baseless, deploy, expand, hit the
		# cap, and confirm the new defeat rule replaces "one HQ or you lose"
		print("mcv: start posts P%d/E%d | player has crawler=%s | beaten=%s (must be false)"
			% [buildings.count_posts(player_fac), buildings.count_posts(ai_fac),
				_has_mcv(player_fac), _is_beaten(player_fac)])
		var mcv: EFUnit = null
		for u in army.units:
			if u.faction == player_fac and u.role == "mcv":
				mcv = u
				break
		if mcv == null:
			print("mcv: FAIL — no crawler spawned")
		else:
			print("mcv: crawler is '%s' hp %d, invisible=%s (must be false)"
				% [mcv.display_name, int(mcv.hp), mcv.get_child_count() == 0])
			army.clear_selection()
			mcv.selected = true
			army.selection.append(mcv)
			_deploy_selected()
			await _wait_seconds(0.4)
			print("mcv: after deploy posts=%d | crawler alive=%s (must be false) | hq idx=%d"
				% [buildings.count_posts(player_fac), _has_mcv(player_fac),
					_find_hq(player_fac)])
			var cp_idx := _find_hq(player_fac)
			var visible_mesh := false
			if cp_idx >= 0:
				var nd = buildings.list[cp_idx]["node"]
				visible_mesh = nd != null and nd.get_child_count() > 0
			print("mcv: deployed post has a visible mesh=%s (must be true)" % visible_mesh)
			# found two more, then prove the cap holds
			for extra in range(3):
				var s_m: Vector2i = world.faction_start(player_fac)
				var spot := s_m + Vector2i(10 + extra * 9, 10)
				var m2 := army.spawn(EFBuildings.mcv_for(player_fac), player_fac, spot)
				await _wait_seconds(0.3)
				army.clear_selection()
				m2.selected = true
				army.selection.append(m2)
				_deploy_selected()
				await _wait_seconds(0.3)
				print("mcv:   extra crawler %d -> posts now %d"
					% [extra + 1, buildings.count_posts(player_fac)])
			print("mcv: cap holds at %d (must be %d)"
				% [buildings.count_posts(player_fac), EFBuildings.MAX_POSTS])
			# raze every post: still NOT beaten while a crawler survives, which
			# is the whole point of the new rule
			for b in buildings.list:
				if b["type"] == "command_post" and b["faction"] == player_fac:
					b["hp"] = 0.0
			print("mcv: posts razed, crawler alive -> beaten=%s (must be FALSE)"
				% _is_beaten(player_fac))
			for u2 in army.units.duplicate():
				if u2.faction == player_fac and u2.role == "mcv" and u2.hp > 0:
					army.kill_unit(u2, false)
			print("mcv: last crawler gone too   -> beaten=%s (must be TRUE)"
				% _is_beaten(player_fac))
		var s_c: Vector2i = world.faction_start(player_fac)
		rig.center_on((s_c.x + 0.5) * T, (s_c.y + 0.5) * T)
		rig.target_dist = 34.0
		rig.dist = 34.0

	if args.has("--choke"):
		# The nastiest reported case: a heavy column squeezed through a narrow
		# gap. Open ground was never the hard part — measured baseline for this
		# was 1 of 20 units through after a full minute.
		var wallrow := 0
		var s_c2: Vector2i = world.faction_start(player_fac)
		# build a wall across the map with one 2-tile gap, 20 tiles ahead
		var gy: int = s_c2.y + 14
		var gap_x: int = s_c2.x + 6
		var wall_cells: Array[Vector2i] = []
		for x in range(maxi(1, s_c2.x - 14), mini(world.w - 1, s_c2.x + 26)):
			if x >= gap_x and x <= gap_x + 1:
				continue
			if world.is_buildable(x, gy):
				wall_cells.append(Vector2i(x, gy))
		world.set_runtime_tile(wall_cells, "#")
		army.block_cells(wall_cells)
		wallrow = wall_cells.size()
		var mob: Array[EFUnit] = []
		for i in range(20):
			var nu := army.spawn("bastion", player_fac,
				s_c2 + Vector2i(2 + (i % 5) * 2, 4 + (i / 5) * 2))
			if nu != null:
				mob.append(nu)
		await _wait_seconds(1.0)
		army.clear_selection()
		for u in mob:
			u.selected = true
			army.selection.append(u)
		army.selection_dirty = true
		var beyond := Vector3((gap_x + 0.5) * T, 0, (gy + 8.5) * T)
		army.order_move(beyond)
		print("choke: %d wall tiles, 2-tile gap at x=%d, %d bastions ordered through"
			% [wallrow, gap_x, mob.size()])
		for s in range(6):
			await _wait_seconds(10.0)
			var through := 0
			var moving := 0
			for u in mob:
				if u.hp <= 0:
					continue
				if int(u.global_position.z / T) > gy:
					through += 1
				if u.vel.length() > 0.35:
					moving += 1
			print("choke:   t=%2ds  through %2d/%d  still moving %2d"
				% [(s + 1) * 10, through, mob.size(), moving])
		var final_through := 0
		for u in mob:
			if u.hp > 0 and int(u.global_position.z / T) > gy:
				final_through += 1
		print("choke: VERDICT %s — %d/%d made it through the gap"
			% ["PASS" if final_through >= mob.size() * 0.8 else "FAIL",
				final_through, mob.size()])
		rig.center_on(beyond.x, (gy + 1.0) * T)
		rig.target_dist = 46.0
		rig.dist = 46.0

	if args.has("--jam"):
		# The reported bug: a mass move of vehicles piles up on itself, worst at
		# choke points. Spawn a big armoured column, march it across the map,
		# and measure how many actually ARRIVE rather than grinding in place.
		var jam_units: Array[EFUnit] = []
		var s_j: Vector2i = world.faction_start(player_fac)
		var heavy := ["bastion", "bastion", "outrider", "sperrwagen", "hammerfall"]
		for i in range(24):
			var k: String = heavy[i % heavy.size()]
			var at_j := s_j + Vector2i(3 + (i % 6) * 2, 3 + (i / 6) * 2)
			var nu := army.spawn(k, player_fac, at_j)
			if nu != null:
				jam_units.append(nu)
		for i in range(12):
			var nu2 := army.spawn("iron_guard", player_fac,
				s_j + Vector2i(3 + (i % 6), 12 + (i / 6)))
			if nu2 != null:
				jam_units.append(nu2)
		await _wait_seconds(1.0)
		army.clear_selection()
		for u in jam_units:
			if u.hp > 0:
				u.selected = true
				army.selection.append(u)
		army.selection_dirty = true
		# a destination a realistic march away, not clear across the map, so the
		# test measures jamming rather than travel time
		var s_world := Vector3((s_j.x + 0.5) * T, 0, (s_j.y + 0.5) * T)
		var toward := (Vector3(world.w * T * 0.5, 0, world.h * T * 0.5) - s_world).normalized()
		var dest := s_world + toward * 58.0
		army.order_move(dest)
		var start_pos := {}
		for u in army.selection:
			start_pos[u] = u.global_position
		# sample progress: a jam shows up as distance-to-own-slot flatlining
		# while the unit still believes it has somewhere to be
		var prev_d := {}
		var stalled_peak := 0
		for sample in range(9):
			await _wait_seconds(5.0)
			var stalled := 0
			for u in jam_units:
				if u.hp <= 0 or u.path.is_empty():
					continue
				var goal: Vector3 = u.slot_point if u.slot_point != Vector3.INF else dest
				var d: float = u.global_position.distance_to(goal)
				var was: float = prev_d.get(u, 1e9)
				if was - d < 0.6:          # under 0.6 m of progress in 5 s
					stalled += 1
				prev_d[u] = d
			stalled_peak = maxi(stalled_peak, stalled)
			print("jam:   t=%2ds  stalled-this-window %d" % [(sample + 1) * 5, stalled])
		var arrived := 0
		var still_pathing := 0
		var never_moved := 0
		var worst_overlap := 0
		for u in jam_units:
			if u.hp <= 0:
				continue
			if u.path.is_empty():
				arrived += 1
			else:
				still_pathing += 1
			if u.global_position.distance_to(start_pos.get(u, u.global_position)) < 2.0:
				never_moved += 1
		print("jam: peak stalled-in-a-window %d of %d" % [stalled_peak, jam_units.size()])
		# how badly are they interpenetrating? count pairs closer than they should be
		for i in range(jam_units.size()):
			var a: EFUnit = jam_units[i]
			if a.hp <= 0:
				continue
			var over := 0
			for j in range(jam_units.size()):
				if i == j:
					continue
				var b2: EFUnit = jam_units[j]
				if b2.hp <= 0:
					continue
				if a.global_position.distance_to(b2.global_position) < a.radius + b2.radius:
					over += 1
			worst_overlap = maxi(worst_overlap, over)
		print("jam: %d units | arrived %d | still moving %d | never left start %d | worst overlap %d"
			% [jam_units.size(), arrived, still_pathing, never_moved, worst_overlap])
		print("jam: VERDICT %s" % ["PASS" if arrived >= jam_units.size() * 0.85
			and never_moved == 0 else "FAIL — the column is jamming"])
		rig.center_on(dest.x, dest.z)
		rig.target_dist = 44.0
		rig.dist = 44.0

	if args.has("--march"):
		army.select_all_player()
		var center := Vector3(world.w * T * 0.5, 0, world.h * T * 0.5)
		army.order_move(center)
		var pathed := 0
		for u in army.selection:
			if not u.path.is_empty():
				pathed += 1
		print("march: %d/%d units found a path" % [pathed, army.selection.size()])
		await _wait_seconds(6.0)
		var centroid := Vector3.ZERO
		for u in army.selection:
			centroid += u.global_position
		centroid /= army.selection.size()
		rig.center_on(centroid.x, centroid.z)

	if args.has("--garrison"):
		var inf: Array[EFUnit] = []
		for u in army.units:
			if u.faction == 1 and u.is_infantry() and inf.size() < 3:
				inf.append(u)
		var s1 := rig.position
		var best := -1
		var best_d := 1e18
		for gi in range(structures.garrisons.size()):
			var d: float = structures.garrisons[gi]["center"].distance_squared_to(s1)
			if d < best_d:
				best_d = d
				best = gi
		army.clear_selection()
		for u in inf:
			u.selected = true
			army.selection.append(u)
		var g: Dictionary = structures.garrisons[best]
		army.order_smart(g["center"], structures)
		await _wait_seconds(32.0)
		print("garrison: %d/%d occupants in %s" %
			[g["occupants"].size(), g["capacity"], g["kind_name"]])
		rig.center_on(g["center"].x, g["center"].z)
		rig.target_dist = 20.0
		rig.dist = 20.0

	if args.has("--econ"):
		await _wait_seconds(48.0)
		var dock := buildings.refinery_dock(1)
		rig.center_on(dock.x, dock.z)
		rig.target_dist = 24.0
		rig.dist = 24.0

	if args.has("--war"):
		var s1w: Vector2i = world.starts[1]
		var foes: Array[EFUnit] = []
		for i in range(5):
			foes.append(army.spawn("conscript", 2, s1w + Vector2i(16 + i % 3, 6 + i / 3)))
		foes.append(army.spawn("warpig", 2, s1w + Vector2i(20, 8)))
		var p_before := _count_faction(1)
		var e_before := _count_faction(2)
		army.select_combat_player()
		army.order_smart(foes[5].global_position, structures)
		await _wait_seconds(14.0)
		var mid := Vector3((s1w.x + 17) * T, 0, (s1w.y + 7) * T)
		rig.center_on(mid.x, mid.z)
		rig.target_dist = 26.0
		rig.dist = 26.0
		await _wait_seconds(16.0)
		print("war: karvath %d -> %d | ashfall %d -> %d" %
			[p_before, _count_faction(1), e_before, _count_faction(2)])

	if args.has("--build"):
		buildings.click_item("BASE", "boiler")
		await _wait_until(func():
			return buildings.queues["BASE"] != null and buildings.queues["BASE"]["ready"], 12.0)
		print("boiler ready, placed: %s" % _auto_place("boiler"))
		var p := buildings.power_report(1)
		print("power after boiler: gen %d, use %d" % [p.x, p.y])
		buildings.click_item("BASE", "barracks")
		await _wait_until(func():
			return buildings.queues["BASE"] != null and buildings.queues["BASE"]["ready"], 12.0)
		print("barracks ready, placed: %s" % _auto_place("barracks"))
		var before := army.units.size()
		buildings.click_item("INF", "iron_guard")
		await _wait_until(func(): return army.units.size() > before, 10.0)
		print("trained: units %d -> %d | credits %d" %
			[before, army.units.size(), economy.credits.get(1, 0)])
		# queue stacking: three clicks while busy must yield three more guards
		var before_q := army.units.size()
		buildings.click_item("INF", "iron_guard")
		buildings.click_item("INF", "iron_guard")
		buildings.click_item("INF", "iron_guard")
		print("backlog after clicks: %d" % buildings.backlog["INF"].size())
		var q_ok := await _wait_until(func(): return army.units.size() >= before_q + 3, 25.0)
		print("queue x3 trained: %s (units %d -> %d)" % [q_ok, before_q, army.units.size()])
		var s1b: Vector2i = world.starts[1]
		rig.center_on((s1b.x + 0.5) * T, (s1b.y + 0.5) * T)
		rig.target_dist = 34.0
		rig.dist = 34.0

	if args.has("--air"):
		# the full flight line: airfield tech -> a Kondor -> then a flak duel
		economy.credits[player_fac] = economy.credits.get(player_fac, 0) + 2500
		var air_kind: String = buildings.tab_items("AIR")[0]
		var aa_kind: String = {1: "sperrwagen", 2: "stovepipe", 3: "zephyr"}[ai_fac]
		for bid in ["boiler", "vehicle_works", "airfield"]:
			buildings.click_item("BASE", bid)
			var fin := await _wait_until(func():
				return buildings.queues["BASE"] != null and buildings.queues["BASE"]["ready"], 22.0)
			print("%s built: %s, placed: %s" % [bid, fin, _auto_place(bid)])
		buildings.click_item("AIR", air_kind)
		var got := await _wait_until(func():
			for u2 in army.units:
				if u2.flying and u2.faction == player_fac:
					return true
			return false, 25.0)
		print("%s trained: %s" % [air_kind, got])
		var plane: EFUnit = null
		for u in army.units:
			if u.flying and u.faction == player_fac:
				plane = u
		if plane == null:
			print("AIR TEST FAILED: no player flyer on the field")
		else:
			await _wait_seconds(4.0)
			print("%s airborne: alt %.1f m, hp %d/%d" %
				[air_kind, plane.global_position.y, int(plane.hp), int(plane.max_hp)])
			# the duel: gunship vs flak truck in the empty midfield, far from
			# both base garrisons; auto-acquire fights both sides of it
			var s1a: Vector2i = world.faction_start(player_fac)
			var dxa := 1 if s1a.x < world.w / 2 else -1
			var duel := s1a + Vector2i(dxa * 30, dxa * 20)
			var aa := army.spawn(aa_kind, ai_fac, duel)
			army.clear_selection()
			plane.selected = true
			army.selection.append(plane)
			army.order_smart(Vector3((duel.x + 2.5) * T, 0, (duel.y + 0.5) * T), structures)
			await _wait_seconds(18.0)
			var p_alive := is_instance_valid(plane) and plane.hp > 0
			var aa_alive := is_instance_valid(aa) and aa.hp > 0
			var p_hp := int(plane.hp) if p_alive else 0
			var aa_hp := int(aa.hp) if aa_alive else 0
			print("air duel: %s %s (hp %d) vs %s %s (hp %d)" %
				[air_kind, "alive" if p_alive else "DOWN", p_hp,
				aa_kind, "alive" if aa_alive else "DESTROYED", aa_hp])
			if p_alive and p_hp == int(plane.max_hp):
				print("AIR TEST WARNING: flak never touched the plane")
			if aa_alive and is_instance_valid(aa) and aa_hp == int(aa.max_hp):
				print("AIR TEST WARNING: the plane never fired on the truck")
			var focus := Vector3((duel.x + 1) * T, 0, (duel.y + 0.5) * T)
			rig.center_on(focus.x, focus.z)
			rig.target_dist = 24.0
			rig.dist = 24.0

	if args.has("--pelican"):
		# the air bridge: load three marines, fly them across the map, drop them,
		# then shoot the loaded transport down and count the survivors
		var s1p: Vector2i = world.faction_start(player_fac)
		var dxp := 1 if s1p.x < world.w / 2 else -1
		print("pelican: faction %d AIR tab %s | cost %d from %s | armor %s slots %d" %
			[player_fac, str(buildings.tab_items("AIR")),
			int(EFBuildings.TRAIN["pelican"]["cost"]),
			String(EFBuildings.TRAIN["pelican"]["from"]),
			String(EFArmy.KINDS["pelican"]["armor"]), EFUnit.CARGO_SLOTS])
		var lift: EFUnit = army.spawn("pelican", player_fac, s1p + Vector2i(dxp * 16, dxp * 8))
		await _wait_seconds(3.0)
		print("pelican: spawned for faction %d | alt %.2f m, speed %.2f m/s, hp %d/%d" %
			[lift.faction, lift.global_position.y, lift.vel.length(),
			int(lift.hp), int(lift.max_hp)])

		var troops: Array[EFUnit] = []
		for u in army.units:
			if u.faction == player_fac and u.is_infantry() and troops.size() < 3:
				troops.append(u)
		army.clear_selection()
		for u in troops:
			u.selected = true
			army.selection.append(u)
		var before_all := army.units.size()
		var before_mine := _count_faction(player_fac)
		var lift_pt := Vector3(lift.global_position.x, 0, lift.global_position.z)
		army.order_smart(lift_pt, structures, lift_pt)
		var ordered := 0
		for u in troops:
			if u.load_target == lift:
				ordered += 1
		print("pelican: %d/3 marines took a boarding order (hovering=%s)" %
			[ordered, lift.hovering])
		var boarded := await _wait_until(func(): return lift.cargo_units.size() == 3, 30.0)
		var still_in := 0
		for u in troops:
			if army.units.has(u):
				still_in += 1
		print("pelican: BOARD ok=%s cargo=%d/3 | army.units %d -> %d (delta %d, want -3) | faction %d %d -> %d | %d/3 still loose | hovering=%s alt %.2f m speed %.2f m/s" %
			[boarded, lift.cargo_units.size(), before_all, army.units.size(),
			army.units.size() - before_all, player_fac, before_mine,
			_count_faction(player_fac), still_in, lift.hovering,
			lift.global_position.y, lift.vel.length()])
		army.clear_selection()
		lift.selected = true
		army.selection.append(lift)
		print("pelican: selection panel while loaded: %s" %
			str(army.get_selection_summary()))

		var drop_tile: Vector2i = army._nearest_open(
			Vector2i(world.w / 2 + 8, world.h / 2 - 8))
		var drop := Vector3((drop_tile.x + 0.5) * T, 0, (drop_tile.y + 0.5) * T)
		army.order_smart(drop, structures)
		print("pelican: ordered from (%.0f, %.0f) to (%.0f, %.0f), unload_at=(%.0f, %.0f)" %
			[lift.global_position.x, lift.global_position.z, drop.x, drop.z,
			lift.unload_at.x, lift.unload_at.z])
		var dropped := await _wait_until(func(): return lift.cargo_units.is_empty(), 60.0)
		await _wait_seconds(1.5)
		var back := 0
		var near := 0
		for u in troops:
			if army.units.has(u) and not u.stowed and u.visible:
				back += 1
			if Vector2(u.global_position.x - drop.x,
					u.global_position.z - drop.z).length() < 6.0:
				near += 1
		print("pelican: DROP ok=%s cargo=%d | %d/3 back in army.units | %d/3 within 6 m of (%.0f, %.0f) | faction %d count %d | transport alt %.2f m" %
			[dropped, lift.cargo_units.size(), back, near, drop.x, drop.z,
			player_fac, _count_faction(player_fac), lift.global_position.y])

		army.clear_selection()
		for u in troops:
			if is_instance_valid(u) and u.hp > 0:
				u.selected = true
				army.selection.append(u)
		var lift_pt2 := Vector3(lift.global_position.x, 0, lift.global_position.z)
		army.order_smart(lift_pt2, structures, lift_pt2)
		var reboarded := await _wait_until(func(): return lift.cargo_units.size() == 3, 40.0)
		var riders: Array[EFUnit] = lift.cargo_units.duplicate()
		print("pelican: reboarded=%s cargo=%d before the shootdown" %
			[reboarded, riders.size()])
		if args.has("--savecargo"):
			var aboard := lift.cargo_units.size()
			save_game()
			print("CARGOSAVE fingerprint: credits=%d units=%d aboard=%d live_bodies=%d buildings=%d explored=%.1f%%" %
				[economy.credits.get(player_fac, 0), army.units.size(), aboard,
				army.units.size() + aboard, buildings.list.size(),
				world.explored_percent()])
		army.damage_unit(lift, "FLAK", 9999.0)
		await _wait_seconds(0.5)
		var alive := 0
		var orphan_units := 0
		var orphan_sel := 0
		for u in riders:
			if not is_instance_valid(u):
				continue
			if u.hp > 0:
				alive += 1
			if army.units.has(u):
				orphan_units += 1
			if army.selection.has(u):
				orphan_sel += 1
		print("pelican: DEATH transport hp %d | riders %d | alive passengers %d (want 0) | orphans in army.units %d, in selection %d (want 0, 0) | cargo now %d" %
			[int(lift.hp), riders.size(), alive, orphan_units, orphan_sel,
			lift.cargo_units.size()])
		rig.center_on(drop.x, drop.z)
		rig.target_dist = 26.0
		rig.dist = 26.0

	if args.has("--audio"):
		# every new sound must be LOADED (audio.NAMES) and every deployment
		# lookup must resolve, or units roll out silently
		var missing: Array = []
		for n in EFAudio.NAMES:
			if not audio.streams.has(n):
				missing.append(n)
		print("audio: %d/%d sounds loaded, missing %s"
			% [audio.streams.size(), EFAudio.NAMES.size(),
				missing if not missing.is_empty() else "none"])
		var unresolved: Array = []
		for kd in EFArmy.KINDS.keys():
			var snd := "dep_vehicle"
			if kd in EFBuildings.DEPLOY_SUPER:
				snd = "dep_super"
			else:
				snd = String(EFBuildings.DEPLOY_SND.get(
					String(EFArmy.KINDS[kd].get("kind", "")), ""))
			if snd == "" or not audio.streams.has(snd):
				unresolved.append(kd)
		print("audio: deployment sound resolves for %d/%d kinds, unresolved %s"
			% [EFArmy.KINDS.size() - unresolved.size(), EFArmy.KINDS.size(),
				unresolved if not unresolved.is_empty() else "none"])
		var ann_missing: Array = []
		for f2 in range(1, 5):
			for ev in EFAudio.ANN_EVENTS:
				if not ResourceLoader.exists("res://sounds/ann/f%d_%s.wav" % [f2, ev]):
					ann_missing.append("f%d_%s" % [f2, ev])
		var ann_total: int = 4 * EFAudio.ANN_EVENTS.size()
		print("audio: announcer %d/%d lines present, missing %s"
			% [ann_total - ann_missing.size(), ann_total,
				ann_missing if not ann_missing.is_empty() else "none"])
		audio.announce("construction", true)
		await _wait_seconds(0.6)
		print("audio: announcer speaking=%s (faction %d voice)"
			% [audio._ann_player != null and audio._ann_player.playing, player_fac])
		# the anthem: play it, confirm the stems duck without their transports
		# being touched (that is what keeps the 96 BPM grid locked)
		var bed_pos0: float = music.bed.get_playback_position()
		var ok_start: bool = music.play_anthem(player_fac)
		await _wait_seconds(3.0)
		print("anthem: '%s' started=%s playing=%s | stem duck %.1f dB (want %.1f)"
			% [music.anthem_title(player_fac), ok_start, music.anthem.playing,
				music._anthem_duck, EFMusic.ANTHEM_DUCK_DB])
		print("anthem: bed still running=%s and advanced %.2fs (never stopped/seeked)"
			% [music.bed.playing, music.bed.get_playback_position() - bed_pos0])
		var re: bool = music.play_anthem(player_fac)
		print("anthem: second press cancels instead of restarting -> on=%s (re-armed %s)"
			% [music.anthem_on, re])
		await _wait_seconds(2.5)
		print("anthem: after cancel, duck recovering %.1f dB, cooldown %.0fs"
			% [music._anthem_duck, music.anthem_cd])
		print("anthem: blocked while cooling -> %s (want false)"
			% [music.play_anthem(player_fac)])

	if args.has("--lineup"):
		# parade ground: every unit of one faction in ranked rows, for visual QA.
		# --pfac N picks the faction (the game is already started with it).
		var fac_l := player_fac
		var kinds_l: Array = []
		for tab in ["INF", "VEH", "AIR"]:
			for id in EFBuildings.FACTION_TABS[fac_l][tab]:
				kinds_l.append(id)
		var s_l: Vector2i = world.faction_start(fac_l)
		var per_row := 5
		for i in range(kinds_l.size()):
			var at := s_l + Vector2i(4 + (i % per_row) * 3, 4 + (i / per_row) * 3)
			army.spawn(String(kinds_l[i]), fac_l, at)
		await _wait_seconds(1.2)
		var extra := 0
		for u in army.units:
			if u.faction == fac_l:
				# recursive: the dress pieces live under _body, so a direct
				# child count sees none of them
				extra = maxi(extra,
					u.find_children("*", "MeshInstance3D", true, false).size())
		print("lineup: faction %d, %d kinds spawned (deepest unit mesh count %d)"
			% [fac_l, kinds_l.size(), extra])
		var cx := (s_l.x + 4 + 6) * EFWorld.T
		var cz := (s_l.y + 4 + 3) * EFWorld.T
		rig.center_on(cx, cz)
		rig.target_dist = 30.0
		rig.dist = 30.0

	if args.has("--stance"):
		var inf: Array[EFUnit] = []
		var tanks: Array[EFUnit] = []
		var air: Array[EFUnit] = []
		for u in army.units:
			if u.faction != player_fac or u.hp <= 0:
				continue
			if u.is_infantry() and inf.size() < 4:
				inf.append(u)
			elif u.role == "tank" and tanks.size() < 2:
				tanks.append(u)
		# ARTILLERY: rooted, longer reach, harder hitting
		if not tanks.is_empty():
			var t: EFUnit = tanks[0]
			var base_rng: float = t.weapon["range"]
			army.clear_selection()
			t.selected = true
			army.selection.append(t)
			army.set_stance_selected("ARTILLERY")
			var p0 := t.global_position
			army.order_move(p0 + Vector3(14, 0, 0))
			await _wait_seconds(0.6)
			print("stance test: artillery deploy_t=%.2f pinned=%s (must not move while setting up)"
				% [t.deploy_t, t.is_pinned()])
			await _wait_seconds(2.2)
			var moved := Vector2(t.global_position.x - p0.x, t.global_position.z - p0.z).length()
			print("stance test: ARTILLERY range %.0f -> %.0f, dmg x%.2f, drifted %.2f m (must be ~0)"
				% [base_rng, base_rng * t.range_mult(), t.dmg_mult(), moved])
			army.order_formation(p0 + Vector3(10, 0, 0), Vector2(1, 0), "LINE")
			print("stance test: move order while deployed -> stance is now %s" % t.stance_name())
		# LIGHT FEET and DIG IN
		if inf.size() >= 2:
			var a: EFUnit = inf[0]
			var b: EFUnit = inf[1]
			var base_speed: float = a.speed
			army.clear_selection()
			a.selected = true
			army.selection.append(a)
			army.set_stance_selected("LIGHT FEET")
			print("stance test: LIGHT FEET speed %.2f -> %.2f, incoming x%.2f"
				% [base_speed, a.move_speed(), a.incoming_mult()])
			army.clear_selection()
			b.selected = true
			army.selection.append(b)
			# the test subject must outlive its own measurements: at 72 max hp it
			# died during the damage phase below, and every later reading was
			# taken on a corpse that kill_unit had already pulled from army.units
			b.max_hp = 5000.0
			b.hp = 5000.0
			army.set_stance_selected("DIG IN")
			await _wait_seconds(0.4)
			var live := 0
			for f in army.forts:
				var fd: Dictionary = f
				if not fd.is_empty():
					live += 1
			print("stance test: DIG IN forts=%d range x%.2f incoming x%.2f fort_hp=%.0f"
				% [live, b.range_mult(), b.incoming_mult(),
					float(army.forts[b.fort_ref]["hp"]) if b.fort_ref >= 0 else -1.0])
			var hp0: float = b.hp
			for i in range(6):
				army.damage_unit(b, "BULLET", 40.0)
			print("stance test: dug-in soldier took %.1f hp of 240 raw; fort now %.0f"
				% [hp0 - b.hp, float(army.forts[b.fort_ref]["hp"]) if b.fort_ref >= 0 else 0.0])
			# keep the soldier alive so this measures the FORT collapsing rather
			# than damage_unit early-returning on a corpse
			for i in range(40):
				if b.fort_ref < 0:
					break
				b.hp = b.max_hp
				army.damage_unit(b, "BULLET", 60.0)
			print("stance test: after sustained fire fort_ref=%d stance=%s (must be -1 / STEADY)"
				% [b.fort_ref, b.stance_name()])
			# a dug-in soldier is pinned, so an ordinary move order MUST free him
			# or he is stuck in that hole for the rest of the game
			b.hp = b.max_hp
			army.clear_selection()
			b.selected = true
			army.selection.append(b)
			army.set_stance_selected("DIG IN")
			await _wait_seconds(0.3)
			var dug: bool = b.fort_ref >= 0
			var bp := b.global_position
			army.order_smart(bp + Vector3(9, 0, 0), structures, Vector3.INF)
			await _wait_seconds(2.5)
			var walked := Vector2(b.global_position.x - bp.x,
				b.global_position.z - bp.z).length()
			print("stance test: dug in=%s then ordered to move -> walked %.2f m, fort_ref=%d"
				% [dug, walked, b.fort_ref])
			# and LIGHT FEET must survive a formation order (ARTILLERY shares index 1)
			army.set_stance_selected("LIGHT FEET")
			army.order_formation(b.global_position + Vector3(4, 0, 0), Vector2(1, 0), "LINE")
			print("stance test: light-feet infantry after a formation order -> %s (must stay LIGHT FEET)"
				% b.stance_name())
		# PATROL widens the circle
		for u2 in army.units:
			if u2.faction == player_fac and u2.flying and air.size() < 1:
				air.append(u2)
		if air.is_empty():
			var s2: Vector2i = world.faction_start(player_fac)
			var pl: EFUnit = army.spawn("kondor", player_fac, s2 + Vector2i(3, 3))
			air.append(pl)
		var pln: EFUnit = air[0]
		print("stance test: LOITER orbit %.1f m" % pln.orbit_radius())
		army.clear_selection()
		pln.selected = true
		army.selection.append(pln)
		army.set_stance_selected("PATROL")
		print("stance test: PATROL orbit %.1f m, patrolling=%s" %
			[pln.orbit_radius(), pln.is_patrolling()])
		# FORMATIONS
		army.clear_selection()
		army.select_all_player()
		var flist := army.formation_units()
		var ranks := []
		for u3 in flist:
			ranks.append(army._rank_of(u3))
		var sorted_ok := true
		for i in range(1, ranks.size()):
			if ranks[i] < ranks[i - 1]:
				sorted_ok = false
		var ctr := army.selection_centroid()
		var dest := ctr + Vector3(18, 0, 0)
		for shape in EFArmy.SHAPES:
			var slots := army.formation_slots(flist, dest, Vector2(1, 0), String(shape))
			var mind := 1e9
			for i in range(slots.size()):
				for j in range(i + 1, slots.size()):
					mind = minf(mind, Vector2(slots[i].x - slots[j].x,
						slots[i].z - slots[j].z).length())
			print("stance test: %-7s %d slots, closest pair %.2f m (must exceed push-apart)"
				% [shape, slots.size(), mind])
		print("stance test: role ordering front-to-back %s (sorted=%s)" % [ranks, sorted_ok])

		# double-click: same kind, on screen only
		army.clear_selection()
		var pick: EFUnit = null
		for u4 in army.units:
			if u4.faction == player_fac and u4.is_infantry() and u4.hp > 0:
				pick = u4
				break
		if pick != null:
			var total := 0
			for u5 in army.units:
				if u5.faction == player_fac and u5.kind == pick.kind and u5.hp > 0:
					total += 1
			rig.center_on(pick.global_position.x, pick.global_position.z)
			await _wait_seconds(0.4)
			var sp2 := rig.cam.unproject_position(pick.global_position)
			var got: bool = army.select_same_kind_on_screen(sp2, false, rig.cam, VIEW_W,
				get_viewport().get_visible_rect().size.y)
			var onscreen := 0
			for u6 in army.units:
				if u6.faction == player_fac and u6.kind == pick.kind and u6.hp > 0 \
						and army._on_screen(u6, rig.cam, VIEW_W,
							get_viewport().get_visible_rect().size.y):
					onscreen += 1
			print("stance test: double-click '%s' hit=%s selected %d of %d on screen (%d alive total)"
				% [pick.kind, got, army.selection.size(), onscreen, total])
			var wrong := 0
			for u7 in army.selection:
				if u7.kind != pick.kind:
					wrong += 1
			print("stance test: selection purity — %d of %d are the wrong kind (must be 0)"
				% [wrong, army.selection.size()])

	if args.has("--stanceshot"):
		army.clear_selection()
		for u8 in army.units:
			if u8.faction == player_fac and u8.is_infantry() and u8.hp > 0:
				u8.selected = true
				army.selection.append(u8)
		army.selection_dirty = true
		# deliberately do NOT call ui.set_stance here: this must prove the LIVE
		# path through main._process, which is where the row failed to appear
		await _wait_seconds(0.5)
		print("stanceshot: row visible=%s buttons [%s][%s] emit [%s][%s]"
			% [ui.stance_a_btn.visible, ui.stance_a_btn.text, ui.stance_b_btn.text,
				ui._pick_a, ui._pick_b])
		print("stanceshot: label/emit match = %s (button A must not say one thing and do another)"
			% [ui.stance_a_btn.text == ui._pick_a and ui.stance_b_btn.text == ui._pick_b])
		if army.selection.size() > 1:
			var half := army.selection.size() / 2
			for i in range(half):
				var uu: EFUnit = army.selection[i]
				uu.set_stance(2)
				army._make_fort(uu)
		await _wait_seconds(0.4)
		var st4 := army.stance_summary()
		print("stanceshot: after digging half in -> mixed=%s" % st4[2])
		# and the emitted value must actually reach a unit
		ui.stance_picked.emit(ui._pick_a)
		await _wait_seconds(0.3)
		var got_lf := 0
		for uu2 in army.selection:
			if uu2.stance_name() == ui._pick_a:
				got_lf += 1
		print("stanceshot: pressing button A ('%s') set %d of %d units to it"
			% [ui._pick_a, got_lf, army.selection.size()])
		var c3 := army.selection_centroid()
		rig.center_on(c3.x, c3.z)
		rig.dist = 22.0
		rig.target_dist = 22.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(1.2)

	if args.has("--formshot"):
		army.select_all_player()
		var fl := army.formation_units()
		var c2 := army.selection_centroid()
		var dst := c2 + Vector3(16, 0, 6)
		_shape_i = 0
		var sl := army.formation_slots(fl, dst, Vector2(1, 0.4), EFArmy.SHAPES[_shape_i])
		while _ghost_pool.size() < sl.size():
			_ghost_pool.append(_make_slot_ghost())
		for i in range(sl.size()):
			var g: MeshInstance3D = _ghost_pool[i]
			g.scale = Vector3(fl[i].radius * 2.2, 1.0, fl[i].radius * 2.2)
			g.position = Vector3(sl[i].x, 0.09, sl[i].z)
			g.visible = true
		ui.set_formation_hint(EFArmy.SHAPES[_shape_i], sl.size())
		var st2 := army.stance_summary()
		ui.set_stance(st2[0], String(st2[1]), bool(st2[2]))
		rig.center_on((c2.x + dst.x) * 0.5, (c2.z + dst.z) * 0.5)
		rig.dist = 34.0
		rig.target_dist = 34.0
		rig.cam.position = Vector3(0, 0, rig.dist)
		await _wait_seconds(1.0)

	if args.has("--airlift"):
		# the AI's air bridge: it must build a Pelican off its own economy, fill
		# it from its own muster, fly it to our doorstep and put the troops down.
		# Time is scaled because the whole build-up runs at real-time pace; the
		# wait helpers count scaled delta, so every timeout below stays in
		# sim-seconds.
		Engine.time_scale = 3.0
		economy.credits[ai_fac] = economy.credits.get(ai_fac, 0) + 9000
		var hqa: Vector2i = world.faction_start(player_fac)
		var hq_pt := Vector3((hqa.x + 0.5) * T, 0, (hqa.y + 0.5) * T)
		print("airlift: AI faction %d transport '%s' | muster %d | our HQ (%.0f, %.0f)" %
			[ai_fac, ai._lift_kind, ai.muster_size, hq_pt.x, hq_pt.z])
		var field := await _wait_until(
			func(): return buildings._owns(ai_fac, "airfield"), 180.0)
		print("airlift: airfield ok=%s | commander wants a transport: %s" %
			[field, ai._wants_lift()])
		# it opens with enough troops to attack outright, so it never reaches the
		# training rotation on its own here: hold the wave and hand the air slot
		# its turn. The pick itself is still the AI's — this only lets it choose.
		ai.state = "MUSTER"
		ai._train_i = 3
		ai.attack_cd = 999.0
		var built := await _wait_until(func(): return ai._find_lift() != null, 90.0)
		print("airlift: BUILT ok=%s | ai state=%s | ai units %d | credits %d" %
			[built, ai.state, _count_faction(ai_fac), economy.credits.get(ai_fac, 0)])
		ai.attack_cd = 0.0          # release it: ATTACK fills the hold
		var loading := await _wait_until(func(): return ai._lift_state != "idle", 120.0)
		print("airlift: LOAD ok=%s state=%s | %d troops assigned (cap %d)" %
			[loading, ai._lift_state, ai._lift_troops.size(), EFUnit.CARGO_SLOTS])
		var inbound := await _wait_until(func(): return ai._lift_state == "inbound", 90.0)
		var lift: EFUnit = ai._find_lift()
		var aboard := lift.cargo_units.size() if lift != null else 0
		var dp := lift.unload_at if lift != null else Vector3.INF
		print("airlift: INBOUND ok=%s aboard=%d | drop (%.0f, %.0f) is %.1f m from our HQ" %
			[inbound, aboard, dp.x, dp.z,
			Vector2(dp.x - hq_pt.x, dp.z - hq_pt.z).length()])
		var dropped := await _wait_until(func(): return ai._lift_state == "returning", 120.0)
		await _wait_seconds(2.0)
		var landed := 0
		for u in army.units:
			if u.faction == ai_fac and u.hp > 0 and u.is_infantry() \
					and Vector2(u.global_position.x - hq_pt.x,
						u.global_position.z - hq_pt.z).length() < 22.0:
				landed += 1
		var lift2: EFUnit = ai._find_lift()
		print("airlift: DROP ok=%s | %d AI infantry within 22 m of our HQ (want >= 2) | transport %s, cargo %d | state %s" %
			[dropped, landed, "on the field" if lift2 != null else "gone",
			lift2.cargo_units.size() if lift2 != null else 0, ai._lift_state])
		Engine.time_scale = 1.0
		rig.center_on(hq_pt.x, hq_pt.z)
		rig.target_dist = 30.0
		rig.dist = 30.0

	if args.has("--killhq"):
		print("killhq test: before — objectives %s hq_enemy=%d hp=%.0f" %
			[campaign.obj_done, _hq_enemy, buildings.list[_hq_enemy]["hp"]])
		buildings.take_damage(_hq_enemy, "BLAST", 99999.0)
		var over := await _wait_until(func(): return game_over, 10.0)
		print("killhq test: game_over=%s victory=%s objectives %s (must be [true])"
			% [over, victory, campaign.obj_done])

	if args.has("--mission2"):
		# the compressed Grey Tide: waves at 4s/12s, survive 25s
		var won := await _wait_until(func(): return game_over, 60.0)
		print("mission2 test: game_over=%s victory=%s (enemy stragglers %d)" %
			[won, victory, _count_faction(ai_fac)])
		print("mission2 test: objectives %s (both must be true)" % [campaign.obj_done])
		var s1m: Vector2i = world.faction_start(player_fac)
		rig.center_on((s1m.x + 0.5) * T, (s1m.y + 0.5) * T)
		rig.target_dist = 34.0
		rig.dist = 34.0

	if args.has("--saveprep"):
		# build a little history, then record the war
		buildings.click_item("BASE", "boiler")
		await _wait_until(func():
			return buildings.queues["BASE"] != null and buildings.queues["BASE"]["ready"], 12.0)
		_auto_place("boiler")
		buildings.click_item("BASE", "barracks")
		await _wait_until(func():
			return buildings.queues["BASE"] != null and buildings.queues["BASE"]["ready"], 12.0)
		_auto_place("barracks")
		buildings.click_item("INF", "iron_guard")
		await _wait_seconds(4.0)
		save_game()
		print("SAVEPREP fingerprint: credits=%d units=%d buildings=%d explored=%.1f%%" %
			[economy.credits.get(player_fac, 0), army.units.size(),
			buildings.list.size(), world.explored_percent()])

	if args.has("--loadcheck"):
		await _wait_seconds(1.0)
		print("LOADCHECK fingerprint: credits=%d units=%d buildings=%d explored=%.1f%%" %
			[economy.credits.get(player_fac, 0), army.units.size(),
			buildings.list.size(), world.explored_percent()])
		var s1l: Vector2i = world.faction_start(player_fac)
		rig.center_on((s1l.x + 0.5) * T, (s1l.y + 0.5) * T)
		rig.target_dist = 34.0
		rig.dist = 34.0

	if args.has("--autobldg"):
		# idle units open fire on enemy STRUCTURES in range, unprompted
		var s1b2: Vector2i = world.faction_start(player_fac)
		var dxb := 1 if s1b2.x < world.w / 2 else -1
		var spot2 := s1b2 + Vector2i(dxb * 20, dxb * 14)
		buildings._create("gun_turret", ai_fac, spot2)
		var bidx2 := buildings.list.size() - 1
		var hp0b: float = buildings.list[bidx2]["hp"]
		army.spawn("bastion", player_fac, spot2 + Vector2i(-dxb * 5, 0))
		await _wait_seconds(14.0)
		var hp1b: float = buildings.list[bidx2]["hp"]
		print("auto-structure test: enemy turret hp %d -> %d (%s)" %
			[int(hp0b), int(hp1b),
			"units engage structures unprompted" if hp1b < hp0b else "FAILED"])
		rig.center_on((spot2.x - dxb * 2) * T, (spot2.y + 0.5) * T)
		rig.target_dist = 22.0
		rig.dist = 22.0

	if args.has("--aa"):
		# AA turrets: kill the plane first, then strafe the ground stragglers
		var s1z: Vector2i = world.faction_start(player_fac)
		var dxz := 1 if s1z.x < world.w / 2 else -1
		var zspot := s1z + Vector2i(dxz * 9, dxz * 9)
		buildings._create("aa_turret", player_fac, zspot)
		var bird := army.spawn("duster", ai_fac, zspot + Vector2i(dxz * 3, 0))
		var crawler := army.spawn("conscript", ai_fac, zspot + Vector2i(dxz * 4, 1))
		await _wait_seconds(12.0)
		var bird_down := not (is_instance_valid(bird) and bird.hp > 0)
		var crawler_hurt := not (is_instance_valid(crawler) and crawler.hp > 0) \
			or crawler.hp < crawler.max_hp
		print("aa test: plane shot down=%s | ground strafed=%s" %
			[bird_down, crawler_hurt])
		rig.center_on((zspot.x + 0.5) * T, (zspot.y + 0.5) * T)
		rig.target_dist = 22.0
		rig.dist = 22.0

	if args.has("--heal"):
		# quiet troops mend near the Command Post
		var s1h: Vector2i = world.faction_start(player_fac)
		var patient := army.spawn("iron_guard", player_fac, s1h + Vector2i(3, 3))
		await _wait_seconds(0.5)
		army.damage_unit(patient, "BULLET", 50.0)
		var hurt_hp := patient.hp
		await _wait_seconds(20.0)
		print("heal test: %d hp -> %d hp near base (max %d)" %
			[int(hurt_hp), int(patient.hp), int(patient.max_hp)])

	if args.has("--repair"):
		# money mends buildings
		var ridx := -1
		for k in range(buildings.list.size()):
			var rb: Dictionary = buildings.list[k]
			if rb["faction"] == player_fac and rb["type"] == "refinery":
				ridx = k
		buildings.take_damage(ridx, "BLAST", 300.0)
		var hp0: float = buildings.list[ridx]["hp"]
		var c0: int = economy.credits.get(player_fac, 0)
		buildings.toggle_repair(ridx)
		await _wait_seconds(16.0)
		print("repair test: hp %d -> %d, credits %d -> %d" %
			[int(hp0), int(buildings.list[ridx]["hp"]), c0,
			economy.credits.get(player_fac, 0)])

	if args.has("--regrow"):
		# the ember returns: strip a field bare and watch it come back
		economy.regrow_delay = 3.0
		economy.regrow_rate = 300.0
		var s1r: Vector2i = world.faction_start(player_fac)
		var field := army.nearest_field_tile(s1r + Vector2i(6, 2), 12)
		while economy.mine(field, 500.0) > 0.0:
			pass
		print("regrow test: field stripped, tile is now '%s'" %
			world.tile_char(field.x, field.y))
		await _wait_seconds(8.0)
		print("regrow test: tile is '%s' again with %d credits and rising" %
			[world.tile_char(field.x, field.y), int(economy.reserves.get(field, 0.0))])

	if args.has("--shroud"):
		# the veil of war: begin nearly blind, scout to reveal
		print("shroud: %.1f%% explored at game start" % world.explored_percent())
		army.select_all_player()
		var ctr := Vector3(world.w * T * 0.5, 0, world.h * T * 0.5)
		army.order_move(ctr)
		await _wait_seconds(20.0)
		print("shroud: %.1f%% explored after scouting toward the center" %
			world.explored_percent())
		var mid := Vector3(world.w * T * 0.30, 0, world.h * T * 0.30)
		rig.center_on(mid.x, mid.z)
		rig.target_dist = 46.0
		rig.dist = 46.0

	if args.has("--turret"):
		# turrets must actually shoot now (they were blind behind their own base)
		var s1t: Vector2i = world.faction_start(player_fac)
		var dxt := 1 if s1t.x < world.w / 2 else -1
		var tspot := s1t + Vector2i(dxt * 8, dxt * 8)
		buildings._create("gun_turret", player_fac, tspot)
		var f1 := army.spawn("conscript", ai_fac, tspot + Vector2i(dxt * 4, 0))
		var f2 := army.spawn("conscript", ai_fac, tspot + Vector2i(dxt * 4, 1))
		await _wait_seconds(10.0)
		var dead := int(not (is_instance_valid(f1) and f1.hp > 0)) \
			+ int(not (is_instance_valid(f2) and f2.hp > 0))
		print("turret test: %d/2 intruders destroyed by the gun turret" % dead)
		# sticky orders: a bastion marches THROUGH a fight and still arrives
		var bs := army.spawn("bastion", player_fac, tspot + Vector2i(-dxt * 2, -dxt * 2))
		var blocker := army.spawn("conscript", ai_fac, tspot + Vector2i(dxt * 6, dxt * 6))
		var goal := Vector3((tspot.x + dxt * 14) * T, 0, (tspot.y + dxt * 14) * T)
		army.clear_selection()
		bs.selected = true
		army.selection.append(bs)
		army.order_move(goal)
		await _wait_seconds(24.0)
		var arrived := Vector2(bs.global_position.x - goal.x,
			bs.global_position.z - goal.z).length() < 6.0
		print("sticky march: blocker dead=%s, arrived at goal=%s" %
			[not (is_instance_valid(blocker) and blocker.hp > 0), arrived])
		rig.center_on((tspot.x + dxt * 6) * T, (tspot.y + dxt * 6) * T)
		rig.target_dist = 26.0
		rig.dist = 26.0

	if args.has("--super"):
		# the Worldhammer: tech up, charge (skipped), aim at the enemy pickets
		economy.credits[player_fac] = economy.credits.get(player_fac, 0) + 12000
		for bid in ["boiler", "vehicle_works", "doomworks"]:
			buildings.click_item("BASE", bid)
			var fin := await _wait_until(func():
				return buildings.queues["BASE"] != null and buildings.queues["BASE"]["ready"], 32.0)
			print("%s built: %s, placed: %s" % [bid, fin, _auto_place(bid)])
		buildings.sw_charge[player_fac] = buildings.SW_TIME
		print("superweapon ready: %s (%s)" %
			[buildings.sw_ready(player_fac), buildings.sw_name(player_fac)])
		var foe_s: Vector2i = world.faction_start(ai_fac)
		var dxs := 1 if foe_s.x < world.w / 2 else -1
		var tgt := Vector3((foe_s.x + dxs * 6) * T, 0, (foe_s.y + dxs * 6) * T)
		var before_e := _count_faction(ai_fac)
		buildings.fire_superweapon(player_fac, tgt)
		await _wait_seconds(6.0)
		print("superweapon strike: enemy units %d -> %d" % [before_e, _count_faction(ai_fac)])
		rig.center_on(tgt.x, tgt.z)
		rig.target_dist = 30.0
		rig.dist = 30.0
		var before_j := army.units.size()
		buildings.click_item("VEH", "juggernaut")
		var got_j := await _wait_until(func():
			for u2 in army.units:
				if u2.kind == "juggernaut" and u2.faction == player_fac:
					return true
			return false, 45.0)
		print("juggernaut trained: %s (units %d -> %d)" % [got_j, before_j, army.units.size()])

	if args.has("--salvage"):
		# Ashfall economics: a Vulture Crew strips a fresh wreck for 40%%
		var s1v: Vector2i = world.faction_start(player_fac)
		var dxv := 1 if s1v.x < world.w / 2 else -1
		var spot := s1v + Vector2i(dxv * 24, dxv * 16)
		var prey := army.spawn("bastion", ai_fac, spot)
		army.spawn("vulture", player_fac, spot + Vector2i(-dxv * 4, 0))
		await _wait_seconds(1.0)
		var c_before: int = economy.credits.get(player_fac, 0)
		army.damage_unit(prey, "BLAST", 99999.0)
		print("bastion destroyed, wreck worth %d on the ground (wrecks: %d)" %
			[int(EFBuildings.TRAIN["bastion"]["cost"] * 0.4), army.wrecks.size()])
		await _wait_seconds(16.0)
		var c_after: int = economy.credits.get(player_fac, 0)
		print("salvage: credits %d -> %d (wrecks left: %d)" %
			[c_before, c_after, army.wrecks.size()])
		rig.center_on((spot.x + 0.5) * T, (spot.y + 0.5) * T)
		rig.target_dist = 20.0
		rig.dist = 20.0

	if args.has("--arc"):
		# Luminar lightning chains through crowds; shields drink and refill
		var s1c: Vector2i = world.faction_start(player_fac)
		var squad: Array[EFUnit] = []
		for i in range(3):
			squad.append(army.spawn("arc_templar", player_fac, s1c + Vector2i(14 + i, 10)))
		var mob: Array[EFUnit] = []
		for i in range(6):
			mob.append(army.spawn("conscript", ai_fac, s1c + Vector2i(17 + i % 3, 9 + i / 3)))
		await _wait_seconds(14.0)
		var mob_alive := 0
		for m in mob:
			if is_instance_valid(m) and m.hp > 0:
				mob_alive += 1
		var sq_alive := 0
		var sq_shield := 0.0
		for q2 in squad:
			if is_instance_valid(q2) and q2.hp > 0:
				sq_alive += 1
				sq_shield += q2.shield
		print("arc test: mob 6 -> %d alive | templars %d/3, shields %.0f/120" %
			[mob_alive, sq_alive, sq_shield])
		var hq_home := Vector3((s1c.x + 0.5) * T, 0, (s1c.y + 0.5) * T)
		var gi2 := 0
		var dented := 0.0
		for q2 in squad:
			if is_instance_valid(q2) and q2.hp > 0:
				army.damage_unit(q2, "BULLET", 30.0)   # dent the shield on purpose
				dented += q2.shield
				q2.clear_targets()
				army.path_single(q2, hq_home, gi2)
				gi2 += 1
		await _wait_seconds(14.0)
		var sq_shield2 := 0.0
		for q2 in squad:
			if is_instance_valid(q2) and q2.hp > 0:
				sq_shield2 += q2.shield
		print("arc test: shields dented to %.0f, after regrouping at base %.0f (regen %s)" %
			[dented, sq_shield2, "works" if sq_shield2 > dented else "NOT OBSERVED"])
		rig.center_on((s1c.x + 16) * T, (s1c.y + 10) * T)
		rig.target_dist = 22.0
		rig.dist = 22.0

	if args.has("--sell"):
		# demolish refunds half; cancelling a build refunds what was paid
		var c0: int = economy.credits.get(player_fac, 0)
		buildings.click_item("BASE", "boiler")
		await _wait_until(func():
			return buildings.queues["BASE"] != null and buildings.queues["BASE"]["ready"], 12.0)
		_auto_place("boiler")
		var bidx := buildings.list.size() - 1
		var c1: int = economy.credits.get(player_fac, 0)
		buildings.sell(bidx)
		var c2: int = economy.credits.get(player_fac, 0)
		print("sell: built boiler (%d -> %d cr), demolished (+%d cr, hp now %d)" %
			[c0, c1, c2 - c1, int(buildings.list[bidx]["hp"])])
		buildings.click_item("BASE", "boiler")
		await _wait_seconds(2.0)
		var paid: float = buildings.queues["BASE"]["paid"] if buildings.queues["BASE"] != null else 0.0
		var c3: int = economy.credits.get(player_fac, 0)
		buildings.cancel_item("BASE", "boiler")
		var c4: int = economy.credits.get(player_fac, 0)
		print("cancel: paid %.0f into a boiler, refund %d, queue now %s" %
			[paid, c4 - c3, str(buildings.queues["BASE"])])

	if args.has("--dock"):
		# collectors bind to the refinery that bought them, and re-home
		# to the nearest survivor when theirs is destroyed
		var s1d: Vector2i = world.starts[1]
		buildings._create("refinery", 1, s1d + Vector2i(-9, 2))
		var new_idx := buildings.list.size() - 1
		buildings.train_spawn("mule", 1)
		await _wait_seconds(2.0)
		var homes := []
		for u in army.units:
			if u.is_harvester() and u.faction == 1:
				homes.append(u.home_refinery)
		print("dock: homes %s (new refinery is idx %d)" % [str(homes), new_idx])
		var orig := -1
		for k in range(buildings.list.size()):
			var bk: Dictionary = buildings.list[k]
			if bk["type"] == "refinery" and bk["faction"] == 1 and k != new_idx:
				orig = k
		buildings.take_damage(orig, "BLAST", 99999.0)
		# rebinding is lazy — it happens on the next trip home, so give
		# every collector time for a full mine-and-return cycle
		var rebound := await _wait_until(func():
			for u2 in army.units:
				if u2.is_harvester() and u2.faction == 1 and u2.home_refinery == orig:
					return false
			return true, 60.0)
		var homes2 := []
		for u in army.units:
			if u.is_harvester() and u.faction == 1:
				homes2.append(u.home_refinery)
		print("dock: refinery %d destroyed -> rebound=%s, homes now %s" %
			[orig, rebound, str(homes2)])
		rig.center_on((s1d.x - 6) * T, (s1d.y + 3) * T)
		rig.target_dist = 30.0
		rig.dist = 30.0

	if args.has("--ai"):
		# watch the enemy commander run its opening for 100 seconds
		await _wait_seconds(100.0)
		var owned := 0
		for b in buildings.list:
			if b["faction"] == ai_fac and b["hp"] > 0:
				owned += 1
		print("ai: state=%s buildings=%d military=%d credits=%d" %
			[ai.state, owned, ai._military().size(), economy.credits.get(ai_fac, 0)])
		var s2: Vector2i = world.faction_start(ai_fac)
		rig.center_on((s2.x + 0.5) * T, (s2.y + 0.5) * T)
		rig.target_dist = 40.0
		rig.dist = 40.0

	if args.has("--gameover"):
		# six enemy tanks storm the player HQ — prove the defeat pipeline
		var s1g: Vector2i = world.starts[1]
		for i in range(6):
			var w := army.spawn("warpig", 2, s1g + Vector2i(-4 + i % 3, 5 + i / 3))
			w.tgt_building = _hq_player
		await _wait_until(func(): return game_over, 120.0)
		print("gameover test: game_over=%s victory=%s" % [game_over, victory])
		rig.center_on((s1g.x + 0.5) * T, (s1g.y + 0.5) * T)

	print("econ: P1 %d cr | P2 %d cr | %d cr still in the ground" %
		[economy.credits.get(1, 0), economy.credits.get(2, 0), economy.total_reserves()])

	# A selftest that photographs a MOVING subject has to hold it in frame right
	# up to the shutter: this routine waits 120 frames before it shoots, and a
	# 15 m/s Sparrowhawk covers ~30 m in that window — every early --airfacing
	# shot came back as empty ground with the aircraft long gone.
	for i in range(30):
		await get_tree().process_frame
		_track_shot_subject()
	var t0 := Time.get_ticks_msec()
	for i in range(90):
		await get_tree().process_frame
		_track_shot_subject()
	var avg_fps := 90000.0 / maxf(1.0, float(Time.get_ticks_msec() - t0))
	print("selftest avg fps over 90 frames: %.1f" % avg_fps)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	if OS.get_cmdline_user_args().has("--newtank"):
		print("newtank: AT SCREENSHOT cam.position=%s rig.dist=%.1f rig.position=(%.1f, %.1f)"
			% [rig.cam.position, rig.dist, rig.position.x, rig.position.z])
	print("selftest screenshot -> ", path)
	get_tree().quit()


var _shot_subject: EFUnit = null      # kept in frame until the shutter


func _track_shot_subject() -> void:
	if _shot_subject == null or not is_instance_valid(_shot_subject):
		return
	var vps := get_viewport().get_visible_rect().size
	var want := Vector2((vps.x - 220.0) * 0.5, vps.y * 0.5)
	var err := rig.cam.unproject_position(_shot_subject.global_position) - want
	# same per-axis gains as the acquisition loop — one shared gain oscillates
	# in X — with the feed-forward stepped down to a single frame's worth
	var fv: Vector3 = _shot_subject.vel
	rig.center_on(rig.position.x + err.x * 0.017 + fv.x * 0.0167,
		rig.position.z + err.y * 0.023 + fv.z * 0.0167)

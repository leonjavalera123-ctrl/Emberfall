# EMBERFALL: 1940 — settings.gd
#
# What the player asked for, and the one place that knows how to ask the engine
# for it. Everything here is static: there is exactly one set of settings, and
# it has to outlive every battle, menu and scene reload — QUIT TO MENU reloads
# the whole scene, so anything stored on a node would be thrown away by the act
# of leaving the settings screen.
#
# Volume is stored 0..1 LINEAR, because that is what a slider is. It reaches the
# mixer in decibels, because that is what an audio bus is. The conversion lives
# in exactly one function so "the slider is at zero" and "that bus is silent"
# cannot drift apart.

class_name EFSettings
extends RefCounted

const PATH := "user://settings.cfg"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

# [w, h] pairs rather than Vector2i for the same reason campaign.gd's build
# offsets are: a Vector2i is not legal inside a GDScript constant Array.
const RESOLUTIONS := [[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]]

static var master := 1.0
static var music := 1.0
static var sfx := 1.0
static var fullscreen := false
static var res_index := 0
# The studio logo. Read once at boot (main.gd), so there is no apply_* for it —
# turning it off takes effect on the next launch, which is the only launch it
# could possibly affect.
static var play_intro := true


# --- the mixer --------------------------------------------------------------------

static func bus_db(linear: float) -> float:
	# A fader at zero must be SILENCE, not "very quiet". linear_to_db(0.0) is
	# already -inf everywhere we ship, but saying so out loud means the guarantee
	# rests on this line rather than on the platform's log(0).
	if linear <= 0.0:
		return -INF
	return linear_to_db(clampf(linear, 0.0, 1.0))


static func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return          # layout missing: leave the mixer alone rather than guess
	AudioServer.set_bus_volume_db(i, bus_db(linear))


static func volume_of(bus: String) -> float:
	match bus:
		BUS_MUSIC:
			return music
		BUS_SFX:
			return sfx
		_:
			return master


static func apply_audio() -> void:
	_set_bus(BUS_MASTER, master)
	_set_bus(BUS_MUSIC, music)
	_set_bus(BUS_SFX, sfx)


static func set_volume(bus: String, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	match bus:
		BUS_MUSIC:
			music = linear
		BUS_SFX:
			sfx = linear
		_:
			master = linear
	_set_bus(bus, linear)      # AC-7: it is already audible by the next line
	save()
	# Saving inside the drag rather than on release is deliberate. A ConfigFile
	# of five keys is ~150 bytes; a dropped frame is worth more than the write,
	# and "changed but not yet persisted" is a state with no good handling.


# --- the window -------------------------------------------------------------------

static func resolution() -> Vector2i:
	var r: Array = RESOLUTIONS[clampi(res_index, 0, RESOLUTIONS.size() - 1)]
	return Vector2i(int(r[0]), int(r[1]))


static func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return                     # no window to size; the selftests run here
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	# Leaving fullscreen has to happen BEFORE the resize, not after: sizing a
	# window that is still fullscreen does nothing, and the mode change would
	# then restore whatever size it had before it went fullscreen.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var want := resolution()
	if DisplayServer.window_get_size() != want:
		DisplayServer.window_set_size(want)
		_center_window()


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_video()
	save()


static func set_res_index(i: int) -> void:
	res_index = clampi(i, 0, RESOLUTIONS.size() - 1)
	apply_video()
	save()


static func set_play_intro(on: bool) -> void:
	play_intro = on
	save()                         # no apply_video(): nothing on screen changes
	                               # until the next launch reads the flag


static func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var pos := DisplayServer.screen_get_position(screen) \
		+ (DisplayServer.screen_get_size(screen)
			- DisplayServer.window_get_size()) / 2
	DisplayServer.window_set_position(pos)


# F11 still toggles fullscreen from anywhere; this keeps the stored setting and
# the actual window from disagreeing after the player uses it.
static func sync_from_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var now := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if now != fullscreen:
		fullscreen = now
		save()


# --- persistence ------------------------------------------------------------------

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return                     # first launch: the defaults above stand
	master = clampf(float(cfg.get_value("audio", "master", master)), 0.0, 1.0)
	music = clampf(float(cfg.get_value("audio", "music", music)), 0.0, 1.0)
	sfx = clampf(float(cfg.get_value("audio", "sfx", sfx)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	res_index = clampi(int(cfg.get_value("video", "res_index", res_index)),
		0, RESOLUTIONS.size() - 1)
	play_intro = bool(cfg.get_value("video", "play_intro", play_intro))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "res_index", res_index)
	cfg.set_value("video", "play_intro", play_intro)
	cfg.save(PATH)


static func reset_to_defaults() -> void:
	master = 1.0
	music = 1.0
	sfx = 1.0
	fullscreen = false
	res_index = 0
	play_intro = true

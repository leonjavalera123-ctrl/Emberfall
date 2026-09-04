# EMBERFALL: 1940 — intro.gd
# The VANTA CORE studio logo: a 15 s sting that plays once at the top of a
# genuine launch, then hands the screen to the title hall.
#
# It owns its own CanvasLayer rather than riding on EFMenu because EFMenu's
# _clear() queue_frees every child the menu holds on each room change — and the
# first thing EFMenu does is show a room, so the video would vanish on frame
# one. layer = 100 because EFMenu and EFUI are both CanvasLayers sitting on the
# engine default of 1, and nothing in this project has ever had to reason about
# same-layer ordering.

class_name EFIntro
extends CanvasLayer

signal done

const VIDEO_PATH := "res://video/vanta_core_intro.ogv"

# The clip is 15.08 s. This cap is wall-clock and deliberately loose: it is not
# pacing, it is the guarantee that a missing codec, a stalled decode, or a
# `finished` that never arrives can neither trap a player in front of a black
# rectangle nor hang a headless run forever.
const HARD_CAP_MS := 20000

# Launching from a desktop shortcut with Enter, or alt-tabbing as the window
# appears, delivers that event to a window that is only just up — and an
# any-key skip would eat the whole logo before the first frame is read. Observed
# for real during testing: a launch under load skipped itself at 7 s from an
# event nobody sent. Long enough to swallow the launch keystroke, short enough
# that a player deliberately reaching for a key never notices it.
const INPUT_GRACE_MS := 400

# The logo holds for AT LEAST this long: the wordmark lands late in the
# animation, and an early skip meant the studio name was never seen at all.
# Input before this mark is ignored (F11 still passes); after it, a keypress
# starts the fade rather than cutting to the menu.
const SHOW_MIN_MS := 14000

# The end is a FADE, not a cut: through to black, and main fades the title
# hall in on the other side.
const FADE_S := 0.9

var player: VideoStreamPlayer
var is_done := false        # poll this BEFORE awaiting `done`: the failed-load
                            # path finishes deferred and can beat the caller
var load_ms := 0            # cost of load()ing 30 MB, reported by --intro
var fading := false         # the outro fade has begun (asserted by --intro)
var _t0 := 0
var _fade_rect: ColorRect = null
var _fade_t := 0.0
var _clip_len := 15.08


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()

	# Black goes down BEFORE the load, so a slow first frame shows black rather
	# than whatever the 3D viewport happened to be holding.
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.position = Vector2.ZERO
	black.size = Vector2(1280, 720)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)

	var t_load := Time.get_ticks_msec()
	var stream := load(VIDEO_PATH) as VideoStream
	load_ms = Time.get_ticks_msec() - t_load
	if stream == null:
		# Deferred, never immediate: our caller add_child()s this node and only
		# then awaits `done`, so emitting inside _ready() would fire into nobody
		# and the boot would stall on an await that can never resolve.
		push_warning("intro: no video at %s — skipping the logo" % VIDEO_PATH)
		call_deferred("_finish", "no stream")
		return

	player = VideoStreamPlayer.new()
	player.stream = stream
	# ANCHORS, not a one-shot size: the engine resizes this control to the
	# video's native 1920x1080 the moment the first frame decodes, so a size
	# assigned here silently loses and the 1280x720 canvas shows the top-left
	# CROP of the frame — logo off-centre, wordmark below the screen. A
	# full-rect anchor is re-asserted by the layout system every frame, so it
	# cannot be overridden by the decoder.
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.expand = true               # source is 1920x1080 — same 16:9, so this
	                                   # is a clean downscale, not a stretch
	player.loop = false                # `finished` NEVER fires while looping
	player.bus = EFSettings.BUS_MUSIC  # a logo sting is score, not SFX. The fader
	                                   # is already on the bus (main._ready calls
	                                   # EFSettings.apply_audio) — do NOT also set
	                                   # volume_db from bus_db(), or a player at
	                                   # 50% music hears it at 25%
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.finished.connect(func(): _begin_fade("finished"))
	add_child(player)
	player.play()
	var sl := player.get_stream_length()
	if sl > 1.0:
		_clip_len = sl

	# the outro veil, above the video, transparent until the fade begins
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)


func _begin_fade(why: String) -> void:
	if fading or is_done:
		return
	fading = true
	print("intro: fading (%s, %.1f s in)" % [why, (Time.get_ticks_msec() - _t0) / 1000.0])


var _probed := false


func _process(dt: float) -> void:
	if not _probed and player != null and Time.get_ticks_msec() - _t0 > 1200:
		_probed = true
		# the assertion that caught the off-centre bug: after the first frame
		# has decoded, the control must STILL span the design canvas
		var ok := player.get_rect() == Rect2(0, 0, 1280, 720)
		print("introprobe: rect=%s spans canvas=%s (must be true)"
			% [player.get_rect(), ok])
	# begin the outro fade so it COMPLETES as the clip ends, rather than
	# starting after it — the last frame dissolves instead of popping
	if not fading and not is_done and player != null \
			and player.stream_position >= _clip_len - FADE_S:
		_begin_fade("clip end")
	if fading and not is_done:
		_fade_t += dt
		_fade_rect.color.a = clampf(_fade_t / FADE_S, 0.0, 1.0)
		if _fade_t >= FADE_S:
			_finish("faded out")
	# Wall-clock, not delta: a dev flag scaling Engine.time_scale must not be
	# able to trip this early, and a decode stall must not make it fire late.
	if not is_done and Time.get_ticks_msec() - _t0 >= HARD_CAP_MS:
		_finish("timeout")


func _input(ev: InputEvent) -> void:
	# _input rather than _unhandled_input: main._unhandled_input bails early on a
	# null world, and a null world IS the entire pre-menu window — a skip bolted
	# onto the end of that handler would be swallowed in silence.
	if is_done or Time.get_ticks_msec() - _t0 < INPUT_GRACE_MS:
		return
	# The logo HOLDS until SHOW_MIN_MS: the wordmark lands late in the clip and
	# a skip before it means the studio name is never seen. After the hold a
	# keypress begins the fade — the exit is always the smooth one.
	var can_skip := Time.get_ticks_msec() - _t0 >= SHOW_MIN_MS
	if ev is InputEventKey and ev.pressed and not ev.echo:
		# F11 has to survive the logo: a fullscreen intro on a bad resolution is
		# otherwise inescapable. main._unhandled_input handles F11 ABOVE its own
		# world guard, but only ever sees what we leave unhandled. Bare modifiers
		# are ignored so reaching for Alt+F4 does not read as "skip".
		if ev.keycode in [KEY_F11, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return
		if can_skip:
			_begin_fade("skipped")
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed:
		if can_skip:
			_begin_fade("skipped")
		get_viewport().set_input_as_handled()


func _finish(why: String) -> void:
	if is_done:
		return
	is_done = true
	set_process(false)
	set_process_input(false)
	if player != null and player.is_playing():
		player.stop()
	print("intro: %s (%.1f s in)" % [why, (Time.get_ticks_msec() - _t0) / 1000.0])
	done.emit()

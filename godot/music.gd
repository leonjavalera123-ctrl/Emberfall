# EMBERFALL: 1940 — music.gd
#
# A layered score rather than a playlist. Two in-game stems were rendered on the
# same 96 BPM / 28-bar grid and are exactly the same length, so they are started
# in the same frame and simply left running:
#
#   mus_bed   FORGE AND ASH — the machine working. Always audible.
#   mus_war   IRON WEATHER  — drums and brass. Rides in on the shooting.
#
# Because they never stop or restart independently, they stay locked forever and
# the "combat swell" is nothing but a volume ride on the war layer. No crossfade,
# no tempo clash, no re-sync logic.
#
# This node is deliberately NOT in main's PROCESS_MODE_PAUSABLE list — the score
# keeps playing over the pause overlay (ducked), the way a war does not stop
# being a war because you looked away.

class_name EFMusic
extends Node

const MENU_DB := -12.0
const BED_DB := -14.0
const WAR_DB := -10.0
const SILENT_DB := -46.0          # war layer's resting level: audible as texture
const DUCK_DB := -7.0             # applied on top while the game is paused

# how fast the war layer answers the guns, and how fast it forgets them
const RISE := 2.4
const FALL := 0.14

# --- the faction anthem -----------------------------------------------------
# Public-domain classical, synthesized for this game. The stems are NEVER
# stopped or seeked while it plays — they are only ducked — so the 96 BPM grid
# stays locked and there is nothing to re-sync when the anthem ends.
const ANTHEM_DB := -5.0           # the anthem is the loudest thing in the mix
const ANTHEM_DUCK_DB := -22.0     # what the stems drop by underneath it
const ANTHEM_FADE := 10.0         # dB/s the duck slews in and out
const ANTHEM_COOLDOWN := 30.0     # seconds after it ends before it can re-arm
const ANTHEM_NAMES := {
	1: "Verdi · Anvil Chorus",
	2: "Grieg · In the Hall of the Mountain King",
	3: "Wagner · Ride of the Valkyries",
	4: "R. Strauss · Also sprach Zarathustra",
}

var menu_player: AudioStreamPlayer
var bed: AudioStreamPlayer
var war: AudioStreamPlayer
var intensity := 0.0              # 0..1, driven by bump()
var available := false
var anthem: AudioStreamPlayer     # built on first use
var anthem_fac := 0
var anthem_on := false
var anthem_cd := 0.0
var _anthem_duck := 0.0           # current dB offset applied to both stems


func _ready() -> void:
	menu_player = _make("mus_menu", MENU_DB)
	bed = _make("mus_bed", BED_DB)
	war = _make("mus_war", SILENT_DB)
	# ALL three, not any: the only consumer treats this as a promise that both
	# battle stems exist and dereferences them
	available = menu_player != null and bed != null and war != null


func _make(track: String, vol_db: float) -> AudioStreamPlayer:
	var path := "res://sounds/%s.wav" % track
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	# The importer's default loop mode is "Detect From WAV", and a python-written
	# WAV carries no smpl chunk — so without this the score plays once and stops.
	# The .import files also request Forward looping; this is the safety net.
	if stream is AudioStreamWAV:
		var w: AudioStreamWAV = stream
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		var per_frame := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
		if w.stereo:
			per_frame *= 2
		if w.format != AudioStreamWAV.FORMAT_QOA and w.data.size() > 0:
			w.loop_end = int(w.data.size() / per_frame) - 1
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p


# --- transport -------------------------------------------------------------------

func play_menu() -> void:
	_stop(bed)
	_stop(war)
	if menu_player != null and not menu_player.playing:
		menu_player.volume_db = MENU_DB
		menu_player.play()


func start_battle() -> void:
	_stop(menu_player)
	intensity = 0.0
	# both stems begin in the same frame: that is the whole sync strategy
	if bed != null:
		bed.volume_db = BED_DB
		bed.play()
	if war != null:
		war.volume_db = SILENT_DB
		war.play()


func stop_all() -> void:
	_stop(menu_player)
	_stop(bed)
	_stop(war)


func _stop(p: AudioStreamPlayer) -> void:
	if p != null and p.playing:
		p.stop()


# --- the combat swell ------------------------------------------------------------

func bump(amount: float) -> void:
	# every wound anywhere on the field nudges this; it decays on its own
	intensity = minf(intensity + amount, 1.0)


# --- the anthem ------------------------------------------------------------------

func _load_anthem(fac: int) -> bool:
	var path := "res://sounds/anth_f%d.wav" % fac
	if not ResourceLoader.exists(path):
		return false
	var stream: AudioStream = load(path)
	if stream == null:
		return false
	# Deliberately NOT built through _make(): that forces LOOP_FORWARD, and a
	# looping anthem would never end and never fire `finished`.
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	if anthem == null:
		anthem = AudioStreamPlayer.new()
		add_child(anthem)
		anthem.finished.connect(_on_anthem_finished)
	anthem.stream = stream
	anthem_fac = fac
	return true


func anthem_ready() -> bool:
	return anthem_cd <= 0.0 and not anthem_on


func anthem_title(fac: int) -> String:
	return String(ANTHEM_NAMES.get(fac, ""))


func play_anthem(fac: int) -> bool:
	if anthem_on:
		cancel_anthem()          # a second press is the stop button
		return false
	if anthem_cd > 0.0:
		return false
	if not _load_anthem(fac):
		return false
	anthem.volume_db = ANTHEM_DB
	anthem.play()
	anthem_on = true
	return true


func cancel_anthem() -> void:
	if anthem != null and anthem.playing:
		anthem_on = false        # set first: stop() does not emit `finished`
		anthem.stop()
	anthem_on = false
	anthem_cd = ANTHEM_COOLDOWN


func _on_anthem_finished() -> void:
	anthem_on = false
	anthem_cd = ANTHEM_COOLDOWN


func _process(dt: float) -> void:
	# the anthem duck rides toward its target whether or not the stems are up,
	# so triggering it from the menu behaves the same as from a battle
	anthem_cd = maxf(0.0, anthem_cd - dt)
	var duck_want: float = ANTHEM_DUCK_DB if anthem_on else 0.0
	_anthem_duck = move_toward(_anthem_duck, duck_want, ANTHEM_FADE * dt)
	if menu_player != null and menu_player.playing:
		menu_player.volume_db = MENU_DB + _anthem_duck
	if war == null or not war.playing:
		return
	var paused: bool = get_tree().paused
	# Fall away slowly so a lull doesn't yank the drums out mid-bar — but not
	# while paused. Everything that raises intensity (army, buildings) is
	# PAUSABLE, so decaying here would drain a battle nobody can refill and the
	# score would come back from a long pause silent instead of merely ducked.
	if not paused:
		intensity = maxf(intensity - FALL * dt, 0.0)
	var want := SILENT_DB + (WAR_DB - SILENT_DB) * _curve(intensity)
	if paused:
		want += DUCK_DB
	want += _anthem_duck
	var rate: float = RISE if want > war.volume_db else 1.6
	war.volume_db = move_toward(war.volume_db, want, (WAR_DB - SILENT_DB) * rate * dt)
	if bed != null and bed.playing:
		var bed_want: float = BED_DB + (DUCK_DB if paused else 0.0) + _anthem_duck
		bed.volume_db = move_toward(bed.volume_db, bed_want, 12.0 * dt)


func _curve(x: float) -> float:
	# ease-in so scattered potshots stay quiet and a real battle opens up fast
	return x * x * (3.0 - 2.0 * x)

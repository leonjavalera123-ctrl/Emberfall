# EMBERFALL: 1940 — audio.gd
# A small pool of positional players fed by the procedurally generated WAVs
# in sounds/ (pure-python wave synth — same trick as Faction Wars).

class_name EFAudio
extends Node3D

const NAMES := ["shot_bullet", "shot_cannon", "shot_flak", "shot_rocket",
	"arc_zap", "expl_small", "expl_big", "sw_klaxon", "sw_boom", "place",
	"ready_chime", "salvage", "victory", "defeat",
	# deployment sounds — what rolled out, told by ear
	"dep_infantry", "dep_vehicle", "dep_air", "dep_harvester", "dep_arc",
	"dep_super"]

var streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _pi := 0
var _ui := 0


func _ready() -> void:
	for n in NAMES:
		var path := "res://sounds/%s.wav" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	for i in range(12):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 140.0
		p.unit_size = 14.0
		add_child(p)
		_pool.append(p)
	for i in range(3):
		var u := AudioStreamPlayer.new()
		add_child(u)
		_ui_pool.append(u)


func play(sound: String, pos: Vector3, vol_db := 0.0) -> void:
	if not streams.has(sound):
		return
	var p := _pool[_pi]
	_pi = (_pi + 1) % _pool.size()
	p.stream = streams[sound]
	p.global_position = pos
	p.volume_db = vol_db
	p.play()


func play_ui(sound: String, vol_db := 0.0) -> void:
	if not streams.has(sound):
		return
	var u := _ui_pool[_ui]
	_ui = (_ui + 1) % _ui_pool.size()
	u.stream = streams[sound]
	u.volume_db = vol_db
	u.play()

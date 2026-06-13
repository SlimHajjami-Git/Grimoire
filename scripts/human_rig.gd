extends Node3D
# Personnage joueur : humain réaliste (squelette Mixamo retargeté sur le
# profil humanoïde Godot) + bibliothèque d'animations de combat MeleeLib
# (Godot4-OpenAnimationLibraries). Même API que character_rig.gd (KayKit) :
# build / set_tint / set_locomotion / set_casting / play_melee / play_dash /
# play_cast_shoot / play_hit / debug_anim — le reste du jeu ne change pas.

const HUMAN_SCENE := preload("res://assets/human/Human.glb")
const MELEE_LIB := preload("res://assets/human/MeleeLib.res")
const LIB_PREFIX := "m/"

const RUN_THRESHOLD := 4.0
const WALK_THRESHOLD := 0.4

const MELEE_ANIMS := ["m/Slash1", "m/Slash2", "m/Slash3"]
const MELEE_DURATIONS := [0.45, 0.45, 0.65]

const LOOP_ANIMS := [
	"m/LightIdle", "m/LightWalking", "m/LightRunning",
	"m/LightStrafeL", "m/LightStrafeR", "m/Retreat", "m/HeavyCharge",
]

var _ap: AnimationPlayer
var _speed := 0.0
var _move_dir := Vector2.ZERO   # direction LOCALE du déplacement (x droite, y avant)
var _busy_until := 0.0
var _casting := false
var _current_loop := ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func build(_tint: Color) -> void:
	var inst := HUMAN_SCENE.instantiate()
	inst.rotation.y = PI  # les modèles Mixamo regardent +Z, Godot avance vers -Z
	add_child(inst)

	_ap = inst.find_child("AnimationPlayer", true, false)
	if _ap == null:
		push_error("Human.glb : AnimationPlayer introuvable")
		return

	# Greffe la bibliothèque de combat (tracks %GeneralSkeleton:Os retargetées)
	var skeleton: Skeleton3D = inst.find_child("GeneralSkeleton", true, false)
	var lib: AnimationLibrary = MELEE_LIB
	if skeleton:
		_strip_invalid_tracks(lib, skeleton)
	_ap.add_animation_library("m", lib)

	for anim_name in LOOP_ANIMS:
		if _ap.has_animation(anim_name):
			_ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

	_play_loop("m/LightIdle")

# Retire les tracks qui visent des os absents de NOTRE squelette (la lib a été
# créée sur un modèle avec des os bonus "Weapon"/"Root") — évite le spam de
# warnings du moteur à chaque lecture.
func _strip_invalid_tracks(lib: AnimationLibrary, skeleton: Skeleton3D) -> void:
	for anim_name in lib.get_animation_list():
		var anim := lib.get_animation(anim_name)
		for i in range(anim.get_track_count() - 1, -1, -1):
			var path := String(anim.track_get_path(i))
			var parts := path.split(":")
			if parts.size() < 2:
				continue
			if skeleton.find_bone(parts[1]) == -1:
				anim.remove_track(i)

func set_tint(_c: Color) -> void:
	pass  # textures du modèle conservées ; l'élément est montré par l'orbe

func set_locomotion(speed: float, local_dir: Vector2 = Vector2.ZERO) -> void:
	_speed = lerpf(_speed, speed, 0.25)
	if local_dir.length() > 0.05:
		_move_dir = _move_dir.lerp(local_dir.normalized(), 0.3)

func set_casting(on: bool) -> void:
	_casting = on

func play_melee(step: int) -> void:
	var i := clampi(step, 0, MELEE_ANIMS.size() - 1)
	_play_action(MELEE_ANIMS[i], MELEE_DURATIONS[i])

func play_dash() -> void:
	_play_action("m/Roll", 0.32)

func play_cast_shoot() -> void:
	_play_action("m/ThrowR", 0.4)

func play_breath(duration: float) -> void:
	# Pose d'exertion tenue pendant tout le rugissement
	_play_action("m/HeavyCharge", duration)

func play_hit() -> void:
	if _now() < _busy_until:
		return
	_play_action("m/Hurt1", 0.3)

func _play_action(anim_name: String, duration: float) -> void:
	if _ap == null or not _ap.has_animation(anim_name):
		return
	_busy_until = _now() + duration
	_current_loop = ""
	var anim_len := _ap.get_animation(anim_name).length
	var speed := anim_len / maxf(duration, 0.05)
	_ap.play(anim_name, 0.1, speed)

func _process(_delta: float) -> void:
	if _ap == null:
		return
	if _now() < _busy_until:
		return
	if _casting:
		_play_loop("m/HeavyCharge")
	elif _speed > WALK_THRESHOLD:
		_play_loop(_locomotion_anim())
	else:
		_play_loop("m/LightIdle")

func _locomotion_anim() -> String:
	if absf(_move_dir.x) > absf(_move_dir.y) * 1.2:
		return "m/LightStrafeR" if _move_dir.x > 0 else "m/LightStrafeL"
	if _move_dir.y < -0.3:
		return "m/Retreat"
	return "m/LightRunning" if _speed > RUN_THRESHOLD else "m/LightWalking"

func debug_anim() -> String:
	if _ap == null:
		return "no-animationplayer"
	return "%s (speed=%.2f, busy=%s)" % [_ap.current_animation, _speed, str(_now() < _busy_until)]

func _play_loop(anim_name: String) -> void:
	if _current_loop == anim_name:
		return
	if _ap == null or not _ap.has_animation(anim_name):
		return
	_current_loop = anim_name
	_ap.play(anim_name, 0.18, 1.0)

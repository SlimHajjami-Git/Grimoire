extends Node3D
# Personnage joueur : modèle KayKit Adventurers "Mage" (CC0, Kay Lousberg)
# riggé avec 75 animations professionnelles. Pilote l'AnimationPlayer du GLB.
# Même API que l'ancien humain procédural (human_model.gd, conservé en
# référence) : build / set_tint / set_locomotion / set_casting / play_melee
# + bonus permis par le rig : play_dash, play_cast_shoot, play_hit.

const MAGE_SCENE := preload("res://assets/kaykit/Mage.glb")
const MODEL_SCALE := 0.82        # le Mage fait ~2.2u avec le chapeau → ~1.8u
const RUN_THRESHOLD := 4.0       # m/s au-delà desquels on court
const WALK_THRESHOLD := 0.4

const MELEE_ANIMS := [
	"1H_Melee_Attack_Slice_Diagonal",
	"1H_Melee_Attack_Slice_Horizontal",
	"1H_Melee_Attack_Chop",
]
const MELEE_DURATIONS := [0.45, 0.45, 0.65]

const LOOP_ANIMS := [
	"Idle", "Walking_A", "Running_A", "Spellcasting",
	"Walking_Backwards", "Running_Strafe_Left", "Running_Strafe_Right",
]

var _ap: AnimationPlayer
var _speed := 0.0
var _busy_until := 0.0
var _casting := false
var _current_loop := ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func build(_tint: Color) -> void:
	var inst := MAGE_SCENE.instantiate()
	inst.rotation.y = PI  # KayKit regarde +Z, Godot avance vers -Z
	inst.scale = Vector3.ONE * MODEL_SCALE
	add_child(inst)

	_ap = inst.find_child("AnimationPlayer", true, false)
	if _ap == null:
		push_error("Mage.glb : AnimationPlayer introuvable")
		return

	# Les animations importées du glTF ne bouclent pas par défaut
	for anim_name in LOOP_ANIMS:
		if _ap.has_animation(anim_name):
			_ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

	# Accessoires intégrés au modèle : le mage garde sa BAGUETTE (arme de
	# mêlée) — le grimoire et le bâton 2 mains sont cachés pour l'instant.
	for hidden in ["Spellbook", "Spellbook_open", "2H_Staff"]:
		var node := inst.find_child(hidden, true, false)
		if node and node is Node3D:
			node.visible = false

	_play_loop("Idle")

func set_tint(_c: Color) -> void:
	pass  # les textures du modèle restent telles quelles ; l'élément actif
	      # est montré par l'orbe flottante et la couleur des sorts

func set_locomotion(speed: float) -> void:
	_speed = lerpf(_speed, speed, 0.25)

func set_casting(on: bool) -> void:
	_casting = on

func play_melee(step: int) -> void:
	var i := clampi(step, 0, MELEE_ANIMS.size() - 1)
	_play_action(MELEE_ANIMS[i], MELEE_DURATIONS[i])

func play_dash() -> void:
	_play_action("Dodge_Forward", 0.32)

func play_cast_shoot() -> void:
	_play_action("Spellcast_Shoot", 0.4)

func play_hit() -> void:
	# Réaction aux dégâts — seulement si aucune action n'est en cours
	if _now() < _busy_until:
		return
	_play_action("Hit_A", 0.3)

# Joue une animation d'action en calant sa durée sur la durée gameplay
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
		_play_loop("Spellcasting")
	elif _speed > RUN_THRESHOLD:
		_play_loop("Running_A")
	elif _speed > WALK_THRESHOLD:
		_play_loop("Walking_A")
	else:
		_play_loop("Idle")

func _play_loop(anim_name: String) -> void:
	if _current_loop == anim_name:
		return
	if _ap == null or not _ap.has_animation(anim_name):
		return
	_current_loop = anim_name
	_ap.play(anim_name, 0.18, 1.0)

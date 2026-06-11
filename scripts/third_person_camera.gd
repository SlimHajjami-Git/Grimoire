extends Node3D
# Caméra 3e personne type Elden Ring :
# - vue de dos, la souris (capturée) orbite librement autour du joueur
# - SpringArm3D : la caméra ne traverse jamais les murs/arbres
# - lock-on : verrouillée sur une cible, la caméra la garde cadrée pendant
#   que le joueur strafe autour
# Purement client-side : chaque joueur a sa propre caméra.

const SENS := 0.0028
const PITCH_MIN := -1.05
const PITCH_MAX := 0.45
const LOCK_TURN := 8.0
const ZOOM_MIN := 2.2
const ZOOM_MAX := 8.0

var yaw := 0.0
var pitch := -0.28
var follow: Node3D = null
var lock_target: Node3D = null

var spring: SpringArm3D
var cam: Camera3D

func setup(p: Node3D) -> void:
	follow = p
	top_level = true
	yaw = p.rotation.y  # démarre dans le dos du joueur

	spring = SpringArm3D.new()
	spring.spring_length = 4.6
	spring.margin = 0.3
	add_child(spring)
	spring.add_excluded_object(p.get_rid())

	cam = Camera3D.new()
	spring.add_child(cam)
	cam.current = true

	global_position = p.global_position + Vector3.UP * 1.5
	rotation.y = yaw
	spring.rotation.x = pitch

func handle_mouse(relative: Vector2) -> void:
	if lock_target != null and is_instance_valid(lock_target):
		return  # en lock, la caméra est pilotée par la cible
	yaw -= relative.x * SENS
	pitch = clampf(pitch - relative.y * SENS, PITCH_MIN, PITCH_MAX)

func zoom(step: float) -> void:
	if spring:
		spring.spring_length = clampf(spring.spring_length + step, ZOOM_MIN, ZOOM_MAX)

func _process(delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return
	global_position = follow.global_position + Vector3.UP * 1.5

	if lock_target != null and is_instance_valid(lock_target):
		var dir := lock_target.global_position - follow.global_position
		dir.y = 0
		if dir.length() > 0.5:
			var target_yaw := atan2(-dir.x, -dir.z)
			yaw = lerp_angle(yaw, target_yaw, LOCK_TURN * delta)
		pitch = lerpf(pitch, -0.22, 4.0 * delta)

	rotation.y = yaw
	spring.rotation.x = pitch

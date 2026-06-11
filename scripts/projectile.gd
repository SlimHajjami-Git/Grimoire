extends Area3D
# Sort projectile AUTOGUIDÉ (type WoW : la boule de feu suit sa cible).
# Spawné par le serveur via MultiplayerSpawner ; chaque pair le simule
# localement, mais SEUL le serveur détecte les impacts et applique les dégâts.
# Le décor (arbres, rochers) bloque les projectiles → le couvert compte.

const SPEED := 22.0
const LIFETIME := 3.0

var dir := Vector3.ZERO
var element := "fire"
var shooter := 0
var damage := 15
var extra := {}
var target_kind := ""
var target_name := ""

var _target: Node3D = null
var _age := 0.0

func setup(data: Dictionary) -> void:
	position = data["pos"]
	dir = data["dir"]
	element = data["element"]
	shooter = data["shooter"]
	damage = data["damage"]
	target_kind = data.get("target_kind", "")
	target_name = data.get("target_name", "")
	extra = data.get("extra", {})

func _ready() -> void:
	_build_visuals()
	var world := get_tree().get_first_node_in_group("world")
	if world:
		_target = world.resolve_target_node(target_kind, target_name)
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
	elif _target == null:
		# Réplication late-join : la cible d'origine n'existe pas (encore) sur
		# ce pair → données de lancement périmées. On masque la copie locale ;
		# le despawn du serveur (répliqué par le spawner) la supprimera.
		visible = false
		set_physics_process(false)

func _build_visuals() -> void:
	var c: Color = ElementData.get_color(element)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 3.5
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	var mesh := MeshInstance3D.new()
	mesh.mesh = sph
	mesh.material_override = mat
	add_child(mesh)

	var light := OmniLight3D.new()
	light.light_color = c
	light.omni_range = 5.0
	light.light_energy = 1.6
	add_child(light)

func _physics_process(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		var goal := _target.global_position + Vector3.UP * 1.1
		dir = (goal - position).normalized()
		# Filet de sécurité serveur : impact par proximité même sans contact physique
		if multiplayer.is_server() and position.distance_to(goal) < 0.9:
			_hit(_target)
			return
	else:
		_target = null

	position += dir * SPEED * delta
	_age += delta
	# Seul le serveur détruit : le despawn est répliqué par le spawner
	if _age > LIFETIME and multiplayer.is_server():
		queue_free()

func _hit(node: Node3D) -> void:
	# Garde anti double-impact : le filet de proximité ET body_entered peuvent
	# se déclencher dans la MÊME frame physique (queue_free est différé) —
	# sans ce garde, ~la moitié des impacts sur joueur faisaient double dégâts.
	if is_queued_for_deletion():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.server_handle_hit(node, damage, element, shooter, extra)
	queue_free()

func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body == _target:
		_hit(body)
	elif body is StaticBody3D:
		queue_free()  # bloqué par le décor

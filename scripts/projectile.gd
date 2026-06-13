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
var _light: OmniLight3D = null
var _light_base := 1.8

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

	# Noyau d'énergie animé (shader). Pour la glace, on garde en plus un pic
	# de cristal solide qui pointe dans le sens du vol.
	add_child(Vfx.make_orb(c, 0.26))
	if element == "ice":
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.13
		spike.height = 0.7
		var crystal_mat := StandardMaterial3D.new()
		crystal_mat.albedo_color = c.lerp(Color(1, 1, 1), 0.5)
		crystal_mat.metallic = 0.4
		crystal_mat.roughness = 0.15
		crystal_mat.emission_enabled = true
		crystal_mat.emission = c
		crystal_mat.emission_energy_multiplier = 1.2
		var spike_mesh := MeshInstance3D.new()
		spike_mesh.mesh = spike
		spike_mesh.material_override = crystal_mat
		spike_mesh.rotation_degrees = Vector3(-90, 0, 0)  # pointe vers -Z
		spike_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spike_mesh)

	# Traînée de braises
	add_child(Vfx.make_trail(c))

	_light = OmniLight3D.new()
	_light.light_color = c
	_light.omni_range = 5.0
	_light.light_energy = _light_base
	add_child(_light)

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
	# Oriente le projectile dans le sens du vol (le pic de glace pointe devant)
	var flat_dir := Vector3(dir.x, 0, dir.z)
	if flat_dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)
	# Scintillement de la lumière (la flamme vacille)
	if _light:
		_light.light_energy = _light_base + sin(_age * 38.0) * 0.5
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

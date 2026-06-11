extends CharacterBody3D
# LE GARDIEN DE GIVRE — premier boss PvE du jeu.
# Le tuer débloque la magie de GLACE pour tous ceux qui l'ont blessé.
# IA serveur : poursuite + coup de mêlée + TRAIT DE GIVRE à distance
# (qui ralentit) pour qu'on ne puisse pas le kiter gratuitement.

const SPEED := 3.6
const AGGRO_RANGE := 14.0
const ATTACK_RANGE := 2.8
const ATTACK_DAMAGE := 20
const ATTACK_INTERVAL := 1.6
const BOLT_RANGE := 26.0
const BOLT_DAMAGE := 14
const BOLT_INTERVAL := 3.0
const GRAVITY := 22.0

const MAX_HP := 400

var element := "ice"
var hp := MAX_HP
var display_hp := MAX_HP       # copie côté client pour le HUD (via sync_boss_hp)
var contributors := {}          # serveur : peer_id -> true (qui a blessé le boss)

var _attack_cd := 0.0
var _bolt_cd := 2.0
var _slow_factor := 0.0
var _slow_until := 0.0
var hp_label: Label3D

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("boss")
	_build_visuals()

func _build_visuals() -> void:
	var c: Color = ElementData.get_color("ice")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c.lerp(Color(0.15, 0.2, 0.35), 0.4)
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.3

	var cap := CapsuleMesh.new()
	cap.radius = 0.9
	cap.height = 2.6
	var body := MeshInstance3D.new()
	body.mesh = cap
	body.material_override = mat
	body.position = Vector3(0, 1.3, 0)
	add_child(body)

	# Couronne de cristaux
	for i in range(4):
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 0.18
		crystal.height = 0.8
		var cm := MeshInstance3D.new()
		cm.mesh = crystal
		cm.material_override = mat
		var ang := TAU * i / 4.0
		cm.position = Vector3(cos(ang) * 0.55, 2.7, sin(ang) * 0.55)
		add_child(cm)

	var name_label := Label3D.new()
	name_label.text = "❄ GARDIEN DE GIVRE ❄"
	name_label.font_size = 72
	name_label.modulate = Color(0.7, 0.9, 1.0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.outline_size = 12
	name_label.position = Vector3(0, 4.0, 0)
	add_child(name_label)

	hp_label = Label3D.new()
	hp_label.text = "%d / %d" % [hp, MAX_HP]
	hp_label.font_size = 52
	hp_label.modulate = Color(0.5, 0.8, 1.0)
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	hp_label.outline_size = 10
	hp_label.position = Vector3(0, 3.5, 0)
	add_child(hp_label)

	var light := OmniLight3D.new()
	light.light_color = c
	light.omni_range = 9.0
	light.light_energy = 1.5
	light.position = Vector3(0, 2.0, 0)
	add_child(light)

func set_hp_display(value: int) -> void:
	display_hp = value
	hp_label.text = "%d / %d" % [maxi(value, 0), MAX_HP]

func apply_slow(pct: float, duration: float) -> void:
	# max/max : un debuff plus faible n'écrase pas un slow plus fort actif
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _slow_until:
		_slow_factor = 0.0
	_slow_factor = maxf(_slow_factor, pct)
	_slow_until = maxf(_slow_until, now + duration)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Un boss mort (queue_free différé en fin de frame) ne doit plus attaquer
	if hp <= 0 or is_queued_for_deletion():
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5

	var now := Time.get_ticks_msec() / 1000.0
	var slow := _slow_factor if now < _slow_until else 0.0
	var eff_speed := SPEED * (1.0 - slow)

	var target := _nearest_player()
	if target != null:
		var to := target.global_position - global_position
		to.y = 0
		var dist := to.length()
		if dist > ATTACK_RANGE * 0.8:
			var d := to.normalized()
			velocity.x = d.x * eff_speed
			velocity.z = d.z * eff_speed
		else:
			velocity.x = 0
			velocity.z = 0
		if dist > 0.5:
			look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)

		var world := get_tree().get_first_node_in_group("world")

		_attack_cd -= delta
		if dist <= ATTACK_RANGE and _attack_cd <= 0.0:
			_attack_cd = ATTACK_INTERVAL
			if world:
				world.server_boss_melee(self)

		_bolt_cd -= delta
		if dist > ATTACK_RANGE and dist <= BOLT_RANGE and _bolt_cd <= 0.0:
			_bolt_cd = BOLT_INTERVAL
			if world:
				world.server_spawn_bolt(
					global_position + Vector3.UP * 2.2, "ice", BOLT_DAMAGE,
					"player", String(target.name), 0,
					{ "slow": 0.3, "slow_duration": 2.0 }
				)
	else:
		velocity.x = 0
		velocity.z = 0

	move_and_slide()

func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_dist := AGGRO_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		var d: float = p.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best

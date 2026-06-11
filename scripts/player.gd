extends CharacterBody3D
# Le mage — combat type WoW :
#   clic gauche  = sélectionner une cible (clic dans le vide = désélection)
#   Tab          = cycler les cibles proches
#   1 / 2 / 3    = lancer les sorts de la magie active
#   R            = changer de magie (parmi celles débloquées)
#   Espace       = dash  •  Échap = annuler la cible
# Bouger pendant une incantation l'INTERROMPT (comme WoW).
# Autorité : le peer propriétaire. PV et dégâts gérés côté serveur (world.gd).

const SPEED := 6.5
const DASH_SPEED := 16.0
const DASH_DURATION := 0.16
const DASH_COOLDOWN := 1.1
const GRAVITY := 22.0
const GCD := 0.8                 # global cooldown entre deux sorts
const TARGET_MAX_RANGE := 60.0   # portée max de sélection de cible

const CAM_YAW := PI * 0.25       # 45° — vue type V Rising / WoW dézoomé
const CAM_PITCH := 0.96          # ~55°

@export var player_name := "Mage"
@export var sync_element: String = "fire":
	set(value):
		sync_element = value
		if is_node_ready():
			_apply_element_visual()

var unlocked: Array = ["fire"]
var hp := 100
var current_target: Node3D = null

var _dash_until := 0.0
var _dash_cd_until := 0.0
var _dash_dir := Vector3.ZERO
var _cam_dist := 14.0

# État d'incantation
var _casting := false
var _cast_slot := -1
var _cast_spell: Dictionary = {}
var _cast_target: Node3D = null   # cible FIGÉE au début de l'incantation (comme WoW)
var _cast_started := 0.0
var _cast_until := 0.0
var _cds := {}            # spell_id -> fin de cooldown (secondes)
var _gcd_until := 0.0

# Ralentissement (appliqué par le serveur via world.client_apply_slow)
var _slow_factor := 0.0
var _slow_until := 0.0

var _want_pick := false
var _autotest_count := 0

var camera: Camera3D
var body_mesh: MeshInstance3D
var orb: MeshInstance3D
var orb_light: OmniLight3D
var name_label: Label3D
var hp_label: Label3D
var target_ring: MeshInstance3D
var _body_mat: StandardMaterial3D
var _orb_mat: StandardMaterial3D

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _enter_tree() -> void:
	# Le nom du node EST le peer_id (posé par le spawn_function de world.gd)
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	add_to_group("players")
	_build_visuals()
	_apply_element_visual()
	if is_multiplayer_authority():
		camera = Camera3D.new()
		camera.name = "Cam"
		camera.top_level = true
		add_child(camera)
		camera.current = true
		_update_camera()
		_build_target_ring()
		if "--autotest" in OS.get_cmdline_user_args():
			var t := Timer.new()
			t.wait_time = 2.0
			t.autostart = true
			t.timeout.connect(_autotest_tick)
			add_child(t)

# ------------------------------------------------------------------ VISUELS

func _build_visuals() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.roughness = 0.8
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.8
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = cap
	body_mesh.material_override = _body_mat
	body_mesh.position = Vector3(0, 0.9, 0)
	add_child(body_mesh)

	_orb_mat = StandardMaterial3D.new()
	_orb_mat.emission_enabled = true
	var sph := SphereMesh.new()
	sph.radius = 0.17
	sph.height = 0.34
	orb = MeshInstance3D.new()
	orb.mesh = sph
	orb.material_override = _orb_mat
	orb.position = Vector3(0, 1.55, -0.6)
	add_child(orb)

	orb_light = OmniLight3D.new()
	orb_light.omni_range = 4.0
	orb_light.light_energy = 1.2
	orb_light.position = Vector3(0, 1.55, -0.6)
	add_child(orb_light)

	name_label = Label3D.new()
	name_label.text = player_name
	name_label.font_size = 56
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.outline_size = 10
	name_label.position = Vector3(0, 2.45, 0)
	add_child(name_label)

	hp_label = Label3D.new()
	hp_label.text = "100"
	hp_label.font_size = 40
	hp_label.modulate = Color(0.4, 1.0, 0.4)
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	hp_label.outline_size = 8
	hp_label.position = Vector3(0, 2.12, 0)
	add_child(hp_label)

func _build_target_ring() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.2)
	mat.emission_energy_multiplier = 1.5
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.92
	target_ring = MeshInstance3D.new()
	target_ring.mesh = torus
	target_ring.material_override = mat
	target_ring.top_level = true
	target_ring.visible = false
	add_child(target_ring)

func _apply_element_visual() -> void:
	var c: Color = ElementData.get_color(sync_element)
	_body_mat.albedo_color = c.lerp(Color(0.25, 0.22, 0.3), 0.45)
	_orb_mat.albedo_color = c
	_orb_mat.emission = c
	_orb_mat.emission_energy_multiplier = 2.5
	orb_light.light_color = c

# ------------------------------------------------------------------ BOUCLE

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if _want_pick:
		_want_pick = false
		_pick_target_under_mouse()
	_validate_target()

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, CAM_YAW)
	var now := _now()

	# Incantation : bouger ou dasher interrompt, la cible FIGÉE doit rester valide
	if _casting:
		if input != Vector2.ZERO or now < _dash_until:
			_cancel_cast("Sort interrompu !")
		elif _cast_spell.get("kind", "") == "bolt" and not _is_enemy(_cast_target):
			_cancel_cast("Cible perdue")
		elif now >= _cast_until:
			_complete_cast()

	var slow := _slow_factor if now < _slow_until else 0.0
	var eff_speed := SPEED * (1.0 - slow)

	if now < _dash_until:
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
	else:
		velocity.x = dir.x * eff_speed
		velocity.z = dir.z * eff_speed

	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()

	if _casting and _cast_target != null:
		_face_node(_cast_target)
	elif dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)

	_update_camera()
	_update_target_ring()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("select_target"):
		_want_pick = true
	elif event.is_action_pressed("target_cycle"):
		_cycle_target()
	elif event.is_action_pressed("clear_target"):
		current_target = null
	elif event.is_action_pressed("spell_1"):
		_try_cast_spell(0)
	elif event.is_action_pressed("spell_2"):
		_try_cast_spell(1)
	elif event.is_action_pressed("spell_3"):
		_try_cast_spell(2)
	elif event.is_action_pressed("dash"):
		_try_dash()
	elif event.is_action_pressed("switch_element"):
		_switch_element()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 1.2, 7.0, 24.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 1.2, 7.0, 24.0)

# ------------------------------------------------------------------ CIBLAGE

func _pick_target_under_mouse() -> void:
	if camera == null:
		return
	var m := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(m)
	var to := from + camera.project_ray_normal(m) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.has("collider"):
		var n: Object = hit["collider"]
		if n is Node3D and (n.is_in_group("players") or n.is_in_group("boss")):
			current_target = n
			return
	# Clic dans le vide → désélection (comme WoW)
	current_target = null

func _cycle_target() -> void:
	var candidates: Array = []
	for n in get_tree().get_nodes_in_group("players"):
		if n != self and n.global_position.distance_to(global_position) <= TARGET_MAX_RANGE:
			candidates.append(n)
	for n in get_tree().get_nodes_in_group("boss"):
		if n.global_position.distance_to(global_position) <= TARGET_MAX_RANGE:
			candidates.append(n)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b):
		return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position)
	)
	var idx: int = candidates.find(current_target)
	current_target = candidates[(idx + 1) % candidates.size()]

func _validate_target() -> void:
	if current_target != null and not _is_enemy(current_target):
		current_target = null

func _is_enemy(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or t.is_queued_for_deletion():
		return false
	# Boss mort mais pas encore despawné (latence) : le client le sait déjà
	# via sync_boss_hp — inutile de gaspiller un sort dessus.
	if t.is_in_group("boss") and t.display_hp <= 0:
		return false
	return true

func _target_is_enemy() -> bool:
	return _is_enemy(current_target)

func _update_target_ring() -> void:
	if target_ring == null:
		return
	if _target_is_enemy():
		target_ring.visible = true
		target_ring.global_position = current_target.global_position + Vector3(0, 0.06, 0)
	else:
		target_ring.visible = false

# ------------------------------------------------------------------ SORTS

func _try_cast_spell(slot: int) -> void:
	var spells: Array = SpellData.get_spells(sync_element)
	if slot < 0 or slot >= spells.size():
		return
	var spell: Dictionary = spells[slot]
	var now := _now()
	if _casting:
		_toast("Déjà en train d'incanter !")
		return
	if now < _gcd_until:
		return
	if now < _cds.get(spell["id"], 0.0):
		_toast("%s n'est pas prêt" % spell["name"])
		return
	if spell["kind"] == "bolt":
		if not _target_is_enemy():
			_toast("Aucune cible !")
			return
		if global_position.distance_to(current_target.global_position) > float(spell["range"]):
			_toast("Trop loin !")
			return
		_face_target()
	if float(spell["cast_time"]) <= 0.0:
		_gcd_until = now + GCD
		_send_cast(slot, spell)
	else:
		# Démarrer une incantation en mouvement = auto-interruption à la frame
		# suivante + GCD brûlé pour rien. On refuse proprement à la place.
		var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if move_input != Vector2.ZERO or now < _dash_until:
			_toast("Impossible en mouvement !")
			return
		_casting = true
		_cast_slot = slot
		_cast_spell = spell
		# La cible est FIGÉE au début du cast (comme WoW) : changer de cible
		# avec Tab/clic pendant l'incantation ne redirige pas le sort.
		_cast_target = current_target if spell["kind"] == "bolt" else null
		_cast_started = now
		_cast_until = now + float(spell["cast_time"])
		_gcd_until = now + GCD

func _complete_cast() -> void:
	_casting = false
	_send_cast(_cast_slot, _cast_spell, _cast_target)
	_cast_target = null

func _cancel_cast(msg: String) -> void:
	_casting = false
	_cast_target = null
	# Le GCD armé au début du cast est remboursé : aucun sort n'est parti
	# (sans ça, une interruption verrouillait tous les sorts pendant 0.8s).
	_gcd_until = 0.0
	_toast(msg)

func _send_cast(slot: int, spell: Dictionary, snapshot_target: Node3D = null) -> void:
	var t := snapshot_target if snapshot_target != null else current_target
	var tk := ""
	var tn := ""
	if spell["kind"] == "bolt":
		# Cible et portée re-vérifiées AVANT de consommer le cooldown : la
		# cible a pu disparaître ou fuir pendant l'incantation — sinon on
		# paierait un cooldown pour un sort que le serveur rejette en silence.
		if not _is_enemy(t):
			return
		if global_position.distance_to(t.global_position) > float(spell["range"]) + 4.0:
			_toast("Trop loin !")
			return
		tk = "boss" if t.is_in_group("boss") else "player"
		tn = String(t.name)
	_cds[spell["id"]] = _now() + float(spell["cooldown"])
	print("[CAST] %s lance %s" % [player_name, spell["id"]])
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.rpc_id(1, "request_spell", sync_element, slot, tk, tn)

func _switch_element() -> void:
	if unlocked.size() <= 1:
		return
	if _casting:
		_cancel_cast("Sort interrompu !")
	var idx: int = unlocked.find(sync_element)
	sync_element = unlocked[(idx + 1) % unlocked.size()]

# Appelé via world.gd après un respawn : nettoie l'état transitoire
# (un mort ne continue pas son incantation et n'est plus ralenti)
func on_respawned() -> void:
	_casting = false
	_slow_until = 0.0

# Appelé via world.gd quand le serveur accorde une nouvelle magie (boss PvE)
func grant_element(element: String) -> void:
	if element not in unlocked:
		unlocked.append(element)
	if _casting:
		_cancel_cast("Sort interrompu !")
	sync_element = element  # auto-équipe : moment dopamine

# ------------------------------------------------------------------ EFFETS

func apply_slow(pct: float, duration: float) -> void:
	# max/max : un debuff plus faible ne doit jamais ÉCRASER un slow plus
	# fort déjà actif (ni raccourcir sa durée).
	var now := _now()
	if now >= _slow_until:
		_slow_factor = 0.0
	_slow_factor = maxf(_slow_factor, pct)
	_slow_until = maxf(_slow_until, now + duration)
	_toast("Ralenti !")

func show_buff_bubble(duration: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.5, 0.85, 1.0, 0.25)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sph := SphereMesh.new()
	sph.radius = 1.1
	sph.height = 2.2
	var bubble := MeshInstance3D.new()
	bubble.mesh = sph
	bubble.material_override = mat
	bubble.position = Vector3(0, 1.0, 0)
	add_child(bubble)
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(bubble):
			bubble.queue_free()
	)

func set_hp_display(value: int) -> void:
	hp = value
	hp_label.text = str(maxi(value, 0))
	var ratio := clampf(value / 100.0, 0.0, 1.0)
	hp_label.modulate = Color(1.0 - ratio * 0.6, 0.3 + ratio * 0.7, 0.35)

# ------------------------------------------------------------------ HUD (lu par world.gd)

func is_casting() -> bool:
	return _casting

func cast_progress() -> float:
	if not _casting or _cast_until <= _cast_started:
		return 0.0
	return clampf((_now() - _cast_started) / (_cast_until - _cast_started), 0.0, 1.0)

func cast_name() -> String:
	return String(_cast_spell.get("name", ""))

func cd_remaining(spell_id: String) -> float:
	return maxf(0.0, _cds.get(spell_id, 0.0) - _now())

func gcd_remaining() -> float:
	return maxf(0.0, _gcd_until - _now())

# ------------------------------------------------------------------ DIVERS

func _try_dash() -> void:
	var now := _now()
	if now < _dash_cd_until:
		return
	if _casting:
		_cancel_cast("Sort interrompu !")
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, CAM_YAW)
	if dir.length() < 0.1:
		dir = -global_transform.basis.z
	_dash_dir = dir.normalized()
	_dash_until = now + DASH_DURATION
	_dash_cd_until = now + DASH_COOLDOWN

func _face_target() -> void:
	_face_node(current_target)

func _face_node(t: Node3D) -> void:
	if not _is_enemy(t):
		return
	var p := t.global_position
	var flat := Vector3(p.x, global_position.y, p.z)
	if flat.distance_to(global_position) > 0.2:
		look_at(flat, Vector3.UP)

func _update_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(sin(CAM_YAW), 0, cos(CAM_YAW)) * cos(CAM_PITCH) * _cam_dist
	offset.y = sin(CAM_PITCH) * _cam_dist
	camera.global_position = global_position + offset
	camera.look_at(global_position + Vector3.UP * 1.0, Vector3.UP)

func _toast(msg: String) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.show_toast(msg)

# ------------------------------------------------------------------ AUTOTEST (headless)

func _autotest_tick() -> void:
	_autotest_count += 1
	if _autotest_count == 1:
		# Se téléporte près de l'arène du boss pour tester le combat complet
		global_position = Vector3(28, 0.2, 28)
		return
	if not _target_is_enemy():
		_cycle_target()
	match _autotest_count % 4:
		0:
			_try_cast_spell(2)  # nova (instantané sans cible)
		1:
			_try_cast_spell(1)  # boule de feu (1.8s d'incantation — teste _casting)
		_:
			_try_cast_spell(0)  # trait (instantané ciblé)

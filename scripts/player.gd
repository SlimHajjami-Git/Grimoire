extends CharacterBody3D
# Le mage — contrôles type Elden Ring :
#   Souris            = caméra libre (3e personne, vue de dos)
#   Clic gauche       = coup d'épée — re-cliquer enchaîne les combos (1→2→3)
#   Tab / clic-molette = verrouiller la cible (re-Tab : cible suivante)
#   1 / 2 / 3         = sorts de la magie active (sur la cible verrouillée)
#   R                 = changer de magie  •  Espace = dash
#   Échap             = déverrouiller la cible, puis libérer la souris
# Bouger pendant une incantation l'interrompt (les sorts se canalisent
# immobile ; la mêlée, elle, reste mobile). L'épée porte ton élément actif.
# Autorité : le peer propriétaire. PV et dégâts gérés côté serveur (world.gd).

const SPEED := 6.5
const MELEE_MOVE_FACTOR := 0.25   # on avance peu pendant un coup d'épée
const DASH_SPEED := 16.0
const DASH_DURATION := 0.16
const DASH_COOLDOWN := 1.1
const GRAVITY := 22.0
const GCD := 0.8
const LOCK_RANGE := 35.0
const TURN_SPEED := 12.0

const MELEE_DURATIONS := [0.45, 0.45, 0.65]
const MELEE_CHAIN_WINDOW := 0.55

const HumanModelScript := preload("res://scripts/human_model.gd")
const CameraRigScript := preload("res://scripts/third_person_camera.gd")

@export var player_name := "Mage"
@export var sync_element: String = "fire":
	set(value):
		sync_element = value
		if is_node_ready():
			_apply_element_visual()

var unlocked: Array = ["fire"]
var hp := 100
var current_target: Node3D = null   # cible verrouillée (lock-on)

var _dash_until := 0.0
var _dash_cd_until := 0.0
var _dash_dir := Vector3.ZERO

# État d'incantation
var _casting := false
var _cast_slot := -1
var _cast_spell: Dictionary = {}
var _cast_target: Node3D = null   # cible FIGÉE au début de l'incantation
var _cast_started := 0.0
var _cast_until := 0.0
var _cds := {}            # spell_id -> fin de cooldown (secondes)
var _gcd_until := 0.0

# État mêlée (combos)
var _melee_step := 0
var _melee_until := 0.0
var _melee_chain_until := 0.0
var _melee_queued := false

# Ralentissement (appliqué par le serveur via world.client_apply_slow)
var _slow_factor := 0.0
var _slow_until := 0.0

var _autotest_count := 0
var _prev_pos := Vector3.ZERO

var model: Node3D
var cam_rig: Node3D
var orb: MeshInstance3D
var orb_light: OmniLight3D
var name_label: Label3D
var hp_label: Label3D
var target_ring: MeshInstance3D
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
	_prev_pos = global_position
	if is_multiplayer_authority():
		cam_rig = Node3D.new()
		cam_rig.set_script(CameraRigScript)
		add_child(cam_rig)
		cam_rig.setup(self)
		_build_target_ring()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if "--autotest" in OS.get_cmdline_user_args():
			var t := Timer.new()
			t.wait_time = 2.0
			t.autostart = true
			t.timeout.connect(_autotest_tick)
			add_child(t)

# ------------------------------------------------------------------ VISUELS

func _build_visuals() -> void:
	model = Node3D.new()
	model.set_script(HumanModelScript)
	add_child(model)
	model.build(ElementData.get_color(sync_element))

	# Orbe de magie flottante près de l'épaule gauche : montre l'élément actif
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.emission_enabled = true
	var sph := SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	orb = MeshInstance3D.new()
	orb.mesh = sph
	orb.material_override = _orb_mat
	orb.position = Vector3(-0.45, 1.85, 0)
	add_child(orb)

	orb_light = OmniLight3D.new()
	orb_light.omni_range = 4.0
	orb_light.light_energy = 1.1
	orb_light.position = Vector3(-0.45, 1.85, 0)
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
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
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
	if model:
		model.set_tint(c)
	if _orb_mat:
		_orb_mat.albedo_color = c
		_orb_mat.emission = c
		_orb_mat.emission_energy_multiplier = 2.5
	if orb_light:
		orb_light.light_color = c

# ------------------------------------------------------------------ BOUCLE

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_validate_target()

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam_yaw: float = cam_rig.yaw if cam_rig else rotation.y
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, cam_yaw)
	var now := _now()

	# Incantation : bouger ou dasher interrompt, la cible FIGÉE doit rester valide
	if _casting:
		if input != Vector2.ZERO or now < _dash_until:
			_cancel_cast("Sort interrompu !")
		elif _cast_spell.get("kind", "") == "bolt" and not _is_enemy(_cast_target):
			_cancel_cast("Cible perdue")
		elif now >= _cast_until:
			_complete_cast()

	# Combo mêlée mis en file pendant un coup
	if _melee_queued and now >= _melee_until:
		_melee_queued = false
		_advance_melee()

	var slow := _slow_factor if now < _slow_until else 0.0
	var speed_mult := 1.0 - slow
	if now < _melee_until:
		speed_mult *= MELEE_MOVE_FACTOR

	if now < _dash_until:
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
	else:
		velocity.x = dir.x * SPEED * speed_mult
		velocity.z = dir.z * SPEED * speed_mult

	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()

	# Orientation : lock-on = toujours face à la cible (strafe autour d'elle)
	if _is_enemy(current_target):
		_face_node_smooth(current_target, delta)
	elif _casting and _cast_target != null and is_instance_valid(_cast_target):
		_face_node_smooth(_cast_target, delta)
	elif dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), TURN_SPEED * delta)

	_update_target_ring()
	if model:
		model.set_locomotion(Vector2(velocity.x, velocity.z).length())

func _process(delta: float) -> void:
	# Animation de marche des AUTRES joueurs (vitesse déduite de la position)
	if not is_multiplayer_authority() and model:
		var spd := (global_position - _prev_pos).length() / maxf(delta, 0.0001)
		_prev_pos = global_position
		model.set_locomotion(spd)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if cam_rig:
			cam_rig.handle_mouse(event.relative)
	elif event.is_action_pressed("attack"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # re-capture au clic
		else:
			_try_melee()
	elif event.is_action_pressed("lock_on"):
		_toggle_lock()
	elif event.is_action_pressed("clear_target"):
		if current_target != null:
			current_target = null
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and cam_rig:
			cam_rig.zoom(-0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and cam_rig:
			cam_rig.zoom(0.6)

# ------------------------------------------------------------------ LOCK-ON

func _toggle_lock() -> void:
	var candidates := _lock_candidates()
	if current_target != null:
		var idx := candidates.find(current_target)
		if candidates.size() > 1 and idx != -1:
			current_target = candidates[(idx + 1) % candidates.size()]
		else:
			current_target = null
	elif candidates.size() > 0:
		current_target = candidates[0]
	else:
		_toast("Aucune cible à verrouiller")

func _lock_candidates() -> Array:
	var cam_yaw: float = cam_rig.yaw if cam_rig else rotation.y
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, cam_yaw)
	var list: Array = []
	for n in get_tree().get_nodes_in_group("players"):
		if n != self and _is_enemy(n):
			list.append(n)
	for n in get_tree().get_nodes_in_group("boss"):
		if _is_enemy(n):
			list.append(n)
	var scored: Array = []
	for n in list:
		var to: Vector3 = n.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > LOCK_RANGE or d < 0.01:
			continue
		# Priorité : ce que la caméra regarde, puis le plus proche
		var score: float = fwd.angle_to(to.normalized()) * 2.0 + d * 0.03
		scored.append({ "n": n, "s": score })
	scored.sort_custom(func(a, b): return a["s"] < b["s"])
	return scored.map(func(e): return e["n"])

func _validate_target() -> void:
	if current_target != null and not _is_enemy(current_target):
		current_target = null
	if cam_rig:
		cam_rig.lock_target = current_target

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

# ------------------------------------------------------------------ MÊLÉE

func _try_melee() -> void:
	var now := _now()
	if _casting:
		return
	if now < _melee_until:
		_melee_queued = true  # buffer : le combo s'enchaînera à la fin du coup
		return
	if now <= _melee_chain_until and _melee_step < MELEE_DURATIONS.size() - 1:
		_melee_step += 1
	else:
		_melee_step = 0
	_start_melee()

func _advance_melee() -> void:
	if _melee_step < MELEE_DURATIONS.size() - 1:
		_melee_step += 1
	else:
		_melee_step = 0
	_start_melee()

func _start_melee() -> void:
	var now := _now()
	_melee_until = now + MELEE_DURATIONS[_melee_step]
	_melee_chain_until = _melee_until + MELEE_CHAIN_WINDOW
	if _is_enemy(current_target):
		_face_node(current_target)
	if model:
		model.play_melee(_melee_step)
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.rpc_id(1, "request_melee", sync_element, _melee_step)

# Vue distante d'une attaque (diffusée par le serveur via fx_melee)
func play_melee_anim(step: int) -> void:
	if is_multiplayer_authority():
		return  # déjà jouée localement au moment du clic
	if model:
		model.play_melee(step)

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
	if now < _melee_until:
		return  # on finit le coup d'épée d'abord
	if now < _gcd_until:
		return
	if now < _cds.get(spell["id"], 0.0):
		_toast("%s n'est pas prêt" % spell["name"])
		return
	if spell["kind"] == "bolt":
		if not _target_is_enemy():
			_toast("Verrouille une cible (Tab) !")
			return
		if global_position.distance_to(current_target.global_position) > float(spell["range"]):
			_toast("Trop loin !")
			return
		_face_node(current_target)
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
		# pendant l'incantation ne redirige pas le sort.
		_cast_target = current_target if spell["kind"] == "bolt" else null
		_cast_started = now
		_cast_until = now + float(spell["cast_time"])
		_gcd_until = now + GCD
		if model:
			model.set_casting(true)

func _complete_cast() -> void:
	_casting = false
	if model:
		model.set_casting(false)
	_send_cast(_cast_slot, _cast_spell, _cast_target)
	_cast_target = null

func _cancel_cast(msg: String) -> void:
	_casting = false
	_cast_target = null
	if model:
		model.set_casting(false)
	# Le GCD armé au début du cast est remboursé : aucun sort n'est parti
	_gcd_until = 0.0
	_toast(msg)

func _send_cast(slot: int, spell: Dictionary, snapshot_target: Node3D = null) -> void:
	var t := snapshot_target if snapshot_target != null else current_target
	var tk := ""
	var tn := ""
	if spell["kind"] == "bolt":
		# Cible et portée re-vérifiées AVANT de consommer le cooldown : la
		# cible a pu disparaître ou fuir pendant l'incantation.
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
func on_respawned() -> void:
	_casting = false
	_cast_target = null
	_slow_until = 0.0
	if model:
		model.set_casting(false)

# Appelé via world.gd quand le serveur accorde une nouvelle magie (boss PvE)
func grant_element(element: String) -> void:
	if element not in unlocked:
		unlocked.append(element)
	if _casting:
		_cancel_cast("Sort interrompu !")
	sync_element = element  # auto-équipe : moment dopamine

# ------------------------------------------------------------------ EFFETS

func apply_slow(pct: float, duration: float) -> void:
	# max/max : un debuff plus faible n'écrase jamais un slow plus fort actif
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
	var cam_yaw: float = cam_rig.yaw if cam_rig else rotation.y
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, cam_yaw)
	if dir.length() < 0.1:
		dir = -global_transform.basis.z
	_dash_dir = dir.normalized()
	_dash_until = now + DASH_DURATION
	_dash_cd_until = now + DASH_COOLDOWN

func _face_node(t: Node3D) -> void:
	if not _is_enemy(t):
		return
	var p := t.global_position
	var flat := Vector3(p.x, global_position.y, p.z)
	if flat.distance_to(global_position) > 0.2:
		look_at(flat, Vector3.UP)

func _face_node_smooth(t: Node3D, delta: float) -> void:
	if t == null or not is_instance_valid(t):
		return
	var to := t.global_position - global_position
	to.y = 0
	if to.length() < 0.2:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), TURN_SPEED * delta)

func _toast(msg: String) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.show_toast(msg)

# ------------------------------------------------------------------ AUTOTEST (headless)

func _autotest_tick() -> void:
	_autotest_count += 1
	if _autotest_count == 1:
		# Se téléporte au contact du boss pour tester mêlée + sorts
		global_position = Vector3(32, 0.2, 33)
		return
	if not _target_is_enemy():
		_toggle_lock()
	match _autotest_count % 4:
		0:
			_try_cast_spell(2)  # nova
		1:
			_try_cast_spell(0)  # trait ciblé
		_:
			_try_melee()        # combos d'épée

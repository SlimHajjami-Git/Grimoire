extends Node3D
# Le monde — généré par code avec une seed fixe (identique sur tous les pairs).
# Contient toute la LOGIQUE SERVEUR : spawn, sorts (validation cible/portée/
# cooldown), dégâts via la roue des contres, buffs, morts/respawn, boss et
# déblocage de magie par le PvE.

const WORLD_SEED := 20260611
const WORLD_HALF := 110.0
const SPAWN_RADIUS := 4.0
const BOSS_ARENA := Vector3(34, 0.2, 34)
const BOSS_RESPAWN_DELAY := 30.0
const GCD_MS := 750
const RANGE_SLACK := 4.0
const RESPAWN_INVULN_MS := 2500
const MELEE_RANGE := 2.6
const MELEE_ARC_DEG := 120.0
const MELEE_DAMAGE := [8, 10, 16]
const MELEE_MIN_INTERVAL_MS := 280

const PlayerScene := preload("res://scenes/player.tscn")
const ProjectileScene := preload("res://scenes/projectile.tscn")
const BossScene := preload("res://scenes/boss.tscn")

var players_node: Node3D
var projectiles_node: Node3D
var bosses_node: Node3D
var player_spawner: MultiplayerSpawner
var projectile_spawner: MultiplayerSpawner
var boss_spawner: MultiplayerSpawner

# État serveur
var player_hp := {}          # peer_id -> hp
var _spell_cd := {}          # peer_id -> { spell_id: until_msec }
var _gcd_until := {}         # peer_id -> msec
var _melee_last := {}        # peer_id -> msec du dernier coup d'épée
var _buffs := {}             # peer_id -> { frost_armor_until: msec }
var _invuln_until := {}      # peer_id -> msec
var _projectile_counter := 0
var _boss_counter := 0

# HUD
var hud: CanvasLayer
var status_label: Label
var toast_label: Label
var target_frame: PanelContainer
var tf_name: Label
var tf_hp: ProgressBar
var spell_bar: HBoxContainer
var cast_bar: ProgressBar
var cast_label: Label
var _spell_buttons: Array = []
var _btn_base: Array = []
var _spells_cached: Array = []
var _hud_element := ""
var _toast_timer: SceneTreeTimer
var _local_player: Node3D

func _ready() -> void:
	add_to_group("world")
	_build_environment()
	_build_terrain()
	_setup_spawners()
	_build_hud()

	if multiplayer.is_server():
		Net.player_registered.connect(_on_player_registered)
		Net.player_left.connect(_on_player_left)
		_spawn_boss()
		if not Net.is_dedicated:
			_spawn_player(1, Net.my_name)
		print("[WORLD] Monde prêt (serveur).")
	else:
		Net.client_world_ready()
		print("[WORLD] Monde prêt (client), enregistrement...")

# ---------------------------------------------------------------- SPAWNERS

func _setup_spawners() -> void:
	players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node)
	projectiles_node = Node3D.new()
	projectiles_node.name = "Projectiles"
	add_child(projectiles_node)
	bosses_node = Node3D.new()
	bosses_node.name = "Bosses"
	add_child(bosses_node)

	player_spawner = MultiplayerSpawner.new()
	player_spawner.name = "PlayerSpawner"
	add_child(player_spawner)
	player_spawner.spawn_path = player_spawner.get_path_to(players_node)
	player_spawner.spawn_function = _spawn_player_node

	projectile_spawner = MultiplayerSpawner.new()
	projectile_spawner.name = "ProjectileSpawner"
	add_child(projectile_spawner)
	projectile_spawner.spawn_path = projectile_spawner.get_path_to(projectiles_node)
	projectile_spawner.spawn_function = _spawn_projectile_node

	boss_spawner = MultiplayerSpawner.new()
	boss_spawner.name = "BossSpawner"
	add_child(boss_spawner)
	boss_spawner.spawn_path = boss_spawner.get_path_to(bosses_node)
	boss_spawner.spawn_function = _spawn_boss_node

# Exécutées sur TOUS les pairs avec les mêmes données → état identique
func _spawn_player_node(data: Variant) -> Node:
	var node := PlayerScene.instantiate()
	node.name = str(data["id"])
	node.player_name = data["name"]
	node.position = data["pos"]
	return node

func _spawn_projectile_node(data: Variant) -> Node:
	var node := ProjectileScene.instantiate()
	node.name = "P%d" % data["n"]
	node.setup(data)
	return node

func _spawn_boss_node(data: Variant) -> Node:
	var node := BossScene.instantiate()
	node.name = "Boss%d" % data["n"]
	node.position = data["pos"]
	return node

# ---------------------------------------------------------------- SERVEUR

func _on_player_registered(id: int, info: Dictionary) -> void:
	_spawn_player(id, info["name"])
	rpc("toast", "✨ %s entre dans le monde" % info["name"])
	# Snapshot des PV pour le nouveau pair : les RPC sync_* passés ne lui sont
	# jamais parvenus (il verrait boss et joueurs blessés à PV pleins). Petit
	# délai pour laisser la réplication des spawns atteindre son monde.
	get_tree().create_timer(1.0).timeout.connect(func():
		if not is_inside_tree() or not Net.players.has(id):
			return
		for pid in player_hp:
			if pid != id:
				rpc_id(id, "sync_hp", pid, player_hp[pid])
		for b in get_tree().get_nodes_in_group("boss"):
			rpc_id(id, "sync_boss_hp", String(b.name), b.hp)
	)

func _on_player_left(id: int) -> void:
	var node := players_node.get_node_or_null(str(id))
	if node:
		node.queue_free()
	player_hp.erase(id)
	_spell_cd.erase(id)
	_gcd_until.erase(id)
	_melee_last.erase(id)
	_buffs.erase(id)
	_invuln_until.erase(id)

func _spawn_player(id: int, pname: String) -> void:
	player_hp[id] = 100
	player_spawner.spawn({ "id": id, "name": pname, "pos": _spawn_pos() })

func _spawn_pos() -> Vector3:
	var ang := randf() * TAU
	return Vector3(cos(ang) * SPAWN_RADIUS, 0.2, sin(ang) * SPAWN_RADIUS)

func _spawn_boss() -> void:
	_boss_counter += 1
	boss_spawner.spawn({ "n": _boss_counter, "pos": BOSS_ARENA })
	rpc("toast", "❄ Le Gardien de Givre rôde près du cercle de pierres...")

func resolve_target_node(kind: String, target_name: String) -> Node3D:
	if kind == "player":
		return players_node.get_node_or_null(target_name)
	if kind == "boss":
		return bosses_node.get_node_or_null(target_name)
	return null

# Requête de sort type WoW : le client demande, le serveur VALIDE TOUT
# (slot, cible, portée, cooldown, GCD) puis exécute.
@rpc("any_peer", "call_local", "reliable")
func request_spell(element: String, slot: int, target_kind: String, target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var caster := players_node.get_node_or_null(str(sender))
	if caster == null:
		return
	# L'élément vient du RPC, pas de caster.sync_element : si la magie change
	# entre le début et la fin d'une incantation (ex: déblocage auto pendant
	# le cast), le serveur lancerait sinon le MAUVAIS sort. On valide juste
	# qu'il est bien débloqué pour ce joueur.
	if element not in Net.players.get(sender, {}).get("unlocked", []):
		return
	var spells: Array = SpellData.get_spells(element)
	if slot < 0 or slot >= spells.size():
		return
	var spell: Dictionary = spells[slot]
	var now := Time.get_ticks_msec()

	if _gcd_until.get(sender, 0) > now:
		return
	var cds: Dictionary = _spell_cd.get(sender, {})
	# 150 ms de tolérance : le client pose son CD à l'envoi, le serveur à la
	# réception — sans marge, la latence ferait rejeter des sorts légitimes.
	if cds.get(spell["id"], 0) - 150 > now:
		return

	var target: Node3D = null
	if spell["kind"] == "bolt":
		target = resolve_target_node(target_kind, target_name)
		if target == null or target == caster:
			return
		if target.is_in_group("boss") and target.hp <= 0:
			return
		if caster.global_position.distance_to(target.global_position) > float(spell["range"]) + RANGE_SLACK:
			return

	cds[spell["id"]] = now + int(float(spell["cooldown"]) * 1000.0)
	_spell_cd[sender] = cds
	# GCD serveur uniquement pour les sorts instantanés : pour un sort à
	# incantation, le client a déjà consommé son GCD au DÉBUT du cast (~2s
	# avant que ce RPC n'arrive) — le re-poser ici mangerait silencieusement
	# l'instantané enchaîné juste après la fin de l'incantation.
	if float(spell["cast_time"]) <= 0.0:
		_gcd_until[sender] = now + GCD_MS
	print("[SPELL] joueur %d lance %s (%s)" % [sender, spell["id"], element])

	match String(spell["kind"]):
		"bolt":
			server_spawn_bolt(
				caster.global_position + Vector3.UP * 1.2,
				element, int(spell["damage"]),
				target_kind, target_name, sender,
				{ "slow": float(spell.get("slow", 0.0)), "slow_duration": float(spell.get("slow_duration", 0.0)) }
			)
		"nova":
			var radius := float(spell["range"])
			rpc("fx_nova", caster.global_position, element, radius)
			for p in get_tree().get_nodes_in_group("players"):
				if p != caster and p.global_position.distance_to(caster.global_position) <= radius:
					server_handle_hit(p, int(spell["damage"]), element, sender)
			for b in get_tree().get_nodes_in_group("boss"):
				if b.global_position.distance_to(caster.global_position) <= radius:
					server_handle_hit(b, int(spell["damage"]), element, sender)
		"self_buff":
			var dur := float(spell.get("buff_duration", 5.0))
			var buffs: Dictionary = _buffs.get(sender, {})
			buffs["frost_armor_until"] = now + int(dur * 1000.0)
			_buffs[sender] = buffs
			rpc("fx_buff", sender, dur)

# Coup d'épée type Elden Ring : le serveur valide la cadence puis touche
# tout ennemi dans la portée ET dans l'arc frontal du lanceur.
# L'épée porte l'élément actif → la roue des contres s'applique aussi en mêlée.
@rpc("any_peer", "call_local", "reliable")
func request_melee(element: String, step: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var caster := players_node.get_node_or_null(str(sender))
	if caster == null:
		return
	if step < 0 or step >= MELEE_DAMAGE.size():
		return
	if element not in Net.players.get(sender, {}).get("unlocked", []):
		return
	var now := Time.get_ticks_msec()
	if _melee_last.get(sender, 0) + MELEE_MIN_INTERVAL_MS > now:
		return
	_melee_last[sender] = now
	rpc("fx_melee", sender, step)

	var facing: Vector3 = -caster.global_transform.basis.z
	facing.y = 0
	facing = facing.normalized()
	var targets: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p != caster:
			targets.append(p)
	for b in get_tree().get_nodes_in_group("boss"):
		targets.append(b)
	for t in targets:
		var to: Vector3 = t.global_position - caster.global_position
		to.y = 0
		var d := to.length()
		if d > MELEE_RANGE or d < 0.01:
			continue
		if facing.angle_to(to.normalized()) <= deg_to_rad(MELEE_ARC_DEG * 0.5):
			server_handle_hit(t, MELEE_DAMAGE[step], element, sender)

# Spawn d'un projectile autoguidé — utilisé par les joueurs ET le boss
func server_spawn_bolt(from: Vector3, element: String, damage: int, target_kind: String, target_name: String, shooter: int, extra := {}) -> void:
	if not multiplayer.is_server():
		return
	var target := resolve_target_node(target_kind, target_name)
	if target == null:
		return
	var dir := (target.global_position + Vector3.UP * 1.1 - from).normalized()
	_projectile_counter += 1
	projectile_spawner.spawn({
		"n": _projectile_counter,
		"pos": from + dir * 0.7,
		"dir": dir,
		"element": element,
		"damage": damage,
		"shooter": shooter,
		"target_kind": target_kind,
		"target_name": target_name,
		"extra": extra,
	})

# Point d'entrée unique des dégâts — projectiles, novas, mêlée du boss
func server_handle_hit(target: Node3D, base_damage: int, element: String, shooter: int, extra := {}) -> void:
	if not multiplayer.is_server():
		return
	if target.is_in_group("boss"):
		_hit_boss(target, base_damage, element, shooter, extra)
	elif target.is_in_group("players"):
		_hit_player(target, base_damage, element, shooter, extra)

func _hit_boss(boss: Node3D, base_damage: int, element: String, shooter: int, extra := {}) -> void:
	if boss.hp <= 0:
		return
	var mult: float = ElementData.get_multiplier(element, boss.element)
	var dmg := int(round(base_damage * mult))
	boss.hp -= dmg
	if shooter > 0:
		boss.contributors[shooter] = true
	if float(extra.get("slow", 0.0)) > 0.0:
		boss.apply_slow(float(extra["slow"]), float(extra["slow_duration"]))
	print("[HIT] Boss -%d (%s x%.1f) par joueur %d → %d PV" % [dmg, element, mult, shooter, boss.hp])
	rpc("fx_damage_number", boss.global_position + Vector3.UP * 3.2, dmg, mult)
	rpc("sync_boss_hp", String(boss.name), boss.hp)
	if boss.hp <= 0:
		_boss_killed(boss)

func _boss_killed(boss: Node3D) -> void:
	rpc("toast", "💀 LE GARDIEN DE GIVRE EST TOMBÉ !")
	for id in boss.contributors:
		if Net.players.has(id) and not "ice" in Net.players[id]["unlocked"]:
			Net.players[id]["unlocked"].append("ice")
			rpc_id(id, "client_grant_element", "ice")
	boss.queue_free()
	get_tree().create_timer(BOSS_RESPAWN_DELAY).timeout.connect(func():
		if is_inside_tree() and multiplayer.is_server():
			_spawn_boss()
	)

func _hit_player(target: Node3D, base_damage: int, element: String, shooter: int, extra := {}) -> void:
	var id := str(target.name).to_int()
	if shooter == id:
		return
	# Joueur déconnecté ce frame (node pas encore libéré) : ne pas ressusciter
	# son entrée player_hp via le .get(id, 100) plus bas.
	if not player_hp.has(id):
		return
	var now := Time.get_ticks_msec()
	if now < _invuln_until.get(id, 0):
		return
	var mult: float = ElementData.get_multiplier(element, target.sync_element)
	var dmg := int(round(base_damage * mult))
	if _buffs.get(id, {}).get("frost_armor_until", 0) > now:
		dmg = int(round(dmg * 0.7))  # Armure de givre : -30% dégâts
	player_hp[id] = player_hp.get(id, 100) - dmg
	print("[HIT] joueur %d -%d (%s x%.1f) par %d → %d PV" % [id, dmg, element, mult, shooter, player_hp[id]])
	rpc("fx_damage_number", target.global_position + Vector3.UP * 2.2, dmg, mult)
	rpc("sync_hp", id, player_hp[id])
	if player_hp[id] <= 0:
		_kill_player(id, shooter, element)
	elif float(extra.get("slow", 0.0)) > 0.0:
		rpc_id(id, "client_apply_slow", id, float(extra["slow"]), float(extra["slow_duration"]))

func _kill_player(victim: int, killer: int, element: String) -> void:
	var vname := Net.player_display_name(victim)
	var kname := Net.player_display_name(killer)
	if killer == 0:
		rpc("toast", "❄ Le Gardien de Givre a gelé %s" % vname)
	else:
		rpc("toast", "⚔ %s a vaporisé %s (%s %s)" % [kname, vname, ElementData.emoji(element), ElementData.display_name(element)])
	_invuln_until[victim] = Time.get_ticks_msec() + RESPAWN_INVULN_MS
	player_hp[victim] = 100
	rpc("sync_hp", victim, 100)
	rpc("client_respawn", victim, _spawn_pos())
	# Dissipe les projectiles encore en vol vers la victime : sinon ils la
	# poursuivraient jusqu'à son point de respawn à travers toute la carte.
	for proj in projectiles_node.get_children():
		if proj.target_kind == "player" and proj.target_name == str(victim):
			proj.queue_free()

# Attaque de mêlée du boss : touche tous les joueurs proches
func server_boss_melee(boss: Node3D) -> void:
	if not multiplayer.is_server():
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.global_position.distance_to(boss.global_position) <= 3.2:
			server_handle_hit(p, boss.ATTACK_DAMAGE, boss.element, 0)

# ---------------------------------------------------------------- RPC CLIENTS

@rpc("authority", "call_local", "reliable")
func sync_hp(id: int, value: int) -> void:
	var node := players_node.get_node_or_null(str(id))
	if node:
		node.set_hp_display(value)

@rpc("authority", "call_local", "reliable")
func sync_boss_hp(boss_name: String, value: int) -> void:
	var node := bosses_node.get_node_or_null(boss_name)
	if node:
		node.set_hp_display(value)

@rpc("authority", "call_local", "reliable")
func client_respawn(id: int, pos: Vector3) -> void:
	var node := players_node.get_node_or_null(str(id))
	if node and node.is_multiplayer_authority():
		node.global_position = pos
		node.on_respawned()

@rpc("authority", "call_local", "reliable")
func client_apply_slow(id: int, pct: float, duration: float) -> void:
	var node := players_node.get_node_or_null(str(id))
	if node and node.is_multiplayer_authority():
		node.apply_slow(pct, duration)

@rpc("authority", "call_local", "reliable")
func client_grant_element(element: String) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			p.grant_element(element)
	show_toast("🔮 NOUVELLE MAGIE DÉBLOQUÉE : %s %s !" % [ElementData.display_name(element), ElementData.emoji(element)])

@rpc("authority", "call_local", "reliable")
func toast(msg: String) -> void:
	show_toast(msg)

@rpc("authority", "call_local", "reliable")
func fx_damage_number(pos: Vector3, amount: int, mult: float) -> void:
	var label := Label3D.new()
	label.text = str(amount)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	if mult > 1.0:
		label.text += " !"
		label.font_size = 96
		label.modulate = Color(1.0, 0.55, 0.2)
	elif mult < 1.0:
		label.font_size = 48
		label.modulate = Color(0.6, 0.65, 0.8)
	else:
		label.font_size = 64
		label.modulate = Color.WHITE
	label.position = pos
	add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", pos.y + 1.6, 0.8)
	tw.tween_property(label, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(label.queue_free)

@rpc("authority", "call_local", "reliable")
func fx_nova(pos: Vector3, element: String, radius: float) -> void:
	var c: Color = ElementData.get_color(element)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(c.r, c.g, c.b, 0.8)
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.0
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = mat
	ring.position = pos + Vector3(0, 0.3, 0)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.45)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)

@rpc("authority", "call_local", "reliable")
func fx_buff(id: int, duration: float) -> void:
	var node := players_node.get_node_or_null(str(id))
	if node:
		node.show_buff_bubble(duration)

# Diffuse l'animation d'un coup d'épée à tous les pairs
@rpc("authority", "call_local", "reliable")
func fx_melee(id: int, step: int) -> void:
	var node := players_node.get_node_or_null(str(id))
	if node:
		node.play_melee_anim(step)

# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	var help := Label.new()
	help.text = "ZQSD bouger  •  Souris caméra  •  Clic gauche attaque (recliquer = combo)  •  Tab verrouiller la cible  •  1-3 sorts  •  R magie  •  Espace dash  •  Échap déverrouiller/souris"
	help.position = Vector2(16, 12)
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 4)
	hud.add_child(help)

	var goal := Label.new()
	goal.text = "🎯 Objectif : tuez le Gardien de Givre (cercle de pierres au nord-est) pour débloquer la GLACE"
	goal.position = Vector2(16, 36)
	goal.add_theme_font_size_override("font_size", 13)
	goal.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.9))
	goal.add_theme_color_override("font_outline_color", Color.BLACK)
	goal.add_theme_constant_override("outline_size", 4)
	hud.add_child(goal)

	# --- Frame de cible (haut centre, comme WoW)
	target_frame = PanelContainer.new()
	target_frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_frame.offset_left = -190.0
	target_frame.offset_right = 190.0
	target_frame.offset_top = 64.0
	target_frame.visible = false
	hud.add_child(target_frame)

	var tf_box := VBoxContainer.new()
	tf_box.add_theme_constant_override("separation", 4)
	target_frame.add_child(tf_box)

	tf_name = Label.new()
	tf_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tf_name.add_theme_font_size_override("font_size", 18)
	tf_box.add_child(tf_name)

	tf_hp = ProgressBar.new()
	tf_hp.custom_minimum_size = Vector2(360, 16)
	tf_hp.show_percentage = false
	tf_box.add_child(tf_hp)

	# --- Barre d'incantation (cast bar)
	cast_bar = ProgressBar.new()
	cast_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cast_bar.offset_left = -160.0
	cast_bar.offset_right = 160.0
	cast_bar.offset_top = -160.0
	cast_bar.offset_bottom = -142.0
	cast_bar.min_value = 0.0
	cast_bar.max_value = 1.0
	cast_bar.show_percentage = false
	cast_bar.visible = false
	hud.add_child(cast_bar)

	cast_label = Label.new()
	cast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cast_label.offset_left = -160.0
	cast_label.offset_right = 160.0
	cast_label.offset_top = -184.0
	cast_label.offset_bottom = -162.0
	cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cast_label.add_theme_font_size_override("font_size", 14)
	cast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cast_label.add_theme_constant_override("outline_size", 4)
	cast_label.visible = false
	hud.add_child(cast_label)

	# --- Statut (PV + magies)
	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_label.offset_top = -136.0
	status_label.offset_bottom = -108.0
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(status_label)

	# --- Barre de sorts (bas centre)
	spell_bar = HBoxContainer.new()
	spell_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spell_bar.offset_top = -100.0
	spell_bar.offset_bottom = -28.0
	spell_bar.offset_left = -260.0
	spell_bar.offset_right = 260.0
	spell_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	spell_bar.add_theme_constant_override("separation", 10)
	hud.add_child(spell_bar)

	# --- Toast (annonces)
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 90.0
	toast_label.offset_bottom = 140.0
	toast_label.offset_left = -400.0
	toast_label.offset_right = 400.0
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 26)
	toast_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 8)
	toast_label.text = ""
	hud.add_child(toast_label)

func _rebuild_spell_bar() -> void:
	for b in _spell_buttons:
		b.queue_free()
	_spell_buttons.clear()
	_btn_base.clear()
	_spells_cached = SpellData.get_spells(_hud_element)
	for i in _spells_cached.size():
		var spell: Dictionary = _spells_cached[i]
		var base := "[%d] %s %s" % [i + 1, spell["icon"], spell["name"]]
		var b := Button.new()
		b.text = base
		b.custom_minimum_size = Vector2(150, 58)
		b.focus_mode = Control.FOCUS_NONE
		var slot := i
		b.pressed.connect(func():
			if _local_player and is_instance_valid(_local_player):
				_local_player._try_cast_spell(slot)
		)
		spell_bar.add_child(b)
		_spell_buttons.append(b)
		_btn_base.append(base)

func show_toast(msg: String) -> void:
	if toast_label == null:
		print("[TOAST] ", msg)
		return
	toast_label.text = msg
	_toast_timer = get_tree().create_timer(3.5)
	var current := msg
	_toast_timer.timeout.connect(func():
		if toast_label.text == current:
			toast_label.text = ""
	)

func _process(_delta: float) -> void:
	if status_label == null:
		return
	if _local_player == null or not is_instance_valid(_local_player):
		_local_player = null
		for p in get_tree().get_nodes_in_group("players"):
			if p.is_multiplayer_authority():
				_local_player = p
				break
	if _local_player == null:
		status_label.text = "Connexion au monde..."
		return

	# Statut : PV + magies débloquées
	var parts: Array[String] = []
	for e in _local_player.unlocked:
		if e == _local_player.sync_element:
			parts.append("[ %s %s ]" % [ElementData.emoji(e), ElementData.display_name(e)])
		else:
			parts.append("%s %s" % [ElementData.emoji(e), ElementData.display_name(e)])
	var locked_hint := ""
	if not "ice" in _local_player.unlocked:
		locked_hint = "   🔒 GLACE (boss PvE)"
	status_label.text = "❤ %d      %s%s" % [_local_player.hp, "   ".join(parts), locked_hint]

	# Barre de sorts : reconstruite si la magie active change, cooldowns à jour
	if _hud_element != _local_player.sync_element:
		_hud_element = _local_player.sync_element
		_rebuild_spell_bar()
	for i in _spell_buttons.size():
		var b: Button = _spell_buttons[i]
		var spell: Dictionary = _spells_cached[i]
		var rem: float = maxf(_local_player.cd_remaining(spell["id"]), _local_player.gcd_remaining())
		if rem > 0.05:
			b.disabled = true
			b.text = "%s\n%.1f s" % [_btn_base[i], rem]
		else:
			b.disabled = false
			b.text = _btn_base[i]

	# Cast bar
	if _local_player.is_casting():
		cast_bar.visible = true
		cast_label.visible = true
		cast_bar.value = _local_player.cast_progress()
		cast_label.text = _local_player.cast_name()
	else:
		cast_bar.visible = false
		cast_label.visible = false

	# Frame de cible
	var t: Node3D = _local_player.current_target
	if t != null and is_instance_valid(t):
		target_frame.visible = true
		if t.is_in_group("boss"):
			tf_name.text = "%s  Gardien de Givre" % ElementData.emoji(t.element)
			tf_hp.max_value = t.MAX_HP
			tf_hp.value = t.display_hp
		else:
			tf_name.text = "%s  %s" % [ElementData.emoji(t.sync_element), t.player_name]
			tf_hp.max_value = 100
			tf_hp.value = t.hp
	else:
		target_frame.visible = false

# ---------------------------------------------------------------- MONDE 3D

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.08, 0.32)
	sky_mat.sky_horizon_color = Color(0.85, 0.5, 0.62)
	sky_mat.ground_bottom_color = Color(0.1, 0.07, 0.16)
	sky_mat.ground_horizon_color = Color(0.55, 0.35, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.6, 0.85)
	env.fog_density = 0.012
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.85, 0.7)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, -30, 0)
	add_child(sun)

func _build_terrain() -> void:
	# Sol
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.16, 0.3, 0.2)
	ground_mat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_HALF * 2, WORLD_HALF * 2)
	var ground_mesh := MeshInstance3D.new()
	ground_mesh.mesh = plane
	ground_mesh.material_override = ground_mat
	add_child(ground_mesh)

	var ground_body := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(WORLD_HALF * 2, 1.0, WORLD_HALF * 2)
	ground_col.shape = ground_shape
	ground_col.position = Vector3(0, -0.5, 0)
	ground_body.add_child(ground_col)
	add_child(ground_body)

	# Végétation déterministe : même seed → même monde sur tous les pairs
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED

	for i in range(70):
		var pos := Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-100, 100))
		if pos.length() < 10.0 or pos.distance_to(BOSS_ARENA) < 14.0:
			continue
		_add_tree(pos, rng)

	for i in range(26):
		var pos := Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-100, 100))
		if pos.length() < 8.0 or pos.distance_to(BOSS_ARENA) < 12.0:
			continue
		_add_rock(pos, rng)

	_build_boss_arena()
	_add_fairy_lights(rng)

func _add_tree(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var tree := Node3D.new()
	tree.position = pos
	add_child(tree)

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.24, 0.16)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28
	trunk.bottom_radius = 0.4
	trunk.height = 3.2
	var trunk_mesh := MeshInstance3D.new()
	trunk_mesh.mesh = trunk
	trunk_mesh.material_override = trunk_mat
	trunk_mesh.position = Vector3(0, 1.6, 0)
	tree.add_child(trunk_mesh)

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.15 + rng.randf() * 0.15, 0.4 + rng.randf() * 0.3, 0.3 + rng.randf() * 0.25)
	var leaves := SphereMesh.new()
	var r := 1.6 + rng.randf() * 0.8
	leaves.radius = r
	leaves.height = r * 2.0
	var leaves_mesh := MeshInstance3D.new()
	leaves_mesh.mesh = leaves
	leaves_mesh.material_override = leaf_mat
	leaves_mesh.position = Vector3(0, 3.8, 0)
	tree.add_child(leaves_mesh)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 3.2
	col.shape = shape
	col.position = Vector3(0, 1.6, 0)
	body.add_child(col)
	tree.add_child(body)

func _add_rock(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var rock := Node3D.new()
	rock.position = pos
	add_child(rock)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.52)
	mat.roughness = 0.9
	var s := 0.6 + rng.randf() * 1.0
	var mesh := SphereMesh.new()
	mesh.radius = s
	mesh.height = s * 1.4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, s * 0.4, 0)
	rock.add_child(mi)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = s * 0.9
	col.shape = shape
	col.position = Vector3(0, s * 0.4, 0)
	body.add_child(col)
	rock.add_child(body)

func _build_boss_arena() -> void:
	# Cercle de pierres dressées autour de l'antre du Gardien
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.45, 0.6)
	mat.roughness = 0.7
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.55, 0.85, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.55, 0.85, 1.0)
	glow_mat.emission_energy_multiplier = 2.0

	for i in range(8):
		var ang := TAU * i / 8.0
		var pos := BOSS_ARENA + Vector3(cos(ang) * 9.0, 0, sin(ang) * 9.0)

		var pillar := BoxMesh.new()
		pillar.size = Vector3(1.2, 4.5, 1.2)
		var mi := MeshInstance3D.new()
		mi.mesh = pillar
		mi.material_override = mat
		mi.position = pos + Vector3(0, 2.25, 0)
		add_child(mi)

		var orb_mesh := SphereMesh.new()
		orb_mesh.radius = 0.3
		orb_mesh.height = 0.6
		var orb := MeshInstance3D.new()
		orb.mesh = orb_mesh
		orb.material_override = glow_mat
		orb.position = pos + Vector3(0, 4.9, 0)
		add_child(orb)

		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.2, 4.5, 1.2)
		col.shape = shape
		col.position = pos + Vector3(0, 2.25, 0)
		body.add_child(col)
		add_child(body)

func _add_fairy_lights(rng: RandomNumberGenerator) -> void:
	# Orbes féériques flottantes — pure ambiance
	var colors := [Color(0.8, 0.6, 1.0), Color(0.5, 0.9, 1.0), Color(1.0, 0.75, 0.9)]
	for i in range(14):
		var c: Color = colors[i % colors.size()]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 3.0
		var mesh := SphereMesh.new()
		mesh.radius = 0.15
		mesh.height = 0.3
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(rng.randf_range(-90, 90), 1.5 + rng.randf() * 3.0, rng.randf_range(-90, 90))
		add_child(mi)

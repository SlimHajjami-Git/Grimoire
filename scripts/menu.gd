extends Control
# Menu principal — Héberger ou Rejoindre par IP.
# Args spéciaux (après "--" en ligne de commande) :
#   --server          → serveur dédié headless, sans joueur local
#   --autojoin=IP     → rejoint automatiquement (utilisé pour les tests)

var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label

func _ready() -> void:
	var uargs := OS.get_cmdline_user_args()
	for a in uargs:
		if a == "--server":
			print("[MENU] Mode serveur dédié")
			var err := Net.host("SERVER", true)
			if err != OK:
				# Sans ce check, un port déjà pris donnerait un serveur fantôme
				# qui boote le monde mais n'écoute sur rien.
				printerr("[MENU] Échec du démarrage serveur : ", Net.last_error)
				get_tree().quit(1)
				return
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
		if a == "--vfxshow":
			get_tree().change_scene_to_file.call_deferred("res://scenes/vfxshow.tscn")
			return
		if a == "--phototest":
			# Mode dev : héberge en solo, le joueur fait des captures d'écran
			Net.host("PhotoBot")
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
		if a.begins_with("--autojoin"):
			var ip := "127.0.0.1"
			if "=" in a:
				ip = a.split("=")[1]
			print("[MENU] Autojoin vers ", ip)
			Net.join(ip, "Bot%d" % (randi() % 1000))
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
	_build_ui()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "GRIMOIRE ONLINE"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Survie magique — la magie se gagne en PvE, se défend en PvP"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_spacer(10))

	name_edit = LineEdit.new()
	name_edit.text = "Mage%d" % (randi() % 999)
	name_edit.placeholder_text = "Ton nom de mage"
	name_edit.custom_minimum_size = Vector2(340, 40)
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_edit)

	var host_btn := Button.new()
	host_btn.text = "⚔  HÉBERGER UNE PARTIE"
	host_btn.custom_minimum_size = Vector2(340, 48)
	host_btn.pressed.connect(_on_host)
	box.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)

	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "IP du serveur"
	ip_edit.custom_minimum_size = Vector2(220, 40)
	join_row.add_child(ip_edit)

	var join_btn := Button.new()
	join_btn.text = "REJOINDRE"
	join_btn.custom_minimum_size = Vector2(112, 40)
	join_btn.pressed.connect(_on_join)
	join_row.add_child(join_btn)

	status_label = Label.new()
	status_label.text = Net.last_error
	status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)

	var help := Label.new()
	help.text = "Pour jouer à deux sur le même PC : lance le jeu 2 fois\n(une fenêtre héberge, l'autre rejoint 127.0.0.1)"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.55, 0.5, 0.65))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _on_host() -> void:
	var err := Net.host(_player_name())
	if err != OK:
		status_label.text = Net.last_error
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")

func _on_join() -> void:
	var err := Net.join(ip_edit.text.strip_edges(), _player_name())
	if err != OK:
		status_label.text = Net.last_error
		return
	status_label.text = "Connexion..."
	get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")

func _player_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Mage"

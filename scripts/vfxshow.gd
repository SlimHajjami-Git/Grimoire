extends Node3D
# Vitrine VFX dev-only : montre les effets de sorts en gros plan sur fond
# neutre, sans le reste du jeu. Lancée via menu --vfxshow, capture des PNG.

func _ready() -> void:
	# Environnement sombre et neutre pour bien voir les effets lumineux
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.10, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Sol mat pour recevoir lumière + ombres d'impact
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.18, 0.18, 0.22)
	ground.material_override = gmat
	ground.position.y = -1.5
	add_child(ground)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.3, 2.4)
	cam.current = true
	add_child(cam)

	if "--vfxshow" in OS.get_cmdline_user_args():
		_run()

func _run() -> void:
	# 1 : orbe de FEU en gros plan
	var fire := Vfx.make_orb(ElementData.get_color("fire"), 0.5)
	add_child(fire)
	add_child(Vfx.make_trail(ElementData.get_color("fire")))
	await get_tree().create_timer(0.6).timeout
	await _snap("vfx_1_orbe_feu")
	fire.queue_free()

	# 2 : orbe de GLACE
	var ice := Vfx.make_orb(ElementData.get_color("ice"), 0.5)
	add_child(ice)
	await get_tree().create_timer(0.6).timeout
	await _snap("vfx_2_orbe_glace")
	ice.queue_free()

	# 3 : orbe de FOUDRE (montre que la palette s'adapte à tout élément)
	var bolt := Vfx.make_orb(ElementData.get_color("lightning"), 0.5)
	add_child(bolt)
	await get_tree().create_timer(0.6).timeout
	await _snap("vfx_3_orbe_foudre")
	bolt.queue_free()

	# 4 : explosion d'impact de feu
	Vfx.impact_burst(self, Vector3(0, 0, 0), ElementData.get_color("fire"), 1.3)
	await get_tree().create_timer(0.12).timeout
	await _snap("vfx_4_impact")
	get_tree().quit()

func _snap(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Users/Mega-PC/Desktop/GRIMOIRE_ONLINE/tools/%s.png" % file_name)
	print("[VFX] ", file_name)

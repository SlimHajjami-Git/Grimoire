extends Node
# Autoload Vfx — effets visuels générés par code (particules, flashs,
# télégraphes de zone). Tout est éphémère et s'auto-détruit.
# En headless (serveur dédié), ces nodes existent mais ne rendent rien : safe.

# Explosion d'impact : gerbe de particules + flash lumineux, s'auto-détruit.
func impact_burst(parent: Node, pos: Vector3, color: Color, size := 1.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.top_level = true
	parent.add_child(root)
	root.global_position = pos

	var p := _make_particles(color, 0.06 * size)
	p.amount = 24
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.45
	var mat := p.process_material as ParticleProcessMaterial
	mat.initial_velocity_min = 2.5 * size
	mat.initial_velocity_max = 5.0 * size
	mat.spread = 180.0
	root.add_child(p)
	p.emitting = true

	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 5.0 * size
	light.light_energy = 2.5
	root.add_child(light)
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)

	root.get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(root):
			root.queue_free()
	)

# Traînée continue derrière un projectile (à ajouter comme enfant).
func make_trail(color: Color) -> GPUParticles3D:
	var p := _make_particles(color, 0.05)
	p.amount = 40
	p.lifetime = 0.5
	p.local_coords = false  # les particules restent dans le monde → traînée
	var mat := p.process_material as ParticleProcessMaterial
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.4
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	p.emitting = true
	return p

# Lueur de canalisation entre les mains du lanceur (à libérer à la fin).
func make_cast_glow(color: Color) -> Node3D:
	var root := Node3D.new()

	var p := _make_particles(color, 0.045)
	p.amount = 26
	p.lifetime = 0.6
	var mat := p.process_material as ParticleProcessMaterial
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.35
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.2
	mat.gravity = Vector3(0, 0.6, 0)
	p.emitting = true
	root.add_child(p)

	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 2.2
	light.light_energy = 0.8  # discret : le bloom amplifie déjà beaucoup
	root.add_child(light)
	return root

# Télégraphe de frappe au sol : disque + anneau qui pulse pendant `delay`.
# C'est l'avertissement que l'ennemi peut ESQUIVER — il doit être lisible.
func strike_telegraph(parent: Node, pos: Vector3, radius: float, color: Color, delay: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.top_level = true
	parent.add_child(root)
	root.global_position = pos

	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.04
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = disc_mat
	root.add_child(disc)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = color
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 2.0
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = maxf(radius - 0.12, 0.1)
	ring_mesh.outer_radius = radius
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_mat
	ring.position.y = 0.06
	root.add_child(ring)

	# Pulsation d'urgence : l'alpha du disque monte jusqu'à l'impact
	var tw := root.create_tween()
	tw.tween_property(disc_mat, "albedo_color:a", 0.5, delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	root.get_tree().create_timer(delay + 0.1).timeout.connect(func():
		if is_instance_valid(root):
			root.queue_free()
	)

# ---------------------------------------------------------------- interne

func _make_particles(color: Color, particle_size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.gravity = Vector3(0, -1.5, 0)
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.color = color
	p.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = particle_size
	mesh.height = particle_size * 2.0
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.albedo_color = color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 2.5
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh
	return p

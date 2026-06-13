extends Node
# Autoload Vfx — effets visuels shader-driven, tout généré par code.
# Textures procédurales (bruit + dégradés radiaux), pas de fichiers binaires.
# En headless (serveur dédié) les nodes existent mais ne rendent rien : safe.

const OrbShader := preload("res://assets/shaders/energy_orb.gdshader")
const FlashShader := preload("res://assets/shaders/flash.gdshader")

var _noise_tex: NoiseTexture2D       # turbulence du noyau de sort
var _soft_dot: GradientTexture2D     # sprite doux pour particules
var _scorch_tex: GradientTexture2D   # décalque de brûlure au sol

func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.035
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 256
	_noise_tex.height = 256
	_noise_tex.seamless = true
	_noise_tex.noise = noise

	_soft_dot = _radial_gradient([
		[0.0, Color(1, 1, 1, 1)],
		[0.5, Color(1, 1, 1, 0.55)],
		[1.0, Color(1, 1, 1, 0.0)],
	])
	_scorch_tex = _radial_gradient([
		[0.0, Color(0.05, 0.04, 0.03, 0.85)],
		[0.7, Color(0.05, 0.04, 0.03, 0.6)],
		[1.0, Color(0.05, 0.04, 0.03, 0.0)],
	])

# Palette chaud/moyen/froid dérivée de la couleur d'élément (généralise feu,
# glace, foudre… : cœur clair, milieu = teinte, bord = version sombre).
# On garde de la saturation dans le "chaud" pour que la teinte d'élément
# reste lisible même avec le bloom (sinon tout vire au blanc).
func palette(base: Color) -> Array:
	return [
		base.lerp(Color(1, 1, 1), 0.55),
		base.lerp(Color(1, 1, 1), 0.08),
		base.darkened(0.6),
	]

# Matériau du noyau d'un sort (sphère animée). Réutilisable projectile/cast.
func orb_material(color: Color, intensity := 1.35) -> ShaderMaterial:
	var pal := palette(color)
	var mat := ShaderMaterial.new()
	mat.shader = OrbShader
	mat.set_shader_parameter("noise_tex", _noise_tex)
	mat.set_shader_parameter("color_hot", pal[0])
	mat.set_shader_parameter("color_mid", pal[1])
	mat.set_shader_parameter("color_cool", pal[2])
	mat.set_shader_parameter("intensity", intensity)
	return mat

# Noyau de sort prêt à l'emploi : sphère shader + lueur. Renvoie le MeshInstance.
func make_orb(color: Color, radius := 0.28) -> MeshInstance3D:
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	var orb := MeshInstance3D.new()
	orb.mesh = sph
	orb.material_override = orb_material(color)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return orb

# Traînée de braises derrière un projectile (à ajouter comme enfant).
func make_trail(color: Color) -> GPUParticles3D:
	var p := _particles(color, 0.09, 44, 0.55)
	p.local_coords = false  # particules laissées dans le monde → traînée
	var mat := p.process_material as ParticleProcessMaterial
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.12
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.gravity = Vector3(0, 0.8, 0)
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.5
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	_add_size_fade(mat)
	p.emitting = true
	return p

# Lueur de canalisation entre les mains (à libérer à la fin de l'incantation).
func make_cast_glow(color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(make_orb(color, 0.13))

	var p := _particles(color, 0.06, 30, 0.7)
	var mat := p.process_material as ParticleProcessMaterial
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.32
	mat.direction = Vector3(0, 1, 0)
	mat.gravity = Vector3(0, 0.5, 0)
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.25
	_add_size_fade(mat)
	p.emitting = true
	root.add_child(p)

	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 2.4
	light.light_energy = 1.0
	root.add_child(light)
	return root

# Explosion d'impact : flash fresnel qui grossit + gerbe de braises + lumière.
func impact_burst(parent: Node, pos: Vector3, color: Color, size := 1.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.top_level = true
	parent.add_child(root)
	root.global_position = pos

	# Flash fresnel
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = FlashShader
	flash_mat.set_shader_parameter("color", color.lerp(Color(1, 1, 1), 0.4))
	flash_mat.set_shader_parameter("intensity", 2.4)
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.3 * size
	flash_mesh.height = 0.6 * size
	var flash := MeshInstance3D.new()
	flash.mesh = flash_mesh
	flash.material_override = flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flash)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 3.0 * size, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash_mat, "shader_parameter/intensity", 0.0, 0.35)

	# Gerbe de braises
	var p := _particles(color, 0.08 * size, 26, 0.5)
	p.one_shot = true
	p.explosiveness = 1.0
	var mat := p.process_material as ParticleProcessMaterial
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05
	mat.spread = 180.0
	mat.gravity = Vector3(0, -4.0, 0)
	mat.initial_velocity_min = 3.0 * size
	mat.initial_velocity_max = 6.0 * size
	_add_size_fade(mat)
	root.add_child(p)
	p.emitting = true

	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 5.0 * size
	light.light_energy = 3.0
	root.add_child(light)
	root.create_tween().tween_property(light, "light_energy", 0.0, 0.3)

	root.get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(root):
			root.queue_free()
	)

# Télégraphe de frappe au sol : disque + anneau qui pulse pendant `delay`,
# + décalque de brûlure persistant après l'impact. C'est l'avertissement
# ESQUIVABLE → il doit rester très lisible.
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
	ring_mesh.inner_radius = maxf(radius - 0.14, 0.1)
	ring_mesh.outer_radius = radius
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_mat
	ring.position.y = 0.06
	root.add_child(ring)

	var tw := root.create_tween()
	tw.tween_property(disc_mat, "albedo_color:a", 0.55, delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	root.get_tree().create_timer(delay + 0.1).timeout.connect(func():
		if is_instance_valid(root):
			root.queue_free()
	)

# Décalque de brûlure au sol qui s'estompe (après une frappe).
func scorch_mark(parent: Node, pos: Vector3, radius: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var decal := Decal.new()
	decal.top_level = true
	decal.texture_albedo = _scorch_tex
	decal.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	parent.add_child(decal)
	decal.global_position = pos + Vector3.UP * 0.5
	parent.get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(decal):
			decal.create_tween().tween_property(decal, "modulate", Color(1, 1, 1, 0), 4.0)
	)
	parent.get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(decal):
			decal.queue_free()
	)

# ---------------------------------------------------------------- interne

func _particles(color: Color, particle_size: float, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	var mat := ParticleProcessMaterial.new()
	mat.color = color.lerp(Color(1, 1, 1), 0.3)
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(particle_size, particle_size) * 2.0
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.albedo_texture = _soft_dot
	mesh_mat.albedo_color = color.lerp(Color(1, 1, 1), 0.3)
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 2.0
	mesh_mat.cast_shadow = false
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh
	return p

# Fait rétrécir + fondre les particules sur leur durée de vie.
func _add_size_fade(mat: ParticleProcessMaterial) -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	mat.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt

func _radial_gradient(stops: Array) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = []
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex

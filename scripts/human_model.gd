extends Node3D
# Humain procédural — tête, torse, bras, jambes, épée — avec animations par
# code (marche, idle, combos d'épée, pose d'incantation).
# Sera remplacé par un vrai modèle riggé (glTF/Mixamo) en phase art : l'API
# (build/set_tint/set_locomotion/play_melee/set_casting) restera identique.

var _speed := 0.0          # vitesse lissée (m/s) pour le cycle de marche
var _phase := 0.0          # phase du cycle de marche
var _busy_until := 0.0     # fin de l'anim d'attaque en cours
var _casting := false

var torso: MeshInstance3D
var head: MeshInstance3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var hip_l: Node3D
var hip_r: Node3D

var _tunic_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func build(tint: Color) -> void:
	_skin_mat = StandardMaterial3D.new()
	_skin_mat.albedo_color = Color(0.85, 0.66, 0.52)
	_skin_mat.roughness = 0.9

	_tunic_mat = StandardMaterial3D.new()
	_tunic_mat.roughness = 0.85

	var pants_mat := StandardMaterial3D.new()
	pants_mat.albedo_color = Color(0.22, 0.2, 0.26)
	pants_mat.roughness = 0.9

	# Torse (tunique)
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.46, 0.62, 0.26)
	torso = MeshInstance3D.new()
	torso.mesh = torso_mesh
	torso.material_override = _tunic_mat
	torso.position = Vector3(0, 1.25, 0)
	add_child(torso)

	# Tête
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.17
	head_mesh.height = 0.34
	head = MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = _skin_mat
	head.position = Vector3(0, 1.78, 0)
	add_child(head)

	# Yeux (face avant = -Z)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.1, 0.1, 0.15)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.025
		eye_mesh.height = 0.05
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.06, 1.81, -0.15)
		add_child(eye)

	# Bras (pivot à l'épaule pour pouvoir les balancer)
	shoulder_l = _make_limb(Vector3(-0.31, 1.5, 0), 0.07, 0.5, _tunic_mat)
	shoulder_r = _make_limb(Vector3(0.31, 1.5, 0), 0.07, 0.5, _tunic_mat)

	# Jambes (pivot à la hanche)
	hip_l = _make_limb(Vector3(-0.13, 1.0, 0), 0.085, 0.78, pants_mat)
	hip_r = _make_limb(Vector3(0.13, 1.0, 0), 0.085, 0.78, pants_mat)

	_build_sword()
	set_tint(tint)

func _make_limb(pos: Vector3, radius: float, length: float, mat: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, -length * 0.5, 0)
	pivot.add_child(mi)
	return pivot

func _build_sword() -> void:
	# Épée dans la main droite, lame vers le bas au repos
	var sword := Node3D.new()
	sword.position = Vector3(0, -0.52, 0)
	shoulder_r.add_child(sword)

	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.3, 0.2, 0.12)
	var grip := MeshInstance3D.new()
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.025
	grip_mesh.bottom_radius = 0.025
	grip_mesh.height = 0.16
	grip.mesh = grip_mesh
	grip.material_override = grip_mat
	sword.add_child(grip)

	var guard_mat := StandardMaterial3D.new()
	guard_mat.albedo_color = Color(0.55, 0.5, 0.35)
	guard_mat.metallic = 0.6
	var guard := MeshInstance3D.new()
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.2, 0.04, 0.06)
	guard.mesh = guard_mesh
	guard.material_override = guard_mat
	guard.position = Vector3(0, -0.1, 0)
	sword.add_child(guard)

	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.8, 0.82, 0.9)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.25
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.05, 0.75, 0.12)
	blade.mesh = blade_mesh
	blade.material_override = blade_mat
	blade.position = Vector3(0, -0.5, 0)
	sword.add_child(blade)

func set_tint(c: Color) -> void:
	if _tunic_mat:
		_tunic_mat.albedo_color = c.lerp(Color(0.3, 0.28, 0.34), 0.55)

func set_locomotion(speed: float) -> void:
	_speed = lerpf(_speed, speed, 0.25)

func set_casting(on: bool) -> void:
	_casting = on

func play_melee(step: int) -> void:
	var durations := [0.45, 0.45, 0.65]
	_busy_until = _now() + durations[clampi(step, 0, 2)]
	var tw := create_tween()
	match step:
		0:
			# Taillade verticale du bras droit
			tw.tween_property(shoulder_r, "rotation:x", -2.4, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(shoulder_r, "rotation:x", 0.9, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.tween_property(shoulder_r, "rotation:x", 0.0, 0.17)
		1:
			# Revers horizontal
			tw.set_parallel(true)
			tw.tween_property(shoulder_r, "rotation:x", -1.5, 0.1)
			tw.tween_property(shoulder_r, "rotation:z", -1.1, 0.1)
			tw.chain().tween_property(shoulder_r, "rotation:z", 0.9, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.chain().set_parallel(true)
			tw.tween_property(shoulder_r, "rotation:x", 0.0, 0.19)
			tw.tween_property(shoulder_r, "rotation:z", 0.0, 0.19)
		2:
			# Coup final à deux mains, par-dessus la tête
			tw.set_parallel(true)
			tw.tween_property(shoulder_r, "rotation:x", -2.8, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(shoulder_l, "rotation:x", -2.8, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.chain().set_parallel(true)
			tw.tween_property(shoulder_r, "rotation:x", 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.tween_property(shoulder_l, "rotation:x", 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.chain().set_parallel(true)
			tw.tween_property(shoulder_r, "rotation:x", 0.0, 0.25)
			tw.tween_property(shoulder_l, "rotation:x", 0.0, 0.25)

func _process(delta: float) -> void:
	var now := _now()
	var run := clampf(_speed / 6.5, 0.0, 1.2)
	_phase += delta * (2.0 + run * 9.0)

	# Jambes : cycle de marche permanent
	if run > 0.05:
		var swing := sin(_phase) * 0.65 * run
		hip_l.rotation.x = swing
		hip_r.rotation.x = -swing
	else:
		hip_l.rotation.x = lerpf(hip_l.rotation.x, 0.0, 8.0 * delta)
		hip_r.rotation.x = lerpf(hip_r.rotation.x, 0.0, 8.0 * delta)

	# Bras : libres seulement hors attaque/incantation
	if now >= _busy_until:
		if _casting:
			# Pose d'incantation : les deux bras tendus vers l'avant
			shoulder_l.rotation.x = lerpf(shoulder_l.rotation.x, -1.35, 10.0 * delta)
			shoulder_r.rotation.x = lerpf(shoulder_r.rotation.x, -1.35, 10.0 * delta)
		elif run > 0.05:
			var swing := sin(_phase) * 0.5 * run
			shoulder_l.rotation.x = -swing
			shoulder_r.rotation.x = swing
			shoulder_l.rotation.z = lerpf(shoulder_l.rotation.z, 0.0, 8.0 * delta)
			shoulder_r.rotation.z = lerpf(shoulder_r.rotation.z, 0.0, 8.0 * delta)
		else:
			shoulder_l.rotation.x = lerpf(shoulder_l.rotation.x, 0.0, 6.0 * delta)
			shoulder_r.rotation.x = lerpf(shoulder_r.rotation.x, 0.0, 6.0 * delta)

	# Respiration légère à l'arrêt
	if run <= 0.05 and torso:
		torso.position.y = 1.25 + sin(now * 2.2) * 0.008

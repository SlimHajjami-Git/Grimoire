extends SceneTree
# Sonde dev-only : vérifie le retargeting du modèle humain (le squelette doit
# s'appeler GeneralSkeleton avec les os du profil humanoïde standard).
# Usage : godot --headless --path . --script res://probe_model.gd

func _init() -> void:
	var ps: PackedScene = load("res://assets/human/Human.glb")
	if ps == null:
		print("LOAD FAILED")
		quit(1)
		return
	var inst := ps.instantiate()
	_dump(inst, 0)
	inst.free()
	quit(0)

func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is AnimationPlayer:
		extra = "  ANIMS=" + str(n.get_animation_list())
	elif n is Skeleton3D:
		var bones := []
		for i in range(mini(n.get_bone_count(), 12)):
			bones.append(n.get_bone_name(i))
		extra = "  BONES(%d, 12 premiers)=" % n.get_bone_count() + str(bones)
	elif n is MeshInstance3D:
		extra = "  AABB=" + str(n.get_aabb())
	print(pad, n.name, " : ", n.get_class(), extra)
	for c in n.get_children():
		_dump(c, depth + 1)

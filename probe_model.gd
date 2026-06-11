extends SceneTree
# Sonde dev-only : inspecte un .glb importé (animations, squelette, tailles).
# Usage : godot --headless --path . --script res://probe_model.gd

func _init() -> void:
	var ps: PackedScene = load("res://assets/kaykit/Mage.glb")
	if ps == null:
		print("LOAD FAILED: Mage.glb")
		quit(1)
		return
	var inst := ps.instantiate()
	print("=== MAGE.GLB ===")
	_dump(inst, 0)
	inst.free()

	for w in ["res://assets/kaykit/sword_1handed.gltf", "res://assets/kaykit/staff.gltf"]:
		var wps: PackedScene = load(w)
		if wps == null:
			print("LOAD FAILED: ", w)
		else:
			var wi := wps.instantiate()
			print("=== ", w, " ===")
			_dump(wi, 0)
			wi.free()
	quit(0)

func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is AnimationPlayer:
		extra = "  ANIMS=" + str(n.get_animation_list())
	elif n is Skeleton3D:
		var bones := []
		for i in range(n.get_bone_count()):
			bones.append(n.get_bone_name(i))
		extra = "  BONES=" + str(bones)
	elif n is MeshInstance3D:
		extra = "  AABB=" + str(n.get_aabb())
	print(pad, n.name, " : ", n.get_class(), extra)
	for c in n.get_children():
		_dump(c, depth + 1)

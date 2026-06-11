extends SceneTree
# Script de validation dev-only — charge tous les scripts et scènes pour
# détecter les erreurs de parsing sans ouvrir l'éditeur.
# Usage : godot --headless --path . --script res://validate.gd

func _init() -> void:
	var paths := [
		"res://scripts/element_data.gd",
		"res://scripts/spell_data.gd",
		"res://scripts/input_setup.gd",
		"res://scripts/net.gd",
		"res://scripts/menu.gd",
		"res://scripts/world.gd",
		"res://scripts/player.gd",
		"res://scripts/human_model.gd",
		"res://scripts/third_person_camera.gd",
		"res://scripts/projectile.gd",
		"res://scripts/boss.gd",
		"res://scenes/menu.tscn",
		"res://scenes/world.tscn",
		"res://scenes/player.tscn",
		"res://scenes/projectile.tscn",
		"res://scenes/boss.tscn",
	]
	var failed := false
	for p in paths:
		var res := load(p)
		if res == null:
			failed = true
			print("FAIL  ", p)
		else:
			print("OK    ", p)
	# Instanciation des scènes (hors arbre : _ready non appelé, juste la structure)
	for sp in ["res://scenes/player.tscn", "res://scenes/projectile.tscn", "res://scenes/boss.tscn"]:
		var ps: PackedScene = load(sp)
		if ps:
			var inst := ps.instantiate()
			if inst:
				print("INST  ", sp)
				inst.free()
			else:
				failed = true
				print("FAIL-INST ", sp)
	if failed:
		print("VALIDATION: FAILED")
		quit(1)
	else:
		print("VALIDATION: ALL OK")
		quit(0)

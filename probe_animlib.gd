extends SceneTree
# Sonde dev-only : liste le contenu des AnimationLibrary (.res) téléchargées.
# Usage : godot --headless --path . --script res://probe_animlib.gd

const TARGETS := [
	"res://assets/human/MeleeLib.res",
	"res://assets/human/ShooterLib.res",
]

func _init() -> void:
	for path in TARGETS:
		var lib := load(path) as AnimationLibrary
		if lib == null:
			print("LOAD FAILED: ", path)
			continue
		print("=== ", path, " ===")
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			print("  %s  (%.2fs, %d tracks)" % [anim_name, anim.length, anim.get_track_count()])
		# Chemin de la première track de la première anim → comprendre le ciblage
		var names := lib.get_animation_list()
		if names.size() > 0:
			var a := lib.get_animation(names[0])
			if a.get_track_count() > 0:
				print("  EXEMPLE TRACK PATH: ", a.track_get_path(0))
	quit(0)

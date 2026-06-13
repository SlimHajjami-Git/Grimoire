extends Node
# Autoload — grimoire des sorts par élément (système type WoW).
# Chaque sort : dégâts, temps d'incantation, cooldown, portée, type.
# kind :
#   "bolt"      → projectile autoguidé vers la CIBLE (nécessite une cible)
#   "nova"      → AoE instantanée autour du lanceur (pas de cible requise)
#   "self_buff" → buff sur soi-même (pas de cible requise)
#   "strike"    → frappe au sol TÉLÉGRAPHIÉE sur la position de la cible :
#                 zone marquée pendant `delay` secondes → ESQUIVABLE au dash
#   "breath"    → SOUFFLE : torrent en cône devant le lanceur (façon Fairy
#                 Tail). Inspiration (cast_time) puis rugissement : le lanceur
#                 est enraciné et inflige des dégâts par ticks dans un cône.
# Champs optionnels : slow / slow_duration (ralentissement appliqué à l'impact),
#                     buff / buff_duration (pour self_buff),
#                     radius / delay (pour strike),
#                     cone_angle / ticks / tick_interval (pour breath)

const SPELLS := {
	"fire": [
		{ "id": "fire_bolt", "name": "Trait de feu", "icon": "🔥",
			"damage": 11, "cast_time": 0.0, "cooldown": 1.2, "range": 28.0, "kind": "bolt" },
		{ "id": "fireball", "name": "Boule de feu", "icon": "☄",
			"damage": 30, "cast_time": 1.8, "cooldown": 6.0, "range": 32.0, "kind": "bolt" },
		{ "id": "fire_nova", "name": "Nova ardente", "icon": "💥",
			"damage": 16, "cast_time": 0.0, "cooldown": 10.0, "range": 8.0, "kind": "nova" },
		{ "id": "meteor", "name": "Météore", "icon": "🌠",
			"damage": 35, "cast_time": 0.0, "cooldown": 12.0, "range": 30.0, "kind": "strike",
			"radius": 4.0, "delay": 0.9 },
		{ "id": "dragon_roar", "name": "Rugissement du Dragon", "icon": "🐉",
			"damage": 11, "cast_time": 0.7, "cooldown": 16.0, "range": 15.0, "kind": "breath",
			"cone_angle": 30.0, "ticks": 6, "tick_interval": 0.18,
			"slow": 0.3, "slow_duration": 0.5 },
	],
	"ice": [
		{ "id": "frost_shard", "name": "Éclat de givre", "icon": "❄",
			"damage": 9, "cast_time": 0.0, "cooldown": 1.2, "range": 28.0, "kind": "bolt",
			"slow": 0.35, "slow_duration": 2.5 },
		{ "id": "ice_lance", "name": "Lance de glace", "icon": "🧊",
			"damage": 28, "cast_time": 2.0, "cooldown": 6.0, "range": 32.0, "kind": "bolt" },
		{ "id": "frost_armor", "name": "Armure de givre", "icon": "🛡",
			"damage": 0, "cast_time": 0.0, "cooldown": 14.0, "range": 0.0, "kind": "self_buff",
			"buff": "frost_armor", "buff_duration": 5.0 },
		{ "id": "blizzard", "name": "Blizzard", "icon": "🌨",
			"damage": 18, "cast_time": 0.0, "cooldown": 12.0, "range": 30.0, "kind": "strike",
			"radius": 4.5, "delay": 0.8, "slow": 0.5, "slow_duration": 3.0 },
	],
}

# Kit générique pour les éléments pas encore designés (eau, foudre, terre, vent)
const GENERIC := [
	{ "id": "elem_bolt", "name": "Trait élémentaire", "icon": "✦",
		"damage": 11, "cast_time": 0.0, "cooldown": 1.2, "range": 28.0, "kind": "bolt" },
	{ "id": "elem_surge", "name": "Déferlante", "icon": "✸",
		"damage": 28, "cast_time": 1.8, "cooldown": 6.0, "range": 32.0, "kind": "bolt" },
]

func get_spells(element: String) -> Array:
	return SPELLS.get(element, GENERIC)

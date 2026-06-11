extends Node
# Autoload — grimoire des sorts par élément (système type WoW).
# Chaque sort : dégâts, temps d'incantation, cooldown, portée, type.
# kind :
#   "bolt"      → projectile autoguidé vers la CIBLE (nécessite une cible)
#   "nova"      → AoE instantanée autour du lanceur (pas de cible requise)
#   "self_buff" → buff sur soi-même (pas de cible requise)
# Champs optionnels : slow / slow_duration (ralentissement appliqué à l'impact),
#                     buff / buff_duration (pour self_buff)

const SPELLS := {
	"fire": [
		{ "id": "fire_bolt", "name": "Trait de feu", "icon": "🔥",
			"damage": 11, "cast_time": 0.0, "cooldown": 1.2, "range": 28.0, "kind": "bolt" },
		{ "id": "fireball", "name": "Boule de feu", "icon": "☄",
			"damage": 30, "cast_time": 1.8, "cooldown": 6.0, "range": 32.0, "kind": "bolt" },
		{ "id": "fire_nova", "name": "Nova ardente", "icon": "💥",
			"damage": 16, "cast_time": 0.0, "cooldown": 10.0, "range": 8.0, "kind": "nova" },
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

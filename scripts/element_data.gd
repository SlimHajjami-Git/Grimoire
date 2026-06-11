extends Node
# Autoload — table centrale du système élémentaire (la "roue des contres").
# Reprise du prototype GRIMOIRE, c'est le cœur stratégique du jeu.
# En PvP, ta magie ACTIVE est aussi ton élément défensif : changer de magie
# change ton attaque ET ta défense → mind-game permanent.

const COUNTERS := {
	"fire": { "ice": 1.5, "wind": 1.3, "water": 0.5, "fire": 0.5 },
	"ice": { "water": 1.5, "earth": 1.3, "fire": 0.5, "ice": 0.5 },
	"water": { "fire": 1.5, "earth": 1.2, "lightning": 0.5, "water": 0.5 },
	"lightning": { "water": 1.5, "wind": 1.3, "earth": 0.5, "lightning": 0.5 },
	"earth": { "lightning": 1.5, "ice": 0.7, "wind": 0.5, "earth": 0.5 },
	"wind": { "earth": 1.5, "water": 1.2, "fire": 0.5, "wind": 0.5 },
	# À venir : shadow, light, metal, gravity, time, blood (magies rares de donjon)
}

const COLORS := {
	"fire": Color(1.0, 0.38, 0.15),
	"ice": Color(0.55, 0.85, 1.0),
	"water": Color(0.20, 0.45, 0.95),
	"lightning": Color(1.0, 1.0, 0.4),
	"earth": Color(0.65, 0.45, 0.25),
	"wind": Color(0.6, 1.0, 0.7),
	"shadow": Color(0.35, 0.2, 0.5),
	"light": Color(1.0, 0.95, 0.7),
	"metal": Color(0.72, 0.72, 0.8),
	"gravity": Color(0.3, 0.25, 0.4),
	"time": Color(0.8, 0.7, 0.95),
	"blood": Color(0.6, 0.1, 0.1),
}

const NAMES_FR := {
	"fire": "FEU", "ice": "GLACE", "water": "EAU",
	"lightning": "FOUDRE", "earth": "TERRE", "wind": "VENT",
}

const EMOJI := {
	"fire": "🔥", "ice": "❄", "water": "💧",
	"lightning": "⚡", "earth": "🪨", "wind": "🌪",
}

func get_multiplier(attacker: String, target: String) -> float:
	if attacker in COUNTERS:
		var row: Dictionary = COUNTERS[attacker]
		if target in row:
			return row[target]
	return 1.0

func get_color(element: String) -> Color:
	return COLORS.get(element, Color.WHITE)

func display_name(element: String) -> String:
	return NAMES_FR.get(element, element.to_upper())

func emoji(element: String) -> String:
	return EMOJI.get(element, "✦")

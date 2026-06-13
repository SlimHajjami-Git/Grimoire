extends Node
# Autoload — enregistre les actions clavier/souris au démarrage.
# physical_keycode = positionnel : WASD physique = ZQSD sur clavier AZERTY.
# Schéma type Elden Ring : souris = caméra, clic gauche = attaque (combos),
# Tab/clic-molette = lock-on, 1-3 = sorts.

func _enter_tree() -> void:
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("move_up", KEY_W)
	_key("move_down", KEY_S)
	_key("dash", KEY_SPACE)
	_key("switch_element", KEY_R)
	_key("lock_on", KEY_TAB)
	_key("clear_target", KEY_ESCAPE)
	_key("spell_1", KEY_1)
	_key("spell_2", KEY_2)
	_key("spell_3", KEY_3)
	_key("spell_4", KEY_4)
	_key("spell_5", KEY_5)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_mouse("lock_on", MOUSE_BUTTON_MIDDLE)

func _key(action: String, key: int) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

func _mouse(action: String, button: int) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

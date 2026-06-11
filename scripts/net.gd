extends Node
# Autoload — gestion de la connexion réseau (ENet) et du registre des joueurs.
# Modèle : serveur autoritaire. Le host peut être un joueur (listen server)
# ou un serveur dédié headless (lancé avec : godot --headless -- --server).

const PORT := 7777
const MAX_PLAYERS := 32

signal player_registered(peer_id: int, info: Dictionary)
signal player_left(peer_id: int)

var my_name: String = "Mage"
var is_dedicated := false
var last_error := ""

# Serveur uniquement : peer_id -> { name: String, unlocked: Array }
var players: Dictionary = {}

var _connected := false
var _world_ready := false
var _registered := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(player_name: String, dedicated := false) -> Error:
	_reset_session()
	my_name = player_name
	is_dedicated = dedicated
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		last_error = "Impossible d'ouvrir le port %d (déjà utilisé ?)" % PORT
		return err
	multiplayer.multiplayer_peer = peer
	players[1] = _make_info(my_name)
	print("[NET] Serveur démarré sur le port ", PORT, " (dédié: ", dedicated, ")")
	return OK

func join(ip: String, player_name: String) -> Error:
	_reset_session()
	my_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		last_error = "Adresse invalide : " + ip
		return err
	multiplayer.multiplayer_peer = peer
	print("[NET] Connexion vers ", ip, ":", PORT, " ...")
	return OK

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_reset_session()

# Appelé par world.gd quand la scène du monde est prête côté client :
# on ne s'enregistre auprès du serveur qu'une fois le monde chargé,
# sinon le spawn répliqué arriverait avant que les spawners existent.
func client_world_ready() -> void:
	_world_ready = true
	_try_register()

func _try_register() -> void:
	if _world_ready and _connected and not _registered:
		_registered = true
		rpc_id(1, "register_player", my_name)

@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return  # déjà enregistré — un doublon re-spawnerait le joueur (full
		        # heal gratuit) et créerait un node fantôme répliqué partout
	players[id] = _make_info(pname)
	print("[NET] Joueur enregistré : ", pname, " (id ", id, ")")
	player_registered.emit(id, players[id])

func _make_info(pname: String) -> Dictionary:
	return { "name": pname, "unlocked": ["fire"] }

func player_display_name(id: int) -> String:
	if id == 0:
		return "Le Gardien de Givre"
	if players.has(id):
		return players[id]["name"]
	return "???"

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[NET] Pair connecté : ", id)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("[NET] Pair déconnecté : ", id)
		players.erase(id)
		player_left.emit(id)

func _on_connected_to_server() -> void:
	print("[NET] Connecté au serveur.")
	_connected = true
	_try_register()

func _on_connection_failed() -> void:
	last_error = "Connexion échouée — vérifie l'IP et que le serveur tourne."
	_back_to_menu()

func _on_server_disconnected() -> void:
	last_error = "Le serveur a fermé la connexion."
	_back_to_menu()

func _back_to_menu() -> void:
	multiplayer.multiplayer_peer = null
	_reset_session()
	get_tree().change_scene_to_file.call_deferred("res://scenes/menu.tscn")

func _reset_session() -> void:
	_connected = false
	_world_ready = false
	_registered = false
	players.clear()
	is_dedicated = false

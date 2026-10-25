extends Node

# TODO: make this simpler to use, likely by merging some signals idk.

## Emitted when the server has been started successfully.
## [param port] is the local port, or [constant STEAM_VIRTUAL_PORT] for Steam.
signal hosted(port: int)
## Emitted when the server could not be started.
signal host_failed(error: Error)
## Emitted when this peer has connected to a server.
signal connected
## Emitted when this peer could not connect to a server.
signal connection_failed
## Emitted when this peer has been disconnected from the server.
signal disconnected
## Emitted when another peer has connected to this server.
signal client_joined(id: int)
## Emitted when another peer has disconnected from this server.
signal client_left(id: int)
## Emitted when [method connect_to] receives an invalid IP address.
signal ip_invalid(address: String)
## Emitted when [method host] or [method connect_to] receives an invalid port.
signal port_invalid(port: int)
## Emitted when [method connect_to] receives an invalid Steam ID.
signal steam_id_invalid(steam_id: String)
## Emitted when Steam is selected but cannot be initialized or used.
signal steam_unavailable(reason: String)
## Emitted when [method connect_to] targets the current user's own Steam ID.
signal steam_self_connect(steam_id: String)
## Emitted when a client connection attempt does not complete in time.
signal connection_timed_out

## Network role of the current peer.
enum Role {NONE, HOST, CLIENT}
## Available ways to host or join a game.
enum ConnectionMethod {LOCAL, STEAM}

const DEFAULT_PORT := 20220
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_MAX_CLIENTS := 8
const DEFAULT_CONNECTION_TIMEOUT := 10.0
## Virtual port used by [SteamMultiplayerPeer]. Kept at 0 for regular games.
const STEAM_VIRTUAL_PORT := 0

## Enable debug info logging.
var debug_enabled := false
## Transport used by [method host] and [method connect_to].
var connection_method: ConnectionMethod = ConnectionMethod.LOCAL
## Steam App ID used when Steam is initialized lazily. 0 uses project settings or the environment.
var steam_app_id := 0
## Seconds to wait for a client connection before giving up.
var connection_timeout := DEFAULT_CONNECTION_TIMEOUT
## Port used to create a local server or client.
var PORT := DEFAULT_PORT
## Maximum number of clients allowed on a local server.
var MAX_CLIENTS := DEFAULT_MAX_CLIENTS
## Current network peer, or [code]null[/code] when not connected.
var current_peer: MultiplayerPeer
## Current peer network role.
var role: Role = Role.NONE

var _is_connected := false
var _connection_timer: Timer


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_connection_timer = Timer.new()
	_connection_timer.one_shot = true
	_connection_timer.timeout.connect(_on_connection_timeout)
	add_child(_connection_timer)

	_log("Con is initialized")


## Start a server using [member connection_method].
func host() -> Error:
	match connection_method:
		ConnectionMethod.LOCAL:
			return _host_local()
		ConnectionMethod.STEAM:
			return _host_steam()

	push_error("Con: unknown connection method %d." % connection_method)
	return ERR_INVALID_PARAMETER


## Connect to a server using [member connection_method].
## [param address] is an IP address for local connections or a Steam ID for Steam.
func connect_to(address: String = DEFAULT_ADDRESS) -> Error:
	address = address.strip_edges()
	match connection_method:
		ConnectionMethod.LOCAL:
			return _connect_local(address)
		ConnectionMethod.STEAM:
			return _connect_steam(address)

	push_error("Con: unknown connection method %d." % connection_method)
	return ERR_INVALID_PARAMETER


## Whether the given string is a valid IP address.
func is_valid_ip(address: String) -> bool:
	return address.strip_edges().is_valid_ip_address()


## Whether the given number is a valid port.
func is_valid_port(port: int) -> bool:
	return port >= 1 and port <= 65535


## Whether the given string is a valid Steam ID.
func is_valid_steam_id(steam_id: String) -> bool:
	var value := steam_id.strip_edges()
	return value.is_valid_int() and int(value) > 0


## Whether the GodotSteam extension and its MultiplayerPeer are available.
func is_steam_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


## Whether Steam is initialized and the current user is logged on.
func is_steam_ready() -> bool:
	if not is_steam_available():
		return false
	var steam = Engine.get_singleton("Steam")
	var result: Dictionary = steam.call("get_steam_init_result")
	if result.is_empty() or int(result.get("status", 1)) != 0:
		return false
	return bool(steam.call("loggedOn"))


## Steam ID of the current user, or 0 when Steam is not ready.
func get_steam_id() -> int:
	if not is_steam_ready():
		return 0
	return int(Engine.get_singleton("Steam").call("getSteamID"))


func _host_local() -> Error:
	if not is_valid_port(PORT):
		var error := ERR_INVALID_PARAMETER
		push_error("Con: invalid port %d." % PORT)
		port_invalid.emit(PORT)
		return error

	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		push_error("Con: could not host on PORT %d: %s" % [PORT, error_string(error)])
		host_failed.emit(error)
		return error

	current_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_log("Hosting on PORT %d (max clients: %d)" % [PORT, MAX_CLIENTS])
	hosted.emit(PORT)
	return OK


func _host_steam() -> Error:
	var error := _ensure_steam()
	if error != OK:
		return error

	_reset_peer()
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		_fail_steam("Could not create SteamMultiplayerPeer.")
		return ERR_CANT_CREATE
	peer.set("server_relay", true)
	error = int(peer.call("create_host", STEAM_VIRTUAL_PORT))
	if error != OK:
		push_error("Con: could not host via Steam: %s" % error_string(error))
		host_failed.emit(error)
		return error

	current_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_log("Hosting via Steam (virtual port: %d)" % STEAM_VIRTUAL_PORT)
	hosted.emit(STEAM_VIRTUAL_PORT)
	return OK


func _connect_local(address: String) -> Error:
	if not address.is_valid_ip_address():
		var error := ERR_INVALID_PARAMETER
		push_error("Con: invalid IP address \"%s\"." % address)
		ip_invalid.emit(address)
		return error
	if not is_valid_port(PORT):
		var error := ERR_INVALID_PARAMETER
		push_error("Con: invalid PORT %d." % PORT)
		port_invalid.emit(PORT)
		return error

	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		push_error("Con: could not connect to %s:%d: %s" % [address, PORT, error_string(error)])
		connection_failed.emit()
		return error

	current_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_is_connected = false
	_connection_timer.start(connection_timeout)
	_log("Connecting to %s:%d" % [address, PORT])
	return OK


func _connect_steam(steam_id: String) -> Error:
	if not is_valid_steam_id(steam_id):
		var error := ERR_INVALID_PARAMETER
		push_error("Con: invalid Steam ID \"%s\"." % steam_id)
		steam_id_invalid.emit(steam_id)
		return error

	var error := _ensure_steam()
	if error != OK:
		return error

	var local_steam_id := get_steam_id()
	if local_steam_id > 0 and int(steam_id) == local_steam_id:
		push_error("Con: cannot connect to your own Steam ID \"%s\"." % steam_id)
		steam_self_connect.emit(steam_id)
		return ERR_INVALID_PARAMETER

	_reset_peer()
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		_fail_steam("Could not create SteamMultiplayerPeer.")
		return ERR_CANT_CREATE
	peer.set("server_relay", true)
	error = int(peer.call("create_client", int(steam_id), STEAM_VIRTUAL_PORT))
	if error != OK:
		push_error("Con: could not connect to Steam ID %s: %s" % [steam_id, error_string(error)])
		connection_failed.emit()
		return error

	current_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_is_connected = false
	_connection_timer.start(connection_timeout)
	_log("Connecting via Steam to %s" % steam_id)
	return OK


func _ensure_steam() -> Error:
	if not is_steam_available():
		_fail_steam("GodotSteam is not installed.")
		return ERR_UNAVAILABLE

	var steam = Engine.get_singleton("Steam")
	var result: Dictionary = steam.call("get_steam_init_result")
	if result.is_empty():
		result = steam.call("steamInitEx", steam_app_id, true)

	var status := int(result.get("status", 1))
	if status != 0:
		var reason := String(result.get("verbal", "unknown error"))
		_fail_steam("Steam initialization failed: %s" % reason)
		return ERR_UNAVAILABLE
	if not bool(steam.call("loggedOn")):
		_fail_steam("Steam user is not logged on.")
		return ERR_UNAVAILABLE
	return OK


func _fail_steam(reason: String) -> void:
	push_error("Con: %s" % reason)
	steam_unavailable.emit(reason)


## Stop hosting or disconnect from the server, whichever is active.
func stop() -> void:
	if not is_active():
		return
	_reset_peer()
	_log("Stopped")


## Disconnect a client from the server. Only works while hosting.
func kick_client(id: int) -> void:
	if not is_host() or current_peer == null:
		return
	if not multiplayer.get_peers().has(id):
		return
	current_peer.disconnect_peer(id)
	_log("Kicking client %d" % id)


## Whether this peer is currently hosting or connecting/connected to a server.
func is_active() -> bool:
	return role != Role.NONE


## Whether this peer is hosting a server.
func is_host() -> bool:
	return role == Role.HOST


## Whether this peer is a client.
func is_client() -> bool:
	return role == Role.CLIENT


## Unique network ID of this peer, or 0 when not connected.
func get_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


## IDs of clients connected to this server. Empty when not hosting.
func get_client_ids() -> PackedInt32Array:
	if not is_host():
		return PackedInt32Array()
	return multiplayer.get_peers()


## Release the peer and reset state without emitting any signals.
func _reset_peer() -> void:
	var peer := current_peer
	current_peer = null
	role = Role.NONE
	_is_connected = false
	if _connection_timer != null:
		_connection_timer.stop()
	if peer != null:
		peer.close()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null


func _on_connected_to_server() -> void:
	role = Role.CLIENT
	_is_connected = true
	_connection_timer.stop()
	_log("Connected to server as peer %d" % multiplayer.get_unique_id())
	connected.emit()


func _on_connection_timeout() -> void:
	if not is_client() or _is_connected:
		return
	_log("Connection timed out after %.0f seconds" % connection_timeout)
	_reset_peer()
	connection_timed_out.emit()


func _on_connection_failed() -> void:
	_log("Connection failed")
	_reset_peer()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	_log("Disconnected from server")
	_reset_peer()
	disconnected.emit()


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	_log("Client %d joined" % id)
	client_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	_log("Client %d left" % id)
	client_left.emit(id)


func _log(text: String) -> void:
	if debug_enabled:
		print("Con: %s" % text)

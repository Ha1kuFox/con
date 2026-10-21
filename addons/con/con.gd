extends Node

# TODO: make this simpler to use, likely by merging some signals idk.

## Emitted when the server has been started successfully.
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

## Network role of the current peer.
enum Role {NONE, HOST, CLIENT}

const DEFAULT_PORT := 20220
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_MAX_CLIENTS := 8

## Enable debug info logging.
var debug_enabled := false
## Port used to create server or client.
var PORT := DEFAULT_PORT
## Maximum number of clients allowed on this server.
var MAX_CLIENTS := DEFAULT_MAX_CLIENTS
## Current network peer, or [code]null[/code] when not connected.
var current_peer: ENetMultiplayerPeer
## Current peer network role.
var role: Role = Role.NONE


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_log("Con is initialized")


## Start a server.
func host() -> Error:
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


## Whether the given string is a valid IP address.
func is_valid_ip(address: String) -> bool:
	return address.strip_edges().is_valid_ip_address()


## Whether the given number is a valid port.
func is_valid_port(port: int) -> bool:
	return port >= 1 and port <= 65535


## Connect to a server.
func connect_to(address: String = DEFAULT_ADDRESS) -> Error:
	address = address.strip_edges()
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
	_log("Connecting to %s:%d" % [address, PORT])
	return OK


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
	if peer != null:
		peer.close()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null


func _on_connected_to_server() -> void:
	role = Role.CLIENT
	_log("Connected to server as peer %d" % multiplayer.get_unique_id())
	connected.emit()


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

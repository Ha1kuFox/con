extends Node

## Enable debug info logging
var debug_enabled: bool = false
## Port of game server
var PORT: int = 20220
## Current network peer for local connection
var current_peer: ENetMultiplayerPeer

## Create server host on given port
func host() -> void:
	current_peer = ENetMultiplayerPeer.new()
	current_peer.create_server(PORT)
	_log("Host is created")


func _log(text: String) -> void:
	if debug_enabled:
		print(text)


func _ready() -> void:
	# Basic initialization
	_log("Con is initialized")

extends Control

@onready var address_edit: LineEdit = %Address
@onready var port_spin: SpinBox = %Port
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var status_label: Label = %Status


func _ready() -> void:
	Con.debug_enabled = true
	Con.PORT = int(port_spin.value)

	Con.hosted.connect(_on_hosted)
	Con.host_failed.connect(_on_host_failed)
	Con.connected.connect(_on_connected)
	Con.connection_failed.connect(_on_connection_failed)
	Con.disconnected.connect(_on_disconnected)
	Con.client_joined.connect(_on_client_joined)
	Con.client_left.connect(_on_client_left)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)

	_set_status("Not connected. Host a game or join one.")
	_update_controls()


func _on_host_pressed() -> void:
	Con.PORT = int(port_spin.value)
	var error := Con.host()
	if error != OK:
		_update_controls()
		return
	_set_status("Hosting on port %d. Waiting for players..." % Con.PORT)
	_update_controls()


func _on_join_pressed() -> void:
	Con.PORT = int(port_spin.value)
	var error := Con.connect_to(address_edit.text)
	if error != OK:
		_update_controls()
		return
	_set_status("Connecting to %s:%d..." % [address_edit.text, Con.PORT])
	_update_controls()


func _on_disconnect_pressed() -> void:
	Con.stop()
	_set_status("Disconnected.")
	_update_controls()


func _on_hosted(port: int) -> void:
	_set_status("Hosting on port %d. Your peer ID is %d." % [port, Con.get_peer_id()])
	_update_controls()


func _on_host_failed(error: Error) -> void:
	_set_status("Could not host: %s" % error_string(error))
	_update_controls()


func _on_connected() -> void:
	_set_status("Connected to server. Your peer ID is %d." % Con.get_peer_id())
	_update_controls()


func _on_connection_failed() -> void:
	_set_status("Connection failed. Is the server running?")
	_update_controls()


func _on_disconnected() -> void:
	_set_status("Disconnected from server.")
	_update_controls()


func _on_client_joined(id: int) -> void:
	_set_status("Player %d joined. %d player(s) connected." % [id, Con.get_client_ids().size() + 1])


func _on_client_left(id: int) -> void:
	_set_status("Player %d left. %d player(s) connected." % [id, Con.get_client_ids().size() + 1])


func _set_status(text: String) -> void:
	status_label.text = text


func _update_controls() -> void:
	var active := Con.is_active()
	host_button.disabled = active
	join_button.disabled = active
	disconnect_button.disabled = not active
	address_edit.editable = not active
	port_spin.editable = not active

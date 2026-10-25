extends Control

@onready var method_option: OptionButton = %Method
@onready var address_label: Label = %AddressLabel
@onready var address_edit: LineEdit = %Address
@onready var port_label: Label = %PortLabel
@onready var port_spin: SpinBox = %Port
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var host_id_section: VBoxContainer = %HostIdSection
@onready var host_id_edit: LineEdit = %HostId
@onready var copy_id_button: Button = %CopyIdButton
@onready var status_label: Label = %Status

var _local_address := ""
var _steam_id := ""


func _ready() -> void:
	Con.debug_enabled = true
	# SpaceWar test App ID. Replace with your own App ID for release.
	Con.steam_app_id = 480
	Con.PORT = int(port_spin.value)
	_local_address = address_edit.text

	method_option.add_item("Local", Con.ConnectionMethod.LOCAL)
	method_option.add_item("Steam", Con.ConnectionMethod.STEAM)
	method_option.select(0)

	Con.hosted.connect(_on_hosted)
	Con.host_failed.connect(_on_host_failed)
	Con.connected.connect(_on_connected)
	Con.connection_failed.connect(_on_connection_failed)
	Con.connection_timed_out.connect(_on_connection_timed_out)
	Con.disconnected.connect(_on_disconnected)
	Con.client_joined.connect(_on_client_joined)
	Con.client_left.connect(_on_client_left)
	Con.ip_invalid.connect(_on_ip_invalid)
	Con.steam_id_invalid.connect(_on_steam_id_invalid)
	Con.steam_unavailable.connect(_on_steam_unavailable)
	Con.steam_self_connect.connect(_on_steam_self_connect)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	copy_id_button.pressed.connect(_on_copy_pressed)
	address_edit.text_changed.connect(_on_address_changed)
	method_option.item_selected.connect(_on_method_selected)

	_on_method_selected(method_option.selected)
	_set_status("Not connected. Host a game or join one.")
	_update_controls()


func _on_host_pressed() -> void:
	Con.connection_method = method_option.get_item_id(method_option.selected)
	Con.PORT = int(port_spin.value)
	var error: Error = Con.host()
	if error != OK:
		_update_controls()
		return
	_update_controls()


func _on_join_pressed() -> void:
	Con.connection_method = method_option.get_item_id(method_option.selected)
	Con.PORT = int(port_spin.value)
	var address := address_edit.text.strip_edges()
	var error: Error = Con.connect_to(address)
	if error != OK:
		_update_controls()
		return

	if Con.connection_method == Con.ConnectionMethod.STEAM:
		_set_status("Connecting via Steam to %s..." % address)
	else:
		_set_status("Connecting to %s:%d..." % [address, Con.PORT])
	_update_controls()


func _on_disconnect_pressed() -> void:
	Con.stop()
	_set_status("Disconnected.")
	_update_controls()


func _on_hosted(port: int) -> void:
	if Con.connection_method == Con.ConnectionMethod.STEAM:
		_set_status("Hosting via Steam. Share your Steam ID with friends.")
	else:
		_set_status("Hosting on port %d. Your peer ID is %d." % [port, Con.get_peer_id()])
	_update_controls()


func _on_host_failed(error: Error) -> void:
	_set_status("Could not host: %s" % error_string(error))
	_update_controls()


func _on_connected() -> void:
	_set_status("Connected to server. Your peer ID is %d." % Con.get_peer_id())
	_update_controls()


func _on_connection_failed() -> void:
	if Con.connection_method == Con.ConnectionMethod.STEAM:
		_set_status("Steam connection failed. Make sure both players are online.")
	else:
		_set_status("Connection failed. Is the server running?")
	_update_controls()


func _on_connection_timed_out() -> void:
	if Con.connection_method == Con.ConnectionMethod.STEAM:
		_set_status("Steam connection timed out.")
	else:
		_set_status("Connection timed out. Check the host address and port.")
	_update_controls()


func _on_disconnected() -> void:
	_set_status("Disconnected from server.")
	_update_controls()


func _on_client_joined(id: int) -> void:
	_set_status("Player %d joined. %d player(s) connected." % [id, Con.get_client_ids().size() + 1])


func _on_client_left(id: int) -> void:
	_set_status("Player %d left. %d player(s) connected." % [id, Con.get_client_ids().size() + 1])


func _on_ip_invalid(address: String) -> void:
	_set_address_invalid(true)
	_set_status("Invalid IP address: \"%s\"." % address)


func _on_steam_id_invalid(steam_id: String) -> void:
	_set_address_invalid(true)
	_set_status("Invalid Steam ID: \"%s\"." % steam_id)


func _on_steam_unavailable(reason: String) -> void:
	_set_status("Steam unavailable: %s" % reason)


func _on_steam_self_connect(_steam_id: String) -> void:
	_set_address_invalid(true)
	_set_status("That's your own Steam ID. Use the host's ID from another Steam account, or test with Local mode.")
	_update_controls()


func _on_method_selected(index: int) -> void:
	if Con.connection_method == Con.ConnectionMethod.STEAM:
		_steam_id = address_edit.text
	else:
		_local_address = address_edit.text

	Con.connection_method = method_option.get_item_id(index)
	var steam: int = Con.connection_method == Con.ConnectionMethod.STEAM

	address_label.text = "Host Steam ID" if steam else "Host address"
	address_edit.placeholder_text = "Host's Steam ID64" if steam else Con.DEFAULT_ADDRESS
	address_edit.text = _steam_id if steam else _local_address
	_on_address_changed(address_edit.text)


func _on_address_changed(text: String) -> void:
	if text.strip_edges().is_empty():
		_set_address_invalid(false)
	else:
		_set_address_invalid(not _is_target_valid())
	_update_controls()


func _is_target_valid() -> bool:
	var target := address_edit.text.strip_edges()
	if target.is_empty():
		return false
	if Con.connection_method == Con.ConnectionMethod.STEAM:
		return Con.is_valid_steam_id(target)
	return Con.is_valid_ip(target)


func _on_copy_pressed() -> void:
	if host_id_edit.text.is_empty():
		return
	DisplayServer.clipboard_set(host_id_edit.text)
	copy_id_button.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(copy_id_button):
		copy_id_button.text = "Copy"


func _set_address_invalid(invalid: bool) -> void:
	if invalid:
		address_edit.add_theme_color_override("font_color", Color.RED)
	else:
		address_edit.remove_theme_color_override("font_color")


func _set_status(text: String) -> void:
	status_label.text = text


func _update_controls() -> void:
	var active: bool = Con.is_active()
	var hosting: bool = Con.is_host()
	var steam: bool = Con.connection_method == Con.ConnectionMethod.STEAM

	method_option.disabled = active
	host_button.disabled = active
	join_button.disabled = active or not _is_target_valid()
	disconnect_button.disabled = not active
	address_label.visible = not hosting
	address_edit.visible = not hosting
	address_edit.editable = not active
	port_label.visible = not steam
	port_spin.visible = not steam
	port_spin.editable = not active
	if active:
		_set_address_invalid(false)
	_update_host_id()


func _update_host_id() -> void:
	var steam_id: int = Con.get_steam_id() if Con.is_host() and Con.connection_method == Con.ConnectionMethod.STEAM else 0
	host_id_section.visible = steam_id > 0
	host_id_edit.text = str(steam_id) if steam_id > 0 else ""
	if not host_id_section.visible:
		copy_id_button.text = "Copy"

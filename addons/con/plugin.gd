@tool
extends EditorPlugin


func _enable_plugin() -> void:
	add_autoload_singleton("Con", "res://addons/con/con.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton("Con")

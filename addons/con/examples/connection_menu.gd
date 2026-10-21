extends Control


func _ready() -> void:
	Con.debug_enabled = true
	Con.PORT = 20260
	
	# Creating host
	Con.host()
	
	Con.connect_to()

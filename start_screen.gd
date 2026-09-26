extends Control

@onready var start_button: Button = $Center/Sign/Content/StartButton


func _on_start_button_pressed() -> void:
	# Prevent a second click while Godot switches scenes.
	start_button.disabled = true
	var result := get_tree().change_scene_to_file("res://owner_intro.tscn")
	if result != OK:
		start_button.disabled = false
		push_error("Could not open the owner briefing: %s" % error_string(result))

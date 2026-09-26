extends Control

@onready var retry_button: Button = $Center/Sign/Content/Actions/RetryButton
@onready var menu_button: Button = $Center/Sign/Content/Actions/MenuButton

var changing_scene: bool = false


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	# The overlay starts hidden. Give it keyboard focus only when shown.
	if is_visible_in_tree():
		retry_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Hidden Controls can still receive keyboard events.
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("restart") and not event.is_echo():
		# Handle the key before changing scenes, which removes this Control.
		get_viewport().set_input_as_handled()
		_on_retry_button_pressed()


func _on_retry_button_pressed() -> void:
	# Load a fresh ride: distance, installed rails, and inventory all reset.
	_change_scene("res://main.tscn")


func _on_menu_button_pressed() -> void:
	_change_scene("res://start_screen.tscn")


func _change_scene(scene_path: String) -> void:
	if changing_scene:
		return
	changing_scene = true
	retry_button.disabled = true
	menu_button.disabled = true
	var result := get_tree().change_scene_to_file(scene_path)
	if result != OK:
		changing_scene = false
		retry_button.disabled = false
		menu_button.disabled = false
		retry_button.grab_focus()
		push_error("Could not open %s: %s" % [scene_path, error_string(result)])

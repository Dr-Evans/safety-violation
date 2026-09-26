extends Control

@export_range(1.0, 120.0, 1.0) var characters_per_second: float = 35.0
@export var dialogue_lines: Array[String] = [
	"You're the new operator? Good. The coaster is open, and the repair budget is already gone.",
	"Two reusable rails are already on the track. Once the cart passes a rail, drag it to your tray. You can carry ONE at a time.",
	"Drag that rail onto a red gap before the cart gets there. Drag empty space or use A/D to look ahead. Press F to find the cart.",
	"Keep the passengers alive. And if anyone asks about the missing track... it's a budget cut. Now, get to work."
]

@onready var dialogue: RichTextLabel = $Layout/Columns/Sign/Content/Dialogue
@onready var line_count: Label = $Layout/Columns/Sign/Content/Header/LineCount
@onready var hint: Label = $Layout/Columns/Sign/Content/Hint
@onready var continue_button: Button = $Layout/Columns/Sign/Content/Actions/ContinueButton
@onready var skip_button: Button = $Layout/Columns/Sign/Content/Actions/SkipButton
@onready var owner_voice: AudioStreamPlayer = $OwnerVoice

var _line_index: int = 0
var _revealed_characters: float = 0.0
var _typing: bool = false
var _changing_scene: bool = false


func _ready() -> void:
	owner_voice.finished.connect(_on_owner_voice_finished)
	continue_button.grab_focus()
	_show_line()


func _process(delta: float) -> void:
	if not _typing or _changing_scene:
		return
	# Keep the whole sentence laid out; reveal characters without moving words.
	_revealed_characters += maxf(characters_per_second, 1.0) * delta
	var total := dialogue.get_total_character_count()
	dialogue.visible_characters = mini(int(_revealed_characters), total)
	if dialogue.visible_characters >= total:
		_finish_line()


func _unhandled_input(event: InputEvent) -> void:
	if _changing_scene or event.is_echo():
		return
	var advance := event.is_action_pressed("start") or event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton:
		advance = advance or (event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	if advance:
		# Consume this click before loading Main so it cannot pick up a rail.
		get_viewport().set_input_as_handled()
		_advance_dialogue()


func _show_line() -> void:
	if _line_index >= dialogue_lines.size():
		_start_ride()
		return
	dialogue.text = dialogue_lines[_line_index]
	dialogue.visible_characters = 0
	_revealed_characters = 0.0
	_typing = true
	line_count.text = "%d / %d" % [_line_index + 1, dialogue_lines.size()]
	hint.text = "Click or press Space / Enter to reveal the line."
	continue_button.text = "Reveal line"
	owner_voice.play()


func _finish_line() -> void:
	_typing = false
	dialogue.visible_characters = -1
	owner_voice.stop()
	hint.text = "Click or press Space / Enter to continue."
	continue_button.text = "Start ride" if _line_index == dialogue_lines.size() - 1 else "Next"


func _advance_dialogue() -> void:
	if _changing_scene:
		return
	# First click completes the sentence; the next advances to another page.
	if _typing:
		_finish_line()
	else:
		_line_index += 1
		_show_line()


func _on_owner_voice_finished() -> void:
	# Longer custom lines can outlast the voice sample.
	if _typing and not _changing_scene:
		owner_voice.play()


func _start_ride() -> void:
	if _changing_scene:
		return
	_changing_scene = true
	continue_button.disabled = true
	skip_button.disabled = true
	owner_voice.stop()
	var result := get_tree().change_scene_to_file("res://main.tscn")
	if result != OK:
		_changing_scene = false
		continue_button.disabled = false
		skip_button.disabled = false
		if _typing:
			owner_voice.play()
		hint.text = "Could not start the ride. Try again."
		push_error("Could not open the coaster scene: %s" % error_string(result))

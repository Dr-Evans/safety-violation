class_name RepairInventory
extends Control

signal repair_requested(kind: int)

@onready var count_label: Label = $Tray/Content/Info/Count
@onready var hint_label: Label = $Tray/Content/Info/Hint
@onready var slots: Array[PanelContainer] = [
	$Tray/Content/Rising, $Tray/Content/Flat, $Tray/Content/Falling, $Tray/Content/Loop
]

var _enabled: bool = true


func _ready() -> void:
	for kind in range(slots.size()):
		slots[kind].gui_input.connect(_on_slot_input.bind(kind))


func configure(tileset: Texture2D) -> void:
	for kind in range(slots.size()):
		var icon := slots[kind].get_node("Contents/Rail") as RailIcon
		icon.tileset = tileset
		icon.kind = kind
		icon.queue_redraw()
	set_controls_enabled(true)


func set_instruction(title: String, hint: String) -> void:
	count_label.text = title
	hint_label.text = hint


func set_controls_enabled(enabled: bool) -> void:
	_enabled = enabled
	for slot in slots:
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
		slot.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.5)


func _on_slot_input(event: InputEvent, kind: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _enabled:
				repair_requested.emit(kind)
			accept_event()

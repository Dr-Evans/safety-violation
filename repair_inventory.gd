class_name RepairInventory
extends Control

signal drag_requested(kind: int)

@onready var count_label: Label = $Tray/Content/Info/Count
@onready var hint_label: Label = $Tray/Content/Info/Hint
@onready var slots: Array[PanelContainer] = [
	$Tray/Content/Rising, $Tray/Content/Flat, $Tray/Content/Falling, $Tray/Content/Loop
]
@onready var preview: PanelContainer = $Preview
@onready var preview_rail: RailIcon = $Preview/Contents/Rail
@onready var preview_hint: Label = $Preview/Contents/Hint

var _enabled: bool = true
var _held_kind: int = -1


func _ready() -> void:
	for kind in range(slots.size()):
		slots[kind].gui_input.connect(_on_slot_input.bind(kind))


func configure(tileset: Texture2D) -> void:
	preview_rail.tileset = tileset
	for kind in range(slots.size()):
		var icon := slots[kind].get_node("Contents/Rail") as RailIcon
		icon.tileset = tileset
		icon.kind = kind
		icon.queue_redraw()
	set_controls_enabled(true)


func set_instruction(title: String, hint: String) -> void:
	count_label.text = title
	hint_label.text = hint


func set_controls_enabled(enabled: bool, held_kind: int = -1) -> void:
	_enabled = enabled
	_held_kind = held_kind
	for kind in range(slots.size()):
		var slot := slots[kind]
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled and held_kind < 0 else Control.CURSOR_ARROW
		slot.modulate = Color.WHITE if enabled and (held_kind < 0 or kind == held_kind) else Color(1, 1, 1, 0.5)


func show_preview(viewport_point: Vector2, kind: int, valid_drop: bool, hint: String) -> void:
	preview.show()
	preview_rail.kind = kind
	preview_rail.modulate = Color("#c8e8ad") if valid_drop else Color.WHITE
	preview_rail.queue_redraw()
	preview_hint.text = hint
	preview_hint.add_theme_color_override("font_color", Color("#447342") if valid_drop else Color("#6a6660"))
	var local_point := get_global_transform_with_canvas().affine_inverse() * viewport_point
	preview.position = Vector2(
		clampf(local_point.x + 16.0, 8.0, size.x - preview.size.x - 8.0),
		clampf(local_point.y + 16.0, 8.0, size.y - preview.size.y - 8.0)
	)


func hide_preview() -> void:
	preview.hide()


func _on_slot_input(event: InputEvent, kind: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _enabled and _held_kind < 0:
				drag_requested.emit(kind)
			accept_event()

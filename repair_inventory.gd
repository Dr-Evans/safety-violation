class_name RepairInventory
extends Control

signal drag_requested(part_index: int)

@onready var tray: PanelContainer = $Tray
@onready var count_label: Label = $Tray/Content/Info/Count
@onready var slot: PanelContainer = $Tray/Content/Slot
@onready var preview: PanelContainer = $Preview
@onready var preview_rail: TextureRect = $Preview/Contents/Rail
@onready var preview_hint: Label = $Preview/Contents/Hint

var _locations: Array[int] = [0, 1]
var _held_part: int = -1
var _enabled: bool = true
var _rail_texture: AtlasTexture


func _ready() -> void:
	slot.gui_input.connect(_on_slot_input)


func configure(tileset: Texture2D, region: Rect2) -> void:
	# Reuse the same rail sprite as the track, cropped without editing the PNG.
	_rail_texture = AtlasTexture.new()
	_rail_texture.atlas = tileset
	_rail_texture.region = region
	_rail_texture.filter_clip = true
	preview_rail.texture = _rail_texture
	var icon := slot.get_node("Contents/Rail") as TextureRect
	icon.texture = _rail_texture


func update_parts(locations: Array[int], held_part: int, enabled: bool) -> void:
	_locations = locations.duplicate()
	_held_part = held_part
	_enabled = enabled
	var free_parts := locations.count(-1)
	if held_part >= 0 and locations[held_part] == -1:
		free_parts -= 1
	count_label.text = "RAIL INVENTORY  %d/1" % free_parts
	var label := slot.get_node("Contents/Label") as Label
	var icon := slot.get_node("Contents/Rail") as TextureRect
	var stored_part := locations.find(-1)
	icon.visible = stored_part >= 0 and stored_part != held_part
	if held_part >= 0:
		label.text = "IN HAND"
	elif stored_part >= 0:
		label.text = "RAIL"
	else:
		label.text = "EMPTY"
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled and stored_part >= 0 and held_part < 0 else Control.CURSOR_ARROW
	tray.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.65)


func is_over_inventory(viewport_point: Vector2) -> bool:
	# Compare in tray coordinates so window scaling and HUD transforms agree.
	var local_point := tray.get_global_transform_with_canvas().affine_inverse() * viewport_point
	return Rect2(Vector2.ZERO, tray.size).has_point(local_point)


func show_preview(viewport_point: Vector2, valid_drop: bool, hint: String) -> void:
	preview.show()
	preview_hint.text = hint
	preview_hint.add_theme_color_override("font_color", Color("#447342") if valid_drop else Color("#6a6660"))
	preview_rail.modulate = Color("#c8e8ad") if valid_drop else Color.WHITE
	var local_point := get_global_transform_with_canvas().affine_inverse() * viewport_point
	var view_size := size
	preview.position = Vector2(
		clampf(local_point.x + 16.0, 8.0, view_size.x - preview.size.x - 8.0),
		clampf(local_point.y + 16.0, 8.0, view_size.y - preview.size.y - 8.0)
	)


func hide_preview() -> void:
	preview.hide()


func _on_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var stored_part := _locations.find(-1)
			if _enabled and _held_part == -1 and stored_part >= 0:
				drag_requested.emit(stored_part)
			# Inventory clicks never start camera panning.
			accept_event()

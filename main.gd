extends Node2D

@export var conveyor_speed: float = 70.0
@export var ride_speed: float = 220.0
@export var camera_pan_speed: float = 900.0
@export var repair_gap_length: float = 96.0

@onready var camera: Camera2D = $Camera
@onready var track: CoasterTrack = $Track
@onready var cart: PathFollow2D = $Track/Cart
@onready var loss_screen: Control = $HUD/LossScreen
@onready var inventory: RepairInventory = $HUD/Inventory
@onready var train_audio: AudioStreamPlayer = $TrainClack

const TOTAL_PARTS: int = 2
const INVENTORY_CAPACITY: int = 1
# The cart sprite is 52 px wide; leave 4 px extra at its front and rear.
const CART_CLEARANCE: float = 30.0
const CLICK_RADIUS: float = 24.0
const WORLD_WIDTH: float = 11000.0
const IN_INVENTORY: int = -1

# Each value is a fraction of the distance from boarding to the finish.
var gap_starts: Array[float] = [0.06, 0.16, 0.27, 0.38, 0.49, 0.60, 0.71, 0.82, 0.93]
var installed: Array[bool] = []

var available_parts: int = 0
var track_length: float = 0.0

# Distance along the open route; it stops at track_length.
var distance: float = 0.0

var running: bool = false
var crashed: bool = false
var conveyor_start: float = 0.0
var conveyor_end: float = 0.0
var finished: bool = false
var _dragging_camera: bool = false

# Each of our TWO physical parts is either in inventory (-1) or at a gap index.
# A drag previews a move; the real rail stays put until a valid drop succeeds.
# Both rails start installed in the first two repair sections.
var _piece_gaps: Array[int] = [0, 1]
var _dragged_part: int = -1
var _hover_gap: int = -1
var _gap_points: Array[PackedVector2Array] = []


func _ready() -> void:
	installed.resize(gap_starts.size())
	installed.fill(false)
	track.build(gap_starts, repair_gap_length, installed)
	track_length = track.length
	conveyor_start = track.conveyor_start
	conveyor_end = track.conveyor_end
	_cache_gap_targets()
	inventory.configure(track.tileset, track.rail_region)
	inventory.drag_requested.connect(_begin_part_drag)
	_sync_parts()

	cart.loop = false
	cart.rotates = true
	cart.cubic_interp = false
	cart.progress = 0.0

	# The Sprite2D under Cart displays the tileset artwork, configured in
	# main.tscn with its wheel bottoms aligned to the path at local y = 0.

	_set_camera_x(480.0)
	# The title screen's Start game button begins the ride on scene load.
	running = true
	_update_train_audio()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_update_train_audio()
	# Freeze the view behind the loss overlay, including keyboard panning.
	if crashed:
		return

	# Inspection remains possible before launch and after reaching the finish.
	_pan_camera(delta)

	if not running:
		return

	var speed := ride_speed
	if distance < conveyor_end:
		speed = conveyor_speed

	track.advance_conveyor(conveyor_speed * delta)
	var previous_distance := distance
	distance = minf(distance + speed * delta, track_length)
	cart.progress = distance

	# Sweep the whole movement, including the cart's front and rear.
	for i in range(gap_starts.size()):
		if not installed[i] and _overlaps_gap(
			previous_distance - CART_CLEARANCE,
			distance + CART_CLEARANCE,
			i
		):
			crashed = true
			running = false
			# Finish this physics update before showing the loss overlay.
			_show_loss_screen.call_deferred()
			break

	if not crashed and distance >= track_length:
		finished = true
		running = false

	if crashed or finished:
		_cancel_part_drag()
	elif _dragged_part >= 0:
		_update_drag_preview()
	_update_train_audio()
	queue_redraw()


func _update_train_audio() -> void:
	# Start once and let the sound loop; calling play every frame restarts it.
	var climbing := running and not crashed and not finished and conveyor_speed > 0.0
	climbing = climbing and distance >= conveyor_start and distance < conveyor_end
	if climbing:
		train_audio.pitch_scale = 1.0
		if not train_audio.playing:
			train_audio.play()
	elif train_audio.playing:
		train_audio.stop()


func _show_loss_screen() -> void:
	_dragging_camera = false
	_cancel_part_drag()
	# Keep Main alive so its track, cart, and background remain visible.
	loss_screen.show()


func _pan_camera(delta: float) -> void:
	var direction := Input.get_axis("pan_left", "pan_right")
	_set_camera_x(camera.position.x + direction * camera_pan_speed * delta)


func _set_camera_x(value: float) -> void:
	var half_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	camera.position = Vector2(
		clampf(value, half_width, WORLD_WIDTH - half_width),
		270.0
	)
	# Keep repair hit detection current after keyboard or mouse panning.
	camera.force_update_scroll()


func _input(event: InputEvent) -> void:
	# _input runs before GUI controls, so releases work over both track and tray.
	if _dragged_part < 0:
		return
	if crashed or finished:
		_cancel_part_drag()
		return
	if event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_cancel_part_drag()
		else:
			_update_drag_preview()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_part_drag()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_part_drag()
			get_viewport().set_input_as_handled()
		elif event.pressed:
			# Additional presses cannot pick up another rail while dragging.
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel_part_drag()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging_camera = false
		if is_node_ready() and _dragged_part >= 0:
			_cancel_part_drag()


func _unhandled_input(event: InputEvent) -> void:
	# The overlay handles retry/menu input once the ride has crashed.
	if event.is_echo() or crashed:
		return

	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
		return

	if event.is_action_pressed("focus_cart"):
		_set_camera_x(cart.position.x)
		return

	if event.is_action_pressed("start") and not crashed and not finished:
		running = true

	if _dragged_part >= 0:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_camera = false
			if event.pressed:
				# Drag an installed rail. Empty targets never repair on a click.
				if not finished:
					var gap := _find_gap(get_local_mouse_position())
					if gap >= 0:
						var part := _piece_gaps.find(gap)
						if part >= 0:
							_begin_part_drag(part)
						get_viewport().set_input_as_handled()
						return
				_dragging_camera = true
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _dragging_camera:
		# Also stop if the mouse was released outside the game window.
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_dragging_camera = false
			return
		# Move the world with the pointer. Relative movement already accounts
		# for window stretching; dividing by zoom converts it to world units.
		_set_camera_x(camera.position.x - event.relative.x / camera.zoom.x)
		get_viewport().set_input_as_handled()


func _begin_part_drag(part_index: int) -> void:
	if crashed or finished or _dragged_part >= 0:
		return
	if part_index < 0 or part_index >= TOTAL_PARTS or _piece_is_locked(part_index):
		return
	if _piece_gaps[part_index] != IN_INVENTORY and available_parts >= INVENTORY_CAPACITY:
		return
	_dragging_camera = false
	_dragged_part = part_index
	inventory.update_parts(_piece_gaps, _dragged_part, true)
	_update_drag_preview()


func _finish_part_drag() -> void:
	var target := IN_INVENTORY
	if not inventory.is_over_inventory(get_viewport().get_mouse_position()):
		target = _find_gap(get_local_mouse_position())
		if target < 0:
			_cancel_part_drag()
			return
	_commit_part_drop(_dragged_part, target)
	_cancel_part_drag()


func _can_drop_part(part_index: int, target: int) -> bool:
	if crashed or finished or part_index < 0 or part_index >= TOTAL_PARTS:
		return false
	if target < IN_INVENTORY or target >= gap_starts.size():
		return false
	if _piece_is_locked(part_index) or _piece_gaps[part_index] == target:
		return false
	if target == IN_INVENTORY:
		return available_parts < INVENTORY_CAPACITY
	return not installed[target]


func _commit_part_drop(part_index: int, target: int) -> bool:
	# Recheck on RELEASE: the cart may have reached the source during the drag.
	if not _can_drop_part(part_index, target):
		return false
	_piece_gaps[part_index] = target
	_sync_parts()
	return true


func _piece_is_locked(part_index: int) -> bool:
	var source := _piece_gaps[part_index]
	return source >= 0 and _overlaps_gap(
		distance - CART_CLEARANCE, distance + CART_CLEARANCE, source
	)


func _sync_parts() -> void:
	# Derive rail coverage and the count from the two part locations.
	# This prevents losing or duplicating parts when a drop is cancelled.
	installed.fill(false)
	for gap in _piece_gaps:
		if gap >= 0:
			installed[gap] = true
	available_parts = _piece_gaps.count(IN_INVENTORY)
	for i in range(installed.size()):
		track.set_piece_installed(i, installed[i])
	inventory.update_parts(_piece_gaps, _dragged_part, not crashed and not finished)
	queue_redraw()


func _cancel_part_drag() -> void:
	_dragged_part = -1
	_hover_gap = -1
	inventory.hide_preview()
	inventory.update_parts(_piece_gaps, -1, not crashed and not finished)
	queue_redraw()


func _update_drag_preview() -> void:
	var mouse := get_viewport().get_mouse_position()
	var valid := false
	var hint := "Drop on red gap"
	_hover_gap = -1
	if _piece_is_locked(_dragged_part):
		hint = "Rail in use"
	elif inventory.is_over_inventory(mouse):
		valid = _can_drop_part(_dragged_part, IN_INVENTORY)
		hint = "Return to tray" if valid else "Drop on red gap"
	else:
		_hover_gap = _find_gap(get_local_mouse_position())
		if _hover_gap >= 0:
			valid = _can_drop_part(_dragged_part, _hover_gap)
			hint = "Place rail" if valid else "Gap is filled"
	inventory.show_preview(mouse, valid, hint)
	queue_redraw()


func _cache_gap_targets() -> void:
	_gap_points.clear()
	for start in gap_starts:
		var offset := start * track_length
		var end := offset + repair_gap_length
		var points := PackedVector2Array([track.curve.sample_baked(offset)])
		while offset < end:
			offset = minf(offset + 8.0, end)
			points.append(track.curve.sample_baked(offset))
		_gap_points.append(points)


func _find_gap(world_point: Vector2) -> int:
	# Accept drops on either the marker or the actual curved missing rail.
	var closest_gap := -1
	var closest_distance := CLICK_RADIUS
	for i in range(_gap_points.size()):
		var gap_distance := world_point.distance_to(_marker_position(i))
		var points := _gap_points[i]
		for j in range(points.size() - 1):
			var nearest := Geometry2D.get_closest_point_to_segment(world_point, points[j], points[j + 1])
			gap_distance = minf(gap_distance, world_point.distance_to(nearest))
		if gap_distance <= closest_distance:
			closest_distance = gap_distance
			closest_gap = i
	return closest_gap


func _overlaps_gap(
	from_distance: float,
	to_distance: float,
	index: int
) -> bool:
	var gap_start := gap_starts[index] * track_length
	var gap_end := gap_start + repair_gap_length
	return to_distance >= gap_start and from_distance <= gap_end


func _marker_position(index: int) -> Vector2:
	var middle := gap_starts[index] * track_length + repair_gap_length / 2.0
	return track.curve.sample_baked(middle) + Vector2(0, -32)


func _draw() -> void:
	if track_length <= 0.0:
		return

	# Drop targets: red = empty, amber = installed, green = valid drop.
	# A white center means the cart is occupying the piece.
	for i in range(gap_starts.size()):
		var marker := _marker_position(i)
		var marker_color := Color("#c75252")

		if installed[i]:
			marker_color = Color("#f4bf60")

		if i == _hover_gap and _dragged_part >= 0 and _can_drop_part(_dragged_part, i):
			marker_color = Color("#75b06f")
			draw_arc(marker, 22.0, 0.0, TAU, 24, marker_color, 2.0)
		draw_circle(marker, 16.0, marker_color)

		if installed[i] and _overlaps_gap(
			distance - CART_CLEARANCE,
			distance + CART_CLEARANCE,
			i
		):
			draw_circle(marker, 5.0, Color.WHITE)

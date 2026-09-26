extends Node2D

@export var conveyor_speed: float = 70.0
@export var ride_speed: float = 220.0
@export var camera_pan_speed: float = 900.0

@onready var camera: Camera2D = $Camera
@onready var track: CoasterTrack = $Track
@onready var cart: PathFollow2D = $Track/Cart
@onready var loss_screen: Control = $HUD/LossScreen

const TOTAL_PARTS: int = 2
# The cart sprite is 52 px wide; leave 4 px extra at its front and rear.
const CART_CLEARANCE: float = 30.0
const CLICK_RADIUS: float = 24.0
const WORLD_WIDTH: float = 3800.0

# Each value is a fraction of the distance from boarding to the finish.
var gap_starts: Array[float] = [0.18, 0.43, 0.75]
var gap_size: float = 0.015
var installed: Array[bool] = [false, false, false]

var available_parts: int = TOTAL_PARTS
var track_length: float = 0.0

# Distance along the open route; it stops at track_length.
var distance: float = 0.0

var running: bool = false
var crashed: bool = false
var conveyor_end: float = 0.0
var finished: bool = false
var _dragging_camera: bool = false


func _ready() -> void:
	track.build(gap_starts, gap_size, installed)
	track_length = track.length
	conveyor_end = track.conveyor_end

	cart.loop = false
	cart.rotates = true
	cart.cubic_interp = false
	cart.progress = 0.0

	# The Sprite2D under Cart displays the tileset artwork, configured in
	# main.tscn with its wheel bottoms aligned to the path at local y = 0.

	_set_camera_x(480.0)
	# The title screen's Start game button begins the ride on scene load.
	running = true
	queue_redraw()


func _physics_process(delta: float) -> void:
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

	queue_redraw()


func _show_loss_screen() -> void:
	_dragging_camera = false
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

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_camera = false
			if event.pressed:
				# Marker clicks repair rails; only empty space starts a drag.
				if not crashed and not finished:
					var mouse := get_local_mouse_position()
					for i in range(gap_starts.size()):
						if mouse.distance_to(_marker_position(i)) <= CLICK_RADIUS:
							_toggle_piece(i)
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


func _toggle_piece(index: int) -> void:
	# A piece under the cart cannot be removed.
	if installed[index]:
		if _overlaps_gap(
			distance - CART_CLEARANCE,
			distance + CART_CLEARANCE,
			index
		):
			return

		installed[index] = false
		available_parts += 1

	elif available_parts > 0:
		installed[index] = true
		available_parts -= 1

	track.set_piece_installed(index, installed[index])
	queue_redraw()


func _overlaps_gap(
	from_distance: float,
	to_distance: float,
	index: int
) -> bool:
	var gap_start := gap_starts[index] * track_length
	var gap_end := gap_start + gap_size * track_length
	return to_distance >= gap_start and from_distance <= gap_end


func _marker_position(index: int) -> Vector2:
	var middle := (gap_starts[index] + gap_size / 2.0) * track_length
	return track.curve.sample_baked(middle) + Vector2(0, -32)


func _draw() -> void:
	if track_length <= 0.0:
		return

	# Clickable markers: red = empty, amber = installed.
	# A white center means the cart is occupying the piece.
	for i in range(gap_starts.size()):
		var marker := _marker_position(i)
		var marker_color := Color("#c75252")

		if installed[i]:
			marker_color = Color("#f4bf60")

		draw_circle(marker, 16.0, marker_color)

		if installed[i] and _overlaps_gap(
			distance - CART_CLEARANCE,
			distance + CART_CLEARANCE,
			i
		):
			draw_circle(marker, 5.0, Color.WHITE)

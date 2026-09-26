extends Node2D

@export var conveyor_speed: float = 70.0
@export var ride_speed: float = 220.0
@export var camera_pan_speed: float = 900.0

@onready var camera: Camera2D = $Camera
@onready var track: Path2D = $Track
@onready var cart: PathFollow2D = $Track/Cart

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
var belt_offset: float = 0.0
var finished: bool = false


func _ready() -> void:
	_build_track()
	track_length = track.curve.get_baked_length()

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


func _build_track() -> void:
	track.curve = Curve2D.new()
	track.curve.bake_interval = 2.0

	# Boarding platform.
	track.curve.add_point(
		Vector2(100, 440),
		Vector2.ZERO,
		Vector2(40, 0)
	)

	# Beginning of the conveyor incline.
	track.curve.add_point(
		Vector2(220, 440),
		Vector2(-40, 0),
		Vector2(100, -100)
	)

	# Top of the conveyor lift.
	track.curve.add_point(
		Vector2(520, 160),
		Vector2(-100, 0),
		Vector2(120, 0)
	)

	# Record where the conveyor section ends.
	conveyor_end = track.curve.get_baked_length()

	# First drop.
	track.curve.add_point(
		Vector2(900, 440),
		Vector2(-160, 0),
		Vector2(80, 0)
	)

	_add_loop(Vector2(1140, 440), 145.0)

	# Hill between the loops.
	track.curve.add_point(
		Vector2(1500, 440),
		Vector2(-90, 0),
		Vector2(130, 0)
	)
	track.curve.add_point(
		Vector2(1840, 240),
		Vector2(-140, 0),
		Vector2(140, 0)
	)
	track.curve.add_point(
		Vector2(2150, 440),
		Vector2(-130, 0),
		Vector2(80, 0)
	)

	_add_loop(Vector2(2540, 440), 150.0)

	# Final hill and arrival platform.
	track.curve.add_point(
		Vector2(2880, 440),
		Vector2(-90, 0),
		Vector2(100, 0)
	)
	track.curve.add_point(
		Vector2(3100, 300),
		Vector2(-100, 0),
		Vector2(100, 0)
	)
	track.curve.add_point(
		Vector2(3360, 440),
		Vector2(-100, 0),
		Vector2(80, 0)
	)
	track.curve.add_point(
		Vector2(3600, 440),
		Vector2(-80, 0),
		Vector2.ZERO
	)


func _add_loop(base: Vector2, radius: float) -> void:
	var center := base + Vector2(0, -radius)

	# Handle length for approximating a quarter circle.
	var handle := radius * 0.5522848

	# Enter at the bottom, travelling right.
	track.curve.add_point(
		base,
		Vector2(-80, 0),
		Vector2(handle, 0)
	)

	# Right side.
	track.curve.add_point(
		center + Vector2(radius, 0),
		Vector2(0, handle),
		Vector2(0, -handle)
	)

	# Top.
	track.curve.add_point(
		center + Vector2(0, -radius),
		Vector2(handle, 0),
		Vector2(-handle, 0)
	)

	# Left side.
	track.curve.add_point(
		center + Vector2(-radius, 0),
		Vector2(0, -handle),
		Vector2(0, handle)
	)

	# Return to the bottom and exit right.
	track.curve.add_point(
		base,
		Vector2(-handle, 0),
		Vector2(80, 0)
	)


func _physics_process(delta: float) -> void:
	# Inspection remains possible before launch and after the result.
	_pan_camera(delta)

	if not running:
		return

	var speed := ride_speed
	if distance < conveyor_end:
		speed = conveyor_speed

	belt_offset = fposmod(belt_offset + conveyor_speed * delta, 20.0)
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
			break

	if not crashed and distance >= track_length:
		finished = true
		running = false

	queue_redraw()


func _pan_camera(delta: float) -> void:
	var direction := Input.get_axis("pan_left", "pan_right")
	_set_camera_x(camera.position.x + direction * camera_pan_speed * delta)


func _set_camera_x(value: float) -> void:
	var half_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	camera.position = Vector2(
		clampf(value, half_width, WORLD_WIDTH - half_width),
		270.0
	)
	# Keep mouse-to-world coordinates current after panning or pressing F.
	camera.force_update_scroll()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return

	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
		return

	if event.is_action_pressed("focus_cart"):
		_set_camera_x(cart.position.x)
		return

	if event.is_action_pressed("start") and not crashed and not finished:
		running = true

	if crashed or finished:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse := get_local_mouse_position()

			for i in range(gap_starts.size()):
				if mouse.distance_to(_marker_position(i)) <= CLICK_RADIUS:
					_toggle_piece(i)
					break


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

	queue_redraw()


func _overlaps_gap(
	from_distance: float,
	to_distance: float,
	index: int
) -> bool:
	var gap_start := gap_starts[index] * track_length
	var gap_end := gap_start + gap_size * track_length
	return to_distance >= gap_start and from_distance <= gap_end


func _gap_at(offset: float) -> int:
	for i in range(gap_starts.size()):
		var gap_start := gap_starts[i] * track_length
		var gap_end := gap_start + gap_size * track_length

		if offset >= gap_start and offset <= gap_end:
			return i

	return -1


func _marker_position(index: int) -> Vector2:
	var middle := (gap_starts[index] + gap_size / 2.0) * track_length
	return track.curve.sample_baked(middle) + Vector2(0, -32)


func _draw() -> void:
	if track_length <= 0.0:
		return

	# Draw the route as short line segments, omitting empty gaps.
	var offset := 0.0
	while offset < track_length:
		var next_offset := minf(offset + 4.0, track_length)
		var gap := _gap_at((offset + next_offset) / 2.0)

		if gap == -1 or installed[gap]:
			var rail_color := Color("#ff7a36")
			if gap != -1:
				rail_color = Color("#f4bf60")

			draw_line(
				track.curve.sample_baked(offset),
				track.curve.sample_baked(next_offset),
				rail_color,
				5.0
			)

		offset = next_offset

	_draw_conveyor()

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


func _draw_conveyor() -> void:
	var offset := belt_offset
	while offset < conveyor_end:
		var pose := track.curve.sample_baked_with_rotation(offset)
		var across := pose.y * 5.0
		draw_line(
			pose.origin - across,
			pose.origin + across,
			Color("#f4bf60"),
			3.0
		)
		offset += 20.0

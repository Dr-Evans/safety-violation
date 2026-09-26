extends Node2D

@export var conveyor_speed: float = 80.0
@export var initial_speed: float = 160.0
@export var speed_increase_per_second: float = 6.0
@export var maximum_speed: float = 440.0
@export var repair_bonus: int = 100

@onready var track: CoasterTrack = $Track
@onready var cart: Node2D = $Cart
@onready var cart_visual: CartVisual = $Cart/Visual
@onready var inventory: RepairInventory = $HUD/Inventory
@onready var loss_screen: Control = $HUD/LossScreen
@onready var train_audio: AudioStreamPlayer = $TrainClack
@onready var repair_audio: AudioStreamPlayer = $RepairSound
@onready var crash_audio: AudioStreamPlayer = $CrashSound
@onready var score_label: Label = $HUD/Score/Content/Score
@onready var distance_label: Label = $HUD/Score/Content/Details
@onready var background_layers: Array[Parallax2D] = [
	$Background/Artwork/Clouds, $Background/Artwork/FarMountains,
	$Background/Artwork/NearMountains, $Background/Artwork/Ground
]

const CART_X: float = 260.0
const CART_CLEARANCE: float = 30.0
const DROP_RADIUS: float = 28.0
const REPAIR_ACTIONS = ["repair_rising", "repair_flat", "repair_falling", "repair_loop"]

var distance: float = 0.0
var score: int = 0
var repairs: int = 0
var crashed: bool = false
var _bonus_points: int = 0
var _ride_elapsed: float = 0.0
var _current_speed: float = 160.0
var _scroll_x: float = 0.0
var _dragged_kind: int = -1
var _hover_id: int = -1
var _feedback: String = ""
var _feedback_remaining: float = 0.0


func _ready() -> void:
	_current_speed = maxf(initial_speed, 1.0)
	track.begin_run()
	inventory.configure(track.tileset)
	inventory.drag_requested.connect(_begin_drag)
	for layer in background_layers:
		layer.ignore_camera_scroll = true
	_update_world()
	_update_hud()
	_update_targets()


func _physics_process(delta: float) -> void:
	if crashed:
		return
	var segment := track.segment_at(distance)
	if segment == null:
		return
	if not segment.conveyor:
		_ride_elapsed += delta
	_current_speed = maxf(0.0, conveyor_speed) if segment.conveyor else minf(
		maxf(initial_speed, 1.0) + maxf(speed_increase_per_second, 0.0) * _ride_elapsed,
		maxf(maximum_speed, initial_speed)
	)
	if segment.conveyor:
		segment.advance_chain(_current_speed * delta)
	track.ensure_ahead(distance + _current_speed * delta, _scroll_x)
	var previous_distance := distance
	_advance(_current_speed * delta)
	# Keep visual motion tied to the actual distance travelled.
	cart_visual.advance(distance - previous_distance, delta)
	if crashed:
		cart_visual.reset_suspension()
		return
	track.prune(distance)
	_update_world()
	_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
	_update_hud()
	_update_targets()
	_update_train_audio()
	if _dragged_kind >= 0:
		_update_drag_preview()


func _advance(amount: float) -> void:
	var next_distance := distance + amount
	# Sweep the whole step, including the nose of the cart, even at high speed.
	for segment in track.segments:
		if not segment.broken:
			continue
		var gap_start := segment.start_distance + segment.gap_start
		var gap_end := segment.start_distance + segment.gap_end
		if next_distance + CART_CLEARANCE >= gap_start and distance - CART_CLEARANCE <= gap_end:
			distance = maxf(distance, gap_start - CART_CLEARANCE)
			_crash()
			return
	distance = next_distance


func _update_world() -> void:
	var segment := track.segment_at(distance)
	if segment == null:
		return
	var local_distance := clampf(distance - segment.start_distance, 0.0, segment.length)
	var pose := segment.curve.sample_baked_with_rotation(local_distance)
	# Scroll steadily forward through a loop, letting the cart travel around it.
	_scroll_x = segment.position.x + segment.width * local_distance / segment.length
	track.position.x = CART_X - _scroll_x
	cart.position = track.position + segment.position + pose.origin
	cart.rotation = pose.get_rotation()
	for layer in background_layers:
		layer.scroll_offset.x = -fposmod(distance * layer.scroll_scale.x, layer.repeat_size.x)


func _update_hud() -> void:
	score = int(distance / 10.0) + _bonus_points
	score_label.text = "SCORE  %d" % score
	distance_label.text = "%dm  |  SPEED %.2fx  |  %d REPAIRS" % [
		int(distance / 10.0), _current_speed / maxf(initial_speed, 1.0), repairs
	]
	var next := _next_gap()
	var instruction := "NO GAP AHEAD"
	if next != null:
		instruction = "NEXT: %s [%s]" % [RailSegment.TYPE_NAMES[next.kind], RailSegment.TYPE_KEYS[next.kind]]
	inventory.set_instruction(instruction, _feedback if _feedback_remaining > 0.0 else "Drag or press A / S / D / F.")


func _can_repair(segment: RailSegment) -> bool:
	return not crashed and segment != null and segment.broken and (
		distance + CART_CLEARANCE < segment.start_distance + segment.gap_start
	)


func _visible_gap(segment: RailSegment) -> bool:
	var screen := segment.get_global_transform_with_canvas() * segment.marker_position()
	var view := get_viewport_rect().size
	return screen.x >= 30.0 and screen.x <= view.x - 30.0 and screen.y >= 90.0 and screen.y <= view.y - 100.0


func _next_gap() -> RailSegment:
	# Keyboard repairs the nearest gap along the route, never an offscreen gap.
	for segment in track.segments:
		if _can_repair(segment) and _visible_gap(segment):
			return segment
	return null


func _gap_under_mouse() -> RailSegment:
	var closest: RailSegment = null
	var radius := DROP_RADIUS
	var mouse := get_global_mouse_position()
	for segment in track.segments:
		if not _can_repair(segment) or not _visible_gap(segment):
			continue
		var separation := segment.distance_to_gap(segment.to_local(mouse))
		if separation <= radius:
			radius = separation
			closest = segment
	return closest


func _try_repair(segment: RailSegment, kind: int) -> bool:
	if not _can_repair(segment):
		return false
	if segment.kind != kind:
		_set_feedback("Wrong rail! Use %s [%s]." % [
			RailSegment.TYPE_NAMES[segment.kind], RailSegment.TYPE_KEYS[segment.kind]
		])
		return false
	if not segment.install():
		return false
	_bonus_points += maxi(repair_bonus, 0)
	repairs += 1
	repair_audio.play()
	_set_feedback("+%d  Correct rail!" % maxi(repair_bonus, 0))
	_update_hud()
	_update_targets()
	return true


func _set_feedback(message: String) -> void:
	_feedback = message
	_feedback_remaining = 1.5
	_update_hud()


func _update_targets() -> void:
	var next := _next_gap()
	for segment in track.segments:
		var hover_state := 0
		if segment.segment_id == _hover_id and _dragged_kind >= 0:
			hover_state = 1 if segment.kind == _dragged_kind else -1
		segment.set_target(segment == next, hover_state)


func _input(event: InputEvent) -> void:
	if crashed or event.is_echo():
		return
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
		return
	for kind in range(REPAIR_ACTIONS.size()):
		if event.is_action_pressed(REPAIR_ACTIONS[kind]):
			get_viewport().set_input_as_handled()
			_cancel_drag()
			var next := _next_gap()
			if next != null:
				_try_repair(next, kind)
			return
	if _dragged_kind < 0:
		return
	if event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_cancel_drag()
		else:
			_update_drag_preview()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_drag()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel_drag()
		get_viewport().set_input_as_handled()


func _begin_drag(kind: int) -> void:
	if crashed or _dragged_kind >= 0 or kind < 0 or kind > RailSegment.LOOP:
		return
	_dragged_kind = kind
	inventory.set_controls_enabled(true, _dragged_kind)
	_update_drag_preview()


func _finish_drag() -> void:
	var target := _gap_under_mouse()
	if target != null:
		_try_repair(target, _dragged_kind)
	_cancel_drag()


func _cancel_drag() -> void:
	_dragged_kind = -1
	_hover_id = -1
	inventory.hide_preview()
	inventory.set_controls_enabled(not crashed)
	_update_targets()


func _update_drag_preview() -> void:
	var target := _gap_under_mouse()
	_hover_id = target.segment_id if target != null else -1
	var valid := target != null and target.kind == _dragged_kind
	var message := "Drop on a red gap"
	if target != null:
		message = "Place rail" if valid else "Needs %s" % RailSegment.TYPE_NAMES[target.kind]
	inventory.show_preview(get_viewport().get_mouse_position(), _dragged_kind, valid, message)
	_update_targets()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready():
		_cancel_drag()


func _update_train_audio() -> void:
	var segment := track.segment_at(distance)
	var climbing := not crashed and segment != null and segment.conveyor and _current_speed > 0.0
	if climbing and not train_audio.playing:
		train_audio.play()
	elif not climbing and train_audio.playing:
		train_audio.stop()


func _crash() -> void:
	crashed = true
	_cancel_drag()
	_update_world()
	_update_hud()
	train_audio.stop()
	crash_audio.play()
	# Freeze the generated track behind the existing loss overlay.
	loss_screen.call_deferred("show_results", score, distance / 10.0, repairs)

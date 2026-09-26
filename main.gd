extends Node2D

@export var conveyor_speed: float = 80.0
@export var initial_speed: float = 220.0
@export var speed_increase_per_second: float = 6.0
@export var music_full_speed_at: float = 440.0
@export_range(1.0, 2.0, 0.05) var maximum_music_speed: float = 1.25
@export var repair_bonus: int = 100
# Minimum and maximum delay between birds, in seconds.
@export var bird_spawn_interval := Vector2(6.0, 10.0)
@export_range(0.8, 3.0, 0.1) var bird_landing_duration: float = 1.8

@onready var track: CoasterTrack = $Track
@onready var cart: Node2D = $Cart
@onready var wagons: Array[Node2D] = [$Cart, $MiddleWagon, $RearWagon]
@onready var cart_visuals: Array[CartVisual] = [
	$Cart/Visual, $MiddleWagon/Visual, $RearWagon/Visual
]
@onready var couplers: Array[Line2D] = [$FrontCoupler, $RearCoupler]
@onready var inventory: RepairInventory = $HUD/Inventory
@onready var loss_screen: Control = $HUD/LossScreen
@onready var train_audio: AudioStreamPlayer = $TrainClack
@onready var soundtrack: AudioStreamPlayer = $Soundtrack
@onready var repair_audio: AudioStreamPlayer = $RepairSound
@onready var crash_audio: AudioStreamPlayer = $CrashSound
@onready var score_label: Label = $HUD/Score/Content/Score
@onready var distance_label: Label = $HUD/Score/Content/Details
@onready var background_layers: Array[Parallax2D] = [
	$Background/Artwork/Clouds, $Background/Artwork/FarMountains,
	$Background/Artwork/NearMountains, $Background/Artwork/Ground
]

const CART_X: float = 260.0
const WAGON_SPACING: float = 60.0
const CART_CLEARANCE: float = 30.0
const LOOP_SPEED_BONUS: float = 0.1
const REPAIR_ACTIONS = ["repair_rising", "repair_flat", "repair_falling", "repair_loop"]
const BIRD_REACTION_TIME: float = 1.0
const BIRD_MIN_DESCENT: float = 0.8

var distance: float = 0.0
var score: int = 0
var repairs: int = 0
var crashed: bool = false
var _bonus_points: int = 0
var _ride_elapsed: float = 0.0
var _loop_speed_bonus: float = 0.0
var _current_speed: float = 220.0
var _soundtrack_start_distance: float = INF
var _scroll_x: float = 0.0
var _feedback: String = ""
var _feedback_remaining: float = 0.0
var _birds: Array[BirdObstacle] = []
var _bird_rng := RandomNumberGenerator.new()
var _bird_spawn_remaining: float = 0.0


func _ready() -> void:
	_current_speed = maxf(initial_speed, 1.0)
	track.begin_run()
	_bird_rng.randomize()
	_reset_bird_timer()
	for segment in track.segments:
		if segment.conveyor:
			_soundtrack_start_distance = segment.start_distance + segment.length
			break
	var starting_segment := track.segment_at(distance)
	if starting_segment != null and starting_segment.conveyor:
		_current_speed = maxf(conveyor_speed, 0.0)
	inventory.configure(track.tileset)
	inventory.repair_requested.connect(_repair_next_gap)
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
	_current_speed = maxf(0.0, conveyor_speed) if segment.conveyor else _riding_speed()
	if segment.conveyor:
		segment.advance_chain(_current_speed * delta)
	track.ensure_ahead(distance + _current_speed * delta, _scroll_x)
	_update_birds(delta)
	var previous_distance := distance
	_advance(_current_speed * delta)
	# Keep visual motion tied to the actual distance travelled.
	for visual in cart_visuals:
		visual.advance(distance - previous_distance, delta)
	if crashed:
		for visual in cart_visuals:
			visual.reset_suspension()
		return
	# Keep the rails under the final wagon until the entire train has passed.
	track.prune(distance - WAGON_SPACING * (wagons.size() - 1))
	_update_world()
	_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
	_update_hud()
	_update_targets()
	_update_train_audio()
	_update_soundtrack()


func _riding_speed() -> float:
	var base_speed := maxf(initial_speed, 1.0)
	return base_speed + maxf(speed_increase_per_second, 0.0) * _ride_elapsed + _loop_speed_bonus


func _advance(amount: float) -> void:
	var next_distance := distance + amount
	var collision_distance := INF
	# Sweep the whole step, including the nose of the cart, even at high speed.
	for segment in track.segments:
		if not segment.broken:
			continue
		var gap_start := segment.start_distance + segment.gap_start
		var gap_end := segment.start_distance + segment.gap_end
		if next_distance + CART_CLEARANCE >= gap_start and distance - CART_CLEARANCE <= gap_end:
			collision_distance = minf(collision_distance, maxf(distance, gap_start - CART_CLEARANCE))
	for bird in _birds:
		if not is_instance_valid(bird) or not bird.is_blocking():
			continue
		if next_distance + CART_CLEARANCE >= bird.route_distance and distance - CART_CLEARANCE <= bird.route_distance:
			collision_distance = minf(collision_distance, maxf(distance, bird.route_distance - CART_CLEARANCE))
	if collision_distance < INF:
		distance = collision_distance
		_crash()
		return
	var completed_loops := 0
	for segment in track.segments:
		if segment.kind != RailSegment.LOOP:
			continue
		# gap_end marks the bottom of the completed circle, before the exit rail.
		var loop_end := segment.start_distance + segment.gap_end
		if distance < loop_end and next_distance >= loop_end:
			completed_loops += 1
	distance = next_distance
	if completed_loops > 0:
		_loop_speed_bonus += maxf(initial_speed, 1.0) * LOOP_SPEED_BONUS * completed_loops
		_current_speed = _riding_speed()
		_set_feedback("Loop complete! +%.1fx speed" % (LOOP_SPEED_BONUS * completed_loops))


func _update_world() -> void:
	var segment := track.segment_at(distance)
	if segment == null:
		return
	var local_distance := clampf(distance - segment.start_distance, 0.0, segment.length)
	# Scroll steadily forward through a loop, letting the cart travel around it.
	_scroll_x = segment.position.x + segment.width * local_distance / segment.length
	track.position.x = CART_X - _scroll_x
	for i in range(wagons.size()):
		var wagon_distance := distance - WAGON_SPACING * i
		var wagon_segment := track.segment_at(wagon_distance)
		if wagon_segment == null:
			continue
		var wagon_offset := clampf(wagon_distance - wagon_segment.start_distance, 0.0, wagon_segment.length)
		var pose := wagon_segment.curve.sample_baked_with_rotation(wagon_offset)
		wagons[i].position = track.position + wagon_segment.position + pose.origin
		wagons[i].rotation = pose.get_rotation()
	for i in range(couplers.size()):
		couplers[i].points = PackedVector2Array([
			wagons[i].position + Vector2(-24, -8).rotated(wagons[i].rotation),
			wagons[i + 1].position + Vector2(24, -8).rotated(wagons[i + 1].rotation)
		])
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
	var hint := "Click or press A / S / D / F."
	for bird in _birds:
		if is_instance_valid(bird) and bird.can_clear():
			hint = "Click the bird before the train!"
			break
	inventory.set_instruction(instruction, _feedback if _feedback_remaining > 0.0 else hint)


func _can_repair(segment: RailSegment) -> bool:
	return not crashed and segment != null and segment.broken and (
		distance + CART_CLEARANCE < segment.start_distance + segment.gap_start
	)


func _visible_gap(segment: RailSegment) -> bool:
	var screen := segment.get_global_transform_with_canvas() * segment.marker_position()
	var view := get_viewport_rect().size
	return screen.x >= 30.0 and screen.x <= view.x - 30.0 and screen.y >= 90.0 and screen.y <= view.y - 100.0


func _next_gap() -> RailSegment:
	# Clicks and keyboard shortcuts repair the nearest visible gap along the route.
	for segment in track.segments:
		if _can_repair(segment) and _visible_gap(segment):
			return segment
	return null


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
		segment.set_target(segment == next)


func _input(event: InputEvent) -> void:
	if crashed or event.is_echo():
		return
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var click_global: Vector2 = get_canvas_transform().affine_inverse() * event.position
		for bird in _birds:
			if is_instance_valid(bird) and bird.hit_test(click_global):
				bird.dismiss()
				repair_audio.play()
				_set_feedback("Bird cleared!")
				get_viewport().set_input_as_handled()
				return
	for kind in range(REPAIR_ACTIONS.size()):
		if event.is_action_pressed(REPAIR_ACTIONS[kind]):
			get_viewport().set_input_as_handled()
			_repair_next_gap(kind)
			return


func _repair_next_gap(kind: int) -> void:
	if crashed or kind < 0 or kind > RailSegment.LOOP:
		return
	var next := _next_gap()
	if next != null:
		_try_repair(next, kind)


func _reset_bird_timer() -> void:
	var minimum := maxf(1.0, bird_spawn_interval.x)
	_bird_spawn_remaining = _bird_rng.randf_range(minimum, maxf(minimum, bird_spawn_interval.y))


func _update_birds(delta: float) -> void:
	for i in range(_birds.size() - 1, -1, -1):
		var bird := _birds[i]
		if not is_instance_valid(bird):
			_birds.remove_at(i)
			continue
		bird.advance(delta)
		bird.set_hovered(bird.hit_test(get_global_mouse_position()))
	# Leave the boarding platform, conveyor and first safe exit free of birds.
	var current := track.segment_at(distance)
	if current == null or current.segment_id < 3 or current.conveyor:
		return
	_bird_spawn_remaining -= delta
	if _bird_spawn_remaining > 0.0 or not _birds.is_empty():
		return
	if _spawn_bird():
		_reset_bird_timer()
	else:
		# Wait for a visible rail with enough time to descend and react.
		_bird_spawn_remaining = 0.5


func _spawn_bird() -> bool:
	var landing_segment: RailSegment = null
	var landing_offset: float = 0.0
	var best_distance: float = distance
	var landing_screen := Vector2.ZERO
	var view := get_viewport_rect().size
	var duration := maxf(bird_landing_duration, BIRD_MIN_DESCENT)
	var descent_budget := duration + BIRD_REACTION_TIME
	# Account for acceleration during the approach when reserving reaction time.
	var approach_speed := maxf(_current_speed + maxf(speed_increase_per_second, 0.0) * descent_budget, 1.0)
	track.ensure_ahead(distance + approach_speed * descent_budget, _scroll_x)
	for segment in track.segments:
		if segment.start_distance + segment.length <= distance:
			continue
		# Avoid the circle and routes that would change speed during the descent.
		if segment.kind == RailSegment.LOOP:
			break
		if segment.conveyor or segment.segment_id < 3:
			continue
		for fraction in [0.25, 0.82]:
			var offset: float = segment.length * fraction
			if segment.broken and offset >= segment.gap_start - 48.0 and offset <= segment.gap_end + 48.0:
				continue
			var target_distance := segment.start_distance + offset
			var time_to_train := (target_distance - distance - CART_CLEARANCE) / approach_speed
			if time_to_train < descent_budget:
				continue
			var point := segment.get_global_transform_with_canvas() * segment.curve.sample_baked(offset)
			# The rail may start offscreen, but scrolls into view during the flight.
			var predicted_screen := point - Vector2(_current_speed * duration, 0)
			if predicted_screen.x < CART_X + 200.0 or predicted_screen.x > view.x - 75.0 or point.y < 150.0 or point.y > view.y - 130.0:
				continue
			if target_distance > best_distance:
				landing_segment = segment
				landing_offset = offset
				best_distance = target_distance
				landing_screen = predicted_screen
	if landing_segment == null:
		return false
	var arrival_screen := Vector2(minf(landing_screen.x + 35.0, view.x - 40.0), -32.0)
	var arrival_global := get_canvas_transform().affine_inverse() * arrival_screen
	var bird := BirdObstacle.new()
	# Parenting to the rail keeps the landing fixed through scrolling and rebasing.
	landing_segment.add_child(bird)
	bird.configure(landing_segment, landing_offset, arrival_global, duration)
	_birds.append(bird)
	return true


func _update_soundtrack() -> void:
	if crashed or distance < _soundtrack_start_distance:
		return
	# Increase the music gently from normal speed to the configured cap.
	var base_speed := maxf(initial_speed, 1.0)
	var speed_progress := clampf(
		(_current_speed - base_speed) / maxf(music_full_speed_at - base_speed, 1.0), 0.0, 1.0
	)
	soundtrack.pitch_scale = lerpf(1.0, maximum_music_speed, speed_progress)
	if not soundtrack.playing:
		soundtrack.play()


func _update_train_audio() -> void:
	var segment := track.segment_at(distance)
	var climbing := not crashed and segment != null and segment.conveyor and _current_speed > 0.0
	if climbing and not train_audio.playing:
		train_audio.play()
	elif not climbing and train_audio.playing:
		train_audio.stop()


func _crash() -> void:
	crashed = true
	inventory.set_controls_enabled(false)
	_update_world()
	_update_hud()
	train_audio.stop()
	soundtrack.stop()
	crash_audio.play()
	# Freeze the generated track behind the existing loss overlay.
	loss_screen.call_deferred("show_results", score, distance / 10.0, repairs)

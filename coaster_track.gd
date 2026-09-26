class_name CoasterTrack
extends Node2D

@export var tileset: Texture2D
@export_range(0.0, 1.0, 0.05) var broken_probability: float = 0.6
# Set a nonzero seed to reproduce a particular route while tuning.
@export var generation_seed: int = 0

var segments: Array[RailSegment] = []
var _rng := RandomNumberGenerator.new()
var _tail_x: float = -260.0
var _tail_y: float = 400.0
var _tail_distance: float = -260.0
var _next_id: int = 0
var _since_loop: int = 0
var _next_loop: int = 9


func begin_run() -> void:
	for segment in segments:
		segment.free()
	segments.clear()
	_tail_x = -260.0
	_tail_y = 400.0
	_tail_distance = -260.0
	_next_id = 0
	_since_loop = 0
	if generation_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = generation_seed
	_next_loop = _rng.randi_range(8, 12)
	# A safe boarding platform, conveyor climb and exit give time to learn.
	_append_segment(RailSegment.FLAT, 400.0, false, false, 360.0)
	_append_segment(RailSegment.RISING, 310.0, false, true)
	_append_segment(RailSegment.FLAT, 310.0, false)
	ensure_ahead(0.0, 0.0)


func ensure_ahead(distance: float, scroll_x: float) -> void:
	# Check both horizontal coverage and path length: loops use lots of path.
	while _tail_x < scroll_x + 1400.0 or _tail_distance < distance + 1800.0:
		_generate_segment()


func _generate_segment() -> void:
	if _since_loop >= _next_loop:
		if _tail_y >= 390.0:
			_append_segment(RailSegment.LOOP, _tail_y, _rng.randf() < broken_probability, false, 520.0)
			_since_loop = 0
			_next_loop = _rng.randi_range(8, 12)
			return
		# Bring an elevated section down before starting a full loop.
		_append_segment(RailSegment.FALLING, minf(_tail_y + 90.0, 400.0), _rng.randf() < broken_probability)
		_since_loop += 1
		return
	var choices: Array[int] = [RailSegment.FLAT]
	if _tail_y > 220.0:
		choices.append(RailSegment.RISING)
	if _tail_y < 400.0:
		choices.append(RailSegment.FALLING)
	var kind := choices[_rng.randi_range(0, choices.size() - 1)]
	var next_y := _tail_y
	if kind == RailSegment.RISING:
		next_y -= 90.0
	elif kind == RailSegment.FALLING:
		next_y += 90.0
	_append_segment(kind, next_y, _rng.randf() < broken_probability)
	_since_loop += 1


func _append_segment(kind: int, end_y: float, broken: bool,
	conveyor: bool = false, width: float = 320.0) -> void:
	var segment := RailSegment.new()
	segment.segment_id = _next_id
	_next_id += 1
	segment.start_distance = _tail_distance
	segment.position = Vector2(_tail_x, 0)
	segment.configure(tileset, kind, _tail_y, end_y, broken, conveyor, width)
	add_child(segment)
	segments.append(segment)
	_tail_x += width
	_tail_y = end_y
	_tail_distance += segment.length


func segment_at(distance: float) -> RailSegment:
	for segment in segments:
		if distance < segment.start_distance + segment.length:
			return segment
	return null


func find_segment(segment_id: int) -> RailSegment:
	for segment in segments:
		if segment.segment_id == segment_id:
			return segment
	return null


func prune(distance: float) -> void:
	# Keep the previous section visible behind the cart and free older ones.
	while segments.size() > 2 and segments[1].start_distance + segments[1].length < distance:
		var old := segments.pop_front() as RailSegment
		old.free()
	# Rebase local positions; endless play never accumulates huge coordinates.
	if not segments.is_empty() and segments[0].position.x > 2000.0:
		var shift := segments[0].position.x
		for segment in segments:
			segment.position.x -= shift
		_tail_x -= shift

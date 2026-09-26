class_name BirdObstacle
extends Node2D

const PERCHED: Texture2D = preload("res://assets/background 2.0/bird_stay.png")
const WINGS_UP: Texture2D = preload("res://assets/background 2.0/bird_fly_wings_up.png")
const WINGS_DOWN: Texture2D = preload("res://assets/background 2.0/bird_fly_wings_down.png")
const CLICK_RADIUS: float = 28.0
const SPRITE_SCALE: float = 3.0
const FLAP_INTERVAL: float = 0.14
const ESCAPE_DURATION: float = 0.8

enum State { APPROACHING, LANDED, LEAVING }

var route_distance: float = 0.0
var state: State = State.APPROACHING
var _landing_point := Vector2.ZERO
var _arrival_point := Vector2.ZERO
var _landing_duration: float = 1.8
var _elapsed: float = 0.0
var _animation_time: float = 0.0
var _hovered: bool = false
var _sprite: Sprite2D
var _hint: Label


func _ready() -> void:
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite = Sprite2D.new()
	_sprite.texture = WINGS_UP
	_sprite.scale = Vector2.ONE * SPRITE_SCALE
	# Align the feet with the rail, accounting for the transparent bottom row.
	_sprite.position = Vector2(0, -(PERCHED.get_height() * 0.5 - 1.0) * SPRITE_SCALE)
	add_child(_sprite)
	_hint = Label.new()
	_hint.text = "CLICK BIRD"
	_hint.position = Vector2(-60, -70)
	_hint.size = Vector2(120, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color("#fff3d6"))
	_hint.add_theme_color_override("font_outline_color", Color("#172126"))
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(_hint)


func configure(segment: RailSegment, local_distance: float,
	arrival_global: Vector2, duration: float) -> void:
	route_distance = segment.start_distance + local_distance
	_landing_point = segment.curve.sample_baked(local_distance)
	_arrival_point = segment.to_local(arrival_global)
	_landing_duration = maxf(duration, 0.1)
	position = _arrival_point


func advance(delta: float) -> void:
	_elapsed += delta
	_animation_time += delta
	if state == State.APPROACHING:
		var progress := clampf(_elapsed / _landing_duration, 0.0, 1.0)
		# Ease into the landing while the parent rail scrolls toward the train.
		var eased := 1.0 - pow(1.0 - progress, 2.0)
		position = _arrival_point.lerp(_landing_point, progress)
		position.y = lerpf(_arrival_point.y, _landing_point.y, eased)
		position.x += sin(progress * PI) * 24.0
		if progress >= 1.0:
			state = State.LANDED
	elif state == State.LEAVING:
		position += Vector2(150, -560) * delta
		modulate.a = clampf(1.0 - _elapsed / ESCAPE_DURATION, 0.0, 1.0)
		if _elapsed >= ESCAPE_DURATION:
			queue_free()
	_sprite.texture = PERCHED if state == State.LANDED else (
		WINGS_UP if int(_animation_time / FLAP_INTERVAL) % 2 == 0 else WINGS_DOWN
	)


func can_clear() -> bool:
	return state != State.LEAVING


func is_blocking() -> bool:
	return state == State.LANDED


func hit_test(global_point: Vector2) -> bool:
	return can_clear() and to_local(global_point).distance_to(_sprite.position) <= CLICK_RADIUS


func dismiss() -> void:
	state = State.LEAVING
	_elapsed = 0.0
	_hint.hide()
	_hovered = false
	queue_redraw()


func set_hovered(hovered: bool) -> void:
	if _hovered != hovered:
		_hovered = hovered
		queue_redraw()


func _draw() -> void:
	if not can_clear() or _sprite == null:
		return
	var color := Color("#fff3d6") if _hovered else Color("#eaa34f")
	draw_arc(_sprite.position, CLICK_RADIUS, 0.0, TAU, 32, color, 2.0)

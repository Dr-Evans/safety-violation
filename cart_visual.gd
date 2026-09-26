class_name CartVisual
extends Node2D

@export_range(0.0, 1.0, 0.05) var motion_amount: float = 1.0

const WHEEL_RADIUS: float = 4.0
const RATTLE_DISTANCE: float = 32.0

@onready var rear_spoke: Polygon2D = $RearSpoke
@onready var front_spoke: Polygon2D = $FrontSpoke

var _travel: float = 0.0
var _wheel_angle: float = 0.0


func advance(movement: float, delta: float) -> void:
	if motion_amount <= 0.0:
		rear_spoke.rotation = 0.0
		front_spoke.rotation = 0.0
		reset_suspension()
		return

	if movement <= 0.0 or delta <= 0.0:
		reset_suspension()
		return

	# Distance drives the wheels and rattle, so both follow the actual ride speed.
	_travel = fposmod(_travel + movement, RATTLE_DISTANCE * 2.0)
	_wheel_angle = fposmod(_wheel_angle + movement / WHEEL_RADIUS, TAU)
	rear_spoke.rotation = _wheel_angle
	front_spoke.rotation = _wheel_angle

	var strength := clampf(movement / delta / 220.0, 0.0, 1.0) * motion_amount
	var phase := _travel / RATTLE_DISTANCE * TAU
	position.y = sin(phase) * 0.9 * strength
	rotation = sin(phase * 0.5) * deg_to_rad(0.8) * strength


func reset_suspension() -> void:
	position = Vector2.ZERO
	rotation = 0.0

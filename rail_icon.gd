class_name RailIcon
extends Control

@export var kind: int = RailSegment.FLAT
@export var tileset: Texture2D


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	if tileset == null or size.x < 1.0:
		return
	var from_y := size.y * 0.5
	var to_y := from_y
	if kind == RailSegment.RISING:
		from_y = size.y - 7.0
		to_y = 5.0
	elif kind == RailSegment.FALLING:
		from_y = 5.0
		to_y = size.y - 7.0
	var shape := Curve2D.new()
	var span := size.x - 16.0
	if kind == RailSegment.LOOP:
		var center := size * 0.5
		var radius := (size.y - 6.0) * 0.4
		var handle := radius * 0.5522848
		var base := center + Vector2(0, radius)
		shape.add_point(Vector2(8, base.y), Vector2.ZERO, Vector2(8, 0))
		shape.add_point(base, Vector2(-8, 0), Vector2(handle, 0))
		shape.add_point(center + Vector2(radius, 0), Vector2(0, handle), Vector2(0, -handle))
		shape.add_point(center + Vector2(0, -radius), Vector2(handle, 0), Vector2(-handle, 0))
		shape.add_point(center + Vector2(-radius, 0), Vector2(0, -handle), Vector2(0, handle))
		shape.add_point(base, Vector2(-handle, 0), Vector2(8, 0))
		shape.add_point(Vector2(size.x - 8, base.y), Vector2(-8, 0), Vector2.ZERO)
	else:
		shape.add_point(Vector2(8, from_y), Vector2.ZERO, Vector2(span * 0.35, 0))
		shape.add_point(Vector2(size.x - 8, to_y), Vector2(-span * 0.35, 0), Vector2.ZERO)
	var texture_size := Vector2(tileset.get_size())
	var first_uv := RailSegment.RAIL_REGION.position / texture_size
	var last_uv := RailSegment.RAIL_REGION.end / texture_size
	var uvs := PackedVector2Array([first_uv, Vector2(last_uv.x, first_uv.y),
		last_uv, Vector2(first_uv.x, last_uv.y)])
	var length := shape.get_baked_length()
	var offset := 0.0
	while offset < length:
		var end := minf(offset + 4.0, length)
		var first := shape.sample_baked_with_rotation(offset)
		var last := shape.sample_baked_with_rotation(end)
		draw_colored_polygon(PackedVector2Array([first.origin, last.origin,
			last.origin + last.y * 5.0, first.origin + first.y * 5.0]), Color.WHITE, uvs, tileset)
		offset = end

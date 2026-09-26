class_name RailSegment
extends Node2D

const RISING: int = 0
const FLAT: int = 1
const FALLING: int = 2
const LOOP: int = 3
const TYPE_NAMES = ["RISING", "FLAT", "FALLING", "LOOP"]
const TYPE_KEYS = ["A", "S", "D", "F"]
const RAIL_REGION := Rect2(0, 434, 496, 62)
const SUPPORT_REGION := Rect2(0, 496, 496, 496)
const GAP_LENGTH: float = 92.0

var segment_id: int = 0
var kind: int = FLAT
var start_distance: float = 0.0
var length: float = 0.0
var width: float = 320.0
var end_y: float = 400.0
var broken: bool = false
var repaired: bool = false
var conveyor: bool = false
var gap_start: float = 0.0
var gap_end: float = 0.0
var curve: Curve2D
var gap_points := PackedVector2Array()

var _tileset: Texture2D
var _quads: Array[PackedVector2Array] = []
var _quad_in_gap: Array[bool] = []
var _uvs := PackedVector2Array()
var _supports: Array[Rect2] = []
var _marker: Label
var _focused: bool = false
var _hover_state: int = 0
var _chain_links: Array[Sprite2D] = []
var _chain_offset: float = 0.0


func configure(texture: Texture2D, type: int, from_y: float, to_y: float,
	needs_repair: bool, is_conveyor: bool = false, span_width: float = 320.0) -> void:
	_tileset = texture
	kind = type
	width = span_width
	end_y = to_y
	broken = needs_repair
	conveyor = is_conveyor
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_curve(from_y)
	length = curve.get_baked_length()
	if kind != LOOP:
		gap_start = (length - GAP_LENGTH) * 0.5
		gap_end = gap_start + GAP_LENGTH
	_cache_art()
	if broken:
		_build_marker()
	if conveyor:
		_build_chain()
	queue_redraw()


func _build_curve(from_y: float) -> void:
	curve = Curve2D.new()
	curve.bake_interval = 2.0
	if kind != LOOP:
		# Horizontal handles make neighbouring sections join smoothly.
		curve.add_point(Vector2(0, from_y), Vector2.ZERO, Vector2(width * 0.35, 0))
		curve.add_point(Vector2(width, end_y), Vector2(-width * 0.35, 0), Vector2.ZERO)
		return
	var radius := 110.0
	var base := Vector2(width * 0.5, from_y)
	var center := base + Vector2(0, -radius)
	var handle := radius * 0.5522848
	curve.add_point(Vector2(0, from_y), Vector2.ZERO, Vector2(80, 0))
	curve.add_point(base, Vector2(-80, 0), Vector2(handle, 0))
	gap_start = curve.get_baked_length()
	curve.add_point(center + Vector2(radius, 0), Vector2(0, handle), Vector2(0, -handle))
	curve.add_point(center + Vector2(0, -radius), Vector2(handle, 0), Vector2(-handle, 0))
	curve.add_point(center + Vector2(-radius, 0), Vector2(0, -handle), Vector2(0, handle))
	curve.add_point(base, Vector2(-handle, 0), Vector2(80, 0))
	gap_end = curve.get_baked_length()
	curve.add_point(Vector2(width, from_y), Vector2(-80, 0), Vector2.ZERO)


func _cache_art() -> void:
	var texture_size := Vector2(_tileset.get_size())
	var uv_start := RAIL_REGION.position / texture_size
	var uv_end := RAIL_REGION.end / texture_size
	_uvs = PackedVector2Array([uv_start, Vector2(uv_end.x, uv_start.y),
		uv_end, Vector2(uv_start.x, uv_end.y)])
	_cache_span(0.0, gap_start, false)
	_cache_span(gap_start, gap_end, true)
	_cache_span(gap_end, length, false)
	var offset := gap_start
	gap_points.append(curve.sample_baked(offset))
	while offset < gap_end:
		offset = minf(offset + 8.0, gap_end)
		gap_points.append(curve.sample_baked(offset))
	if kind == LOOP:
		return
	offset = 0.0
	while offset < length:
		var pose := curve.sample_baked_with_rotation(offset)
		var support_width := 64.0 if absf(pose.x.y) < 0.08 else 4.0
		var y := pose.origin.y + 8.0
		while y < 468.0:
			var height := minf(64.0, 468.0 - y)
			_supports.append(Rect2(pose.origin.x - support_width * 0.5, y, support_width, height))
			y += height
		offset += 120.0


func _cache_span(from_distance: float, to_distance: float, in_gap: bool) -> void:
	var offset := from_distance
	while offset < to_distance:
		var next_offset := minf(offset + 4.0, to_distance)
		var first := curve.sample_baked_with_rotation(offset)
		var last := curve.sample_baked_with_rotation(next_offset)
		_quads.append(PackedVector2Array([first.origin, last.origin,
			last.origin + last.y * 8.0, first.origin + first.y * 8.0]))
		_quad_in_gap.append(in_gap)
		offset = next_offset


func marker_position() -> Vector2:
	return curve.sample_baked((gap_start + gap_end) * 0.5) + Vector2(0, -28)


func _build_marker() -> void:
	_marker = Label.new()
	_marker.text = "%s [%s]" % [TYPE_NAMES[kind], TYPE_KEYS[kind]]
	_marker.position = marker_position() + Vector2(-70, -40)
	_marker.size = Vector2(140, 24)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])
	font.font_weight = 700
	_marker.add_theme_font_override("font", font)
	_marker.add_theme_font_size_override("font_size", 14)
	_marker.add_theme_color_override("font_color", Color("#fff3d6"))
	_marker.add_theme_color_override("font_outline_color", Color("#172126"))
	_marker.add_theme_constant_override("outline_size", 5)
	add_child(_marker)


func set_target(focused: bool, hover_state: int = 0) -> void:
	if _focused == focused and _hover_state == hover_state:
		return
	_focused = focused
	_hover_state = hover_state
	queue_redraw()


func install() -> bool:
	if not broken:
		return false
	broken = false
	repaired = true
	if is_instance_valid(_marker):
		_marker.hide()
	queue_redraw()
	return true


func distance_to_gap(local_point: Vector2) -> float:
	var nearest := local_point.distance_to(marker_position())
	for i in range(gap_points.size() - 1):
		var point := Geometry2D.get_closest_point_to_segment(local_point, gap_points[i], gap_points[i + 1])
		nearest = minf(nearest, local_point.distance_to(point))
	return nearest


func _build_chain() -> void:
	var chain_texture := AtlasTexture.new()
	chain_texture.atlas = _tileset
	chain_texture.region = Rect2(0, 434, 31, 31)
	chain_texture.filter_clip = true
	for i in range(ceili(length / 20.0)):
		var link := Sprite2D.new()
		link.texture = chain_texture
		link.scale = Vector2(3, 10) / 31.0
		link.modulate = Color("#ffd37a")
		link.z_index = 1
		add_child(link)
		_chain_links.append(link)
	advance_chain(0.0)


func advance_chain(movement: float) -> void:
	_chain_offset = fposmod(_chain_offset + movement, 20.0)
	for i in range(_chain_links.size()):
		var offset := i * 20.0 + _chain_offset
		var link := _chain_links[i]
		link.visible = offset < length
		if link.visible:
			var pose := curve.sample_baked_with_rotation(offset)
			link.position = pose.origin + pose.y * 4.0
			link.rotation = pose.get_rotation()


func _draw() -> void:
	if _tileset == null:
		return
	for rect in _supports:
		draw_texture_rect_region(_tileset, rect, Rect2(SUPPORT_REGION.position, rect.size * 31.0 / 4.0))
	for i in range(_quads.size()):
		if _quad_in_gap[i] and broken:
			continue
		var tint := Color("#ffe0a0") if _quad_in_gap[i] and repaired else Color.WHITE
		draw_colored_polygon(_quads[i], tint, _uvs, _tileset)
	if not broken:
		return
	var color := Color("#e06969")
	if _hover_state > 0:
		color = Color("#91d27a")
	# The dotted ghost rail makes the missing slope legible.
	for i in range(0, gap_points.size() - 1, 2):
		draw_line(gap_points[i], gap_points[i + 1], color, 3.0)
	var marker := marker_position()
	draw_circle(marker, 14.0, color)
	if _focused or _hover_state != 0:
		draw_arc(marker, 21.0, 0.0, TAU, 24, Color("#fff3d6") if _hover_state == 0 else color, 2.0)

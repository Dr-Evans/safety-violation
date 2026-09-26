class_name CoasterTrack
extends Path2D

# These regions select artwork from the original PNG without changing it.
# Each pixel in the source artwork was enlarged to a 31 x 31 block.
@export var tileset: Texture2D
@export var rail_region: Rect2 = Rect2(0, 434, 496, 62)
@export var support_region: Rect2 = Rect2(0, 496, 496, 496)
@export_range(1.0, 8.0, 1.0) var art_pixel_size: float = 4.0
@export_range(64.0, 192.0, 16.0) var support_spacing: float = 128.0
@export var ground_y: float = 480.0
@export var repair_tint: Color = Color("#ffe0a0")

const SOURCE_PIXEL_SIZE: float = 31.0
const SEGMENT_LENGTH: float = 4.0
const CHAIN_SPACING: float = 20.0

var length: float = 0.0
var conveyor_end: float = 0.0

# Cache the artwork geometry once; moving the cart does not rebuild the rails.
var _rail_quads: Array[PackedVector2Array] = []
var _rail_gaps: PackedInt32Array = PackedInt32Array()
var _rail_uvs: PackedVector2Array = PackedVector2Array()
var _supports: Array[Rect2] = []
var _loop_ranges: Array[Vector2] = []
var _installed: Array[bool] = []
var _chain_sprites: Array[Sprite2D] = []
var _chain_texture: AtlasTexture
var _chain_offset: float = 0.0


func build(starts: Array[float], gap_size: float, installed: Array[bool]) -> void:
	_build_track()
	length = curve.get_baked_length()
	_installed = installed.duplicate()
	_cache_rails(starts, gap_size)
	_cache_supports()
	_build_conveyor()
	queue_redraw()


func set_piece_installed(index: int, value: bool) -> void:
	_installed[index] = value
	queue_redraw()


func advance_conveyor(movement: float) -> void:
	_chain_offset = fposmod(_chain_offset + movement, CHAIN_SPACING)
	for i in range(_chain_sprites.size()):
		var offset := i * CHAIN_SPACING + _chain_offset
		var link := _chain_sprites[i]
		link.visible = offset < conveyor_end
		if link.visible:
			var pose := curve.sample_baked_with_rotation(offset)
			link.position = pose.origin + pose.y * 4.0
			link.rotation = pose.get_rotation()


func _build_track() -> void:
	_loop_ranges.clear()
	curve = Curve2D.new()
	curve.bake_interval = 2.0

	# Boarding platform.
	curve.add_point(
		Vector2(100, 440),
		Vector2.ZERO,
		Vector2(40, 0)
	)

	# Beginning of the conveyor incline.
	curve.add_point(
		Vector2(220, 440),
		Vector2(-40, 0),
		Vector2(100, -100)
	)

	# Top of the conveyor lift.
	curve.add_point(
		Vector2(520, 160),
		Vector2(-100, 0),
		Vector2(120, 0)
	)

	# Record where the conveyor section ends.
	conveyor_end = curve.get_baked_length()

	# First drop.
	curve.add_point(
		Vector2(900, 440),
		Vector2(-160, 0),
		Vector2(80, 0)
	)

	_add_loop(Vector2(1140, 440), 145.0)

	# Hill between the loops.
	curve.add_point(
		Vector2(1500, 440),
		Vector2(-90, 0),
		Vector2(130, 0)
	)
	curve.add_point(
		Vector2(1840, 240),
		Vector2(-140, 0),
		Vector2(140, 0)
	)
	curve.add_point(
		Vector2(2150, 440),
		Vector2(-130, 0),
		Vector2(80, 0)
	)

	_add_loop(Vector2(2540, 440), 150.0)

	# Final hill and arrival platform.
	curve.add_point(
		Vector2(2880, 440),
		Vector2(-90, 0),
		Vector2(100, 0)
	)
	curve.add_point(
		Vector2(3100, 300),
		Vector2(-100, 0),
		Vector2(100, 0)
	)
	curve.add_point(
		Vector2(3360, 440),
		Vector2(-100, 0),
		Vector2(80, 0)
	)
	curve.add_point(
		Vector2(3600, 440),
		Vector2(-80, 0),
		Vector2.ZERO
	)


func _add_loop(base: Vector2, radius: float) -> void:
	var loop_start := curve.get_baked_length()
	var center := base + Vector2(0, -radius)

	# Handle length for approximating a quarter circle.
	var handle := radius * 0.5522848

	# Enter at the bottom, travelling right.
	curve.add_point(
		base,
		Vector2(-80, 0),
		Vector2(handle, 0)
	)

	# Right side.
	curve.add_point(
		center + Vector2(radius, 0),
		Vector2(0, handle),
		Vector2(0, -handle)
	)

	# Top.
	curve.add_point(
		center + Vector2(0, -radius),
		Vector2(handle, 0),
		Vector2(-handle, 0)
	)

	# Left side.
	curve.add_point(
		center + Vector2(-radius, 0),
		Vector2(0, -handle),
		Vector2(0, handle)
	)

	# Return to the bottom and exit right.
	curve.add_point(
		base,
		Vector2(-handle, 0),
		Vector2(80, 0)
	)

	# Skip upright scaffolding inside the loop and its approach.
	_loop_ranges.append(Vector2(loop_start, curve.get_baked_length()))


func _cache_rails(starts: Array[float], gap_size: float) -> void:
	_rail_quads.clear()
	_rail_gaps.clear()
	# UVs select just the rail strip within the whole tileset (0..1 coordinates).
	var texture_size := Vector2(tileset.get_size())
	var uv_start := rail_region.position / texture_size
	var uv_end := rail_region.end / texture_size
	_rail_uvs = PackedVector2Array([
		uv_start, Vector2(uv_end.x, uv_start.y),
		uv_end, Vector2(uv_start.x, uv_end.y)
	])

	# Split exactly at every gap boundary so the artwork matches collision checks.
	var cursor := 0.0
	for i in range(starts.size()):
		var gap_start := starts[i] * length
		var gap_end := gap_start + gap_size * length
		_cache_span(cursor, gap_start, -1)
		_cache_span(gap_start, gap_end, i)
		cursor = gap_end
	_cache_span(cursor, length, -1)


func _cache_span(from_distance: float, to_distance: float, gap: int) -> void:
	var rail_depth := rail_region.size.y * art_pixel_size / SOURCE_PIXEL_SIZE
	var offset := from_distance
	while offset < to_distance:
		var next_offset := minf(offset + SEGMENT_LENGTH, to_distance)
		var start_pose := curve.sample_baked_with_rotation(offset)
		var end_pose := curve.sample_baked_with_rotation(next_offset)
		# The rail's top edge is the same path the cart's wheels follow.
		# Four corners let the sprite strip bend without cracks between sections.
		_rail_quads.append(PackedVector2Array([
			start_pose.origin,
			end_pose.origin,
			end_pose.origin + end_pose.y * rail_depth,
			start_pose.origin + start_pose.y * rail_depth
		]))
		_rail_gaps.append(gap)
		offset = next_offset


func _cache_supports() -> void:
	_supports.clear()
	var tile_size := support_region.size * art_pixel_size / SOURCE_PIXEL_SIZE
	var rail_depth := rail_region.size.y * art_pixel_size / SOURCE_PIXEL_SIZE
	var offset := 0.0
	while offset < length:
		var pose := curve.sample_baked_with_rotation(offset)
		# Upright frames belong under hills, rather than across the loop's opening.
		if not _inside_loop(offset) and pose.x.x > 0.2:
			# Wide frames fit flat sections. On a slope, use the frame's left
			# wooden post so scaffolding does not poke above the inclined rail.
			var width := tile_size.x if absf(pose.x.y) < 0.08 else art_pixel_size
			var y := pose.origin.y + rail_depth
			while y < ground_y:
				var height := minf(tile_size.y, ground_y - y)
				_supports.append(Rect2(
					pose.origin.x - width * 0.5, y, width, height
				))
				y += height
		offset += support_spacing


func _inside_loop(offset: float) -> bool:
	for interval in _loop_ranges:
		if offset >= interval.x and offset <= interval.y:
			return true
	return false


func _build_conveyor() -> void:
	for link in _chain_sprites:
		link.free()
	_chain_sprites.clear()
	_chain_offset = 0.0
	# A single silver pixel from the rail becomes each gold chain link.
	_chain_texture = AtlasTexture.new()
	_chain_texture.atlas = tileset
	_chain_texture.region = Rect2(0, 434, SOURCE_PIXEL_SIZE, SOURCE_PIXEL_SIZE)
	_chain_texture.filter_clip = true
	for i in range(ceili(conveyor_end / CHAIN_SPACING)):
		var link := Sprite2D.new()
		link.name = "ChainLink%d" % i
		link.texture = _chain_texture
		link.scale = Vector2(3.0, 10.0) / SOURCE_PIXEL_SIZE
		link.modulate = Color("#ffd37a")
		link.z_index = 1
		add_child(link)
		_chain_sprites.append(link)
	advance_conveyor(0.0)


func _draw() -> void:
	if tileset == null or length <= 0.0:
		return

	# Supports stay upright. The final tile is cropped at ground height.
	for rect in _supports:
		var source_size := rect.size * SOURCE_PIXEL_SIZE / art_pixel_size
		draw_texture_rect_region(
			tileset, rect, Rect2(support_region.position, source_size)
		)

	for i in range(_rail_quads.size()):
		var gap := _rail_gaps[i]
		if gap != -1 and not _installed[gap]:
			continue
		var tint := Color.WHITE if gap == -1 else repair_tint
		draw_colored_polygon(_rail_quads[i], tint, _rail_uvs, tileset)

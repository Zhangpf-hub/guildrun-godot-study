@tool
extends Control

@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
## Border widths in source pixels, measured from the left, top, right and bottom.
@export var border := Vector4.ZERO:
	set(value):
		border = value
		queue_redraw()
@export var pixels_per_unit := 1.0:
	set(value):
		pixels_per_unit = value
		queue_redraw()
@export var draw_center := true:
	set(value):
		draw_center = value
		queue_redraw()


func _draw() -> void:
	if not texture or pixels_per_unit <= 0.0:
		return
	var source := texture.get_size()
	var uv_x := PackedFloat32Array([0, border.x, source.x - border.z, source.x])
	var uv_y := PackedFloat32Array([0, border.y, source.y - border.w, source.y])
	var dst_x := _cuts(size.x, border.x, border.z)
	var dst_y := _cuts(size.y, border.y, border.w)
	for y in 3:
		for x in 3:
			if not draw_center and x == 1 and y == 1:
				continue
			var dest := Rect2(dst_x[x], dst_y[y], dst_x[x + 1] - dst_x[x], dst_y[y + 1] - dst_y[y])
			var region := Rect2(uv_x[x], uv_y[y], uv_x[x + 1] - uv_x[x], uv_y[y + 1] - uv_y[y])
			if dest.has_area() and region.has_area():
				draw_texture_rect_region(texture, dest, region)


func _cuts(length: float, start: float, end: float) -> PackedFloat32Array:
	# Unity proportionally reduces opposite borders when they cannot both fit.
	var scale_factor := 1.0 / pixels_per_unit
	if start + end > 0.0:
		scale_factor = minf(scale_factor, length / (start + end))
	return PackedFloat32Array([0, start * scale_factor, length - end * scale_factor, length])

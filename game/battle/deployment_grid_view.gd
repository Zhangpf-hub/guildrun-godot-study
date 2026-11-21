extends Node3D
## The live Unity board uses four Tilemap sprite states and the BattleGrid origin.

const TILE_DATA := "res://balancing/deployment_grid.json"

var _size := Vector2i.ZERO
var _tiles: Dictionary[Vector2i, Sprite3D] = {}
var _styles: Dictionary = {}


func _ready() -> void:
	hide()
	var entries: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TILE_DATA))
	for name: String in entries:
		var row: Dictionary = entries[name]
		_styles[name] = {
			"texture": load(row.texture),
			"pixel_size": float(row.pixel_size),
			"color": Color(row.color[0], row.color[1], row.color[2], row.color[3]),
		}


func update_tiles(grid: GuildrunBattleGrid, placing: bool, dragging: bool, hovered: Vector2i, source: Vector2i) -> void:
	visible = placing
	if not placing:
		return
	if grid.size != _size:
		_rebuild(grid.size)
	for cell in _tiles:
		var playable := cell.y < (grid.size.y >> 1)
		var state := "open" if playable else "enemy"
		if dragging:
			if playable and cell == source:
				state = "ally"
			elif playable and grid.occupants.has(cell):
				state = "invalid"
			elif cell == hovered:
				state = "ally" if playable else "invalid"
		var tile := _tiles[cell]
		if tile.get_meta("placement_state", "") != state:
			var style: Dictionary = _styles[state]
			tile.texture = style.texture
			tile.pixel_size = style.pixel_size
			tile.modulate = style.color
			tile.set_meta("placement_state", state)


func _rebuild(dimensions: Vector2i) -> void:
	for tile: Sprite3D in _tiles.values():
		tile.free()
	_tiles.clear()
	_size = dimensions
	for y in _size.y:
		for x in _size.x:
			var cell := Vector2i(x, y)
			var tile := Sprite3D.new()
			tile.position = GuildrunBattleGrid.center(cell)
			tile.rotation.x = -PI * 0.5
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(tile)
			_tiles[cell] = tile

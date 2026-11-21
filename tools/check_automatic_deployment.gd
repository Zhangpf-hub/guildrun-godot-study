extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func verify() -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var grid := fight._grid
	expect(fight._next_free_position() == Vector2i(3, 0), "Automatic search starts at (3,0)")
	expect(fight._next_free_position([Vector2i(3, 0)]) == Vector2i(4, 0),
			"Automatic search advances horizontally and skips a reserved formation slot")
	var all_candidates: Array[Vector2i] = []
	for y in grid.size.y:
		for x in range(3, grid.size.x):
			all_candidates.append(Vector2i(x, y))
	expect(fight._next_free_position(all_candidates) == Vector2i(-1, -1),
			"Exhaustion neither wraps into columns 0–2 nor returns an out-of-bounds position")

	var manual_target := Vector2i(4, 4)
	fight.select_hero(4)
	expect(fight._next_free_position() == Vector2i(4, 0), "Automatic deployment preserves an occupied ally tile")
	expect(not fight.transfer_hero(Vector2i(3, 0), manual_target), "A direct drop cannot target the enemy half")
	expect(fight.transfer_hero(Vector2i(3, 0), Vector2i(0, 3)), "A direct drop may use column zero inside the player half")
	stage.free()

	stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	fight = stage.encounter
	grid = fight._grid
	var enemy: GuildrunBoardUnit = grid.occupants[Vector2i(3, 4)]
	for y in range(grid.size.y >> 1):
		for x in range(3, grid.size.x):
			grid.occupants[Vector2i(x, y)] = enemy
	fight.select_hero(4)
	expect(is_instance_valid(fight._hero) and fight._hero.grid_cell == manual_target,
			"Hero selection scans the opposite half after exhausting the lower candidate rows")
	expect(grid.occupants.get(Vector2i(3, 4)) == enemy, "Enemy remains in its occupied tile")
	stage.free()
	print("AUTOMATIC_DEPLOYMENT start, horizontal order, reserved slots, exhaustion, full-board fallback and direct drop")
	quit(1 if failed else 0)

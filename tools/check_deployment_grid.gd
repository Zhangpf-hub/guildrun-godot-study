extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func verify() -> void:
	var stage: Node = load("res://battle/stage.tscn").instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	var view: Node3D = fight._deployment_grid_view
	await process_frame
	expect(not view.visible, "Placement grid visible during hero selection")
	fight.select_hero(4)
	stage.battle_camera.advance(4.0)
	await process_frame
	fight._process(0.0)
	expect(not view.visible, "Ordinary deployment should leave the board clear until drag")
	var camera := root.get_camera_3d()
	var source: Vector2i = fight._hero.grid_cell
	var screen_source := camera.unproject_position(fight._hero.global_position)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen_source
	root.push_input(press, true)
	fight._process(0.0)
	expect(not view.visible, "A stationary press is not a hero drag")
	var motion := InputEventMouseMotion.new()
	motion.position = screen_source + Vector2(16, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	fight._process(0.0)
	expect(view.visible and view.get_child_count() == fight._grid.size.x * fight._grid.size.y,
			"Dragging a deployed hero reveals one source tile per board cell")
	if not view.visible or view.get_child_count() == 0:
		stage.free()
		quit(1)
		return
	var ally_cell := Vector2i.ZERO
	var enemy_cell := Vector2i(0, fight._grid.size.y >> 1)
	var ally_tile: Sprite3D = view._tiles[ally_cell]
	var enemy_tile: Sprite3D = view._tiles[enemy_cell]
	expect(ally_tile.get_meta("placement_state") == "open" and enemy_tile.get_meta("placement_state") == "enemy",
			"Original near/far row split differs")
	expect(ally_tile.texture.resource_path.ends_with("sharedassets3_420.png") and
			is_equal_approx(ally_tile.pixel_size, 1.0 / 65.0), "Original open sprite or pixels per unit differ")
	expect(ally_tile.modulate.is_equal_approx(Color(0.94339621, 0.94048661, 0.86774653, 0.37647060)),
			"Original open tint differs")
	var screen_tile := camera.unproject_position(enemy_tile.global_position)
	expect(fight._cell_at(screen_tile) == GuildrunEncounter.NO_SLOT and fight._cell_at(screen_tile, false) == enemy_cell,
			"Forbidden tile targets must stay outside deployment input")
	fight._grid.occupants[ally_cell] = fight._hero
	view.update_tiles(fight._grid, true, true, enemy_cell, source)
	expect(enemy_tile.get_meta("placement_state") == "invalid" and
			enemy_tile.texture.resource_path.ends_with("sharedassets3_537.png"), "Forbidden tile feedback missing")
	expect(view._tiles[source].get_meta("placement_state") == "ally", "Dragged hero tile feedback missing")
	expect(ally_tile.get_meta("placement_state") == "invalid", "Occupied tile feedback missing")
	fight._grid.occupants.erase(ally_cell)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = screen_tile
	root.push_input(release, true)
	fight._process(0.0)
	expect(not view.visible and fight._hero.grid_cell == source,
			"Releasing on the forbidden side hides the tiles and preserves formation")
	fight.start_fight()
	await process_frame
	expect(not view.visible, "Placement grid visible during combat")
	stage.free()
	print("DEPLOYMENT_GRID source tiles, board projection, drag states, phase visibility")
	quit(1 if failed else 0)

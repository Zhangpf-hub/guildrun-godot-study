extends SceneTree

func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var expected: Array = []
	var scene: PackedScene = load("res://battle/stage.tscn")
	for refresh_rate: int in [30, 60, 120]:
		var stage = scene.instantiate()
		root.add_child(stage)
		var fight: GuildrunEncounter = stage.encounter
		fight.select_hero(26)
		fight.start_fight()
		var turtle: GuildrunBoardUnit = stage.grid.occupants[Vector2i(3, 4)]
		# Split the first native step exactly one Q16 unit before its boundary.
		fight._physics_process(2183.0 / 65536.0)
		if fight._frame != 0:
			push_error("Battle advanced early")
			quit(1)
			return
		fight._physics_process(1.0 / 65536.0)
		if fight._frame != 1:
			push_error("Lost first battle step")
			quit(1)
			return
		var trace: Array = []
		for second in 30:
			for frame in refresh_rate:
				fight._physics_process(1.0 / refresh_rate)
			var hero := fight._hero
			trace.append([fight._frame, fight.phase, hero.grid_cell, hero.health, hero.mana, hero.total_shield(), turtle.health])
			if fight.phase == GuildrunEncounter.Phase.RESULT:
				break
		if fight.phase != GuildrunEncounter.Phase.RESULT or (not expected.is_empty() and expected != trace):
			push_error("Battle depends on caller cadence: %d" % refresh_rate)
			quit(1)
			return
		expected = trace
		stage.free()
	print("30/60/120 callbacks per second agreed through the final battle step: ", expected.back())
	quit()


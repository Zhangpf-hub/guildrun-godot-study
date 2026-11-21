extends SceneTree


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var scene := load("res://UI/first_crossroads.tscn") as PackedScene
	var seen := {}
	var roster: Array[int] = [4, 24]
	var shop := GuildrunFirstShop.new()
	root.add_child(shop)
	for seed_value in 200:
		for index in range(1, 3):
			var crossroads: GuildrunFirstCrossroads = scene.instantiate()
			root.add_child(crossroads)
			crossroads._rng.seed = seed_value
			crossroads.setup(roster)
			crossroads.reward_claimed.connect(shop.apply_event_reward)
			var offers := crossroads.offers
			if offers.size() != 3 or offers[0] != 809 or offers[1] < 800 or offers[1] > 806 or offers[2] < 902 or offers[2] > 908:
				push_error("Unexpected crossroads 120 path")
				quit(1)
				return
			crossroads.select_path(index)
			var id := offers[index]
			var event: Dictionary = crossroads._data.events[str(id)]
			if index == 1:
				var before := shop.items.size()
				crossroads.claim()
				crossroads.claim()
				if shop.items.size() != before + 1 or not event.choices.any(func(p: Array): return int(p[0]) == shop.items.back()):
					push_error("Item reward outside pool or repeated")
					quit(1)
					return
			else:
				var before: int = shop.hero_modifiers.get(24, []).size()
				crossroads.claim(26)
				if crossroads.claimed:
					push_error("Training accepted a hero outside the roster")
					quit(1)
					return
				crossroads.claim(24)
				crossroads.claim(4)
				if shop.hero_modifiers[24].size() != before + 1 or shop.hero_modifiers[24].back() != int(event.modifier) or shop.hero_modifiers.has(4):
					push_error("Training did not apply the selected modifier exactly once")
					quit(1)
					return
			seen[id] = true
			crossroads.free()
		if seen.size() == 14:
			print("Verified 7 item events and 7 training events across ", seed_value + 1, " seeds")
			shop.free()
			quit(0)
			return
	push_error("Failed to reach all tutorial pool entries")
	quit(1)

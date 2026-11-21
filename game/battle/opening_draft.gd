extends RefCounted

const RULES = preload("res://battle/difficulty_rules.gd")
static var catalog: Dictionary

var choices: Array[Dictionary] = []
var progress_path: String
var tokens := 0
var xp := 0
var _rng := RandomNumberGenerator.new()


static func data() -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/opening.json"))
	return catalog


static func past_tutorial(progress: ConfigFile) -> bool:
	# Existing saves with a forest win have also passed the third shop.
	return bool(progress.get_value("opening", "tutorial_checkpoint", false)) or int(progress.get_value("forest", "highest_beaten", -1)) >= 0


static func save_value(progress: ConfigFile, path: String, key: String, value: Variant) -> void:
	progress.set_value("opening", key, value)
	var result := progress.save(path)
	if result != OK:
		push_warning("Cannot save opening progress: %s" % error_string(result))


static func token_cap(progress_xp: int) -> int:
	var config := data()
	var cap := int(config.max_tokens) - int(config.locked_slots)
	for gate: Array in config.token_slots:
		if progress_xp >= int(gate[0]):
			cap += int(gate[1])
	return cap


static func reached_boss(path: String) -> void:
	var progress: ConfigFile = RULES.read_progress(path)
	var cap := token_cap(int(progress.get_value("opening", "xp", 0)))
	save_value(progress, path, "tokens", mini(cap, int(progress.get_value("opening", "tokens", 0)) + 2))


static func finish_run(path: String, won_fights: int, chunks: int, won_forest: bool, endless_cycles: int) -> int:
	var progress: ConfigFile = RULES.read_progress(path)
	var old_xp := int(progress.get_value("opening", "xp", 0))
	var rates: Dictionary = data().xp
	var gained := maxi(0, won_fights - 1) * int(rates.RegularEncounterWonXpReward)
	gained += chunks * int(rates.StageCompletionXpReward) + endless_cycles * int(rates.EndlessCycleXpReward)
	if won_forest:
		gained += int(rates.VictoryXpReward)
	var new_cap := token_cap(old_xp + gained)
	var new_slots := new_cap - token_cap(old_xp)
	progress.set_value("opening", "tokens", mini(new_cap, int(progress.get_value("opening", "tokens", 0)) + new_slots))
	save_value(progress, path, "xp", old_xp + gained)
	return gained


func start(path: String) -> void:
	progress_path = path
	roll(true)


func roll(initial := false) -> bool:
	var progress: ConfigFile = RULES.read_progress(progress_path)
	tokens = int(progress.get_value("opening", "tokens", 0))
	xp = int(progress.get_value("opening", "xp", 0))
	if not initial and tokens <= 0:
		return false
	var heroes := _draw(data().pools.hero)
	var rewards: Array[Dictionary] = []
	if tokens > 0:
		tokens -= 1
		save_value(progress, progress_path, "tokens", tokens)
		rewards = _draw(data().pools.relic)
	choices.clear()
	for index in heroes.size():
		var hero: Dictionary = heroes[index]
		var row := {"id": int(hero.id), "portrait": hero.icon}
		if index < rewards.size():
			row.relic = int(rewards[index].id)
			row.relic_icon = rewards[index].icon
		choices.append(row)
	return true


func _draw(pool: Array) -> Array[Dictionary]:
	var eligible := pool.filter(func(row: Dictionary): return int(row.xp) <= xp)
	var picked: Array[Dictionary] = []
	while picked.size() < int(data().choices) and not eligible.is_empty():
		var total := 0
		for row: Dictionary in eligible:
			total += int(row.weight)
		var ticket := _rng.randi_range(1, total)
		for index in eligible.size():
			ticket -= int(eligible[index].weight)
			if ticket <= 0:
				picked.append(eligible.pop_at(index))
				break
	return picked


static func pick_reward(kind: String, pool: int, progress_xp: int, rng: RandomNumberGenerator, exclude: Array = []) -> int:
	var candidates: Array = data().rewards["%s_%d" % [kind, pool]].filter(func(row: Array): return int(row[2]) <= progress_xp and not exclude.has(int(row[0])))
	var total := 0
	for row: Array in candidates:
		total += int(row[1])
	if total > 0:
		var ticket := rng.randi_range(1, total)
		for row: Array in candidates:
			ticket -= int(row[1])
			if ticket <= 0:
				return int(row[0])
	return -1


static func reward_description(id: int) -> String:
	var lines := PackedStringArray()
	var labels: Dictionary = data().descriptions[str(id)]
	for label: String in labels:
		var values: Dictionary = labels[label].duplicate()
		for key: String in values:
			if values[key] == "1d1":
				values[key] = "0"
		lines.append(TranslationServer.translate("Relics.Relic_%d.%s" % [id, label]).format(values))
	var markup := RegEx.new()
	markup.compile("<[^>]+>|\\[|\\]")
	return markup.sub("\n".join(lines), "", true)


static func kit_choices(roster: Array[int], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var kits: Dictionary = data().kit
	var types := [0, 1, 2]
	var attributes := [0, 1, 2, 3, 4, 5, 6]
	# The native draft permutes timing and stat indices separately without replacement.
	for pool: Array in [types, attributes]:
		for end in range(pool.size() - 1, 0, -1):
			var pick := rng.randi_range(0, end)
			var tmp: int = pool[end]
			pool[end] = pool[pick]
			pool[pick] = tmp
	var item_pool: Array = kits.items[types[1]]
	var stat_index: int = attributes[0]
	var ids := [int(kits.shards[types[0]]), int(item_pool[attributes[1] if item_pool.size() > 1 else 0]),
			int(kits.stats[types[2]][stat_index])]
	var result: Array[Dictionary] = []
	for i in ids.size():
		var id: int = ids[i]
		var name := TranslationServer.translate("Relics.Relic_%d.Name" % id)
		var option := {"kind": "starter_kit", "value": id, "choice": i + 1,
				"caption": "%s\n%s" % [name, reward_description(id)], "outcome": name}
		if i == 2 and types[2] == 0:
			var children: Array[Dictionary] = []
			for hero in roster:
				children.append({"kind": "starter_kit", "value": id, "hero": hero, "choice": 1,
						"caption": TranslationServer.translate("Heroes.Hero_%d.Name" % hero), "outcome": name})
			option.children = children
		result.append(option)
	return result

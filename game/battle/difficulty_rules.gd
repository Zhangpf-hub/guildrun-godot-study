extends RefCounted

const PROGRESS_PATH := "user://forest_contracts.cfg"
const DRAGON_STACKS := {7002: [1, 18, 4], 7003: [2, 8, 3], 7004: [3, 12, 2]}
static var catalog: Dictionary

var selected := 0
var stage_index := 1
var score_bonus := 0
var start_health_q16 := 65536
var survivor_delta := 0
var slots_by_rank := false
var boss_map := {}
var fallback_relic := 0
var planned_bosses := {}
var active_boss_relic := 0
var dragon_stacks := 0
var _chunk := -1


static func data() -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/contracts.json"))
	return catalog


func setup(index: int) -> void:
	var records: Array = data().contracts
	selected = clampi(index, 0, records.size() - 1)
	stage_index = int(records[selected].stage_index)
	score_bonus = selected * int(data().score_per_difficulty)
	for i in range(selected + 1):
		var modifiers: Dictionary = records[i].modifiers
		if modifiers.has("HeroesStartBattlesDamagedEntry"):
			start_health_q16 = int(modifiers.HeroesStartBattlesDamagedEntry.HealthPercentage.RawValue)
		if modifiers.has("SurvivingHeroRewardDeltaEntry"):
			survivor_delta = int(modifiers.SurvivingHeroRewardDeltaEntry.RewardDelta)
		if modifiers.has("HeroItemSlotsPerRankEntry"):
			slots_by_rank = true
		if modifiers.has("ActBossRelicEntry"):
			var entry: Dictionary = modifiers.ActBossRelicEntry
			fallback_relic = int(entry._fallbackRelicId)
			for pair: Dictionary in entry._stageRelicPairs:
				boss_map[int(pair.StageId)] = int(pair.RelicId)


func enter_floor(chunk: int, is_boss: bool, endless: bool) -> void:
	if endless or is_boss or fallback_relic == 0:
		active_boss_relic = 0
		return
	if chunk != _chunk:
		_chunk = chunk
		active_boss_relic = int(boss_map.get(planned_bosses.get(chunk, -1), fallback_relic))
		dragon_stacks = int(DRAGON_STACKS[active_boss_relic][1]) if DRAGON_STACKS.has(active_boss_relic) else 0


func won_battle() -> void:
	if DRAGON_STACKS.has(active_boss_relic):
		dragon_stacks += int(DRAGON_STACKS[active_boss_relic][2])


static func read_progress(path := PROGRESS_PATH) -> ConfigFile:
	var progress := ConfigFile.new()
	if FileAccess.file_exists(path):
		var result := progress.load(path)
		if result != OK:
			push_warning("Cannot read contract progress: %s" % error_string(result))
	return progress


static func unlocked_through(progress: ConfigFile) -> int:
	return clampi(int(progress.get_value("forest", "highest_beaten", -1)) + 1, 0, data().contracts.size() - 1)


static func record_win(index: int, path := PROGRESS_PATH) -> void:
	var progress := read_progress(path)
	progress.set_value("forest", "highest_beaten", maxi(index, int(progress.get_value("forest", "highest_beaten", -1))))
	var key := "wins_%d" % index
	progress.set_value("forest", key, int(progress.get_value("forest", key, 0)) + 1)
	var result := progress.save(path)
	if result != OK:
		push_warning("Cannot save contract progress: %s" % error_string(result))

extends GuildrunFirstCrossroads

signal relic_selected(id: int)

const DESCRIPTION_VALUES := {5000: [8, 150], 5001: [15, 40], 5002: [2.5], 5003: [3], 5004: [20],
		5011: [10, 66], 5012: [15, 55], 5013: [7], 5014: [5], 5015: [15]}

var rewards: Array[int] = []
var reward_closed := false
var _challenge_pools: Array = []


func setup(roster: Array[int], party: GuildrunFirstShop = null) -> void:
	_party = party
	_roster.assign(roster)
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/challenge_roads.json"))
	var floor_rules: Dictionary = party.battle_stage.floor_rules()
	var floor_key := "%d/%d" % [floor_rules.chunk, floor_rules.local_floor]
	$Body/Title.text = tr("Tutorial.NTUT-A07.InfoText1").strip_edges() if party.visit == 3 else tr("Crossroads.ChallengeEncounter.Title")
	offers.append(0)
	_add_card(tr("Crossroads.RegularEncounter.Title"), tr("Crossroads.RegularEncounter.Description"), "", select_path.bind(0))
	for choice: Dictionary in _data.floors[floor_key]:
		var id := _weighted_choice(_data.pools[str(int(choice._enemyRelicPoolId))])
		_challenge_pools.append(choice._rewardRelicPoolIds)
		offers.append(id)
		var description := tr("Relics.Relic_%d.Description" % id).format(DESCRIPTION_VALUES[id])
		var markup := RegEx.new()
		markup.compile("<[^>]+>|\\[|\\]")
		var text := tr("Crossroads.ChallengeEncounter.Description").format({
			"relicDescription": description, "relicRarity": tr("UI.Rarity_Epic" if _epic_pool(choice._rewardRelicPoolIds) else "UI.Rarity_Rare")})
		_add_card(tr("Crossroads.ChallengeEncounter.Title"), markup.sub(text, "", true),
				_data.relics[str(id)].icon, select_path.bind(offers.size() - 1))


func _epic_pool(pools: Array) -> bool:
	for pool: float in pools:
		var entries: Array = _data.pools[str(int(pool))]
		if not entries.is_empty():
			return int(_data.relics[str(int(entries[0][0]))].rarity) == 3
	return false


func _add_card(title: String, description: String, icon: String, callback: Callable) -> void:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 160
	button.add_theme_font_size_override("font_size", 20)
	button.text = title if description.is_empty() else "%s\n\n%s" % [title, description]
	if icon:
		button.icon = load(icon)
		button.add_theme_constant_override("icon_max_width", 64)
	button.pressed.connect(callback)
	$Body/Paths.add_child(button)


func select_path(index: int) -> void:
	if index == 0 and _last_pending_reward():
		_rift_confirmation("ChallengeFightNotSkippedEarly", _select_confirmed.bind(index))
		return
	_select_confirmed(index)


func _last_pending_reward() -> bool:
	var stage := _party.battle_stage
	var rift = stage.red_rift
	return rift != null and rift.missions[rift.Mission.SKIP_BATTLE_REWARD] == rift.Status.PENDING and int(stage.floor_rules().chunk) == 1


func _select_confirmed(index: int) -> void:
	if claimed or index < 0 or index >= offers.size():
		return
	if index == 0 and _last_pending_reward():
		var rift = _party.battle_stage.red_rift
		rift.fail(rift.Mission.SKIP_BATTLE_REWARD)
		_party.battle_stage.encounter._finish_red_rift()
		return
	selected_event = offers[index]
	if index > 0:
		for pool: float in _challenge_pools[index - 1]:
			var entries: Array = _data.pools[str(int(pool))]
			var eligible := entries.filter(func(pair: Array): return not _party.relics.has(int(pair[0])) and not rewards.has(int(pair[0])))
			if not eligible.is_empty():
				rewards.append(_weighted_choice(eligible))
	claimed = true
	path_selected.emit()
	departed.emit()


func show_rewards() -> void:
	for node in $Body/Paths.get_children():
		$Body/Paths.remove_child(node)
		node.queue_free()
	$Shade.color.a = 0.87
	$Body/Title.text = tr("UI.Battle.RelicPicker.Title" if _epic_pool(_challenge_pools[offers.find(selected_event) - 1]) else "Events.Event_2002.EventName")
	for id in rewards:
		_add_card(tr("Relics.Relic_%d.Name" % id), "", _data.relics[str(id)].icon, take_relic.bind(id))
	_add_card(tr("UI.Common.Skip"), "", "", take_relic.bind(-1))
	show()


func take_relic(id: int, confirmed := false) -> void:
	if reward_closed or not visible or not claimed or (id != -1 and not rewards.has(id)):
		return
	if id != -1 and not confirmed and _last_pending_reward():
		_rift_confirmation("ChallengeFightNotSkipped", take_relic.bind(id, true))
		return
	reward_closed = true
	var rift = _party.battle_stage.red_rift
	if rift != null:
		if id == -1:
			rift.complete(rift.Mission.SKIP_BATTLE_REWARD)
		elif _last_pending_reward():
			rift.fail(rift.Mission.SKIP_BATTLE_REWARD)
			_party.battle_stage.encounter._finish_red_rift()
			return
	if id != -1:
		_party.apply_event_reward("relic", id, -1)
	hide()
	relic_selected.emit(id)

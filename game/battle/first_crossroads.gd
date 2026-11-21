class_name GuildrunFirstCrossroads
extends Control

signal path_selected
signal paths_restored
signal path_hovered(index: int)
signal departed
signal reward_claimed(kind: String, value: int, hero: int)

const STAT_KEYS := GuildrunBoardUnit.STAT_NAMES

var offers: Array[int] = []
var selected_event := -1
var claimed := false
var offered_item := -1
var pending_trial: Dictionary = {}
var _trial_view: Control
var _world_road_view: Control
var _data: Dictionary
var _roster: Array[int] = []
var _rng := RandomNumberGenerator.new()
var _party: GuildrunFirstShop
var choices: Array[Dictionary] = []
var _root_choices: Array[Dictionary] = []
var _pending_choice := -1
var _departure_sent := false


func setup(roster: Array[int], party: GuildrunFirstShop = null) -> void:
	_roster.assign(roster)
	_party = party
	$Body/Event/Content/Continue.pressed.connect(_continue_event)
	if is_instance_valid(_party):
		_party.rank_advance_committed.connect(_refresh_event_continue)
	var filename := "second_crossroads" if party != null and party.visit == 2 else "first_crossroads"
	if party != null and party.visit == 4:
		filename = "fourth_crossroads"
	elif party != null and party.visit == 5:
		filename = "first_campfire"
	elif party != null and party.visit == 7:
		filename = "seventh_crossroads"
	elif party != null and party.visit == 9:
		filename = "guild_banner"
	elif party != null and party.visit == 10:
		filename = "tenth_crossroads"
	elif party != null and party.visit == 11:
		filename = "second_campfire"
	if party != null and party.battle_stage != null and party.battle_stage.endless_floor >= 0:
		filename = "endless_crossroads"
	var trial_road := -1
	if party != null and party.battle_stage != null:
		trial_road = party.battle_stage.trial_road_id()
	if trial_road >= 0:
		_data = load("res://battle/forest_trial.gd").road(trial_road)
	elif party != null and party.visit == 1 and party.battle_stage != null and party.battle_stage.normal_opening:
		_data = load("res://battle/opening_draft.gd").data().kit.road
	else:
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/%s.json" % filename))
	var title_key := "Crossroads.Crossroads_%d.Name" % int(_data.id)
	var title := tr(title_key)
	if title == title_key and _data.events.size() == 1:
		title = tr("Events.Event_%s.EventName" % _data.events.keys()[0])
	if trial_road >= 0 and title == title_key:
		title = tr("Crossroads.Crossroads_30.Name")
	$Body/Title.text = title
	var recruit_available := true
	if filename == "endless_crossroads":
		var recruit_event: Dictionary = _data.events["2012"]
		var recruit_pool: Array = _data.pools.hero[str(int(recruit_event.pool))]
		recruit_available = load("res://battle/endless_event.gd").can_offer_recruit(recruit_pool, party)
	for pool: Array in _data.paths:
		var eligible := pool.filter(func(pair: Array): return recruit_available or int(pair[0]) != 2012)
		var available := eligible.filter(func(pair: Array): return not offers.has(int(pair[0])))
		var id := _weighted_choice(available if not available.is_empty() else eligible)
		var index := offers.size()
		offers.append(id)
		if trial_road >= 0:
			continue
		var event: Dictionary = _data.events[str(id)]
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 20)
		button.add_theme_constant_override("icon_max_width", 68)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		if event.icon:
			button.icon = load(event.icon)
		button.text = "%s\n\n%s" % [tr("Events.Event_%d.EventName" % id), _description(id, event)]
		button.pressed.connect(select_path.bind(index))
		$Body/Paths.add_child(button)
	if trial_road >= 0:
		_setup_trial_view(title)


func _setup_trial_view(title: String) -> void:
	_trial_view = load("res://battle/forest_trial_view.gd").new()
	_trial_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_trial_view)
	$Body.hide()
	$Shade.hide()
	_trial_view.setup(title, _path_entries(), select_path, path_hovered.emit)


func _path_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id in offers:
		entries.append({"title": tr("Events.Event_%d.EventName" % id), "description": _description(id, _data.events[str(id)])})
	return entries



func use_world_gates(rects: Array[Rect2], label_rects: Array[Rect2] = []) -> void:
	if is_instance_valid(_trial_view):
		_trial_view.use_world_gates(rects, label_rects)
	elif selected_event < 0 and int(_data.get("id", -1)) in [23, 120]:
		var valid := not rects.is_empty() and rects.size() == offers.size()
		if not is_instance_valid(_world_road_view) and valid:
			_world_road_view = load("res://battle/forest_trial_view.gd").new()
			_world_road_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(_world_road_view)
			_world_road_view.setup_world(_path_entries(), select_path, path_hovered.emit)
		if is_instance_valid(_world_road_view):
			_world_road_view.visible = valid
			_world_road_view.use_world_gates(rects, label_rects)
		$Body.visible = not valid
		$Shade.visible = not valid


func path_icon(index: int) -> Texture2D:
	if index < 0 or index >= offers.size():
		return null
	if not _data.has("events"):
		var holder := get_node_or_null("Body/Paths")
		if holder != null and index < holder.get_child_count() and holder.get_child(index) is Button:
			return holder.get_child(index).icon
		return null
	var path: String = _data.events[str(offers[index])].icon
	if path.is_empty():
		path = _data.get("fallback_icon", "")
	return load(path) if not path.is_empty() else null


func _weighted_choice(pool: Array) -> int:
	var total := 0
	for option: Array in pool:
		total += int(option[1])
	var pick := _rng.randi_range(0, total - 1)
	for option: Array in pool:
		pick -= int(option[1])
		if pick < 0:
			return int(option[0])
	return -1


func _description(id: int, event: Dictionary) -> String:
	if event.kind == "shards":
		return tr("Events.Shared.CrossroadsDescription.GainShards").format({"amount": int(event.amount)})
	var message := tr("Events.Event_%d.CrossroadsDescription" % id)
	if event.has("target_stat"):
		return message.format(_stat_text(event))
	return message


func _stat_text(event: Dictionary) -> Dictionary:
	return {"amount": int(event.amount_q16) >> 16, "stat": tr("UI.Stat.%s.Title" % STAT_KEYS[int(event.target_stat)])}


func select_path(index: int) -> void:
	if selected_event >= 0 or index < 0 or index >= offers.size():
		return
	selected_event = offers[index]
	if is_instance_valid(_world_road_view):
		_world_road_view.hide()
		$Body.show()
		$Shade.show()
	var event: Dictionary = _data.events[str(selected_event)]
	$Body/Title.text = tr("Events.Event_%d.EventName" % selected_event)
	$Body/Paths.hide()
	$Shade.color.a = 0.84
	$Body/Event.show()
	$Body/Event/Artwork.visible = not event.art.is_empty()
	if event.art:
		$Body/Event/Artwork.texture = load(event.art)
	var description: Label = $Body/Event/Content/Description
	match event.kind:
		"forest_trial":
			var trial = load("res://battle/forest_trial.gd")
			_root_choices.assign(trial.generate(selected_event, _data.pools, _party, _rng))
			_show_root_actions()
		"starter_kit":
			_root_choices.assign(load("res://battle/opening_draft.gd").kit_choices(_roster, _rng))
			_show_root_actions()
		"choice":
			var source := "fourth_shop_events" if _party.visit in [4, 7, 10] else "curated_event"
			if _data.id == 123:
				source = "endless_event"
			var builder = load("res://battle/%s.gd" % source).new()
			if source == "endless_event":
				builder.event = event
			if _data.has("remaining_victories"):
				builder.remaining_victories = int(_data.remaining_victories)
			builder.generate(selected_event, _data.pools, _party, _rng)
			choices.assign(builder.options)
			_root_choices.assign(choices)
			description.text = tr("Events.Event_%d.EventDescription" % selected_event)
			_show_root_actions()
		"shards":
			description.text = tr("Events.Event_%d.EventDescription" % selected_event)
			_action(tr("Events.Shared.ChoiceText.GetShards"), -1)
		"item":
			offered_item = _weighted_choice(event.choices)
			description.text = _description(selected_event, event)
			_action(tr("Events.Shared.ChoiceText.TakeReward").format({"name": tr("Items.Item_%d.Name" % offered_item)}), -1)
		"training":
			description.text = tr("Events.Shared.EventDescription.TrainingGrantStat").format(_stat_text(event))
			for hero in _roster:
				_action(tr("Heroes.Hero_%d.Name" % hero), hero)
	path_selected.emit()


func _choice_text(option: Dictionary, outcome: bool) -> String:
	if option.has("outcome" if outcome else "caption"):
		return option["outcome" if outcome else "caption"]
	if option.get("skip", false) and not outcome:
		return tr("UI.Common.Skip")
	var number := int(option.choice)
	var values := {"name": "", "time": 6, "statbonus": 10, "rank": "C", "statlosspercent": 20,
			"combatcount": int(option.get("delay", option.get("duration", 1)))}
	if option.kind in ["item", "relic"]:
		values.name = _party._entry_name(String(option.kind).capitalize(), int(option.value))
	if option.has("hero"):
		values.hero = tr("Heroes.Hero_%d.Name" % int(option.hero))
		if option.get("label_hero", false) and not outcome:
			return values.hero
	values.merge(option.get("format", {}), true)
	if number == 0:
		var text := tr("Events.Shared.ChoiceOutcome.GetReward") if outcome else tr("Events.Shared.ChoiceText.TakeReward").format(values)
		if option.has("extra_relic") and not outcome:
			text += " · " + _party._entry_name("Relic", option.extra_relic)
		return text
	var key := "Events.Event_%d.%s.%s" % [selected_event, option.get("key", "Choice_%d" % number), "ChoiceOutcomeText" if outcome else "ChoiceText"]
	var caption := tr(key)
	if caption == key:
		caption = tr("Events.Shared.ChoiceOutcome.GetReward")
	var markup := RegEx.new()
	markup.compile("<[a-zA-Z0-9_]+>|\\[|\\]")
	return markup.sub(caption.format(values), "", true)


func _rift_confirmation(key: String, accept: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("UI.Dialog.Warning.%s.Title" % key)
	dialog.dialog_text = tr("UI.Dialog.Warning.%s.Description" % key)
	add_child(dialog)
	dialog.confirmed.connect(accept, CONNECT_ONE_SHOT)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	dialog.popup_centered()


func _choice_button(caption: String, callback: Callable, disabled := false) -> void:
	var button := Button.new()
	button.disabled = disabled
	button.text = caption
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 48
	button.pressed.connect(callback)
	$Body/Event/Content/Actions.add_child(button)


func _show_root_actions() -> void:
	_pending_choice = -1
	choices.assign(_root_choices)
	$Body/Event/Content/Description.text = tr("Events.Event_%d.EventDescription" % selected_event)
	var event: Dictionary = _data.events[str(selected_event)]
	if event.kind == "forest_trial":
		var values: Dictionary = load("res://battle/forest_trial.gd").description_format(
				selected_event, _party.battle_stage.last_miniboss_group)
		$Body/Event/Content/Description.text = $Body/Event/Content/Description.text.format(values)
		_show_trial_event()
		return
	if event.has("target_stat"):
		$Body/Event/Content/Description.text = tr("Events.Shared.EventDescription.GrantHeroStat").format(_stat_text(event))
	_clear_actions()
	for i in choices.size():
		var caption := _choice_text(choices[i], false)
		if selected_event in [600, 601]:
			var title := tr("Events.Event_%d.Choice_%d.ChoiceTitle" % [selected_event, int(choices[i].choice)])
			caption = "%s · %s" % [title.format(choices[i].get("format", {})), caption]
		_choice_button(caption, choose_reward.bind(i), choices[i].get("disabled", false))


func _show_trial_event() -> void:
	var shop_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/regular_shop.json"))
	var catalog: Dictionary = shop_data.catalog
	catalog.merge(shop_data.locked_catalog)
	var options: Array[Dictionary] = []
	for option in choices:
		var title := tr("Events.Event_%d.Choice_%d.ChoiceTitle" % [selected_event, int(option.choice)]).format(option.format)
		var entry := {"text": "%s\n%s" % [title, _choice_text(option, false)], "kind": option.kind}
		if option.kind in ["item", "relic"]:
			var kind := String(option.kind).capitalize()
			var key := "%s_%d" % [kind, int(option.value)]
			if catalog.has(key):
				entry.icon = load(catalog[key].icon)
				entry.name = _party._entry_name(kind, int(option.value))
		options.append(entry)
	var artwork: Texture2D = $Body/Event/Artwork.texture if $Body/Event/Artwork.visible else null
	_trial_view.show_event($Body/Title.text, $Body/Event/Content/Description.text, artwork, options, choose_reward, _return_to_trial_paths)


func _return_to_trial_paths() -> void:
	_trial_view.show_roads()
	selected_event = -1
	$Body/Title.text = tr("Crossroads.Crossroads_30.Name")
	$Body/Event.hide()
	$Body/Paths.show()
	paths_restored.emit()



func _clear_actions() -> void:
	for node in $Body/Event/Content/Actions.get_children():
		$Body/Event/Content/Actions.remove_child(node)
		node.queue_free()


func choose_reward(index: int, confirmed := false) -> void:
	if claimed or _pending_choice >= 0 or index < 0 or index >= choices.size():
		return
	if choices[index].get("disabled", false):
		return
	var rift = _party.battle_stage.red_rift
	if not confirmed and rift != null and selected_event == 601 and choices[index].kind != "skip_rift_campfire" and rift.missions[rift.Mission.SKIP_CAMPFIRE] == rift.Status.PENDING and _pending_choice < 0:
		_rift_confirmation("CampfireNotSkipped", choose_reward.bind(index, true))
		return
	_pending_choice = index
	var option := choices[index]
	if option.has("children"):
		_show_children(option.children, _choice_text(option, false))
		return
	if option.has("after"):
		_party.take_curated_reward(option)
		_show_children(option.after, _choice_text(option, true))
		return
	if option.kind == "random_spec":
		var alternatives: Array = preload("res://battle/hero_rank.gd").choices(option.hero).filter(
				func(spec: Dictionary): return int(spec.id) != int(_party.specializations[option.hero].id))
		if not alternatives.is_empty():
			_party.specializations[option.hero] = alternatives[_rng.randi_range(0, alternatives.size() - 1)]
	if option.kind == "well_rank" and _party.hero_ranks[option.hero] == 1:
		_choose_hero(option.hero)
		return
	if option.kind in ["rank", "retrain"]:
		_clear_actions()
		for hero in _roster:
			if (option.kind == "rank" and int(_party.hero_ranks[hero]) <= int(_data.pools.get("max_rank", 1))) or (option.kind == "retrain" and _party.specializations.has(hero)):
				_choice_button(tr("Heroes.Hero_%d.Name" % hero), _choose_hero.bind(hero))
		if selected_event in [600, 601, 2004]:
			_choice_button(tr("UI.Common.Back"), _show_root_actions)
		return
	_finish_choice()


func _show_children(children: Array, caption: String) -> void:
	_pending_choice = -1
	choices.assign(children)
	_clear_actions()
	$Body/Event/Content/Description.text = caption
	for i in choices.size():
		_choice_button(_choice_text(choices[i], false), choose_reward.bind(i))
	if selected_event in [506, 1013] or _data.id == 123:
		_choice_button(tr("UI.Common.Back"), _show_root_actions)


func _continue_event() -> void:
	if _departure_sent or not claimed or _has_pending_rank_up():
		return
	_departure_sent = true
	departed.emit()


func _has_pending_rank_up() -> bool:
	return is_instance_valid(_party) and (_party.pending_hero >= 0 or _party.has_pending_rank_modifier())


func _refresh_event_continue() -> void:
	$Body/Event/Content/Continue.disabled = _has_pending_rank_up()


func _choose_hero(hero: int) -> void:
	var option := choices[_pending_choice]
	option.hero = hero
	if selected_event == 1024 and option.kind == "rank":
		if not claimed and _party.request_rank_up(hero, self):
			_finish_choice()
		return
	if option.kind == "rank" and int(_party.hero_ranks[hero]) >= 2:
		_party.hero_ranks[hero] += 1
		_finish_choice()
		return
	_clear_actions()
	for specialization: Dictionary in preload("res://battle/hero_rank.gd").choices(hero):
		if option.kind == "retrain" and int(_party.specializations[hero].id) == int(specialization.id):
			continue
		_choice_button(tr(specialization.name), _choose_specialization.bind(specialization))
	if selected_event in [600, 601, 2004]:
		var chosen_index := _pending_choice
		_choice_button(tr("UI.Common.Back"), func():
			_pending_choice = -1
			choose_reward(chosen_index))


func _choose_specialization(specialization: Dictionary) -> void:
	if claimed:
		return
	var option := choices[_pending_choice]
	_party.hero_ranks[option.hero] = maxi(2, int(_party.hero_ranks[option.hero]))
	if option.kind == "well_rank":
		option.specialized_now = true
	_party.specializations[option.hero] = specialization
	_finish_choice()


func _finish_choice() -> void:
	if claimed:
		return
	var option := choices[_pending_choice]
	if option.kind == "skip_rift_campfire":
		var rift = _party.battle_stage.red_rift
		rift.complete(rift.Mission.SKIP_CAMPFIRE)
	elif option.has("modifier") and option.has("stage_id"):
		pending_trial = {"modifier": option.modifier, "stage_id": option.stage_id, "kind": option.kind, "value": option.value}
	else:
		_party.take_curated_reward(option)
	claimed = true
	var outcome := _choice_text(option, true)
	$Body/Event/Content/Description.text = outcome
	if not pending_trial.is_empty():
		_trial_view.show_outcome(outcome, func(): departed.emit())
	$Body/Event/Content/Actions.hide()
	_refresh_event_continue()
	$Body/Event/Content/Continue.show()


func _action(caption: String, hero: int) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 48
	button.pressed.connect(claim.bind(hero))
	$Body/Event/Content/Actions.add_child(button)


func claim(hero: int = -1) -> void:
	if selected_event < 0 or claimed:
		return
	var event: Dictionary = _data.events[str(selected_event)]
	var value: int
	var outcome: String
	match event.kind:
		"shards":
			value = int(event.amount)
			outcome = "%s  +%d" % [tr("UI.BattleInfo.Shards.Title"), value]
		"item":
			value = offered_item
			outcome = tr("Events.Shared.ChoiceText.TakeReward").format({"name": tr("Items.Item_%d.Name" % value)})
		"training":
			if not _roster.has(hero):
				return
			value = int(event.modifier)
			var values := _stat_text(event)
			values.hero = tr("Heroes.Hero_%d.Name" % hero)
			outcome = tr("Events.Shared.MechanicalOutcome.AddPermanentStatBonus").format(values)
		_: return
	claimed = true
	$Body/Event/Content/Actions.hide()
	$Body/Event/Content/Description.text = outcome
	$Body/Event/Content/Continue.show()
	reward_claimed.emit(event.kind, value, hero)

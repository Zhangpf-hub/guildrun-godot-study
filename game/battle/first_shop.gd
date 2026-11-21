class_name GuildrunFirstShop
extends Control

signal departed
signal hero_sold(id: int)
signal rank_modifier_choice_requested(hero: int, rank: int, offers: Array[int])
signal rank_advance_committed

var shards: int
var battle_reward: int
var survival_reward: int
var rewind_payout := 0
var roster: Array[int] = []
var reserve_slots: Array[int] = []
var items: Array[int] = []
var equipped_to: Dictionary = {}
var relics: Array[int] = []
var hero_modifiers: Dictionary = {}
var rank_modifiers_by_hero: Dictionary = {}
var hero_ranks: Dictionary = {}
var specializations := {}
var pending_hero := -1
var battle_stage: Node3D
var _rank_picker: Control
var permanent_stats: Dictionary = {}
var ability_progress: Dictionary = {}
var event_durations: Dictionary = {}
var delayed_rewards: Array[Dictionary] = []
var victory_shard_modifiers: Array[Dictionary] = []
var successful_shop_rerolls := 0
var visit := 1
var regular_stock: bool:
	get:
		return visit >= 3 or (battle_stage != null and battle_stage.normal_opening)
var opening_xp := 0
var quest_progress := {}
var completed_quests := {}
var quest_stats := {}
var charm_wins := 0
var kit_id := 0
var kit_hero_stats := {}
var stock: Array = []
var purchased: Dictionary = {}
var _data: Dictionary
var _claimed := false
var _departed := false
var _panel: Control
var _tax_button: Button
var _balance: Label
var _owned: Label
var _selling: Control
var _leave: Button
var _buttons: Dictionary = {}
var _reroll: Button
var _freeze: Button
var frozen := false
var reroll_cost: int
var sale_index := -1
var super_shop := false
var super_sales: Array[int] = []
var offer_ranks := {}
var offer_specs := {}
var offer_rank_modifiers := {}
var _rank_txn = load("res://battle/rank_txn.gd").new()
var _rank_pools: Dictionary
var _rank_rng := RandomNumberGenerator.new()
var _rng := RandomNumberGenerator.new()


func prepare(starter: int, stage: Dictionary, _survivors: int) -> void:
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/first_shop.json"))
	stock = _data.stock[str(starter)]
	shards = int(_data.starting_shards)
	var rewards: Dictionary = stage["<StageRewards>k__BackingField"]
	var bounds: Dictionary = rewards["<GoldRewardRange>k__BackingField"]
	# The tutorial entry gives a fixed reward (both ends of the range are 15).
	battle_reward = int(bounds.FromInclusive)
	survival_reward = 0
	roster.assign([starter])
	hero_ranks[starter] = 1
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func start_normal(starter: int, relic: int, xp: int) -> void:
	visit = 0
	opening_xp = xp
	shards = int(load("res://battle/opening_draft.gd").data().starting_shards)
	roster.append(starter)
	hero_ranks[starter] = 1
	if relic > 0:
		relics.append(relic)
		_apply_starting_reward(relic)
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _apply_starting_reward(relic: int) -> void:
	var rules = load("res://battle/opening_draft.gd")
	var variables: Dictionary = rules.data().descriptions[str(relic)].get("Description", {})
	match relic:
		6001, 6003, 6010:
			shards += int(variables["0"])
		6012:
			battle_stage.max_deployed = mini(battle_stage.max_deployed + int(variables["0"]), int(variables["1"]))
		6013:
			shards = maxi(0, shards - int(variables["0"]))
		6016:
			battle_stage.max_deployed -= int(variables["1"])
	var item_pools: Array = {6001: [3], 6004: [3, 3, 3], 6006: [18, 18]}.get(relic, [])
	if relic >= 6018 and relic <= 6024:
		item_pools = [31 + relic - 6018]
	elif relic >= 6025 and relic <= 6031:
		item_pools = [20 + relic - 6025]
	elif relic >= 6032 and relic <= 6038:
		item_pools = [[6, 12, 14, 16, 4, 8, 10][relic - 6032]]
	for pool: int in item_pools:
		var item: int = rules.pick_reward("Item", pool, opening_xp, _rng)
		if item >= 0:
			items.append(item)
	if relic in [6001, 6005]:
		var bonus: int = rules.pick_reward("Relic", 101 if relic == 6001 else 102, opening_xp, _rng, relics)
		if bonus >= 0:
			relics.append(bonus)


func advance_quest(id: int, amount: int) -> void:
	if relics.has(id) and not completed_quests.has(id) and amount > 0:
		quest_progress[id] = int(quest_progress.get(id, 0)) + amount


func settle_combat(units: Array[GuildrunBoardUnit], victory: bool) -> void:
	if relics.has(3037):
		shards += mini(20, floori(shards / 5.0))
	if victory:
		if relics.has(6017):
			charm_wins += 1
		advance_quest(6002, 1)
		advance_quest(1029, 1)
		if relics.has(1027) or relics.has(1028):
			var classes := {}
			var heroes := 0
			for unit in units:
				if unit.is_hero:
					heroes += 1
					for profession in range(1, 8):
						if unit.has_class(profession):
							classes[profession] = int(classes.get(profession, 0)) + 1
			if heroes >= 3 and not classes.is_empty():
				if classes.values().max() >= 3:
					advance_quest(1027, 1)
				if classes.values().max() == 1:
					advance_quest(1028, 1)
	if quest_progress.is_empty():
		return
	var rules: Dictionary = load("res://battle/opening_draft.gd").data().quests
	for id: int in quest_progress:
		var quest: Dictionary = rules[str(id)]
		if completed_quests.has(id) or int(quest_progress[id]) < int(quest.target):
			continue
		completed_quests[id] = true
		for action: Dictionary in quest.actions:
			if action.kind == "GainShardsAction":
				shards += int(action.values.Amount)
			elif action.kind == "ModifyStatAction":
				var stat := int(action.values.StatType)
				quest_stats[stat] = int(quest_stats.get(stat, 0)) + (int(action.values.Value.RawValue) >> 16)


func deployed_ids() -> Array[int]:
	var deployed: Array[int] = []
	var limit := int(battle_stage.max_deployed)
	while reserve_slots.size() < int(battle_stage.max_total_heroes) - limit:
		reserve_slots.append(-1)
	for id in roster:
		if reserve_slots.has(id):
			continue
		if deployed.size() < limit:
			deployed.append(id)
		else:
			var empty := reserve_slots.find(-1)
			if empty >= 0:
				reserve_slots[empty] = id
	return deployed


func prepare_second(reward: int, survivors: int) -> void:
	visit = 2
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/second_shop.json"))
	var starter := str(roster[0])
	stock = _data.stock[starter].duplicate()
	var alternatives: Array = _data.fallbacks[starter].duplicate()
	# Slot zero is the tutorial's deliberate duplicate. Other hero slots skip owned copies.
	for i in range(1, 3):
		while roster.has(int(_data.catalog[stock[i]].id)) and not alternatives.is_empty():
			stock[i] = alternatives.pop_front()
	battle_reward = reward
	survival_reward = survivors * _survivor_price()
	_reset_visit()


func prepare_third(reward: int, survivors: int, special := false) -> void:
	visit += 1
	super_shop = special
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/regular_shop.json"))
	for key: String in _data.locked_catalog:
		if opening_xp >= int(_data.locked_catalog[key].xp):
			_data.catalog[key] = _data.locked_catalog[key]
	battle_reward = reward
	survival_reward = survivors * _survivor_price()
	reroll_cost = int(_data.super_reroll if super_shop else _data.reroll)
	var keep := frozen and not super_shop
	_reset_visit(keep)
	if not keep:
		_roll_stock()
	frozen = false


func _reset_visit(keep_offers := false) -> void:
	_claimed = false
	_departed = false
	if not keep_offers:
		purchased.clear()
	_buttons.clear()
	if is_instance_valid(_panel):
		_panel.free()
	_panel = null


func _roll_stock() -> void:
	stock = []
	offer_rank_modifiers.clear()
	super_sales.clear()
	offer_ranks.clear()
	offer_specs.clear()
	var counts: Dictionary = _data.super_counts if super_shop else _data.counts
	var odds: Dictionary = _data.super_odds if super_shop else _data.odds
	var second_chunk := battle_stage != null and int(battle_stage.floor_rules().get("chunk", 0)) == 1
	if second_chunk and not super_shop:
		odds = _data.second_chunk_odds
	var sections := []
	for kind: String in ["Hero", "Item", "Relic"]:
		var section := []
		var extra := 1 if kind == "Relic" and relics.has(6007) else 0
		for slot in int(counts[kind]) + extra:
			var tier := 1
			if kind != "Hero" or super_shop or second_chunk:
				var total := 0
				for weight: float in odds[kind].values():
					total += maxi(0, int(weight))
				var roll := _rng.randi_range(0, total - 1)
				for key: String in odds[kind]:
					roll -= maxi(0, int(odds[kind][key]))
					if roll < 0:
						tier = int(key)
						break
			var eligible := []
			for key: String in _data.catalog:
				var row: Dictionary = _data.catalog[key]
				if row.kind != kind or (kind != "Hero" and int(row.tier) != tier) or stock.has(key):
					continue
				if kind == "Hero" and int(hero_ranks.get(int(row.id), 0)) >= 4:
					continue
				if kind == "Relic" and relics.has(int(row.id)):
					continue
				eligible.append(key)
			if eligible.is_empty():
				continue
			section.append(stock.size())
			var pick: String = eligible[_rng.randi_range(0, eligible.size() - 1)]
			if kind == "Hero" and (super_shop or second_chunk):
				offer_ranks[stock.size()] = tier
				if tier >= 3:
					offer_rank_modifiers[stock.size()] = _roll_pre_ranked(int(_data.catalog[pick].id), tier)
				if tier > 1:
					var specs: Array = preload("res://battle/hero_rank.gd").choices(int(_data.catalog[pick].id))
					if not specs.is_empty():
						offer_specs[stock.size()] = specs[_rng.randi_range(0, specs.size() - 1)]
			stock.append(pick)
		if not section.is_empty():
			sections.append(section)
	if super_shop:
		sale_index = -1
		for section: Array in sections:
			super_sales.append(int(section[_rng.randi_range(0, section.size() - 1)]))
	else:
		var section: Array = sections[_rng.randi_range(0, sections.size() - 1)]
		sale_index = int(section[_rng.randi_range(0, section.size() - 1)])


func price_at(index: int) -> int:
	var price := int(_data.catalog[stock[index]].price)
	if offer_ranks.has(index):
		price = int(_data.rank_prices[str(offer_ranks[index])])
	if relics.has(6008) and _data.catalog[stock[index]].kind == "Item":
		price = maxi(0, price - 2)
	if kit_id == 734 and _data.catalog[stock[index]].kind == "Item":
		price = maxi(0, price - 2)
	if index == sale_index or super_sales.has(index):
		price = (price * (65536 - int(_data.discount))) >> 16
	return price


func reroll() -> bool:
	if not regular_stock or not _claimed or _departed or _rank_picker != null or has_pending_rank_modifier() or shards < reroll_cost:
		return false
	shards -= reroll_cost
	successful_shop_rerolls += 1
	if battle_stage:
		battle_stage.sound.play_ui(14)
	reroll_cost += int(_data.reroll_increment)
	frozen = false
	purchased.clear()
	var prior_size := stock.size()
	_roll_stock()
	if prior_size != stock.size():
		_buttons.clear()
		_panel.free()
		_build_panel()
		return true
	for i: int in _buttons.keys():
		var slot: Control = _buttons[i].get_parent()
		_buttons[i].free()
		_add_offer(slot, i)
	_refresh()
	return true


func toggle_freeze() -> void:
	if regular_stock and _claimed and not _departed and _rank_picker == null and not has_pending_rank_modifier():
		frozen = not frozen
		if battle_stage:
			battle_stage.sound.play_ui(15 if frozen else 16)
		_refresh()


func claim_and_open() -> void:
	if _claimed:
		return
	_claimed = true
	shards += battle_reward + survival_reward + rewind_payout
	if battle_stage and battle_stage.red_rift:
		battle_stage.red_rift.visits[int(battle_stage.floor_rules().chunk)] += 1
	_build_panel()


func _build_panel() -> void:
	var expanded := super_shop or stock.size() > 6
	var panel_scene := "super_shop" if expanded else "first_shop"
	_panel = (load("res://UI/%s.tscn" % panel_scene) as PackedScene).instantiate()
	add_child(_panel)
	_panel.pivot_offset_ratio = Vector2.ZERO
	var headings := {
		"CenterPanel/HeroesPanel": "UI.Common.Heroes",
		"CenterPanel/ItemRelicPanel/ItemsToBuyPanel_VerticalLayout": "UI.Common.Items",
		"CenterPanel/ItemRelicPanel/RelicsToBuyPanel_VerticalLayout": "UI.Common.Relics"
	}
	for path: String in headings:
		var label := Label.new()
		label.text = tr(headings[path])
		label.position = Vector2(18, 6)
		label.add_theme_font_size_override("font_size", 28)
		_panel.get_node(path.replace("_VerticalLayout", "") if expanded else path).add_child(label)
	var entries := {"Hero": [], "Item": [], "Relic": []}
	for index in stock.size():
		entries[_data.catalog[stock[index]].kind].append(index)
	for slot: Control in _panel.find_children("*", "Control", true, false):
		if slot.has_meta("offer_slot"):
			var authored := int(slot.get_meta("offer_slot"))
			var first_relic := 7 if expanded else 5
			var kind := "Hero" if authored < 3 else ("Item" if authored < first_relic else "Relic")
			var ordinal := authored - int({"Hero": 0, "Item": 3, "Relic": first_relic}[kind])
			if ordinal < entries[kind].size():
				_add_offer(slot, int(entries[kind][ordinal]))
			else:
				slot.hide()
			if kind == "Relic" and expanded and ordinal == 2 and entries.Relic.size() > 3:
				var extra := slot.duplicate(0) as Control
				for button in extra.get_children().filter(func(child): return child is Button):
					button.free()
				slot.get_parent().add_child(extra)
				extra.position.x += 100
				_add_offer(extra, int(entries.Relic[3]))
	_balance = Label.new()
	_panel.add_child(_balance)
	_balance.position = Vector2(32, 8)
	_balance.add_theme_font_size_override("font_size", 32)
	if battle_stage and battle_stage.red_rift:
		_tax_button = Button.new()
		_tax_button.name = "BuyKeyFragment"
		var graphic: Control = _panel.get_node("ButtonsPanel/ProceedButton/BuyKeyFragmentButton")
		graphic.add_child(_tax_button)
		_tax_button.flat = true
		_tax_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tax_button.pressed.connect(pay_rift_tax)
	_owned = Label.new()
	_panel.add_child(_owned)
	_owned.position = Vector2(32, 60)
	_owned.add_theme_font_size_override("font_size", 20)
	if regular_stock:
		_owned.hide()
		_selling = load("res://battle/shop_selling_panel.gd").new()
		_panel.add_child(_selling)
		_selling.setup(self, _panel.get_node("ButtonsPanel/Panel_CSF/SellingPanel"))
	_leave = Button.new()
	_panel.add_child(_leave)
	_leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_leave.offset_left = -220
	_leave.offset_right = -30
	_leave.offset_top = 12
	_leave.offset_bottom = 66
	_leave.text = tr("UI.Common.Continue")
	_leave.pressed.connect(leave)
	if regular_stock:
		_reroll = Button.new()
		_panel.add_child(_reroll)
		_reroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_reroll.offset_left = -405
		_reroll.offset_right = -225
		_reroll.offset_top = 12
		_reroll.offset_bottom = 66
		_reroll.pressed.connect(reroll)
		_freeze = Button.new()
		_panel.add_child(_freeze)
		_freeze.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_freeze.offset_left = -525
		_freeze.offset_right = -412
		_freeze.offset_top = 12
		_freeze.offset_bottom = 66
		_freeze.pressed.connect(toggle_freeze)
	if not resized.is_connected(_fit_panel):
		resized.connect(_fit_panel)
	show()
	_fit_panel()
	_refresh()


func _fit_panel() -> void:
	if not is_instance_valid(_panel):
		return
	var zoom := minf(size.x / 1450.0, size.y / 815.0)
	if is_instance_valid(_tax_button):
		# The original key-fragment control extends above the shop panel.
		var key_local := _panel.get_global_transform().affine_inverse() * _tax_button.global_position
		var background: Control = _panel.get_node("Background")
		var bounds := background.get_rect().expand(Vector2(0, minf(0, key_local.y - 16)))
		zoom = minf(zoom, size.y / (bounds.size.y + 32))
		_panel.scale = Vector2.ONE * zoom
		_panel.position = (size - bounds.size * zoom) * 0.5 - bounds.position * zoom
		return
	_panel.scale = Vector2.ONE * zoom
	_panel.position = (size - _panel.size * zoom) * 0.5 - Vector2(0, 12) * zoom


func _entry_name(kind: String, id: int) -> String:
	var table: String = {"Hero": "Heroes", "Item": "Items", "Relic": "Relics"}[kind]
	return tr("%s.%s_%d.Name" % [table, kind, id])


func _add_offer(slot: Control, index: int) -> void:
	var offer: Dictionary = _data.catalog[stock[index]]
	var hero: bool = offer.kind == "Hero"
	var button := Button.new()
	slot.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if hero:
		button.offset_left = 34
		button.offset_right = -34
		button.offset_top = 18
		button.offset_bottom = -28
	button.flat = hero
	button.icon = load(offer.icon)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if hero else HORIZONTAL_ALIGNMENT_LEFT
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP if hero else VERTICAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 25)
	var caption := _entry_name(offer.kind, int(offer.id))
	if offer_ranks.has(index):
		caption += " (%s)" % ["C", "B", "A", "S"][int(offer_ranks[index]) - 1]
	button.tooltip_text = caption
	if (super_shop or stock.size() > 6) and not hero:
		button.add_theme_font_size_override("font_size", 18)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.text = str(price_at(index))
	else:
		button.text = "%s\n%d %s" % [caption, price_at(index), tr("UI.BattleInfo.Shards.Title")]
	button.pressed.connect(buy.bind(index))
	_buttons[index] = button


func buy(index: int) -> bool:
	if not _claimed or _departed or _rank_picker != null or has_pending_rank_modifier() or index < 0 or index >= stock.size() or purchased.has(index):
		return false
	var offer: Dictionary = _data.catalog[stock[index]]
	var price := price_at(index)
	if shards < price:
		return false
	match offer.kind:
		"Hero":
			var hero_id := int(offer.id)
			if roster.has(hero_id) and battle_stage and int(hero_ranks[hero_id]) >= int(battle_stage.max_hero_rank):
				return false
			if not roster.has(hero_id):
				if battle_stage and roster.size() >= int(battle_stage.max_total_heroes):
					var notice := AcceptDialog.new()
					notice.title = tr("UI.Dialog.MaxHeroes.Title")
					notice.dialog_text = tr("UI.Dialog.MaxHeroes.Description").format([battle_stage.max_total_heroes])
					notice.visibility_changed.connect(func(): 
						if not notice.visible: notice.queue_free())
					add_child(notice)
					notice.popup_centered()
					return false
				_recruit(hero_id, int(offer_ranks.get(index, 1)), offer_specs.get(index, {}), offer_rank_modifiers.get(index, {}))
				if battle_stage:
					battle_stage.sound.play_shop_voice(battle_stage._heroes[hero_id], "purchase_vo")
			elif int(hero_ranks[hero_id]) == 1:
				pending_hero = hero_id
			elif not _prepare_rank_modifier_choice(hero_id):
				return false
		"Item":
			items.append(int(offer.id))
			if battle_stage:
				battle_stage.sound.play_ui(18)
		"Relic":
			relics.append(int(offer.id))
			if battle_stage:
				battle_stage.sound.play_ui(19)
		_: return false
	shards -= price
	purchased[index] = true
	_refresh()
	if pending_hero >= 0:
		show_rank_picker(pending_hero, offer.icon, self)
	elif has_pending_rank_modifier():
		_emit_rank_modifier_choice()
	return true


func show_rank_picker(id: int, portrait: String, parent: Node) -> void:
	pending_hero = id
	var options: Array = preload("res://battle/hero_rank.gd").choices(id)
	_rank_picker = preload("res://battle/specialization_picker.gd").new()
	parent.add_child(_rank_picker)
	_rank_picker.setup(id, portrait, options)
	_rank_picker.chosen.connect(choose_specialization)
	_rank_picker.dismissed.connect(_close_rank_picker)


func choose_specialization(index: int) -> bool:
	if pending_hero < 0 or _rank_picker == null:
		return false
	var options: Array = preload("res://battle/hero_rank.gd").choices(pending_hero)
	if index < 0 or index >= options.size():
		return false
	var hero := pending_hero
	pending_hero = -1
	specializations[hero] = options[index]
	hero_ranks[hero] = 2
	var changes := PackedStringArray()
	if battle_stage:
		battle_stage.sound.play_ui(9)
		battle_stage.sound.play_shop_voice(battle_stage._heroes[hero], "rankup_b_vo")
		var mods: Array = hero_modifiers.get(hero, [])
		var before: Dictionary = battle_stage.hero_stats(hero, mods, equipment(hero), relics)
		var after: Dictionary = battle_stage.hero_stats(hero, mods, equipment(hero), relics, 2, options[index])
		for stat: String in preload("res://battle/hero_rank.gd").data().growth.base:
			var key := "<%s>k__BackingField" % stat
			if before[key] != after[key]:
				changes.append("%s   %d → %d" % [tr("UI.Stat.%s.Title" % stat), int(before[key]), int(after[key])])
	if is_instance_valid(_panel):
		_refresh()
	_rank_picker.show_result(index, changes)
	rank_advance_committed.emit()
	return true


func _close_rank_picker() -> void:
	if pending_hero >= 0:
		return
	_rank_picker.queue_free()
	_rank_picker = null


func pay_rift_tax() -> bool:
	var floor_info: Dictionary = battle_stage.floor_rules()
	var paid: bool = battle_stage.red_rift.pay_tax(self, int(floor_info.chunk), int(battle_stage.red_rift.visits[int(floor_info.chunk)]))
	if paid:
		_refresh()
	return paid


func leave() -> void:
	if not _claimed or _departed or _rank_picker != null or has_pending_rank_modifier():
		return
	_departed = true
	hide()
	departed.emit()


func has_pending_rank_modifier() -> bool:
	return not _rank_txn.pending.is_empty()


func _modifier_classes(hero: int, include_specialization: bool) -> Array[int]:
	var result: Array[int] = []
	if not battle_stage or not battle_stage._heroes.has(hero):
		return result
	var row: Dictionary = battle_stage._heroes[hero]
	var secondary := int(row._class2ID)
	if include_specialization:
		var spec: Dictionary = specializations.get(hero, {})
		var spec_class := int(spec.get("class", -1))
		if spec_class > 0:
			secondary = spec_class
	for candidate: int in [int(row._class1ID), secondary]:
		if candidate > 0 and not result.has(candidate):
			result.append(candidate)
	return result


func _modifier_data() -> Dictionary:
	if _rank_pools.is_empty():
		_rank_pools = _rank_txn.pool_data()
	return _rank_pools


func _roll_pre_ranked(hero: int, rank: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = _rank_rng
	var result := {}
	var classes := _modifier_classes(hero, false)
	if classes.is_empty():
		return result
	for earned_rank in range(3, rank + 1):
		var selected: Array[int] = [classes[rng.randi_range(0, classes.size() - 1)]]
		var offers: Array[int] = _rank_txn.draw(_modifier_data(), selected, earned_rank, 1, result.values(), rng)
		if not offers.is_empty():
			result[earned_rank] = offers[0]
	return result


func has_recruitment_space() -> bool:
	return is_instance_valid(battle_stage) and roster.size() < int(battle_stage.max_total_heroes)


func _recruit(hero: int, rank: int, spec: Dictionary, modifiers: Dictionary) -> void:
	roster.append(hero)
	hero_ranks[hero] = rank
	_apply_pre_ranked(hero, rank, modifiers)
	if not spec.is_empty():
		specializations[hero] = spec
	if battle_stage:
		deployed_ids()


func _apply_pre_ranked(hero: int, rank: int, explicit: Dictionary) -> void:
	if explicit.is_empty():
		return
	var enabled := {}
	for modifier: String in _modifier_data().enabled:
		enabled[int(modifier)] = true
	_rank_txn.grant_pre_ranked(hero, rank, explicit, enabled, record_rank_modifier)


func _prepare_rank_modifier_choice(hero: int) -> bool:
	if not battle_stage or not roster.has(hero) or has_pending_rank_modifier() or _rank_picker != null:
		return false
	var current := int(hero_ranks.get(hero, 0))
	var cap := int(battle_stage.max_hero_rank)
	if current < 2 or current >= cap:
		return false
	var classes := _modifier_classes(hero, true)
	var offers: Array[int] = _rank_txn.draw(_modifier_data(), classes, current + 1,
		3 if classes.size() == 1 else 4, rank_modifiers_for(hero).values(), _rank_rng)
	return _rank_txn.begin_existing(hero, current, cap, offers)


func _emit_rank_modifier_choice() -> void:
	var choice: Dictionary = _rank_txn.pending
	rank_modifier_choice_requested.emit(int(choice.hero), int(choice.rank), choice.offers.duplicate())


func choose_rank_modifier(index: int) -> bool:
	if not _rank_txn.accept_existing(index, hero_ranks, record_rank_modifier):
		return false
	if is_instance_valid(_panel):
		_refresh()
	rank_advance_committed.emit()
	return true


# The training event restores the hero DTO before asking the registry to advance it.
func return_from_training(hero: int) -> bool:
	return request_rank_up(hero, get_parent())


func request_rank_up(hero: int, presentation_parent: Node) -> bool:
	if not roster.has(hero) or not battle_stage or _rank_picker != null or has_pending_rank_modifier() or pending_hero >= 0:
		return false
	if int(hero_ranks.get(hero, 0)) == 1 and int(battle_stage.max_hero_rank) >= 2:
		var portrait: Texture2D = battle_stage.hero_portrait(hero)
		var icon := portrait.resource_path
		show_rank_picker(hero, icon, presentation_parent)
		return true
	if not _prepare_rank_modifier_choice(hero):
		return false
	_emit_rank_modifier_choice()
	return true


# Rank modifiers carry the acquisition rank. Training rewards are stored separately.
func record_rank_modifier(hero: int, rank: int, modifier: int) -> bool:
	if not roster.has(hero) or rank < 1 or rank > 4 or modifier <= 0:
		return false
	var ranks := rank_modifiers_for(hero)
	ranks[rank] = modifier
	rank_modifiers_by_hero.erase(str(hero))
	rank_modifiers_by_hero[hero] = ranks
	return true


func rank_modifiers_for(hero: int) -> Dictionary:
	var stored: Variant = rank_modifiers_by_hero.get(hero, rank_modifiers_by_hero.get(str(hero), {}))
	var result := {}
	if not stored is Dictionary:
		return result
	for rank: int in range(1, 5):
		var modifier: Variant = stored.get(rank, stored.get(str(rank)))
		if (modifier is int or modifier is float) and int(modifier) > 0:
			result[rank] = int(modifier)
	return result


func apply_event_reward(kind: String, value: int, hero: int) -> void:
	match kind:
		"shards": shards += value
		"item": items.append(value)
		"relic": relics.append(value)
		"training":
			if not hero_modifiers.has(hero):
				hero_modifiers[hero] = []
			hero_modifiers[hero].append(value)


func take_curated_reward(option: Dictionary) -> void:
	if option.kind == "starter_kit":
		take_starter_kit(int(option.value), int(option.get("hero", -1)))
	elif option.kind == "hero":
		var hero := int(option.value)
		if roster.has(hero) or not has_recruitment_space() or not battle_stage._heroes.has(hero):
			return
		_recruit(hero, 4, option.get("spec", {}), option.get("rank_modifiers", {}))
	elif option.kind == "recharge":
		battle_stage.encounter.restore_rewind()
	elif option.has("delay"):
		delayed_rewards.append({"delay": option.delay, "kind": option.kind, "value": option.value})
	elif option.kind in ["item", "relic", "shards", "training"]:
		apply_event_reward(option.kind, option.value, int(option.get("hero", -1)))
	elif option.kind == "well_rank":
		shards += int(option.value)
		if int(hero_ranks[option.hero]) == 2 and not option.has("specialized_now"):
			hero_ranks[option.hero] = 3
	if option.has("extra_relic"):
		relics.append(int(option.extra_relic))
	if option.has("item"):
		items.append(int(option.item))
	if option.has("party_modifier"):
		for hero in roster:
			apply_event_reward("training", option.party_modifier, hero)
	if option.has("modifier"):
		apply_event_reward("training", option.modifier, option.hero)
	if option.has("shard_delta"):
		victory_shard_modifiers.append({"amount": int(option.shard_delta), "remaining": int(option.duration)})
	var effect := int(option.get("effect", option.value if option.kind == "effect" else -1))
	if effect >= 0:
		event_durations[effect] = maxi(int(event_durations.get(effect, 0)), int(option.duration))
		if not relics.has(effect):
			relics.append(effect)


func take_starter_kit(id: int, hero: int) -> void:
	kit_id = id
	relics.append(id)
	var rules = load("res://battle/opening_draft.gd")
	var config: Dictionary = rules.data()
	var values: Dictionary = config.descriptions[str(id)].Description
	if id == 720:
		shards += int(values["0"])
	elif id >= 725 and id <= 731:
		var item: int = rules.pick_reward("Item", [6, 14, 12, 16, 4, 8, 10][id - 725], opening_xp, _rng)
		if item >= 0:
			items.append(item)
	elif id >= 736 and id <= 742 and roster.has(hero):
		var stat := int(config.kit.stat_types[id - 736])
		kit_hero_stats.get_or_add(hero, {})[stat] = int(values["0"])


func kit_growth(unit: GuildrunBoardUnit) -> void:
	if kit_id < 757 or kit_id > 763 or visit not in [1, 2]:
		return
	var rules: Dictionary = load("res://battle/opening_draft.gd").data()
	var stat := int(rules.kit.stat_types[kit_id - 757])
	var amount := int(rules.descriptions[str(kit_id)].Description["2"])
	var id := int(unit.stat("Id")._sequentialId)
	var bonuses: Dictionary = kit_hero_stats.get_or_add(id, {})
	bonuses[stat] = int(bonuses.get(stat, 0)) + amount
	var key: String = GuildrunBoardUnit.STAT_NAMES[stat]
	unit.combat_stats[key] = int(unit.combat_stats.get(key, 0)) + amount
	if stat == 1:
		unit.max_health += amount
		unit.health += amount
		unit.set_meta("health", unit.health)


func enter_kit_floor(floor_number: int, boss: bool) -> void:
	if (floor_number >= 4 and kit_id in [723, 734]) or (boss and kit_id in [724, 771, 764, 777, 778, 779, 780, 781, 782]):
		relics.erase(kit_id)
		kit_id = 0


func combat_shards(base: int) -> int:
	if relics.has(5119):
		return 0
	var result := base
	for modifier: Dictionary in victory_shard_modifiers:
		result += int(modifier.amount)
	return maxi(0, result)


func advance_event_rewards(victory := true) -> void:
	if victory:
		for i in range(victory_shard_modifiers.size() - 1, -1, -1):
			victory_shard_modifiers[i].remaining -= 1
			if victory_shard_modifiers[i].remaining == 0:
				victory_shard_modifiers.remove_at(i)
	for relic: int in event_durations.keys():
		event_durations[relic] -= 1
		if event_durations[relic] == 0:
			relics.erase(relic)
			event_durations.erase(relic)
			if relic == 5113:
				shards += 25
	if not victory:
		return
	for i in range(delayed_rewards.size() - 1, -1, -1):
		var reward := delayed_rewards[i]
		reward.delay -= 1
		if reward.delay == 0:
			apply_event_reward(reward.kind, int(reward.value), -1)
			delayed_rewards.remove_at(i)


func _survivor_price() -> int:
	var kit_bonus := 2 if kit_id == 723 and visit in [2, 3] else int(kit_id == 724)
	return int(_data.surviving_hero_shards) + kit_bonus + int(relics.has(6009)) + (int(battle_stage.contract.survivor_delta) if battle_stage else 0)


func can_assign(index: int, hero: int, limit: int) -> bool:
	if index < 0 or index >= items.size() or equipped_to.get(index, -1) == hero:
		return false
	if hero == -1:
		return true
	if not roster.has(hero):
		return false
	return equipped_to.values().count(hero) < _equipment_limit(hero, limit)


func equipment_limit(hero: int) -> int:
	var base_limit := int(battle_stage.base_equipment_limit) if battle_stage else 0
	return _equipment_limit(hero, base_limit)


func _equipment_limit(hero: int, limit: int) -> int:
	if battle_stage and battle_stage.contract.slots_by_rank:
		limit = mini(int(hero_ranks.get(hero, 1)), int(battle_stage.max_item_slots))
	elif battle_stage and int(hero_ranks.get(hero, 1)) >= int(battle_stage.max_hero_rank):
		limit = mini(limit + 1, int(battle_stage.max_item_slots))
	if relics.has(6012):
		limit = maxi(1, limit - 1)
	if relics.has(6016):
		limit = mini(int(battle_stage.max_item_slots), limit + 2)
	if kit_id == 771:
		limit = mini(int(battle_stage.max_item_slots), limit + 1)
	return limit


func assign_item(index: int, hero: int, limit: int) -> bool:
	if not can_assign(index, hero, limit):
		return false
	if hero == -1:
		equipped_to.erase(index)
	else:
		equipped_to[index] = hero
	if battle_stage:
		battle_stage.sound.play_ui(33 if hero == -1 else 32)
	return true


func equipment(hero: int) -> Array[int]:
	var result: Array[int] = []
	for index: int in equipped_to:
		if equipped_to[index] == hero:
			result.append(items[index])
	return result


## Hero keys identify a roster member. Item keys identify one copy in the inventory.
func resale_price(kind: String, key: int) -> int:
	if battle_stage == null:
		return -1
	if kind == "Hero" and roster.has(key):
		return battle_stage.resale_price_for("heroRank", int(hero_ranks.get(key, 1)), super_shop)
	if kind == "Item" and key >= 0 and key < items.size():
		var tier := int(battle_stage.field(battle_stage.items[items[key]], "Rarity"))
		return battle_stage.resale_price_for("itemRarity", tier, super_shop)
	return -1


func sell(kind: String, key: int) -> bool:
	if not regular_stock or not _claimed or _departed or _rank_picker != null or has_pending_rank_modifier():
		return false
	var price := resale_price(kind, key)
	if price < 0:
		return false
	if kind == "Hero":
		if roster.size() <= 1:
			return false
		roster.erase(key)
		var sold_slot := reserve_slots.find(key)
		if sold_slot >= 0:
			reserve_slots[sold_slot] = -1
		if roster.size() == 1:
			var remaining_slot := reserve_slots.find(roster[0])
			if remaining_slot >= 0:
				reserve_slots[remaining_slot] = -1
		for index: int in equipped_to.keys():
			if equipped_to[index] == key:
				equipped_to.erase(index)
		rank_modifiers_by_hero.erase(str(key))
		for records: Dictionary in [hero_ranks, hero_modifiers, rank_modifiers_by_hero, specializations, permanent_stats, ability_progress]:
			records.erase(key)
		hero_sold.emit(key)
	else:
		if battle_stage.red_rift and items[key] == battle_stage.red_rift.anchor_id:
			return false
		remove_inventory_item(key)
	shards += price
	battle_stage.sound.play_ui(17)
	_refresh()
	return true


func remove_inventory_item(index: int) -> void:
	items.remove_at(index)
	var owners := {}
	for slot: int in equipped_to:
		if slot != index:
			owners[slot - 1 if slot > index else slot] = equipped_to[slot]
	equipped_to = owners


func _refresh() -> void:
	if is_instance_valid(_tax_button):
		var rift = battle_stage.red_rift
		var floor_info: Dictionary = battle_stage.floor_rules()
		var chunk := int(floor_info.chunk)
		var cost: int = rift.tax(chunk, int(rift.visits[chunk]))
		_tax_button.visible = rift.missions[rift.Mission.FIRST_KEY + chunk] == rift.Status.PENDING
		_tax_button.disabled = shards < cost
		var graphic: Control = _tax_button.get_parent()
		graphic.visible = _tax_button.visible
		var caption := tr("UI.Battle.ShopPanel.AssembleRiftKey.KeyFragment").format([cost, tr("UI.BattleInfo.Shards.Title")])
		graphic.get_node("Text (TMP)/UnityText").text = caption
		graphic.get_node("ShopLeftPanel").visible = int(floor_info.local_floor) == 4
		_tax_button.accessibility_name = caption
		_tax_button.tooltip_text = tr("UI.Battle.ShopPanel.AssembleRiftKey.Description").format([chunk + 1, rift.tax_increase[chunk], maxi(0, 4 - int(floor_info.local_floor))])
	_balance.text = "%s  %d" % [tr("UI.BattleInfo.Shards.Title"), shards]
	var groups := PackedStringArray()
	for kind: String in ["Hero", "Item", "Relic"]:
		var names := PackedStringArray()
		var inventory: Array = {"Hero": roster, "Item": items, "Relic": relics}[kind]
		for id: int in inventory:
			var caption := _entry_name(kind, id)
			if kind == "Hero" and int(hero_ranks.get(id, 1)) > 1:
				caption += " (%s %d)" % [tr("UI.RankUpAnimation").strip_edges(), int(hero_ranks[id])]
			names.append(caption)
		if not names.is_empty():
			groups.append(" · ".join(names))
	_owned.text = "     /     ".join(groups)
	if is_instance_valid(_selling):
		_selling.refresh()
	if is_instance_valid(_reroll):
		_reroll.text = tr("UI.Battle.ShopPanel.RerollShop").format([reroll_cost, tr("UI.BattleInfo.Shards.Title")])
		_reroll.disabled = shards < reroll_cost
	if is_instance_valid(_freeze):
		_freeze.text = tr("UI.Battle.ShopPanel.Unfreeze" if frozen else "UI.Battle.ShopPanel.Freeze")
	for index: int in _buttons:
		var button: Button = _buttons[index]
		button.disabled = has_pending_rank_modifier() or purchased.has(index) or shards < price_at(index)
		button.visible = not purchased.has(index)

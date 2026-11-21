extends "res://battle/translated_battle_canvas.gd"

signal card_updated(card: Control, state: Dictionary)

const NO_SLOT := Vector2i(-2, -2)

var _encounter: GuildrunEncounter
var _active_cards: Array[Control] = []
var _reserve_cards: Array[Control] = []
var _states: Dictionary[Control, Dictionary] = {}
var _last_inputs: Array = []
var _skills: GDScript = load("res://battle/bottom_roster_abilities.gd")


func bind_cards(active: Array[Control], reserve: Array[Control]) -> void:
	_active_cards = active
	_reserve_cards = reserve
	_states.clear()
	_last_inputs.clear()


func setup(encounter: GuildrunEncounter) -> void:
	_encounter = encounter
	refresh()
	set_process(true)


func _process(_delta: float) -> void:
	if is_instance_valid(_encounter):
		refresh(_encounter._selected_slot)


func refresh(selected: Vector2i = NO_SLOT) -> void:
	if not is_instance_valid(_encounter):
		hide()
		return
	var shop := _encounter.first_shop
	visible = _encounter.phase in [
		GuildrunEncounter.Phase.PLACE, GuildrunEncounter.Phase.FIGHT,
		GuildrunEncounter.Phase.RESULT, GuildrunEncounter.Phase.SHOP,
		GuildrunEncounter.Phase.CROSSROADS,
	]
	if not visible:
		return
	var stage := _encounter._stage
	var has_party := is_instance_valid(shop)
	var starter := _encounter._hero
	var starter_id := int(starter.get_meta("hero_id")) if is_instance_valid(starter) else -1
	var starter_rank := starter.rank if starter_id >= 0 else 0
	var occupants: Dictionary = _encounter._grid.occupants if _encounter.phase == GuildrunEncounter.Phase.PLACE else {}
	var inputs: Array = [
		_encounter.phase, stage.max_deployed, stage.max_total_heroes, selected,
		starter_id, starter_rank, occupants, has_party,
		stage.base_equipment_limit, stage.max_item_slots, stage.max_hero_rank, stage.contract.slots_by_rank,
	]
	if has_party:
		inputs.append_array([shop.roster, shop.reserve_slots, shop.hero_ranks, shop.items, shop.equipped_to, shop.relics, shop.kit_id,
				shop.specializations, shop.rank_modifiers_by_hero])
	if inputs == _last_inputs:
		return
	var active: Array[int] = []
	var reserve: Array[int] = []
	if is_instance_valid(shop):
		active = shop.deployed_ids()
		reserve = shop.reserve_slots
	elif is_instance_valid(_encounter._hero):
		active.append(int(_encounter._hero.get_meta("hero_id")))
		reserve.resize(maxi(0, int(_encounter._stage.max_total_heroes) - int(_encounter._stage.max_deployed)))
		reserve.fill(-1)
	_last_inputs = inputs.duplicate(true)
	_refresh_section(_active_cards, active, int(stage.max_deployed), false, selected)
	_refresh_section(_reserve_cards, reserve, reserve.size(), true, selected)


func _refresh_section(cards: Array[Control], ids: Array[int], capacity: int, reserve: bool, selected: Vector2i) -> void:
	for index in cards.size():
		var card := cards[index]
		card.visible = index < capacity
		if not card.visible:
			_states.erase(card)
			continue
		var id := ids[index] if index < ids.size() else -1
		var slot := _resolve_slot(id, index, reserve)
		var shop := _encounter.first_shop
		var equipment_capacity := 0
		if id >= 0:
			equipment_capacity = shop.equipment_limit(id) if is_instance_valid(shop) else int(_encounter._stage.base_equipment_limit)
		var specialization: Dictionary = shop.specializations.get(id, {}) if id >= 0 and is_instance_valid(shop) else {}
		var modifiers := shop.rank_modifiers_for(id) if id >= 0 and is_instance_valid(shop) else {}
		var state := {
			"skills": _skills.slots_for(id, int(specialization.get("id", -1)), modifiers),
			"index": index,
			"hero_id": id,
			"reserve": reserve,
			"slot": slot,
			"selected": slot != NO_SLOT and selected == slot,
			"rank": int(shop.hero_ranks.get(id, 0)) if is_instance_valid(shop) else (_encounter._hero.rank if id >= 0 else 0),
			"equipment": shop.equipment(id) if id >= 0 and is_instance_valid(shop) else [],
			"capacity": equipment_capacity,
		}
		if _states.get(card, {}) == state:
			continue
		_states[card] = state
		card.tooltip_text = tr("Heroes.Hero_%d.Name" % id) if id >= 0 else ""
		if card is Button:
			card.expand_icon = true
			card.icon = _encounter._stage.hero_portrait(id) if id >= 0 else null
		card_updated.emit(card, state.duplicate(true))


func _resolve_slot(id: int, index: int, reserve: bool) -> Vector2i:
	if _encounter.phase != GuildrunEncounter.Phase.PLACE:
		return NO_SLOT
	if reserve:
		return Vector2i(-1, index) if is_instance_valid(_encounter.first_shop) else NO_SLOT
	var hero := _encounter.board_hero(id)
	if is_instance_valid(hero):
		return hero.grid_cell
	if id < 0:
		return _encounter._next_free_position()
	return NO_SLOT


func slot_at(point: Vector2) -> Vector2i:
	if not is_visible_in_tree() or _encounter.phase != GuildrunEncounter.Phase.PLACE:
		return NO_SLOT
	for card in _states:
		if card.is_visible_in_tree() and card.get_global_rect().has_point(point):
			return _states[card].slot
	return NO_SLOT


func card_state(card: Control) -> Dictionary:
	return _states.get(card, {}).duplicate(true)




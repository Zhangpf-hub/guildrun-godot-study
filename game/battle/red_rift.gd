extends RefCounted

enum Mission { SKIP_BATTLE_REWARD, SKIP_CAMPFIRE, FIRST_KEY, SECOND_KEY, DEATH_LIMIT, ANCHOR }
enum Status { INACTIVE, PENDING, COMPLETE, FAILED }

const CLASS_GROUPS := [[2, 3], [4, 5, 1], [7, 6]]
const NAME_KEYS := ["SkipChallenge", "SkipCampfire", "Act1KeyFragment", "Act2KeyFragment", "HeroDeath", "RiftAnchor"]

var status := Status.PENDING
var missions: Array[int] = [1, 1, 1, 1, 1, 1]
var charges: Array[int] = [0, 0, 0]
var deaths := 0
var anchor_id: int
var target_wins: int
var death_limit: int
var tax_start: Array[int]
var tax_increase: Array[int]
var visits: Array[int] = [0, 0]
var _settled := false
var first_run: bool


func configure(settings: Dictionary, progress: ConfigFile) -> void:
	anchor_id = int(settings._anchorItemId)
	target_wins = int(settings.ChallengeWinsPerClass)
	death_limit = int(settings.ChallengeMaxHeroDeaths)
	tax_start.assign([int(settings.ChallengeShopTaxAct1StartValue), int(settings.ChallengeShopTaxAct2StartValue)])
	tax_increase.assign([int(settings.ChallengeShopTaxAct1GrowthPerShop), int(settings.ChallengeShopTaxAct2GrowthPerShop)])
	first_run = int(progress.get_value("red_rift", "runs", 0)) == 0


func complete(mission: Mission) -> void:
	_set_mission(mission, Status.COMPLETE)


func fail(mission: Mission) -> void:
	_set_mission(mission, Status.FAILED)


func _set_mission(mission: Mission, result: Status) -> void:
	if status != Status.PENDING or missions[mission] != Status.PENDING:
		return
	missions[mission] = result
	if missions.has(Status.FAILED):
		status = Status.FAILED
	elif not missions.has(Status.PENDING):
		status = Status.COMPLETE


func tax(chunk: int, visit_in_chunk: int) -> int:
	return tax_start[chunk] + (visit_in_chunk - 1) * tax_increase[chunk]


func pay_tax(party: GuildrunFirstShop, chunk: int, visit_in_chunk: int) -> bool:
	var mission := Mission.FIRST_KEY if chunk == 0 else Mission.SECOND_KEY
	var price := tax(chunk, visit_in_chunk)
	if status != Status.PENDING or missions[mission] != Status.PENDING or party.shards < price:
		return false
	party.shards -= price
	complete(mission)
	return true


func give_anchor(party: GuildrunFirstShop, starter: int) -> void:
	party.items.append(anchor_id)
	if not first_run:
		party.equipped_to[party.items.size() - 1] = starter


func carrier_id(party: GuildrunFirstShop) -> int:
	var index := party.items.find(anchor_id)
	return int(party.equipped_to.get(index, -1)) if index >= 0 else -1


func allows_deployment(party: GuildrunFirstShop, event_fight: bool) -> bool:
	return event_fight or missions[Mission.ANCHOR] != Status.PENDING or party.deployed_ids().has(carrier_id(party))


func finish_battle(party: GuildrunFirstShop, units: Array[GuildrunBoardUnit], victory: bool, event_fight: bool, final_boss: bool) -> void:
	if status != Status.PENDING:
		return
	if victory and missions[Mission.ANCHOR] == Status.PENDING:
		var owner := carrier_id(party)
		for unit in units:
			if unit.is_hero and int(unit.get_meta("hero_id")) == owner:
				_charge_anchor(unit, party)
				break
	if event_fight:
		return
	for unit in units:
		if unit.is_hero and unit.defeated:
			deaths += 1
	if deaths >= death_limit:
		fail(Mission.DEATH_LIMIT)
	if final_boss:
		complete(Mission.DEATH_LIMIT)
		for i in missions.size():
			if missions[i] == Status.PENDING:
				missions[i] = Status.FAILED
				status = Status.FAILED


func _charge_anchor(unit: GuildrunBoardUnit, party: GuildrunFirstShop) -> void:
	for i in CLASS_GROUPS.size():
		if charges[i] < target_wins and CLASS_GROUPS[i].any(func(id: int): return unit.has_class(id)):
			charges[i] += 1
			break
	if charges.min() >= target_wins:
		complete(Mission.ANCHOR)
		party.remove_inventory_item(party.items.find(anchor_id))


func save_outcome(path: String, victory: bool) -> void:
	if _settled:
		return
	var rules = load("res://battle/difficulty_rules.gd")
	var save: ConfigFile = rules.read_progress(path)
	save.set_value("red_rift", "runs", int(save.get_value("red_rift", "runs", 0)) + 1)
	var streak := int(save.get_value("red_rift", "streak", 0)) + 1 if victory else 0
	save.set_value("red_rift", "streak", streak)
	if victory:
		save.set_value("red_rift", "wins", int(save.get_value("red_rift", "wins", 0)) + 1)
		save.set_value("red_rift", "best", maxi(streak, int(save.get_value("red_rift", "best", 0))))
	var error := save.save(path)
	if error != OK:
		push_warning("Cannot save Red Rift result: %s" % error_string(error))
	else:
		_settled = true

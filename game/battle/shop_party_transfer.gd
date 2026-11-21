extends RefCounted


static func can_move(shop: GuildrunFirstShop, source: Vector2i, target: Vector2i, hero: int) -> bool:
	if source == target or source.x == 0 and target.x == 0:
		return false
	var active := shop.deployed_ids()
	var reserves := shop.reserve_slots
	if not _slot_exists(source, shop.battle_stage.max_deployed, reserves.size()):
		return false
	if not _slot_exists(target, shop.battle_stage.max_deployed, reserves.size()):
		return false
	if hero < 0 or _hero_at(source, active, reserves) != hero:
		return false
	return true


static func is_last_active_drop(shop: GuildrunFirstShop, source: Vector2i, target: Vector2i) -> bool:
	return source.x == 0 and target.x == 1 and shop.deployed_ids().size() == 1 and shop.reserve_slots[target.y] < 0


static func move(shop: GuildrunFirstShop, formation: Dictionary,
		source: Vector2i, target: Vector2i, hero: int) -> bool:
	if not can_move(shop, source, target, hero) or is_last_active_drop(shop, source, target):
		return false
	var active := shop.deployed_ids()
	var reserves := shop.reserve_slots
	var displaced := _hero_at(target, active, reserves)
	if source.x == 1:
		reserves[source.y] = displaced
	if target.x == 1:
		reserves[target.y] = hero
	if source.x != target.x:
		# The registry changes membership. The drop target is never a battle cell.
		formation.erase(hero if source.x == 0 else displaced)
	shop.battle_stage.sound.play_ui(4)
	return true


static func _slot_exists(slot: Vector2i, active_capacity: int, reserve_capacity: int) -> bool:
	return slot.y >= 0 and (slot.x == 0 and slot.y < active_capacity
			or slot.x == 1 and slot.y < reserve_capacity)


static func _hero_at(slot: Vector2i, active: Array[int], reserves: Array[int]) -> int:
	var section := active if slot.x == 0 else reserves
	return section[slot.y] if slot.y < section.size() else -1

extends RefCounted

const SLOTS_PER_COLUMN := 7

var _encounter: GuildrunEncounter


func bind(encounter: GuildrunEncounter) -> void:
	_encounter = encounter


func snapshot() -> Dictionary:
	var visible := is_instance_valid(_encounter) and _encounter.phase in [
		GuildrunEncounter.Phase.PLACE,
		GuildrunEncounter.Phase.FIGHT,
		GuildrunEncounter.Phase.RESULT,
		GuildrunEncounter.Phase.SHOP,
		GuildrunEncounter.Phase.CROSSROADS,
		GuildrunEncounter.Phase.EVENT,
		GuildrunEncounter.Phase.RELIC_REWARD,
	]
	var unequipped: Array[Dictionary] = []
	if is_instance_valid(_encounter) and is_instance_valid(_encounter.first_shop):
		var inventory := _encounter.first_shop
		for index in inventory.items.size():
			if not inventory.equipped_to.has(index):
				unequipped.append({"index": index, "item_id": inventory.items[index]})
	var columns: Array[Array] = []
	var capacity := (floori(unequipped.size() / float(SLOTS_PER_COLUMN)) + 1) * SLOTS_PER_COLUMN
	for index in capacity:
		if index % SLOTS_PER_COLUMN == 0:
			columns.append([])
		var slot := {"index": -1, "item_id": -1}
		if index < unequipped.size():
			slot = unequipped[index]
		columns.back().append(slot)
	return {"visible": visible, "count": unequipped.size(), "columns": columns}

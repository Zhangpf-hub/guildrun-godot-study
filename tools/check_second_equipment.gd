extends SceneTree


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var fight: GuildrunEncounter = stage.encounter
	fight.select_hero(4)
	fight.start_fight()
	for i in 2400:
		if fight.phase != GuildrunEncounter.Phase.FIGHT:
			break
		fight._physics_process(1.0 / 30.0)
	fight.open_first_shop()
	var shop := fight.first_shop
	if not shop.buy(2) or not shop.buy(3) or not shop.buy(5):
		push_error("Could not purchase Kai, gem and assassin medal")
		quit(1)
		return
	shop.leave()
	fight.crossroads.select_path(0)
	fight.crossroads.claim()
	fight.crossroads.get_node("Body/Event/Content/Continue").pressed.emit()
	var yuuna: GuildrunBoardUnit = fight._hero
	var kai: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 0)]
	var panel: GuildrunEquipmentPanel = fight._equipment_panel
	var kai_base: int = stage.field(stage._heroes[26], "Crit")
	if yuuna.stat("Crit") != 65 or kai.stat("Crit") != kai_base:
		push_error("Class medal granted incorrect stats")
		quit(1)
		return
	panel.get_child(0).get_child(1).pressed.emit()
	panel.get_child(1).get_child(0).pressed.emit()
	if shop.equipment(4) != [119] or yuuna.stat("Crit") != 80:
		push_error("Item click did not equip the gem")
		quit(1)
		return
	var payload := {"inventory": panel.get_instance_id(), "index": 0}
	panel._drop(Vector2.ZERO, payload, 26)
	if yuuna.stat("Crit") != 65 or kai.stat("Crit") != kai_base + 15 or shop.items.size() != 1:
		push_error("Transfer duplicated or lost an item effect")
		quit(1)
		return
	panel._drop(Vector2.ZERO, payload, -1)
	if kai.stat("Crit") != kai_base or not shop.equipment(26).is_empty():
		push_error("Returning the gem did not reverse its effects")
		quit(1)
		return
	# Three equal item IDs are distinct inventory instances and occupy three slots.
	shop.items.append_array([119, 119, 119])
	for index in 3:
		if not shop.assign_item(index, 4, stage.base_equipment_limit):
			push_error("Could not equip valid item instance")
			quit(1)
			return
	if shop.assign_item(3, 4, stage.base_equipment_limit) or shop.equipment(4).size() != 3:
		push_error("Starting item capacity mismatch")
		quit(1)
		return
	var stat: Dictionary = stage.hero_stats(26, [], [114], [1000, 1006])
	if stage.field(stat, "MaxHealth") != 975 or stage.field(stat, "Magic") != 12 or stage.field(stat, "Attack") != 50:
		push_error("Multiple stat item or warrior medal mismatch")
		quit(1)
		return
	var mage: Dictionary = stage.hero_stats(14, [], [], [1006])
	if stage.field(mage, "Magic") != 50:
		push_error("Mage medal mismatch")
		quit(1)
		return
	print("Verified all three class medals, two-stat item, equip/transfer/remove and three-slot limit")
	stage.free()
	quit()

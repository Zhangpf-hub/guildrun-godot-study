extends RefCounted


static func index_controls(root: Control) -> Dictionary[int, Control]:
	var by_id: Dictionary[int, Control] = {}
	for child: Control in root.find_children("*", "Control", true, false):
		if child.has_meta("unity_id"):
			by_id[int(child.get_meta("unity_id"))] = child
	return by_id


static func show_item(by_id: Dictionary[int, Control], slot: Dictionary, item: int, stage: Node) -> void:
	var occupied := item >= 0
	by_id[int(slot._emptySlotParent)].visible = not occupied
	by_id[int(slot._activeSlotParent)].visible = occupied
	by_id[int(slot._hoveringSlotParent)].hide()
	by_id[int(slot._activeNameText)].hide()
	by_id[int(slot._frameImage)].visible = occupied
	if occupied:
		var image := by_id[int(slot._activeSlotImage)].get_node("UnityImage") as TextureRect
		image.texture = GuildrunEquipmentPanel.item_texture(stage, item)

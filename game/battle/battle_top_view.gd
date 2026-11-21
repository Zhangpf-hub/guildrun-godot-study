extends "res://battle/translated_battle_canvas.gd"

const PANEL := "Canvas/Root/CoreGameUI/TopUIPanel/ChunkUIPanel"
const CLOCK := "TimerPanel/ResolutionPhasePanel"

var encounter: GuildrunEncounter
var panel: Control
var route: Array[Dictionary] = []
var assets: Dictionary
var starting_shards: int
var chunk := -2
var _last_local := -2
var _last_phase := -1


func bind(value: GuildrunEncounter) -> void:
	encounter = value
	panel = get_node(PANEL)
	assets = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/battle_top.json"))
	starting_shards = int(load("res://battle/opening_draft.gd").data().starting_shards) if value._stage.normal_opening else int(JSON.parse_string(FileAccess.get_file_as_string("res://balancing/first_shop.json")).starting_shards)
	fit_source_canvas($Canvas)
	refresh()


func _process(_delta: float) -> void:
	if is_instance_valid(encounter):
		refresh()


func refresh() -> void:
	var stage = encounter._stage
	var rules: Dictionary = stage.floor_rules()
	var endless := int(stage.endless_floor)
	visible = encounter.phase != GuildrunEncounter.Phase.END_SCREEN and (not rules.is_empty() or endless >= 0)
	if not visible:
		return
	var index := -1 if endless >= 0 else int(rules.chunk)
	var local := endless if endless >= 0 else int(rules.local_floor)
	if index != chunk:
		chunk = index
		_rebuild()
		_last_local = -2
	if local != _last_local or _last_phase != encounter.phase:
		_last_local = local
		_last_phase = encounter.phase
		_color_route(local)
		panel.get_node(CLOCK).visible = encounter.phase != GuildrunEncounter.Phase.PICK
		panel.get_node("ActsPanelView/EndlessIndicatorHolder/ActText/UnityText").text = str(endless + 1)
	var shards := starting_shards if encounter.first_shop == null else encounter.combat_shard_balance()
	var wallet := panel.get_node("Middle/Left_Shard/CurrentGoldAmount/UnityText") as Label
	var stabilizer := panel.get_node("Middle/Right_RiftStabilizer/AccumulatedShardsText/UnityText") as Label
	if wallet.text != str(shards) or stabilizer.text != str(encounter.rewind_reserve):
		wallet.text = str(shards)
		stabilizer.text = str(encounter.rewind_reserve)
		_fit_currencies(wallet, stabilizer)
	panel.get_node("Middle/Right_RiftStabilizer").visible = chunk >= 0
	var seconds := encounter.battle_time_q16 >> 16
	panel.get_node(CLOCK + "/TimerText/UnityText").text = "%02d:%02d" % [(seconds / 60) % 60, seconds % 60]


func _fit_currencies(wallet: Label, stabilizer: Label) -> void:
	var left := panel.get_node("Middle/Left_Shard") as Control
	var right := panel.get_node("Middle/Right_RiftStabilizer") as Control
	var pad: Vector4 = left.get_meta("layout_padding")
	var wallet_width := maxf(wallet.get_parent().get_meta("min_width"), wallet.get_minimum_size().x)
	left.offset_left = left.offset_right - maxf(left.get_meta("min_width"), pad.x + wallet_width + pad.z)
	_place(wallet.get_parent(), pad.x, (left.size.y + pad.y - pad.w) / 2, wallet_width)
	pad = right.get_meta("layout_padding")
	var amount_width := maxf(stabilizer.get_parent().get_meta("min_width"), stabilizer.get_minimum_size().x)
	var icon := right.get_node("StabilizerIcon") as Control
	var icon_width := float(icon.get_meta("preferred_width"))
	right.offset_right = right.offset_left + maxf(right.get_meta("min_width"), pad.x + amount_width + icon_width + pad.z)
	_place(stabilizer.get_parent(), pad.x, (right.size.y + pad.y - pad.w) / 2, amount_width)
	_place(icon, pad.x + amount_width, (right.size.y + pad.y - pad.w) / 2, icon_width)


func _place(slot: Control, x: float, center_y: float, width: float) -> void:
	var height := slot.size.y
	slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	slot.position = Vector2(x, center_y - height / 2)
	slot.size = Vector2(width, height)


func _event_kind(floor_index: int, data: Dictionary) -> String:
	if int(data.event_override) == 1:
		return ""
	if int(data.event_override) == 3 or encounter._stage._trial_roads.has(floor_index):
		return "fightEvent"
	match int(data.road_id):
		23, 113: return "mining"
		50, 53: return "campfire"
	return "event"


func _rebuild() -> void:
	for entry in route:
		entry.slot.free()
	route.clear()
	var stage = encounter._stage
	if chunk >= 0:
		for i in stage._act_floors.size():
			var floor_data: Dictionary = stage._act_floors[i]
			if int(floor_data.chunk) != chunk:
				continue
			var local := int(floor_data.local_floor)
			var final_floor: bool = i == stage._act_floors.size() - 1
			var boss: bool = final_floor or int(stage._act_floors[i + 1].chunk) != chunk
			var icon := ("actBoss" if final_floor else "miniBoss") if boss else "fight"
			_add_slot("boss" if boss else "fight", icon, 2 * local)
			if not boss:
				_add_slot("connector", "", 2 * local)
			var event_kind := _event_kind(i, floor_data)
			if not event_kind.is_empty():
				_add_slot("large", event_kind, 2 * local + 1)
				_add_slot("connector", "", 2 * local + 1)
		if chunk < int(stage._act_floors.back().chunk):
			_add_slot("dots", "", 999)
			_add_slot("large", "actBoss", 999)
	var pad: Vector4 = panel.get_meta("layout_padding")
	var x := pad.x
	var center_y := (panel.size.y + pad.y - pad.w) / 2.0
	for entry in route:
		var slot: Control = entry.slot
		var width := float(slot.get_meta("preferred_width"))
		_place(slot, x, center_y, width)
		x += width
	var acts := panel.get_node("ActsPanelView") as Control
	var act_width := float(acts.get_meta("preferred_width"))
	var holder := acts.get_node("EndlessIndicatorHolder") as Control
	holder.get_node("EndlessIndicator").visible = chunk < 0
	holder.get_node("ActText").visible = chunk < 0
	acts.visible = chunk < 0
	if chunk < 0:
		_place(acts, x, center_y, act_width)
		_place(holder.get_node("EndlessIndicator"), 0, acts.size.y / 2, 20)
		_place(holder.get_node("ActText"), 24, acts.size.y / 2, 21)
		x += act_width
	var width := x + pad.z
	panel.offset_left = -width / 2
	panel.offset_right = width / 2


func _add_slot(kind: String, icon: String, order: int) -> void:
	var wrapper := (load(assets.templates[kind]) as PackedScene).instantiate()
	var slot := wrapper.get_child(0) as Control
	wrapper.remove_child(slot)
	wrapper.free()
	panel.add_child(slot, true)
	var image: TextureRect
	if not icon.is_empty():
		image = slot.get_node("FightIcon/UnityImage" if kind == "fight" else "UnityImage")
		image.texture = load(assets.icons[icon])
	else:
		image = slot.get_child(0).get_node("UnityImage")
	route.append({"slot": slot, "image": image, "icon": icon, "kind": kind, "order": order})


func _color_route(local: int) -> void:
	var at_road := encounter.phase in [GuildrunEncounter.Phase.CROSSROADS, GuildrunEncounter.Phase.EVENT]
	var cursor := 2 * local + int(at_road)
	for entry in route:
		var order := int(entry.order)
		var state := "future"
		if order < cursor:
			state = "past"
		elif order == cursor:
			state = "current"
		elif order == cursor + 1 and not at_road:
			state = "next"
		if entry.kind == "boss" and state in ["next", "future"]:
			state = "bossNext" if state == "next" else "bossFuture"
		var slot: Control = entry.slot
		var tint := Color.from_string(assets.colors[state], Color.WHITE)
		entry.image.self_modulate = tint
		var marker := slot.get_node_or_null("CurrentMarker") as Control
		if marker:
			marker.visible = order == cursor
			marker.modulate = tint

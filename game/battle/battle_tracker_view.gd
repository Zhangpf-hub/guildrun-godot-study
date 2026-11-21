extends "res://battle/translated_battle_canvas.gd"

const PANEL := "Canvas/Root/CoreGameUI/InformationSideBar/DamageTrackerPanel/MainPanel"
const PORTRAIT := "HeroPortrait/HeroRoundPortrait_Small/Image/HeroRoundPortrait/UnityImage"
const KEYS := ["UI.Battle.DamageDealt", "UI.Battle.DamageTaken", "UI.Battle.ShieldsHealing"]
const MODES := ["AttackButton", "DefenseButton", "HealButton"]
const FIELDS := GuildrunBattleStatistics.DISPLAY_FIELDS

var encounter: GuildrunEncounter
var mode := 0
var _rows: Array[Control] = []
var _portraits: Dictionary = {}
var _last_frame := -1
var _last_phase := -1


func bind(value: GuildrunEncounter) -> void:
	encounter = value
	var panel := get_node(PANEL) as Control
	var buttons := panel.get_node("ButtonsHolder") as Control
	var padding: Vector4 = buttons.get_meta("layout_padding")
	var spacing: float = buttons.get_meta("layout_spacing")
	var width := (panel.size.x - padding.x - padding.z - 2 * spacing) / 3.0
	for i in MODES.size():
		var slot := buttons.get_node(MODES[i]) as Control
		slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		slot.position = Vector2(padding.x + (width + spacing) * i, padding.y)
		slot.size = Vector2(width, buttons.size.y - padding.y)
		var action := Button.new()
		action.name = "SelectMode"
		action.flat = true
		action.accessibility_name = tr(KEYS[i])
		slot.add_child(action)
		action.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		action.pressed.connect(select_mode.bind(i))
	var holder := panel.get_node("TrackerViewHolder") as Control
	for row: Control in holder.get_children():
		if row.name.begins_with("HeroTrackerView"):
			_rows.append(row)
			row.get_node("HeroPortrait/HeroRoundPortrait_Small/StarHolder").hide()
			row.get_node("HeroPortrait/RankImage").hide()
		else:
			row.hide()
	fit_source_canvas($Canvas)
	select_mode(0)


func select_mode(index: int) -> void:
	mode = index
	var panel := get_node(PANEL) as Control
	panel.get_node("TitlePanel/Title/TitleText/UnityText").text = tr(KEYS[mode])
	for i in MODES.size():
		panel.get_node("ButtonsHolder/" + str(MODES[i]) + "/EnabledIcon").visible = i == mode
	refresh()


func _process(_delta: float) -> void:
	if not is_instance_valid(encounter):
		return
	if encounter.phase == GuildrunEncounter.Phase.PLACE or encounter.phase != _last_phase or encounter._frame != _last_frame:
		refresh()


func refresh() -> void:
	_last_phase = encounter.phase
	_last_frame = encounter._frame
	visible = encounter.phase in [GuildrunEncounter.Phase.PLACE, GuildrunEncounter.Phase.FIGHT, GuildrunEncounter.Phase.RESULT]
	if not visible:
		return
	var entries: Array[Dictionary] = []
	for unit in encounter._units:
		if not is_instance_valid(unit) or not unit.is_hero:
			continue
		var entry: Dictionary = {}
		if encounter.phase == GuildrunEncounter.Phase.FIGHT and encounter.battle_statistics != null:
			entry = encounter.battle_statistics.units.get(unit.get_instance_id(), {})
		elif encounter.phase == GuildrunEncounter.Phase.RESULT:
			entry = encounter.last_battle_statistics.get("units", {}).get(unit.get_instance_id(), {})
		var amounts: Array[int] = []
		var total := 0
		for field: String in FIELDS[mode]:
			var amount := int(entry.get(field, 0))
			amounts.append(amount)
			total += amount
		entries.append({"id": int(unit.get_meta("hero_id")), "amounts": amounts, "total": total})
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return a.total > b.total)
	var maximum := maxi(1, int(entries.front().total)) if not entries.is_empty() else 1
	var panel := get_node(PANEL) as Control
	var holder := panel.get_node("TrackerViewHolder") as Control
	var inner: Vector4 = panel.get_meta("layout_padding")
	var padding: Vector4 = holder.get_meta("layout_padding")
	var spacing: float = holder.get_meta("layout_spacing")
	var slots := mini(_rows.size(), encounter._stage.max_deployed)
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	holder.position = Vector2(inner.x, padding.y)
	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < slots
		if not row.visible:
			continue
		var height := 60.0 if row.size.y <= 0 else row.size.y
		row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		row.position = Vector2(0, (height + spacing) * i)
		row.size = Vector2(panel.size.x - inner.x - inner.z, height)
		var present := i < entries.size()
		row.get_node("DamageNumber").visible = present
		row.get_node("DamagePanel").visible = present
		row.get_node("RelicView").hide()
		var portrait := row.get_node(PORTRAIT) as TextureRect
		if not present:
			portrait.texture = null
			continue
		var entry := entries[i]
		var id := int(entry.id)
		if not _portraits.has(id):
			_portraits[id] = encounter._stage.hero_portrait(id)
		portrait.texture = _portraits[id]
		row.get_node("DamageNumber/UnityText").text = str(entry.total)
		var cursor := 0.0
		for n in 8:
			var slider := row.get_node("DamagePanel/Slider_%d" % (n + 1)) as Control
			var amount := int(entry.amounts[n]) if n < entry.amounts.size() else 0
			slider.visible = amount > 0
			if slider.visible:
				var fill := slider.get_node("Fill Area/Fill") as Control
				fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				fill.anchor_left = cursor
				cursor += amount / float(maximum)
				fill.anchor_right = cursor
				fill.get_node("UnityImage").color = GuildrunBattleStatistics.DISPLAY_COLORS[mode][n]
	panel.size.y = padding.y + slots * (60 + spacing) + padding.w + inner.w

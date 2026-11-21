extends "res://battle/translated_battle_canvas.gd"

const STATS := "Panel/BattleStatsPanel"
const REWARDS := "Panel/RewardsPanel"
const SWITCH := STATS + "/TitlePanel/SwitchHolder"
const VERSUS := STATS + "/TitlePanel/BottomPanel/VersusPortraits"
const TRACKER := STATS + "/DetailStatsPanel/DamageTrackerSummary/DamageTrackerHolder"
const PORTRAIT := "PortraitPic/Image/HeroRoundPortrait/UnityImage"
const DAMAGE_ICON := "HeroDamageIndicator/DamageIcon/UnityImage"
const BANISHED_ICON := preload("res://sprites/resources_903.png")
const SHARD_ICON := "res://sprites/resources_971.png"
const FIELDS := GuildrunBattleStatistics.DISPLAY_FIELDS
const HERO_STATS := ["MaxHealth", "Attack", "Magic", "Defense"]
# OnEnable delays StartBattleResultSequence by 0.02; an empty tracker waits 0.5.
const ENTRANCE_DELAY := 0.02
const EMPTY_TRACKER_DURATION := 0.5

var title: Label
var proceed_slot: Control
var proceed_text: Label
var reward_target: Control
var _encounter: GuildrunEncounter
var _template: Control
var _hero_portraits: Control
var _enemy_portraits: Control
var _desaturated_portrait: ShaderMaterial
var _reward_scene: PackedScene = load("res://UI/battle_text_reward.tscn")
var _transition: Tween
var _entrance: Dictionary
var _hero_details: VBoxContainer
var _track: Control
var _rewards: Control
var _proceed_outline: Control


func bind(encounter: GuildrunEncounter) -> void:
	_encounter = encounter
	_entrance = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/result_entrance.json"))
	title = get_node("Panel/TitlePanel/TitleText/UnityText")
	proceed_slot = get_node(REWARDS + "/ButtonContainer/ProceedButton")
	proceed_text = proceed_slot.get_node("Text (TMP)/UnityText")
	_track = get_node(TRACKER)
	_template = _track.get_child(0)
	_template.hide()
	_rewards = get_node(REWARDS + "/Scroll_Rewards/Viewport/Content")
	_proceed_outline = proceed_slot.get_node("HighlightUI_Proceed") as Control
	_bind_outline(_proceed_outline)
	var named_labels := {
		STATS + "/TitlePanel/StatsTitleText": "UI.Battle.ResultPanel.Stats.Title",
		SWITCH + "/TrackerButton/Text (TMP)": "UI.Battle.ResultPanel.Stats.Tracker",
		SWITCH + "/HeroStatsButton/Text (TMP)": "UI.Battle.ResultPanel.Stats.HeroStats",
		REWARDS + "/ResultTitleText": "UI.Battle.ResultPanel.Results",
		REWARDS + "/TotalEarnedRewardView/RewardTitle": "UI.Battle.ResultPanel.TotalEarned",
	}
	for path: String in named_labels:
		get_node(path + "/UnityText").text = tr(named_labels[path])
	var stats_section := get_node(STATS) as Control
	var rewards_section := get_node(REWARDS) as Control
	place(stats_section, Rect2(0, 0, 1000, 654))
	place(rewards_section, Rect2(1012, 0, 388, 654))
	place(get_node(REWARDS + "/ResultTitleText"), Rect2(30, 24, 326, 30))
	place(get_node(REWARDS + "/Scroll_Rewards"), Rect2(30, 78, 328, 348))
	get_node(REWARDS + "/Scroll_Rewards/Viewport").offset_right = 0
	place(get_node(REWARDS + "/Line"), Rect2(30, 450, 328, 2))
	place(get_node(REWARDS + "/TotalEarnedRewardView"), Rect2(30, 476, 328, 34))
	place(proceed_slot, Rect2(6, 10, 280, 68))
	_hero_portraits = get_node(VERSUS + "/PortraitsRow_Heroes")
	_hero_portraits.get_child(0).hide()
	_enemy_portraits = get_node(VERSUS + "/PortraitsRow_Enemies")
	_enemy_portraits.get_child(0).hide()
	_desaturated_portrait = ShaderMaterial.new()
	_desaturated_portrait.shader = load("res://materials/ui_portrait_desaturated.gdshader")
	_hero_details = VBoxContainer.new()
	_hero_details.add_theme_constant_override("separation", 12)
	_track.get_parent().add_child(_hero_details)
	_hero_details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 2:
		var slot: Control = get_node(SWITCH + ("/TrackerButton" if i == 0 else "/HeroStatsButton"))
		var button := Button.new()
		bind_hit_area(button, slot, slot.get_node("Text (TMP)/UnityText").text)
		button.pressed.connect(_select_hero_stats.bind(i == 1))
	fit_source_canvas(self)
	hide()


func present(snapshot: Dictionary, rewards: Array[Dictionary], victory: bool, animate: bool) -> void:
	if _transition != null:
		_transition.kill()
	modulate.a = 1.0
	get_node("DefeatBackground").visible = not victory
	_set_durations(snapshot)
	_fill_units(snapshot.get("units", {}))
	_fill_rewards(rewards)
	set_proceed_highlight(false)
	_select_hero_stats(false)
	_play_entrance(animate)
	show()


func _set_durations(snapshot: Dictionary) -> void:
	var duration := String.num(float(snapshot.get("elapsed_q16", 0)) / 65536.0, 1)
	get_node(STATS + "/TitlePanel/BottomPanel/CombatDurationText/UnityText").text = \
			tr("UI.Battle.ResultPanel.FightDuration").replace("\\n", "\n").format([duration]).replace("{duration}", duration)
	var total := get_node(STATS + "/TitlePanel/TotalDurationText") as Control
	total.visible = int(snapshot.get("battle_count", 0)) > 1
	if total.visible:
		var elapsed := float(snapshot.run_elapsed_q16) / 65536.0
		var minutes := floori(elapsed / 60.0)
		var seconds := String.num(elapsed - minutes * 60.0, 1)
		var key := "RunDuration" if minutes > 0 else "RunDurationShort"
		var args := [minutes, seconds] if minutes > 0 else [seconds]
		var template := tr("UI.Battle.ResultPanel." + key)
		if template.is_empty() or template.begins_with("UI.Battle.ResultPanel."):
			template = "Run Duration\n{0} m {1} s" if minutes > 0 else "Run Duration\n{0} s"
		total.get_node("UnityText").text = template.replace("\\n", "\n").format(args)


func _play_entrance(animate: bool) -> void:
	_transition = create_tween().set_parallel(true) if animate else null
	if animate:
		modulate.a = 0.0
		_transition.tween_property(self, ^"modulate:a", 1.0, _entrance.canvas_fade_duration) \
				.set_delay(_entrance.canvas_fade_delay)
	_apply_entrance_tracks(self, _entrance.stats.tracks, ENTRANCE_DELAY)
	var tracker_start: float = ENTRANCE_DELAY + float(_entrance.stats.duration)
	var stagger: float = _entrance.tracker_stagger
	var row_count := _track.get_child_count() - 1
	for i in row_count:
		_apply_entrance_tracks(_track.get_child(i + 1) as Control, _entrance.tracker.tracks, tracker_start + i * stagger)
	var tracker_duration: float = EMPTY_TRACKER_DURATION
	if row_count > 0:
		tracker_duration = float(_entrance.tracker.duration) + (row_count - 1) * stagger
	var rewards_start: float = tracker_start + tracker_duration + float(_entrance.reward_delay)
	_apply_entrance_tracks(self, _entrance.rewards.tracks, rewards_start)


func _apply_entrance_tracks(root: Control, tracks: Array, phase_start: float) -> void:
	for track: Dictionary in tracks:
		var target := root.get_node(NodePath(track.path)) as Control
		var property := NodePath(track.property)
		if _transition == null:
			target.set_indexed(property, float(track.to))
			continue
		target.set_indexed(property, float(track.from))
		var animation := _transition.tween_property(target, property, float(track.to), float(track.duration))
		animation.from(float(track.from)).set_delay(phase_start + float(track.start))
		if not track.linear:
			animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fill_units(entries: Dictionary) -> void:
	_clear_generated(_hero_portraits, _hero_portraits.get_child(0))
	_clear_generated(_enemy_portraits, _enemy_portraits.get_child(0))
	_clear_generated(_track, _template)
	_clear_generated(_hero_details)
	var largest := 1
	for entry: Dictionary in entries.values():
		if entry.ally:
			for mode in FIELDS.size():
				largest = maxi(largest, GuildrunBattleStatistics.total(entry, mode))
	var side_counts: Array[int] = [0, 0]
	for id: int in entries:
		var entry: Dictionary = entries[id]
		var side := 0 if entry.ally else 1
		if side_counts[side] < 6:
			var portraits := _hero_portraits if entry.ally else _enemy_portraits
			var icon := portraits.get_child(0).duplicate() as Control
			portraits.add_child(icon)
			var x := 248 - 54 * side_counts[0] if entry.ally else 54 * side_counts[1]
			place(icon, Rect2(x, 0, 42, 42))
			_set_portrait(icon, entry)
			if not entry.ally and entry.get("defeated", false):
				icon.get_node(PORTRAIT).material = _desaturated_portrait
				icon.get_node(DAMAGE_ICON).texture = BANISHED_ICON
				icon.get_node("HeroDamageIndicator").show()
			icon.show()
			side_counts[side] += 1
		if not entry.ally:
			continue
		var row := _template.duplicate() as Control
		_track.add_child(row)
		place(row, Rect2(0, -8 + (_track.get_child_count() - 2) * 56, 904, 56))
		_set_portrait(row.get_node("HeroRoundIconSmall"), entry)
		var holder := row.get_node("DamageSlidersHolder") as Control
		holder.clip_contents = true
		for mode in FIELDS.size():
			var meter := holder.get_node("DamageSliders_%d" % (mode + 1)) as Control
			meter.get_node("DamageNumber/UnityText").text = str(GuildrunBattleStatistics.total(entry, mode))
			var cursor := 0.0
			for i in 8:
				var slider := meter.get_node("Slider_%d" % (i + 1)) as Control
				var value := int(entry[FIELDS[mode][i]]) if i < FIELDS[mode].size() else 0
				slider.visible = value > 0
				if slider.visible:
					var fill := slider.get_node("Fill Area/Fill") as Control
					fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
					fill.anchor_left = cursor
					cursor += float(value) / largest
					fill.anchor_right = cursor
					fill.get_node("UnityImage").color = GuildrunBattleStatistics.DISPLAY_COLORS[mode][i]
		row.show()
	for unit: GuildrunBoardUnit in _encounter._units:
		if unit.is_hero and entries.has(unit.get_instance_id()):
			var attributes := PackedStringArray()
			for field: String in HERO_STATS:
				attributes.append("%s  %d" % [tr("UI.Stat.%s.Title" % field), int(unit.stat(field))])
			var detail := Label.new()
			detail.text = "%s     %s" % [entries[unit.get_instance_id()].label, "     ".join(attributes)]
			detail.add_theme_font_size_override("font_size", 20)
			_hero_details.add_child(detail)


func _fill_rewards(rewards: Array[Dictionary]) -> void:
	var viewport := _rewards.get_parent() as Control
	viewport.clip_contents = true
	_clear_generated(_rewards)
	reward_target = null
	var total := 0
	for i in rewards.size():
		var reward := rewards[i]
		var wrapper := _reward_scene.instantiate() as Control
		_rewards.add_child(wrapper)
		place(wrapper, Rect2(0, 6 + 42 * i, 328, 34))
		var row: Control = wrapper.get_node("ResultShardRewardView")
		place(row, Rect2(0, 0, 328, 34))
		var label := row.get_node("RewardTitle/UnityText") as Label
		place(label.get_parent(), Rect2(16, 0, 240 if reward.has("amount") else 298, 34))
		label.text = reward.title
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var amount := row.get_node("ShardValueText/UnityText") as Label
		place(amount.get_parent(), Rect2(218, 0, 94, 34))
		_bind_outline(row.get_node("HighlightUI") as Control)
		if reward.has("explanation"):
			row.mouse_filter = Control.MOUSE_FILTER_PASS
			row.tooltip_text = reward.explanation
		if reward.has("amount"):
			_set_shards(amount, int(reward.amount))
			total += int(reward.amount)
		else:
			amount.hide()
		if reward_target == null:
			reward_target = row
	var total_slot := get_node(REWARDS + "/TotalEarnedRewardView") as Control
	total_slot.visible = rewards.any(func(reward: Dictionary) -> bool: return reward.has("amount"))
	_set_shards(total_slot.get_node("ShardValueText/UnityText"), total)


func set_reward_highlight(active: bool) -> void:
	if is_instance_valid(reward_target):
		reward_target.get_node("HighlightUI").visible = active
		# Unity lifts the tutorial reward above the scroll mask while explaining shards.
		var viewport := _rewards.get_parent() as Control
		viewport.clip_contents = not active


func set_proceed_highlight(active: bool) -> void:
	_proceed_outline.visible = active


func _bind_outline(holder: Control) -> void:
	var shader := load("res://UI/tutorial_blinking_edge.gdshader") as Shader
	var images: Array[ColorRect] = [holder.get_node("UnityImage"), holder.get_node("Highlight_Rotating/UnityImage")]
	for index in images.size():
		var image := images[index]
		var shading := ShaderMaterial.new()
		shading.shader = shader
		shading.set_shader_parameter(&"rotating", index == 1)
		image.material = shading
		var update_size := func() -> void:
			shading.set_shader_parameter(&"rect_size", image.size)
		image.resized.connect(update_size)
		update_size.call()
	holder.hide()


func _set_shards(label: Label, amount: int) -> void:
	label.text = str(amount)
	var icon := label.get_node_or_null("Shard") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "Shard"
		icon.texture = load(SHARD_ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_child(icon)
	var width := label.get_theme_font("font").get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	icon.offset_left = -width - 30.0
	icon.offset_right = -width - 3.0
	icon.offset_top = 1.0
	icon.offset_bottom = 33.0


func _select_hero_stats(active: bool) -> void:
	_track.visible = not active
	_hero_details.visible = active
	get_node(SWITCH + "/HeroStatsButton/EnabledGraphic").visible = active
	get_node(SWITCH + "/HeroStatsButton/Background").hide()
	get_node(SWITCH + "/TrackerButton/EnabledGraphic").visible = not active


func _set_portrait(icon: Control, entry: Dictionary) -> void:
	var image := icon.get_node(PORTRAIT) as TextureRect
	image.texture = load(entry.portrait) if not entry.portrait.is_empty() else null
	icon.tooltip_text = entry.label
	icon.mouse_filter = Control.MOUSE_FILTER_PASS


func _clear_generated(parent: Control, template: Control = null) -> void:
	for child in parent.get_children():
		if child != template:
			parent.remove_child(child)
			child.queue_free()


func place(control: Control, rect: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size

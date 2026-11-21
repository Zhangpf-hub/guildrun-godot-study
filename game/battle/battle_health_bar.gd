extends Control

const ITEM_VIEW := preload("res://battle/party_item_view.gd")

static var _settings: Dictionary
static var _prefab: PackedScene
static var _shader: Shader

var _health_fill: ShaderMaterial
var _text_panel: Control
var _text: Label
var _mana_panel: Control
var _mana_fill: ColorRect
var _equipment_rows: Control
var _equipment_nodes: Dictionary[int, Control] = {}
var _socket: Vector3
var _has_socket := false
var _last_health := -1
var _damage_from := 1.0
var _damage_fill := 1.0
var _damage_left := 0.0
var _death_elapsed := 0.0


func setup(unit: GuildrunBoardUnit) -> void:
	if _settings.is_empty():
		_settings = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/battle_health_bars.json"))
		_prefab = load("res://UI/battle_health_bar.tscn")
		_shader = load("res://UI/battle_health_fill.gdshader")
	var scene := _prefab.instantiate() as Control
	scene.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(scene)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visual_id := str(int(unit.stat("VisualConfig").m_PathID))
	var slot: Dictionary = _settings.sockets.get(visual_id, {})
	_has_socket = not slot.is_empty()
	if _has_socket:
		_socket = Vector3(slot.position[0], slot.position[1], slot.position[2])
	var bar: Control = scene.get_node("HealthBar")
	if unit.is_hero:
		_equipment_nodes = ITEM_VIEW.index_controls(bar.get_node("TopBar"))
		_equipment_rows = _equipment_nodes[int(_settings.equipment_parent)]
	else:
		_equipment_rows = bar.get_node("TopBar/HeroItemRows")
	_equipment_rows.hide()
	var image: ColorRect = bar.get_node("HealthBarImage/UnityImage")
	var colors: Dictionary = _settings.colors
	var side := "player" if unit.is_hero else "enemy"
	_health_fill = ShaderMaterial.new()
	_health_fill.shader = _shader
	image.material = _health_fill
	_health_fill.set_shader_parameter("primary", _color(colors[side + "PrimaryColor"]))
	_health_fill.set_shader_parameter("secondary", _color(colors[side + "SecondaryColor"]))
	_health_fill.set_shader_parameter("shield", _color(colors[side + "ShieldColor"]))
	_health_fill.set_shader_parameter("background", _color(colors.background))
	_health_fill.set_shader_parameter("separator", _color(colors.separator))
	_health_fill.set_shader_parameter("width", image.size.x)
	_health_fill.set_shader_parameter("minor_thickness", float(_settings.minor_thickness))
	_health_fill.set_shader_parameter("major_thickness", float(_settings.major_thickness))
	_text_panel = bar.get_node("HealthText")
	_text = _text_panel.get_node("UnityText")
	_mana_panel = bar.get_node("ManaBackgroundImage")
	_mana_fill = _mana_panel.get_node("ManaSlider/PrimeryFillImage/UnityImage")
	var fill_rect: Control = _mana_fill.get_parent()
	fill_rect.anchor_top = 0.0
	fill_rect.anchor_bottom = 1.0
	hide()



func set_equipment(stage: Node3D, shop: GuildrunFirstShop, panel: GuildrunEquipmentPanel, hero_id: int) -> void:
	var capacity: int = shop.equipment_limit(hero_id) if is_instance_valid(shop) else stage.base_equipment_limit
	var item_indices: Array[int] = []
	if is_instance_valid(shop):
		for index: int in shop.equipped_to:
			if int(shop.equipped_to[index]) == hero_id:
				item_indices.append(index)
	for index in _settings.equipment_slots.size():
		var binding: Dictionary = _settings.equipment_slots[index]
		var slot := _equipment_nodes[int(binding.root)]
		slot.visible = index < capacity
		if not slot.visible:
			continue
		var item_index := item_indices[index] if index < item_indices.size() else -1
		var item := int(shop.items[item_index]) if item_index >= 0 else -1
		ITEM_VIEW.show_item(_equipment_nodes, binding, item, stage)
		if is_instance_valid(panel):
			_bind_equipment_hit(slot, panel, hero_id, item_index)
	_layout_equipment_rows()


func _layout_equipment_rows() -> void:
	# Unity TopBar bottom padding is 6, with 2 units between equipment rows.
	var top_bar := _equipment_rows.get_parent() as Control
	_equipment_rows.position = Vector2((top_bar.size.x - _equipment_rows.size.x) * 0.5, top_bar.size.y - 6.0)
	var bottom := 0.0
	for row: Control in _equipment_rows.get_children():
		var width := 0.0
		for slot: Control in row.get_children():
			if slot.visible:
				width += slot.size.x
		row.visible = width > 0.0
		if not row.visible:
			continue
		row.position = Vector2((_equipment_rows.size.x - row.size.x) * 0.5, bottom - row.size.y)
		bottom -= row.size.y + 2.0
		var x := (row.size.x - width) * 0.5
		for slot: Control in row.get_children():
			if slot.visible:
				slot.position = Vector2(x, (row.size.y - slot.size.y) * 0.5)
				x += slot.size.x


func _bind_equipment_hit(slot: Control, panel: GuildrunEquipmentPanel, hero_id: int, item_index: int) -> void:
	var hit := slot.get_node_or_null("InventoryHit") as Button
	if hit == null:
		hit = Button.new()
		hit.name = "InventoryHit"
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		slot.add_child(hit)
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(func() -> void:
			var index := int(hit.get_meta("item_index", -1))
			if index >= 0:
				panel.select_item(index)
			else:
				panel.assign_selected_item(hero_id))
	hit.set_meta("item_index", item_index)
	hit.set_drag_forwarding(
			func(point: Vector2) -> Variant: return panel.item_drag_data(point, item_index, hit),
			panel.can_drop_item.bind(hero_id), panel.drop_item.bind(hero_id))


func update_unit(unit: GuildrunBoardUnit, camera: Camera3D, show_bar: bool, preparation: bool, delta: float) -> void:
	if unit.defeated:
		_death_elapsed += delta
	else:
		_death_elapsed = 0.0
	var point := unit.to_global(_socket) + unit.get_parent_node_3d().global_basis * unit.visual_offset
	visible = show_bar and _has_socket and _death_elapsed < float(_settings.death_delay) and not camera.is_position_behind(point)
	if not visible:
		return
	var dimensions := camera.get_viewport().get_visible_rect().size
	var reference := Vector2(_settings.reference[0], _settings.reference[1])
	var ratio := dimensions / reference
	var ui_scale := pow(2.0, lerpf(log(ratio.x) / log(2.0), log(ratio.y) / log(2.0), float(_settings.scale_match)))
	scale = Vector2.ONE * ui_scale
	position = camera.unproject_position(point) - Vector2(0.0, float(_settings.offset) * ui_scale)
	z_index = clampi(-roundi(camera.to_local(unit.global_position).length() * 10.0), -4096, 0)
	var shield := unit.total_shield()
	var total := maxi(1, unit.max_health + shield)
	var health := float(unit.health) / total
	if _last_health >= 0 and _last_health != unit.health:
		_damage_from = _damage_fill
		_damage_left = float(_settings.damage_duration)
	_last_health = unit.health
	_damage_left = maxf(0.0, _damage_left - delta)
	_damage_fill = lerpf(health, _damage_from, _damage_left / float(_settings.damage_duration))
	_health_fill.set_shader_parameter("health_fill", health)
	_health_fill.set_shader_parameter("damage_fill", _damage_fill)
	_health_fill.set_shader_parameter("shield_fill", float(unit.health + shield) / total)
	var divisions := float(total) / float(_settings.health_per_divider)
	_health_fill.set_shader_parameter("minor_divisions", divisions)
	_health_fill.set_shader_parameter("major_divisions", divisions / float(_settings.minor_dividers_per_major))
	_equipment_rows.visible = preparation and unit.is_hero
	_text_panel.visible = preparation
	if preparation:
		_text.text = str(unit.health if _settings.health_value_current_only else unit.max_health)
	var max_mana := int(unit.stat("MaxMana"))
	_mana_panel.visible = max_mana > 0 and not unit.ability_kind.is_empty()
	if _mana_panel.visible:
		_mana_fill.get_parent().anchor_right = clampf(float(unit.mana) / max_mana, 0.0, 1.0)
		_mana_fill.color = _color(_settings.colors.abilityReadyManaBarColor if unit.mana >= max_mana else _settings.colors.defaultManaBarColor)


func _color(values: Array) -> Color:
	return Color(values[0], values[1], values[2], values[3])

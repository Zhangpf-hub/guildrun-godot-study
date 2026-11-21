extends Node3D
## Rebuilds a board from the same stage and enemy rows used by the demo.
## In the inspector, set stage_id to a StageSheetHolder sequential ID.

@export var stage_id: int = 10000
## Enable for an explicit F6 preview of the first-fight tutorial.
@export var show_first_fight_tutorial := false
@export_range(0, 6) var contract_index := 0
var contract = load("res://battle/difficulty_rules.gd").new()
var track_contract_progress := false
var challenge_run := false
var red_rift: RefCounted
var show_founding_comic := false
var contract_progress_path := "user://forest_contracts.cfg"
var normal_opening := false
var run_seed: Variant

# RelicEffectsProvider.PopulateCommon, build 26551710. Values are class, stat and flat bonus.
const CLASS_MEDALS := {
	1000: {"hero_class": 1, "stat": 6, "amount": 25},
	1003: {"hero_class": 4, "stat": 11, "amount": 15},
	1006: {"hero_class": 7, "stat": 7, "amount": 25},
}

var board_size: Vector2i
var grid: GuildrunBattleGrid
var mana_per_attack: int
var mana_regen_interval_q16: int
var burn_interval_q16: int
var burn_damage_per_stack: int
var frost_interval_q16: int
var poison_interval_q16: int
var poison_damage_per_stack: int
var frost_reductions := {}
var storm_rules: Dictionary
var target_class_priority: Array[int] = []
var combat_end_delay: float
var victory_resurrect_delay: float
var max_deployed: int
var max_total_heroes: int
var second_battle_reward: int
var rewind_starting_shards: int
var rewind_shards_per_win: int
var stage: Dictionary
var _act_floors: Array[Dictionary] = []
var _trial_roads: Dictionary = {}
var _route_stage: Dictionary = {}
var last_miniboss_group: String = ""
var _stages: Dictionary
var endless_floor := -1
var endless_maps: Array[int] = []
var _enemy_scalings := {}
var _enemies: Dictionary
var _heroes: Dictionary
var _small_portraits := {}
var items: Dictionary
var resale_prices := {}
var _super_shop_resale_prices := {}
var base_equipment_limit: int
var max_hero_rank: int
var max_item_slots: int
var ability_item_pools: Array[int] = []
var _stat_modifiers: Dictionary
var _animation_timings: Dictionary
var _abilities: Dictionary
var _active_stall_durations := {}
var _aoe_radii: Dictionary
var _aoe_shapes := {}
var _characters: Dictionary
var _rigs: Dictionary
var _environment_paths: Dictionary
var encounter: GuildrunEncounter
var battle_camera: Node
var _panel_focus: CameraAttributesPractical
var _panel_dof: CompositorEffect
var _hdr_postprocess: CompositorEffect
var _panel_grade_active := false
var _defeat_grade_active := false
var _gate_nodes: Array[Node] = []
var _environment: Node3D
var sound := preload("res://audio/guildrun_audio.gd").new()


func _ready() -> void:
	if RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]:
		_panel_focus = CameraAttributesPractical.new()
		# Battle and shop Volume 65264: focus falloff starts at 10 and reaches full blur at 25.
		_panel_focus.dof_blur_far_distance = 10.0
		_panel_focus.dof_blur_far_transition = 15.0
		_panel_focus.dof_blur_amount = 0.03
		($Battle/GameMainCamera/UnityCamera as Camera3D).attributes = _panel_focus
	add_child(sound)
	var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balancing/sharedassets1.json"))
	for record: Dictionary in records.records:
		if record.type == "StageSheetHolder":
			_stages = _index_rows(record.fields.Entries)
			for id: int in _stages:
				if field(_stages[id], "StageType") == 50 and not field(_stages[id], "DisabledInGame"):
					endless_maps.append(id)
		elif record.type == "EnemyScalingSheetHolder":
			for row: Dictionary in record.fields.Entries:
				_enemy_scalings[int(row._targetEnemyId)] = field(row, "StatScalingList")
		elif record.type == "ActEntry" and record.fields.Title == "Act1Entry":
			var chunks: Array = record.fields.ActChunks
			var trial_limit := int(record.fields._fightCrossroadsPerRun)
			var eligible_trials := 0
			for chunk: Dictionary in chunks:
				for floor_node: Dictionary in field(chunk, "FloorNodes"):
					if int(floor_node._fightCrossroadsId) >= 0:
						eligible_trials += 1
			var trial_chance := int(record.fields._fightCrossroadsChance.RawValue)
			for index in chunks.size():
				var floors: Array = field(chunks[index], "FloorNodes")
				for local_floor in floors.size():
					var floor_node: Dictionary = floors[local_floor]
					var trial_road := int(floor_node._fightCrossroadsId)
					if trial_road >= 0:
						if trial_limit > 0 and (eligible_trials <= trial_limit or randi_range(0, 65535) < trial_chance):
							_trial_roads[_act_floors.size()] = trial_road
							trial_limit -= 1
						eligible_trials -= 1
					_act_floors.append({"chunk": index, "local_floor": local_floor,
							"final_boss": index == chunks.size() - 1 and local_floor == floors.size() - 1,
							"before_final_boss": index == chunks.size() - 1 and local_floor == floors.size() - 2,
							"road_id": int(floor_node._crossroadsId), "event_override": int(field(floor_node, "EventOverrideType"))})
		elif record.type == "EnemySheetHolder":
			_enemies = _index_rows(record.fields.Entries)
		elif record.type == "HeroSheetHolder":
			_heroes = _index_rows(record.fields.Entries)
		elif record.type == "HeroesSingleton":
			mana_per_attack = int(record.fields.ManaGeneratedPerAttack)
			max_deployed = int(record.fields.StartingMaxHeroesOnBoard)
			max_total_heroes = int(record.fields.MaxTotalHeroes)
			max_hero_rank = int(record.fields.MaxHeroRank)
			max_item_slots = int(record.fields.MaxItemSlots)
			for pool: Dictionary in record.fields.FionaItemPoolPerRank:
				ability_item_pools.append(int(pool._itemPoolId))
		elif record.type == "StatModSheetHolder":
			_stat_modifiers = _index_rows(record.fields.Entries)
		elif record.type == "ItemSheetHolder":
			items = _index_rows(record.fields.Entries)
		elif record.type == "ShopSingleton":
			_load_resale_prices(record.fields)
		elif record.type == "EquipmentSingleton":
			base_equipment_limit = int(record.fields.BaseCharacterEquipmentLimit)
		elif record.type == "PlayerSingleton":
			rewind_starting_shards = int(record.fields.StartingAccumulatedShards)
			rewind_shards_per_win = int(record.fields.AccumulatedShardsPerFightWon)
		elif record.type == "TutorialSingleton":
			second_battle_reward = int(record.fields.SecondBattleRewardOverride)
		elif record.type == "BattleSingleton":
			target_class_priority.assign(record.fields._classResistancePriority)
			combat_end_delay = float(record.fields.EndOfCombatDelay.RawValue) / 65536.0
			victory_resurrect_delay = float(record.fields.PostCombatVictoryResurrectDelay)
			storm_rules = {
				"start_q16": int(record.fields.SecondsUntilStormStart.RawValue),
				"escalation_q16": int(record.fields.SecondsUntilExponentialStorm.RawValue),
				"interval_q16": int(record.fields.DamageInterval.RawValue),
				"initial_damage": int(record.fields.DamagePerInterval),
				"increment": int(record.fields.DamageIncreasePerInterval),
				"multiplier_q16": int(record.fields.ExponentialIncreasePerInterval.RawValue),
			}
		elif record.type == "StatusSingleton":
			mana_regen_interval_q16 = int(record.fields.GlobalManaRegenInterval.RawValue)
			burn_interval_q16 = int(record.fields.BurnDamageInterval.RawValue)
			burn_damage_per_stack = int(record.fields.BurnDamagePerStack)
			frost_interval_q16 = int(record.fields.FrostDissipationInterval.RawValue)
			poison_interval_q16 = int(record.fields.PoisonDamageInterval.RawValue)
			poison_damage_per_stack = int(record.fields.PoisonDamagePerStack)
			frost_reductions = {"AttackSpeed": int(record.fields.FrostAttackSpeedReductionPerStack.RawValue),
					"Defense": int(record.fields.FrostDefenseReductionPerStack.RawValue)}
		elif record.type == "ActiveAbilitySheetHolder":
			var area_effects: GDScript = load("res://battle/area_ability_effects.gd")
			var references := {}
			for reference: Dictionary in record.fields.references.RefIds:
				references[str(reference.rid)] = reference
			for row: Dictionary in record.fields.Entries:
				var actions: Array = field(row, "AbilityActions")
				var ability_id := int(field(row, "Id")._sequentialId)
				_active_stall_durations[ability_id] = int(field(row, "StallDuration").RawValue)
				if actions.size() > 1:
					var sequence := {}
					for entry: Dictionary in actions:
						var step: Dictionary = references[str(entry.rid)]
						sequence[step.type["class"]] = step.data
					if ability_id == 20104:
						var anger := {}
						for entry: Dictionary in actions:
							var block: Dictionary = references[entry.rid].data._effectBlocks[0]
							anger.delay = int(field(block, "Delay").RawValue)
							var effect: Dictionary = references[field(block, "Effects")[0].rid].data
							var action: Dictionary = references[effect._actions[0].rid]
							anger[action.type["class"]] = action.data
						_abilities[ability_id] = {"kind": "demon_anger", "data": anger}
					elif sequence.keys() == ["DelayAbilityAction", "AyakaDamageAction", "SetTargetAbilityAction", "VisuallyMoveToTargetAbilityAction", "AyakaMoveBehindTargetAbilityAction"]:
						_abilities[ability_id] = {"kind": "shadow_strike", "data": sequence}
					elif sequence.keys() == ["SkornShieldTauntAction", "SkornShieldDamageAction"]:
						_abilities[ability_id] = {"kind": "skorn_taunt",
								"data": {"taunt": sequence.SkornShieldTauntAction, "strike": sequence.SkornShieldDamageAction}}
					elif sequence.keys() == ["SlimeAction", "MeleeAbilityAction"]:
						var slime: Dictionary = sequence.MeleeAbilityAction.duplicate()
						slime.cleanse = sequence.SlimeAction
						_abilities[ability_id] = {"kind": "slime_strike", "data": slime}
					elif sequence.keys() == ["LizardInFrontOfTargetAbilityAction", "MeleeAbilityAction"]:
						var lizard: Dictionary = sequence.MeleeAbilityAction.duplicate()
						lizard.jump = sequence.LizardInFrontOfTargetAbilityAction
						_abilities[ability_id] = {"kind": "lizard_strike", "data": lizard}
					elif sequence.keys() == ["DelayAbilityAction", "HookFurthestEnemyAbilityAction", "MeleeAbilityAction"]:
						var hook: Dictionary = sequence.MeleeAbilityAction.duplicate()
						hook._delay = sequence.DelayAbilityAction._delay
						hook.drag_speed = int(sequence.HookFurthestEnemyAbilityAction._dragSpeed.RawValue)
						_abilities[ability_id] = {"kind": "hook_strike", "data": hook}
				if actions.size() == 1:
					var action: Dictionary = references.get(str(actions[0].rid), {})
					if action.is_empty():
						continue
					match action.type["class"]:
						"FloeriaAbilityAction", "GustavAbilityAction", "PimentaAbilityAction":
							var data: Dictionary = action.data.duplicate()
							data.area_pulse = area_effects.read_pulse(data._regularEffects, references)
							var timed_refs: Array = data.get("_stallEffects", data.get("_pepperSprayEffects", []))
							data.stall_pulse = area_effects.read_pulse(timed_refs, references)
							var pulse: Dictionary = references[data._regularEffects[0].rid].data
							data.interval = int(field(pulse, "EffectInterval").RawValue)
							data.stall_since = 15 << 16 if ability_id == 22 else int(field(row, "StallDuration").RawValue)
							_abilities[ability_id] = {"kind": action.type["class"], "data": data}
						"EffectAbilityAction":
							if ability_id in [5, 23]:
								var block: Dictionary = action.data._effectBlocks[0]
								var effect: Dictionary = references[field(block, "Effects")[0].rid].data
								var data := {"delay": int(field(block, "Delay").RawValue)}
								for pointer: Dictionary in effect._actions:
									var effect_action: Dictionary = references[pointer.rid]
									data[effect_action.type["class"]] = effect_action.data
								_abilities[ability_id] = {"kind": "petrification" if ability_id == 5 else "permafrost", "data": data}
						"SeraphaelAbilityAction", "LoganAbilityAction", "AreaOfEffectAction", "SnakeAction", "RookAction":
							var data: Dictionary = action.data.duplicate()
							data.statuses = []
							var effects: Array = data.get("_regularEffects", data.get("_effects", []))
							for effect_ref: Dictionary in effects:
								var effect: Dictionary = references[effect_ref.rid].data
								data.interval = int(field(effect, "EffectInterval").RawValue)
								for entry: Dictionary in effect._actions:
									var hit: Dictionary = references[entry.rid]
									match hit.type["class"]:
										"DealCritableDamageWithScalingAction": data.strike = hit.data
										"ApplyStatusFromOwnerStatAction": data.statuses.append(hit.data)
										"ApplyStatusFromOwnerStatPercentAction": data.percent_status = hit.data
										"ApplyStatusFlatFromStatWithBaseAction": data.flat_status = hit.data
										"ApplyStatusWithDurationAction": data.stun_duration = int(hit.data.Duration.RawValue)
										"ApplyShieldFromStatAction": data.self_shield = hit.data
							if data.has("strike") and int(data.interval) > 0:
								_abilities[ability_id] = {"kind": action.type["class"], "data": data}
						"JosephinaAction":
							var data: Dictionary = action.data.duplicate()
							data.stall_duration = int(field(row, "StallDuration").RawValue)
							_abilities[ability_id] = {"kind": action.type["class"], "data": data}
						"MeleeAbilityAction", "SnipeAbilityAction", "SkeletonSmashAction", "ReynaAction", "DragomirAction", "RatnaAbilityAction", "SpiderEnsnareAction", "HydraAction", "ForestGolemAction", "FionaAction", "HoyoungAbilityAction", "NiklasAction", "JavrynAction":
							_abilities[ability_id] = {"kind": action.type["class"], "data": action.data}
						"FunkeAbilityAction":
							_abilities[ability_id] = {"kind": "wildfire", "data": action.data}
						"JoeAbilityAction":
							var data: Dictionary = action.data.duplicate()
							var effect: Dictionary = references[data._regularEffects[0].rid].data
							data.interval = int(field(effect, "EffectInterval").RawValue)
							for entry: Dictionary in effect._actions:
								var hit: Dictionary = references[entry.rid]
								match hit.type["class"]:
									"DealCritableDamageWithScalingAction": data.strike = hit.data
									"KaiDealDamageAction": data.shield_factor = int(hit.data._percentShieldDamage.RawValue)
							_abilities[ability_id] = {"kind": "resolute_strike", "data": data}
		elif record.type == "AoeEntry":
			var shapes: Array = []
			for shape: Dictionary in record.fields.get("references", {}).get("RefIds", []):
				var data: Dictionary = shape.data
				match shape.type["class"]:
					"CircleCollisor":
						var center: Dictionary = field(data, "Center")
						shapes.append({"center": _shape_point(center), "radius": float(data.Radius.RawValue) / 65536.0})
						_aoe_radii.get_or_add(int(record.id), int(data.Radius.RawValue))
					"RectCollisor":
						var polygon := PackedVector2Array()
						for corner: String in ["P1", "P2", "P3", "P4"]:
							polygon.append(_shape_point(data[corner]))
						shapes.append({"polygon": polygon})
			_aoe_shapes[int(record.id)] = shapes
		elif record.type == "CharacterVisualConfig":
			_small_portraits[int(record.id)] = "res://sprites/sharedassets1_%d.png" % int(record.fields.SmallPortraitSprite.m_PathID)
			_animation_timings[str(int(record.id))] = record.fields.AnimationSettings
			sound.visual_audio[int(record.id)] = record.fields.AudioSettings
		elif record.type == "AudioSingleton":
			for mapping: Dictionary in record.fields._sfxMappings:
				if not String(mapping.FmodEvent.Path).is_empty():
					sound.ui_paths[int(mapping.SfxType)] = mapping.FmodEvent.Path
	_characters = JSON.parse_string(FileAccess.get_file_as_string("res://Characters/index.json"))
	_rigs = JSON.parse_string(FileAccess.get_file_as_string("res://Characters/rigs.json"))
	_index_environments("res://Scenes/Stage_Environment/")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stage="):
			stage_id = argument.trim_prefix("--stage=").to_int()
		elif argument == "--first-fight-tutorial":
			show_first_fight_tutorial = true
		elif argument.begins_with("--run-seed="):
			run_seed = argument.trim_prefix("--run-seed=").to_int()
	contract.setup(contract_index)
	if challenge_run:
		red_rift = load("res://battle/red_rift.gd").new()
		red_rift.configure(contract.data().red_rift, contract.read_progress(contract_progress_path))
	if track_contract_progress:
		normal_opening = load("res://battle/opening_draft.gd").past_tutorial(contract.read_progress(contract_progress_path))
	if not contract.boss_map.is_empty():
		var chunk_bosses := {}
		for id: int in contract.boss_map:
			var chunk: int = _act_floors[int(field(_stages[id], "FloorNumber"))].chunk
			if not chunk_bosses.has(chunk):
				chunk_bosses[chunk] = []
			chunk_bosses[chunk].append(id)
		for chunk: int in chunk_bosses:
			contract.planned_bosses[chunk] = chunk_bosses[chunk].pick_random()
	if load_board(stage_id) and stage_id == 10000:
		battle_camera = load("res://battle/battle_camera.gd").new()
		add_child(battle_camera)
		battle_camera.setup($Battle/GameMainCamera/UnityCamera, $Battle/BattleCameraController)
		encounter = GuildrunEncounter.new()
		add_child(encounter)
		encounter.setup(self)


func load_board(id: int) -> bool:
	if not _stages.has(id):
		push_error("Stage ID %s is absent from the demo build." % id)
		return false
	var next_stage: Dictionary = _stages[id]
	var environment_name: String = field(next_stage, "EnvironmentSceneName")
	if not _environment_paths.has(environment_name):
		push_error("Missing environment " + environment_name)
		return false
	for child in $Battle/BattleGrid.get_children():
		if child is GuildrunBoardUnit:
			child.free()
	_panel_dof = null
	_hdr_postprocess = null
	_defeat_grade_active = false
	if is_instance_valid(_environment):
		_environment.free()
	if int(field(next_stage, "StageType")) == 10 and not stage.is_empty() and int(field(stage, "StageType")) != 10:
		_route_stage = stage
	stage_id = id
	stage = next_stage
	if int(field(stage, "StageType")) != 10:
		_route_stage = {}
		contract.enter_floor(int(floor_rules().get("chunk", -1)), int(field(stage, "StageType")) in [2, 3], endless_floor >= 0)
	board_size = Vector2i(field(stage, "Width"), field(stage, "Height"))
	grid = GuildrunBattleGrid.new(board_size)
	_environment = (load(_environment_paths[environment_name]) as PackedScene).instantiate()
	add_child(_environment)
	var volume_path := "res://materials/volumes/%s.tscn" % environment_name
	if ResourceLoader.exists(volume_path):
		var volume := (load(volume_path) as PackedScene).instantiate()
		_environment.add_child(volume)
		_mount_battle_postprocessing(volume)
	set_panel_grade(_panel_grade_active)
	_gate_nodes = _environment.find_children("*", "Node3D").filter(
			func(node: Node): return node.has_meta("unity_crossroads_gate"))
	_gate_nodes.sort_custom(func(left: Node3D, right: Node3D): return left.global_position.x < right.global_position.x)
	var camera := $Battle/GameMainCamera/UnityCamera as Camera3D
	camera.make_current()
	sound.set_board(field(stage, "BiomeBgmName"), field(stage, "BiomeBgmVariation"), environment_name, camera)
	for deployment: Dictionary in field(stage, "EnemyPlacements"):
		_spawn_enemy(deployment)
	return true


func _mount_battle_postprocessing(volume: Node) -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_rendering_device() == null:
		return
	var world := volume.get_node("WorldEffects") as WorldEnvironment
	var effects: Array[CompositorEffect] = []
	var dof_code := _postprocess_shader("battle_panel_dof")
	if dof_code != null:
		_panel_dof = load("res://materials/battle_panel_dof.gd").new()
		_panel_dof.configure(dof_code)
		effects.append(_panel_dof)

	# URP applies bloom, vignette, exposure and the LDR lookup before screen output.
	var bloom_code := _postprocess_shader("battle_bloom")
	if bloom_code != null:
		var grade := volume.get_node("ColorGrade") as ColorRect
		var material := grade.material as ShaderMaterial
		var bloom: CompositorEffect = load("res://materials/battle_bloom.gd").new()
		bloom.configure(bloom_code, volume.get_meta("bloom_filter", Vector4.ZERO),
				volume.get_meta("bloom_strength", Vector4.ZERO), volume.get_meta("bloom_quality", Vector3i.ZERO))
		bloom.configure_hdr_grade(material)
		effects.append(bloom)
		if world.environment.glow_enabled:
			world.environment = world.environment.duplicate() as Environment
			world.environment.glow_enabled = false
		_hdr_postprocess = bloom
		grade.hide()
	var ambient := _environment_ambient_occlusion(volume)
	if ambient != null:
		world.environment = world.environment.duplicate() as Environment
		world.environment.ssao_enabled = false
		effects.push_front(ambient)
	if not effects.is_empty():
		world.compositor = Compositor.new()
		world.compositor.compositor_effects = effects


func _environment_ambient_occlusion(volume: Node) -> CompositorEffect:
	var settings: Vector4 = volume.get_meta("ambient_occlusion", Vector4.ZERO)
	if settings.w <= 0.0:
		return null
	var code := _postprocess_shader("battle_ambient_occlusion")
	var noise_path := "res://materials/battle_ambient_noise.png"
	if code == null or not ResourceLoader.exists(noise_path):
		return null
	var noise := load(noise_path) as Texture2D
	if noise == null:
		return null
	var ambient: CompositorEffect = load("res://materials/battle_ambient_occlusion.gd").new()
	ambient.configure(code, noise, settings)
	var receivers: Dictionary[ShaderMaterial, ShaderMaterial] = {}
	for geometry: MeshInstance3D in _environment.find_children("*", "MeshInstance3D", true, false):
		if geometry.material_override != null:
			var override := _ambient_receiver(geometry.material_override, receivers, ambient)
			if override != null:
				geometry.material_override = override
			continue
		if geometry.mesh == null:
			continue
		for surface in geometry.mesh.get_surface_count():
			var receiver := _ambient_receiver(geometry.get_active_material(surface), receivers, ambient)
			if receiver != null:
				geometry.set_surface_override_material(surface, receiver)
	return ambient if not receivers.is_empty() else null


func _ambient_receiver(source: Material, receivers: Dictionary[ShaderMaterial, ShaderMaterial],
		ambient: CompositorEffect) -> ShaderMaterial:
	var material := source as ShaderMaterial
	if material == null or material.shader == null \
			or not material.shader.resource_path.begins_with("res://materials/environment_plane_cutout"):
		return null
	if not receivers.has(material):
		var receiver := material.duplicate() as ShaderMaterial
		ambient.bind_receiver(receiver)
		receivers[material] = receiver
	return receivers[material]


func _postprocess_shader(name: String) -> RDShaderSPIRV:
	var path := "res://materials/%s.glsl" % name
	if not ResourceLoader.exists(path):
		return null
	var shader := load(path) as RDShaderFile
	var code := shader.get_spirv() if shader != null else null
	return code if code != null and not code.bytecode_compute.is_empty() else null


func set_defeat_grade(active: bool) -> void:
	_defeat_grade_active = active
	if is_instance_valid(_environment):
		var grade := _environment.get_node_or_null("BattleVolume/ColorGrade") as ColorRect
		if grade != null:
			_update_grade_strip(grade.material as ShaderMaterial)


func _update_grade_strip(material: ShaderMaterial) -> void:
	var strip := int(_panel_grade_active) + 2 * int(_defeat_grade_active)
	material.set_shader_parameter("grade_strip", strip)
	if _hdr_postprocess != null:
		_hdr_postprocess.set_grade_strip(strip)


func set_panel_grade(active: bool) -> void:
	_panel_grade_active = active
	if _panel_dof != null:
		_panel_dof.enabled = active
	if _panel_focus != null:
		_panel_focus.dof_blur_far_enabled = active and _panel_dof == null
	if not is_instance_valid(_environment):
		return
	var grade := _environment.get_node_or_null("BattleVolume/ColorGrade") as ColorRect
	if grade != null:
		var material := grade.material as ShaderMaterial
		_update_grade_strip(material)
		var canvas_blur := active and _panel_focus == null and _panel_dof == null
		material.set_shader_parameter("result_blur", 2.5 if canvas_blur else 0.0)


func advance_endless() -> bool:
	if endless_maps.is_empty():
		return false
	endless_floor += 1
	if load_board(endless_maps[endless_floor % endless_maps.size()]):
		return true
	endless_floor -= 1
	return false


@warning_ignore("integer_division")
func endless_cycle() -> int:
	return maxi(0, endless_floor) / endless_maps.size()


func _current_route_stage() -> Dictionary:
	return stage if _route_stage.is_empty() else _route_stage


func set_crossroads_gate_icons(path_icons: Array[Texture2D] = []) -> void:
	set_crossroads_gate_hover(-1)
	var gates := _crossroads_gates()
	for index in gates.size():
		var gate: Node3D = gates[index]
		gate.visible = index < path_icons.size()
		if not gate.visible:
			continue
		var sprite := gate.get_node_or_null("Graphics/Icon/UnitySprite") as Sprite3D
		if sprite == null:
			continue
		var icon := path_icons[index]
		sprite.visible = icon != null
		if icon != null and sprite.texture != null:
			var old_extent := maxf(sprite.texture.get_width(), sprite.texture.get_height())
			var icon_extent := maxf(icon.get_width(), icon.get_height())
			sprite.pixel_size *= old_extent / maxf(1.0, icon_extent)
			sprite.texture = icon


func crossroads_gate_screen_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return rects
	for node in _crossroads_gates():
		var gate: Node3D = node
		if not gate.visible or not gate.has_meta("gate_hit_radius"):
			continue
		var center := gate.to_global(gate.get_meta("gate_hit_center"))
		if camera.is_position_behind(center):
			continue
		var scale_axes := gate.global_basis.get_scale().abs()
		var radius: float = gate.get_meta("gate_hit_radius") * maxf(scale_axes.x, maxf(scale_axes.y, scale_axes.z))
		var screen_center := camera.unproject_position(center)
		var horizontal := camera.unproject_position(center + camera.global_basis.x * radius) - screen_center
		var vertical := camera.unproject_position(center + camera.global_basis.y * radius) - screen_center
		var half_size := Vector2(horizontal.length(), vertical.length())
		rects.append(Rect2(screen_center - half_size, half_size * 2.0))
	return rects


func crossroads_gate_label_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return rects
	for gate in _crossroads_gates():
		if not gate.visible:
			continue
		var title := gate.get_node_or_null("Graphics/Title") as Node3D
		if title == null:
			return []
		# Unity's source Title RectTransform is 8 by 1 with an anchored Y of 3.56.
		var center := title.to_global(Vector3(0.0, 3.56, 0.0))
		var low := camera.unproject_position(center - camera.global_basis.x * 4.0 + camera.global_basis.y * 0.5)
		var high := camera.unproject_position(center + camera.global_basis.x * 4.0 - camera.global_basis.y * 0.5)
		rects.append(Rect2(low, high - low))
	return rects


func set_crossroads_gate_hover(path_index: int) -> void:
	var gates := _crossroads_gates()
	for index in gates.size():
		var gate: Node3D = gates[index]
		var hovered: bool = gate.visible and index == path_index
		var feedback := gate.get_node_or_null("VFX_Hover") as Node3D
		if feedback != null:
			feedback.visible = hovered
		var sprite := gate.get_node_or_null("Graphics/Icon/UnitySprite") as Sprite3D
		if sprite:
			# GateIconView's serialized normal and hover colors across all 30 imported gates.
			sprite.modulate = Color(0.99034953, 1.0, 0.0) if hovered else Color.WHITE


func _crossroads_gates() -> Array[Node]:
	return _gate_nodes


func crossroads_gate_position(index: int) -> Vector3:
	if index >= 0 and index < _gate_nodes.size():
		return _gate_nodes[index].global_position
	return $Battle/BattleCameraController/PortalSpawnPoint.global_position


func trial_road_id() -> int:
	var route := _current_route_stage()
	if endless_floor >= 0 or route.is_empty() or int(field(route, "ActNumber")) != 1:
		return -1
	return int(_trial_roads.get(int(field(route, "FloorNumber")), -1))


func trial_map(event_id: int) -> int:
	var route := _current_route_stage()
	if route.is_empty():
		return -1
	var route_floor := int(field(route, "FloorNumber"))
	var group: String = {1032: "1v1Fight", 1033: "SurvivalFight", 1034: "DealDamageFight", 1035: "HydraFight"}.get(event_id, "")
	if event_id == 1035 and last_miniboss_group == "Hydra":
		group = "DemonFight"
	var mapped_floors: Dictionary = {
		1032: {3: 4, 6: 7, 9: 9},
		1033: {3: 4, 6: 8},
		1034: {3: 5, 6: 9},
	}
	var floor_index := int(mapped_floors.get(event_id, {}).get(route_floor, route_floor))
	var difficulty := int(contract.stage_index) + 90
	for id: int in _stages:
		var row: Dictionary = _stages[id]
		if field(row, "StageType") == 10 and not field(row, "DisabledInGame") and field(row, "GroupName") == group and (event_id == 1035 or field(row, "FloorNumber") == floor_index) and field(row, "DifficultyIndex") == difficulty:
			return id
	return -1


func _load_resale_prices(source: Dictionary) -> void:
	var super_fields := {
		"heroRank": "_superShopHeroRankResaleMultipliers",
		"itemRarity": "_superShopItemRarityResaleMultipliers",
	}
	var fallback := int(source.FallbackSellMultiplier.RawValue)
	for category: String in super_fields:
		var multipliers := {}
		for row: Dictionary in source["_" + category + "ResaleMultipliers"]:
			multipliers[int(field(row, "Element"))] = int(field(row, "Multiplier").RawValue)
		var costs := {}
		var ordinary := {}
		for row: Dictionary in source["_" + category + "Costs"]:
			var tier := int(field(row, "Element"))
			var cost := int(field(row, "Value"))
			costs[tier] = cost
			ordinary[tier] = (cost * int(multipliers.get(tier, fallback))) >> 16
		resale_prices[category] = ordinary
		var prices_by_chunk := {}
		for row: Dictionary in source[super_fields[category]]:
			var tier := int(field(row, "Element"))
			if costs.has(tier):
				var chunk := int(field(row, "ChunkIndex"))
				var prices: Dictionary = prices_by_chunk.get_or_add(chunk, {})
				prices[tier] = (int(costs[tier]) * int(field(row, "Multiplier").RawValue)) >> 16
		_super_shop_resale_prices[category] = prices_by_chunk


func resale_price_for(category: String, tier: int, special: bool) -> int:
	var ordinary := int(resale_prices.get(category, {}).get(tier, -1))
	if not special:
		return ordinary
	var prices: Dictionary = _super_shop_resale_prices.get(category, {})
	var chunk := int(floor_rules().get("chunk", 0))
	return int(prices.get(chunk, {}).get(tier, prices.get(0, {}).get(tier, ordinary)))


func floor_rules() -> Dictionary:
	var route := _current_route_stage()
	if route.is_empty():
		return {}
	var floor_index := int(field(route, "FloorNumber"))
	if int(field(route, "ActNumber")) == 1 and floor_index >= 0 and floor_index < _act_floors.size():
		return _act_floors[floor_index]
	return {}


func next_floor_candidates() -> Array[int]:
	var ids: Array[int] = []
	var route := _current_route_stage()
	if route.is_empty():
		return ids
	var schedule: int = contract.stage_index if int(field(route, "FloorNumber")) == 0 else int(field(route, "DifficultyIndex"))
	for id: int in _stages:
		var row: Dictionary = _stages[id]
		if field(row, "DisabledInGame") or field(row, "ActNumber") != field(route, "ActNumber"):
			continue
		if field(row, "DifficultyIndex") == schedule and field(row, "FloorNumber") == int(field(route, "FloorNumber")) + 1:
			if not contract.planned_bosses.is_empty() and int(field(row, "StageType")) in [2, 3] and id not in contract.planned_bosses.values():
				continue
			ids.append(id)
	return ids


static func field(row: Dictionary, key: String) -> Variant:
	return row["<%s>k__BackingField" % key]


static func _shape_point(point: Dictionary) -> Vector2:
	return Vector2(float(point.X.RawValue), float(point.Y.RawValue)) / 65536.0


func _index_rows(rows: Array) -> Dictionary:
	var index: Dictionary = {}
	for row: Dictionary in rows:
		index[int(field(row, "Id")._sequentialId)] = row
	return index


func _index_environments(directory: String) -> void:
	for file in ResourceLoader.list_directory(directory):
		if file.ends_with("/"):
			_index_environments(directory + file)
		elif file.ends_with(".tscn"):
			_environment_paths[file.get_basename()] = directory + file


func _spawn_enemy(deployment: Dictionary) -> void:
	var enemy_id := int(deployment._enemyId._sequentialId)
	if not _enemies.has(enemy_id):
		push_error("Unknown enemy %s on stage %s" % [enemy_id, stage_id])
		return
	var enemy: Dictionary = _enemies[enemy_id]
	if endless_floor >= 0 and _enemy_scalings.has(enemy_id):
		enemy = enemy.duplicate()
		var scaling = load("res://battle/endless_scaling.gd")
		for rule: Dictionary in _enemy_scalings[enemy_id]:
			var stat := "<%s>k__BackingField" % GuildrunBoardUnit.STAT_NAMES[int(rule.TargetStatType)]
			enemy[stat] = scaling.scaled_stat(int(enemy[stat]), int(rule.Value.RawValue), endless_cycle())
	var cell: Dictionary = field(deployment, "Position")
	spawn_unit(enemy, Vector2i(cell.x, cell.y), int(field(deployment, "Direction")), false)


func hero_portrait(id: int) -> Texture2D:
	return character_portrait(field(_heroes[id], "VisualConfig"))


func character_portrait(visual: Dictionary) -> Texture2D:
	var path: String = _small_portraits.get(int(visual.m_PathID), "")
	return load(path) if not path.is_empty() and ResourceLoader.exists(path, "Texture2D") else null


## Unconditional owner-only constant effects from RankModifierSheetHolder (PathID 60845).
const FLAT_RANK_MODIFIER_STATS := {
	13: [[10, 1], [9, 40]],
	50: [[6, 100], [13, 20]],
	55: [[10, 1], [6, 50]],
	194: [[1, 1000], [13, 20]],
	240: [[11, 60], [13, 20]],
	285: [[18, 40], [12, 8]],
}


func deploy_hero(id: int, cell: Vector2i, modifiers: Array = [], equipment: Array = [], relics: Array = [], rank: int = 1, specialization: Dictionary = {}, earned_rank_modifiers: Dictionary = {}) -> GuildrunBoardUnit:
	if not _heroes.has(id) or not grid.contains(cell) or grid.occupants.has(cell):
		return null
	var unit := spawn_unit(hero_stats(id, modifiers, equipment, relics, rank, specialization, earned_rank_modifiers), cell, 0, true)
	unit.rank = rank
	for earned_rank in range(3, mini(rank, 4) + 1):
		var modifier := int(earned_rank_modifiers.get(earned_rank, earned_rank_modifiers.get(str(earned_rank), -1)))
		if modifier > 0:
			unit.earned_rank_modifiers[earned_rank] = modifier
	return unit


func hero_stats(id: int, modifiers: Array, equipment: Array, relics: Array, rank: int = 1, specialization: Dictionary = {}, earned_rank_modifiers: Dictionary = {}) -> Dictionary:
	var stats: Dictionary = _heroes[id].duplicate()
	preload("res://battle/hero_rank.gd").apply(stats, rank, specialization)
	for modifier: int in modifiers:
		var row: Dictionary = _stat_modifiers[modifier]
		_add_stat(stats, int(field(row, "TargetStat")), int(field(row, "Value").RawValue) >> 16)
	for earned_rank in range(3, mini(rank, 4) + 1):
		var modifier := int(earned_rank_modifiers.get(earned_rank, -1))
		for bonus: Array in FLAT_RANK_MODIFIER_STATS.get(modifier, []):
			_add_stat(stats, int(bonus[0]), int(bonus[1]))
	var classes: Array[int] = [int(stats._class1ID), int(stats._class2ID)]
	var glyph_stats: Array[Array] = []
	for item: int in equipment:
		if item >= 801 and item <= 807:
			if not classes.has(item - 800):
				classes.append(item - 800)
		elif item >= 701 and item <= 707:
			var profession := int([1, 2, 3, 4, 5, 7, 6][item - 701])
			if int(stats._class1ID) == profession or int(stats._class2ID) == profession:
				glyph_stats.append([[6, 4, 1, 11, 9, 7, 12][item - 701], [25, 15, 25, 30, 20, 25, 25][item - 701]])
			if not classes.has(profession):
				classes.append(profession)
	stats["equipment_classes"] = classes
	for item: int in equipment:
		var double_item := item >= 308 and item <= 321 and classes.has(1 + ((item - 308) >> 1))
		for bonus: Dictionary in field(items[item], "StatModifications"):
			_add_stat(stats, int(field(bonus, "TargetStat")), int(field(bonus, "Value")) * (2 if double_item else 1))
	for relic: int in relics:
		if relic == 6014:
			_add_stat(stats, 13, 10)
		if relic >= 783 and relic <= 796:
			var index := (relic - 783) % 7
			var amounts := [-12, -100, -15, -7, -10, -2, -12, 25, 200, 30, 15, 20, 4, 25]
			_add_stat(stats, [6, 1, 4, 11, 8, 12, 7][index], amounts[relic - 783])
		elif relic == 799:
			_add_stat(stats, 1, 500)
		if CLASS_MEDALS.has(relic):
			var medal: Dictionary = CLASS_MEDALS[relic]
			if classes.has(int(medal.hero_class)):
				_add_stat(stats, medal.stat, medal.amount)
	for glyph: Array in glyph_stats:
		var attribute := "<%s>k__BackingField" % GuildrunBoardUnit.STAT_NAMES[int(glyph[0])]
		_add_stat(stats, int(glyph[0]), roundi(int(stats[attribute]) * int(glyph[1]) / 100.0))
	if encounter != null and encounter.first_shop != null:
		var party := encounter.first_shop
		var party_rank_bonuses := GuildrunPartyRankBonuses.constant_bonuses(party, classes)
		for stat_id: int in party_rank_bonuses:
			_add_stat(stats, stat_id, int(party_rank_bonuses[stat_id]))
		for stat_id: int in party.quest_stats:
			_add_stat(stats, stat_id, int(party.quest_stats[stat_id]))
		var hero_bonus: Dictionary = party.kit_hero_stats.get(id, {})
		for stat_id: int in hero_bonus:
			_add_stat(stats, stat_id, int(hero_bonus[stat_id]))
		if party.kit_id in [764, 777, 778, 779, 780, 781, 782]:
			var settings: Dictionary = load("res://battle/opening_draft.gd").data()
			var sustained: Array[int] = []
			sustained.assign(settings.kit.stats[2])
			var index := sustained.find(party.kit_id)
			_add_stat(stats, int(settings.kit.stat_types[index]), int(settings.descriptions[str(party.kit_id)].Description["0"]))
	var percent := (10 if relics.has(5106) else 0) - (20 if relics.has(5112) else 0)
	if red_rift != null and equipment.has(red_rift.anchor_id):
		percent -= 25
	if relics.has(6017) and encounter != null and encounter.first_shop != null:
		percent += encounter.first_shop.charm_wins >> 1
	for effect: int in [5116, 5117, 5120, 797]:
		if relics.has(effect):
			percent += int({5116: -10, 5117: -15, 5120: 10, 797: 10}[effect])
	if percent:
		for key: String in ["Attack", "MaxHealth", "Defense", "Crit", "AttackSpeed", "ManaRegen", "Magic"]:
			var attribute := "<%s>k__BackingField" % key
			stats[attribute] = roundi(int(stats[attribute]) * (100 + percent) / 100.0)
	if relics.has(5104):
		stats["<Defense>k__BackingField"] = roundi(int(stats["<Defense>k__BackingField"]) * 0.5)
	return stats


func _add_stat(stats: Dictionary, stat_id: int, amount: int) -> void:
	var key := "<%s>k__BackingField" % GuildrunBoardUnit.STAT_NAMES[stat_id]
	var current: Variant = stats.get(key, 0)
	if current is Dictionary:
		stats[key] = {"RawValue": int(current.RawValue) + (amount << 16)}
	else:
		stats[key] = int(current) + amount


func spawn_unit(stats: Dictionary, cell: Vector2i, facing: int, hero: bool) -> GuildrunBoardUnit:
	var unit := GuildrunBoardUnit.new()
	var id := int(field(stats, "Id")._sequentialId)
	unit.is_hero = hero
	unit.name = "%s_%s_%s_%s" % ["Hero" if hero else "Enemy", id, cell.x, cell.y]
	unit.initialize(stats, cell, facing)
	# BoardController.InitializeCharacters pre-spawns enemies at yaw pi and heroes at identity.
	unit.rotation.y = 0.0 if hero else PI
	$Battle/BattleGrid.add_child(unit)
	unit.position = grid.center(unit.grid_cell)
	grid.occupants[unit.grid_cell] = unit
	var visual_id := str(int(field(stats, "VisualConfig").m_PathID))
	if _animation_timings.has(visual_id):
		var settings: Dictionary = _animation_timings[visual_id]
		unit.configure_attack(settings._animationTimings)
		if bool(field(settings, "HasFixedDuration")):
			unit.cast_duration_q16 = int(field(settings, "FixedDuration").RawValue)
	var ability: Dictionary = _abilities.get(int(stats._activeAbilityID), {})
	if not ability.is_empty() and (not hero or bool(field(stats, "StartWithActiveAbility"))):
		unit.ability_kind = ability.kind
		unit.active_stall_q16 = int(_active_stall_durations.get(int(stats._activeAbilityID), 0))
		unit.ability_data = ability.data
		if unit.ability_kind in ["LoganAbilityAction", "SeraphaelAbilityAction", "SnakeAction", "RookAction"] or ability.data.has("area_pulse"):
			unit.area_shapes = _aoe_shapes[int(ability.data._regularAoeEntry.m_PathID)]
		if unit.ability_kind == "AreaOfEffectAction":
			unit.area_shapes = _aoe_shapes[int(ability.data._aoeEntry.m_PathID)]
		if unit.ability_kind == "resolute_strike":
			var shape: Dictionary = ability.data._protectorAoeEntry if unit.passive_id() == 102602 else ability.data._regularAoeEntry
			unit.strike_radius = float(_aoe_radii[int(shape.m_PathID)]) / 65536.0
	if _rigs.has(visual_id) and not _rigs[visual_id].is_empty():
		for binding: Dictionary in _rigs[visual_id]:
			unit.add_rig(binding)
		unit.play_idle()
	elif _characters.has(visual_id):
		unit.add_child((load(_characters[visual_id]) as PackedScene).instantiate())
	else:
		push_warning("Missing character visual %s for unit %s" % [visual_id, id])
	return unit

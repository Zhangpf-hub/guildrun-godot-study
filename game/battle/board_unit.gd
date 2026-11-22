class_name GuildrunBoardUnit
extends Node3D

## The action can spawn a projectile or apply a melee effect. Its timing is
## independent of a rendered frame and of the end of the animation.
signal basic_attack_action(target: GuildrunBoardUnit)
signal fury_triggered
signal shield_gained(amount: int)
signal skill_attack_started

const STAT_NAMES := {1: "MaxHealth", 2: "MaxMana", 3: "MoveSpeed", 4: "Defense", 5: "BaseAttackDamage",
		6: "Attack", 7: "Magic", 8: "BaseAttackSpeed", 9: "AttackSpeed", 10: "AttackRange", 11: "Crit",
		12: "ManaRegen", 13: "OmniVamp", 14: "DamageAmp", 15: "HPPerSecond", 16: "BaseTrueDamage",
		17: "BonusTrueDamage", 18: "StartingMana", 19: "FrostResistance", 20: "StunResistance"}

var base_stats: Dictionary
var earned_rank_modifiers: Dictionary = {}
var battle_statistics: GuildrunBattleStatistics
var grid_cell: Vector2i
var direction: int
var health: int
var mana: int
var mana_regen_remaining_q16: int
var mana_lock_q16 := 0
var locked_mana := 0
var ability_kind: String
var ability_data: Dictionary
var rank := 1
var combat_stats := {}
var _stat_percent_q16: Dictionary = {}
var _stat_flat_q16: Dictionary = {}
var bounty_claimed := false
var shadow_triggered := false
var fury_used := false
var has_boss_fury := false
var hydra_heads := 3
var stealth_remaining_q16 := 0
var poison_stacks := 0
var poison_remaining_q16 := 0
var permanent_stats := {}
var cast_target: GuildrunBoardUnit
var current_target: GuildrunBoardUnit
var active_stall_q16 := 0
var javryn_targets: Array[GuildrunBoardUnit] = []
var cast_effect_fired := false
var cast_hit_index := 0
var passive_attacks := 0
var hunter_hits := 0
var stone_skin_triggers := 0
var permafrost_targets := 0
var permafrost_damage := 0
var permafrost_frost := 0
var shield_timer_q16 := 0
var area_shapes: Array
var ability_progress := {}
var shadow_step := -1
var shadow_target: GuildrunBoardUnit
var shadow_landing: Vector2i
var shadow_start_offset := Vector3.ZERO
var visual_offset := Vector3.ZERO
var strike_radius := 0.0
var shields: Array[Dictionary] = []
var cast_duration_q16 := 0
var cast_remaining_q16 := 0
var cast_release_q16 := -1
var burn_stacks := 0
var burn_remaining_q16 := 0
var frost_stacks := 0
var frost_remaining_q16 := 0
var frost_reductions := {}
var stun_remaining_q16 := 0
var slime_cleansed := false
var heal_remaining_q16 := 65536
var max_health: int
var basic_stat_percent := 0
const BASIC_STATS := ["Attack", "Defense", "MaxHealth", "Crit", "AttackSpeed", "Magic", "ManaRegen"]
var is_hero := false
var attack_cooldown_q16 := 0
var moving := false
var move_destination: Vector2i
var defeated := false
var trial_damage_immune := false
var _motion_players: Array[AnimationPlayer] = []
var _state_clips: Array[Dictionary] = []
var _death_blend_times: Dictionary[MeshInstance3D, Vector2] = {}
var _death_blend_tween: Tween
var _revive_tween: Tween
var _revive_materials: Dictionary[MeshInstance3D, Material] = {}
var _death_appearance_speed: float = 1.0
var _ragdoll_profile: Dictionary
var _ragdoll_impact: Dictionary
var _ragdoll: GuildrunCharacterRagdoll
var _ragdoll_animation_stop: Tween
var _ragdoll_start_delay: Tween
var _yuna_skill_effect: Node3D
var _yuna_charge_effect: Node3D
var _yuna_wind_mount: BoneAttachment3D
var _yuna_wind_effect: Node3D
var _yuna_charge_mount: BoneAttachment3D
var _yuna_flight_mount: BoneAttachment3D
var _yuna_release_effect: Node3D
var _yuna_flight_effect: Node3D
var _yuna_landing_effect: Node3D
var effect_scene_clock: Callable
var _yuna_effects: Array[Node3D] = []
var _yuna_basic_effects: Array[Node3D] = []
var _yuna_basic_mount: Node3D
var _basic_hit_q16: int
var _basic_duration_q16: int
var _action_pending := false
var _hit_remaining_q16: int
var _animation_remaining_q16: int
var _attack_target: GuildrunBoardUnit


func initialize(stats: Dictionary, cell: Vector2i, facing: int) -> void:
	base_stats = stats
	grid_cell = cell
	direction = facing
	health = stat("MaxHealth")
	max_health = health
	mana = stat("StartingMana")
	set_meta("hero_id" if is_hero else "enemy_id", int(stat("Id")._sequentialId))
	set_meta("grid_cell", cell)
	set_meta("direction", facing)
	set_meta("health", health)
	set_meta("mana", mana)


func stat(key: String) -> Variant:
	var value: Variant = _flat_and_challenge_stat(key)
	var flat_q16 := int(_stat_flat_q16.get(key, 0))
	var percent_q16 := int(_stat_percent_q16.get(key, 0))
	if flat_q16 == 0 and percent_q16 == 0:
		return value
	var total_q16 := _scale_stat_q16(value, flat_q16, percent_q16)
	if value is Dictionary:
		var scaled: Dictionary = value.duplicate()
		scaled.RawValue = total_q16
		return scaled
	return total_q16 >> 16


func stat_q16(key: String) -> int:
	return _scale_stat_q16(_flat_and_challenge_stat(key), int(_stat_flat_q16.get(key, 0)),
		int(_stat_percent_q16.get(key, 0)))


func _scale_stat_q16(value: Variant, flat_q16: int, percent_q16: int) -> int:
	var base_q16 := int(value.RawValue) if value is Dictionary else (int(value) << 16)
	return ((base_q16 + flat_q16) * (65536 + percent_q16) + 32768) >> 16


func _flat_and_challenge_stat(key: String) -> Variant:
	var value: Variant = base_stats.get("<%s>k__BackingField" % key, 0)
	if combat_stats.has(key) or permanent_stats.has(key) or frost_reductions.has(key):
		value = int(value) + int(combat_stats.get(key, 0)) + int(permanent_stats.get(key, 0)) - int(frost_reductions.get(key, 0))
	if basic_stat_percent and key in BASIC_STATS:
		value = floori(int(value) * (100 + basic_stat_percent) / 100.0)
	return value


## The combat percentage bucket adds signed Q16 deltas. Pass the inverse delta to remove an effect.
func modify_stat_percent(key: String, delta_q16: int) -> void:
	if delta_q16 == 0 or STAT_NAMES.find_key(key) == null:
		return
	var total_q16 := int(_stat_percent_q16.get(key, 0)) + delta_q16
	if total_q16 == 0:
		_stat_percent_q16.erase(key)
	else:
		_stat_percent_q16[key] = total_q16
	_refresh_effect_max_health(key)


func modify_stat_flat_q16(key: String, delta_q16: int) -> void:
	if delta_q16 == 0 or STAT_NAMES.find_key(key) == null:
		return
	_stat_flat_q16[key] = int(_stat_flat_q16.get(key, 0)) + delta_q16
	_refresh_effect_max_health(key)


func _refresh_effect_max_health(key: String) -> void:
	if key == "MaxHealth":
		var previous_max := max_health
		max_health = maxi(1, int(stat("MaxHealth")))
		if not defeated:
			health += maxi(0, max_health - previous_max)
			set_meta("health", health)


func set_basic_stat_percent(percent: int) -> void:
	if percent == basic_stat_percent:
		return
	var ratio := float(health) / maxi(1, max_health)
	basic_stat_percent = percent
	max_health = maxi(1, int(stat("MaxHealth")))
	if not defeated:
		health = clampi(roundi(max_health * ratio), 1, max_health)
	set_meta("health", health)


func gain_mana(amount: int) -> void:
	if amount <= 0 or not bool(stat("StartWithActiveAbility")):
		return
	if is_casting() or mana_lock_q16 > 0:
		locked_mana += amount
		return
	mana = mini(mana + amount, int(stat("MaxMana")))
	set_meta("mana", mana)


@warning_ignore("integer_division")
func effective_attack_damage() -> int:
	return int(stat("BaseAttackDamage")) * (100 + int(stat("Attack"))) / 100


func passive_id() -> int:
	return int(base_stats.get("_passiveAbilityID", -1))


func targetable() -> bool:
	return not defeated and stealth_remaining_q16 == 0


func has_class(id: int) -> bool:
	return is_hero and (int(base_stats._class1ID) == id or int(base_stats._class2ID) == id or base_stats.get("equipment_classes", []).has(id))


@warning_ignore("integer_division")
func gain_shield(amount: int, duration: int, source: GuildrunBoardUnit = null) -> void:
	if amount <= 0:
		return
	shields.append({"amount": amount, "remaining": duration})
	if battle_statistics != null:
		battle_statistics.support(source.get_instance_id() if source else get_instance_id(), 0, amount)
	shield_gained.emit(amount)
	if passive_id() == 102601:
		# KaiHeroicAction grants a separate ten-second shield then grants the attack bonus.
		var factor := 39322 + ((int(stat("Attack")) / 4 / 100) << 16)
		var bonus := (amount * factor) >> 16
		if bonus > 0:
			shields.append({"amount": bonus, "remaining": 10 << 16})
			if battle_statistics != null:
				battle_statistics.support(get_instance_id(), 0, bonus)
			shield_gained.emit(bonus)
		combat_stats.Attack = int(combat_stats.get("Attack", 0)) + 9 + 6 * (rank - 1)


func tick_mana(dt: int, interval: int) -> void:
	if is_casting():
		return
	if mana_lock_q16 > 0:
		mana_lock_q16 = maxi(0, mana_lock_q16 - dt)
		if mana_lock_q16 == 0:
			gain_mana(locked_mana)
			locked_mana = 0
			# The native clock adds an interval to the countdown that was paused.
			mana_regen_remaining_q16 += interval
		return
	mana_regen_remaining_q16 -= dt
	if mana_regen_remaining_q16 <= 0:
		mana_regen_remaining_q16 += interval
		gain_mana(int(stat("ManaRegen")))


func begin_active_ability(target: GuildrunBoardUnit = null, elapsed_q16: int = 0) -> void:
	cast_target = target
	cast_effect_fired = false
	cast_hit_index = 0
	match ability_kind:
		"demon_anger", "petrification", "permafrost":
			cast_release_q16 = int(ability_data.delay)
		"skorn_taunt":
			cast_release_q16 = int(ability_data.taunt._delay.RawValue)
		"JosephinaAction", "SeraphaelAbilityAction", "AreaOfEffectAction", "SnakeAction", "SpiderEnsnareAction", "hook_strike", "FionaAction", "RookAction", "FloeriaAbilityAction", "GustavAbilityAction", "PimentaAbilityAction":
			cast_release_q16 = int(ability_data._delay.RawValue)
		"shadow_strike":
			shadow_step = 0
			cast_release_q16 = int(ability_data.DelayAbilityAction._delay.RawValue)
		"wildfire":
			var attack: Dictionary = ability_data._attacks._attacks[0]
			cast_release_q16 = int(attack["<Delay>k__BackingField"].RawValue)
		"MeleeAbilityAction", "SnipeAbilityAction", "SkeletonSmashAction", "ReynaAction", "DragomirAction", "RatnaAbilityAction", "LoganAbilityAction", "HydraAction", "ForestGolemAction", "HoyoungAbilityAction", "NiklasAction", "JavrynAction":
			cast_release_q16 = int(ability_data._attacks._attacks[0]["<Delay>k__BackingField"].RawValue)
		"slime_strike":
			slime_cleansed = false
			cast_release_q16 = int(ability_data.cleanse._delay.RawValue)
		"lizard_strike":
			cast_release_q16 = int(ability_data.jump._delay.RawValue)
		"resolute_strike":
			cast_release_q16 = int(ability_data._delay.RawValue)
			if passive_id() == 102602:
				cast_release_q16 -= 65536
				if elapsed_q16 >= 15 << 16:
					var lasting := int(ability_data._protectorBaseShield) + ((int(stat("Defense")) * int(ability_data._shieldDefenseScalingPercent.RawValue)) >> 16)
					gain_shield(lasting, 999 << 16)
			var amount := int(ability_data._baseShield)
			amount += (int(stat("Attack")) * int(ability_data._shieldAttackScalingPercent.RawValue)) >> 16
			amount += (int(stat("Magic")) * int(ability_data._shieldMagicScalingPercent.RawValue)) >> 16
			gain_shield(amount, int(ability_data._shieldDuration) << 16)
		_:
			return
	cast_remaining_q16 = maxi(cast_release_q16, cast_duration_q16)
	reset_basic_attack()
	play_state("SkillAttack")
	if ability_kind == "shadow_strike":
		_start_yuna_skill_effect()
	skill_attack_started.emit()


func is_casting() -> bool:
	return cast_remaining_q16 > 0 or shadow_step >= 0


func gain_stealth(duration_q16: int) -> void:
	if not defeated:
		stealth_remaining_q16 = maxi(stealth_remaining_q16, duration_q16)


func resurrect(restored_health: int) -> void:
	defeated = false
	health = restored_health
	set_meta("health", health)
	moving = false
	reset_basic_attack()
	shadow_step = -1
	cast_remaining_q16 = 0
	cast_release_q16 = -1
	set_visual_offset(Vector3.ZERO)
	settle_death_appearance(true)
	play_idle()


func set_visual_offset(offset: Vector3) -> void:
	var change := transform.basis.inverse() * (offset - visual_offset)
	for child in get_children():
		if child is Node3D and not child.top_level:
			child.position += change
	visual_offset = offset


func add_rig(binding: Dictionary) -> void:
	var rig := (load(binding.model) as PackedScene).instantiate() as Node3D
	rig.rotation.y = PI
	add_child(rig)
	if ability_kind == "shadow_strike":
		for skeleton: Skeleton3D in rig.find_children("*", "Skeleton3D", true, false):
			if skeleton.find_bone(&"hand_R") >= 0:
				_yuna_basic_mount = Node3D.new()
				_yuna_basic_mount.name = &"BasicAttackVfxParent"
				# The particle mesh already converts Unity's forward axis; undo the FBX rig correction.
				_yuna_basic_mount.rotation.y = -rig.rotation.y
				skeleton.get_parent().add_child(_yuna_basic_mount)
				break
	# FBX import sanitizes node names such as Body.002 to Body_002.
	var imported_names: Dictionary = {}
	for source_name: String in binding.meshes:
		imported_names[source_name.validate_node_name()] = binding.meshes[source_name]
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := str(mesh.name)
		var appearance: Dictionary = binding.meshes.get(mesh_name, imported_names.get(mesh_name, {}))
		if appearance.is_empty() or mesh.mesh == null:
			continue
		mesh.visible = appearance.visible
		if mesh.visible and appearance.has("death_blend"):
			var timing: Array = appearance.death_blend
			_death_blend_times[mesh] = Vector2(timing[0], timing[1])
		if appearance.get("outline", false):
			var outline_path := "res://materials/character_outline_layer10.tres" if appearance.get("redraw_after_outline", false) \
					else "res://materials/character_outline.tres"
			mesh.material_overlay = load(outline_path) as ShaderMaterial
		for i in mini(mesh.mesh.get_surface_count(), appearance.surfaces.size()):
			var path: String = appearance.surfaces[i]
			if not path.is_empty():
				mesh.set_surface_override_material(i, load(path))
	for player: AnimationPlayer in rig.find_children("*", "AnimationPlayer", true, false):
		_motion_players.append(player)
		_state_clips.append(binding.states)
		for clip: String in binding.loop:
			if binding.loop[clip] and player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func play_idle() -> void:
	play_state("Idle")


func _begin_death_appearance() -> void:
	_cancel_revival_flash()
	if _death_blend_times.is_empty():
		return
	_death_blend_tween = create_tween().set_parallel().set_speed_scale(_death_appearance_speed)
	for mesh: MeshInstance3D in _death_blend_times:
		var timing: Vector2 = _death_blend_times[mesh]
		var update := func(amount: float) -> void:
			mesh.set_instance_shader_parameter(&"death_blend", amount)
		_death_blend_tween.tween_method(update, 0.0, 1.0, timing.y).set_delay(timing.x) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _start_yuna_skill_effect() -> void:
	_stop_yuna_skill_effect()
	_yuna_skill_effect = _add_yuna_effect("res://battle/yuna_skill_hit.tscn", self)
	_yuna_skill_effect.position += basis.inverse() * visual_offset
	_start_yuna_charge_effect()
	if not is_instance_valid(_yuna_charge_mount):
		return

	var skeleton := _yuna_charge_mount.get_skeleton()
	var character_root := skeleton.get_parent() as Node3D
	_yuna_wind_mount = skeleton.get_node_or_null("VFX_Ayaka_SkillAttack_01") as BoneAttachment3D
	if _yuna_wind_mount != null:
		_yuna_wind_effect = _add_yuna_effect("res://battle/yuna_skill_wind.tscn",
			_yuna_wind_mount.get_node("VFX_Ayaka_SkillAttack_01"))
	_yuna_release_effect = _add_yuna_effect("res://battle/yuna_skill_release.tscn", character_root)
	_yuna_landing_effect = _add_yuna_effect("res://battle/yuna_skill_landing.tscn", character_root)
	_yuna_flight_mount = skeleton.get_node_or_null("VFX_Slot") as BoneAttachment3D
	if _yuna_flight_mount != null:
		_yuna_flight_effect = _add_yuna_effect("res://battle/yuna_skill_flight.tscn",
			_yuna_flight_mount.get_node("VFX_Slot"))


func _add_yuna_effect(path: String, anchor: Node3D) -> Node3D:
	var effect := _new_yuna_effect(path, anchor)
	_yuna_effects.append(effect)
	return effect


func _new_yuna_effect(path: String, anchor: Node3D, action_speed: float = 1.0) -> Node3D:
	var scene := load(path) as PackedScene
	var effect := scene.instantiate() as Node3D
	effect.speed_scale = _death_appearance_speed
	effect.action_speed_scale = action_speed
	effect.scene_time = effect_scene_clock
	anchor.add_child(effect)
	return effect


func _start_yuna_charge_effect() -> void:
	if not is_instance_valid(_yuna_charge_mount):
		for skeleton: Skeleton3D in find_children("*", "Skeleton3D", true, false):
			var hand := skeleton.find_bone(&"hand_R")
			if hand >= 0:
				_yuna_charge_mount = BoneAttachment3D.new()
				_yuna_charge_mount.bone_idx = hand
				skeleton.add_child(_yuna_charge_mount)
				break
	if is_instance_valid(_yuna_charge_mount):
		_yuna_charge_effect = _add_yuna_effect("res://battle/yuna_skill_charge.tscn", _yuna_charge_mount)


func _stop_yuna_skill_effect() -> void:
	for effect: Variant in _yuna_effects:
		if is_instance_valid(effect):
			effect.hide()
			effect.queue_free()
	_yuna_effects.clear()
	_yuna_skill_effect = null
	_yuna_charge_effect = null
	_yuna_release_effect = null
	_yuna_flight_effect = null
	_yuna_landing_effect = null
	_yuna_wind_effect = null


func configure_ragdoll(profile: Dictionary, impact: Dictionary) -> void:
	_ragdoll_profile = profile
	_ragdoll_impact = impact


func _play_death_motion(attacker: GuildrunBoardUnit, damage: int) -> void:
	if not _ragdoll_profile.is_empty():
		var anchor: String = _ragdoll_profile.bodies[0].name
		for skeleton: Skeleton3D in find_children("*", "Skeleton3D", true, false):
			if skeleton.find_bone(anchor) < 0:
				continue
			var direction := global_basis.z.normalized()
			if is_instance_valid(attacker):
				var away := global_position - attacker.global_position
				away.y = 0.0
				if not away.is_zero_approx():
					direction = away.normalized()
			var fraction := clampf(inverse_lerp(_ragdoll_impact.min_damage, _ragdoll_impact.max_damage, damage), 0.0, 1.0)
			var impulse := direction * lerpf(_ragdoll_impact.min_force, _ragdoll_impact.max_force, fraction)
			_queue_ragdoll(skeleton, impulse)
			return
	play_state("Die")


func _queue_ragdoll(skeleton: Skeleton3D, impulse: Vector3) -> void:
	# HandleEntityDeath uses four Unity FixedUpdate steps at 50 Hz.
	_ragdoll_start_delay = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_ragdoll_start_delay.set_speed_scale(_death_appearance_speed)
	_ragdoll_start_delay.tween_interval(4.0 / 50.0)
	_ragdoll_start_delay.tween_callback(_activate_ragdoll.bind(skeleton, impulse))


func _activate_ragdoll(skeleton: Skeleton3D, impulse: Vector3) -> void:
	_ragdoll_start_delay = null
	if not is_instance_valid(skeleton):
		return
	_ragdoll = load("res://battle/character_ragdoll.gd").new()
	_ragdoll.name = &"DeathRagdoll"
	GuildrunCharacterRagdoll.restore_missing_leaves(skeleton, _ragdoll_profile)
	skeleton.add_child(_ragdoll)
	_ragdoll.start(skeleton, _ragdoll_profile, impulse, _death_appearance_speed)
	# The current animator continues to drive the non-physics tracks for 0.25 seconds.
	_ragdoll_animation_stop = create_tween().set_speed_scale(_death_appearance_speed)
	_ragdoll_animation_stop.tween_interval(0.25)
	_ragdoll_animation_stop.tween_callback(func() -> void:
		for player in _motion_players:
			player.pause()
	)

func set_death_appearance_speed(multiplier: float) -> void:
	_death_appearance_speed = multiplier
	if _ragdoll_start_delay != null:
		_ragdoll_start_delay.set_speed_scale(multiplier)
	if is_instance_valid(_ragdoll):
		_ragdoll.set_speed(multiplier)
	if _ragdoll_animation_stop != null and _ragdoll_animation_stop.is_valid():
		_ragdoll_animation_stop.set_speed_scale(multiplier)
	for effects: Array[Node3D] in [_yuna_effects, _yuna_basic_effects]:
		for effect: Variant in effects:
			if is_instance_valid(effect):
				effect.speed_scale = multiplier
	if _death_blend_tween != null and _death_blend_tween.is_valid():
		_death_blend_tween.set_speed_scale(multiplier)


func settle_death_appearance(restored: bool) -> void:
	_cancel_revival_flash()
	if restored and _ragdoll_start_delay != null:
		_ragdoll_start_delay.kill()
		_ragdoll_start_delay = null
	if restored and is_instance_valid(_ragdoll):
		if _ragdoll_animation_stop != null and _ragdoll_animation_stop.is_valid():
			_ragdoll_animation_stop.kill()
		_ragdoll_animation_stop = null
		_ragdoll.physical_bones_stop_simulation()
		_ragdoll.active = false
		_ragdoll.queue_free()
		_ragdoll = null
	if _death_blend_tween != null:
		_death_blend_tween.kill()
		_death_blend_tween = null
	for mesh: MeshInstance3D in _death_blend_times:
		mesh.set_instance_shader_parameter(&"death_blend", 0.0 if restored else 1.0)


func play_revival_flash() -> void:
	if _death_blend_times.is_empty():
		return
	_cancel_revival_flash()
	var material := load("res://materials/character_revive.tres") as ShaderMaterial
	_revive_tween = create_tween()
	_revive_tween.tween_interval(float(material.get_meta("revive_delay")))
	_revive_tween.tween_callback(_apply_revive_material.bind(material))
	_revive_tween.tween_interval(float(material.get_meta("revive_duration")))
	_revive_tween.tween_callback(_restore_revival_materials)


func _apply_revive_material(material: ShaderMaterial) -> void:
	for mesh in _death_blend_times:
		_revive_materials[mesh] = mesh.material_override
		mesh.material_override = material


func _restore_revival_materials() -> void:
	for mesh in _revive_materials:
		if is_instance_valid(mesh):
			mesh.material_override = _revive_materials[mesh]
	_revive_materials.clear()
	_revive_tween = null


func _cancel_revival_flash() -> void:
	if _revive_tween != null:
		_revive_tween.kill()
		_restore_revival_materials()


func take_damage(amount: int, source: GuildrunBoardUnit = null,
		origin := GuildrunBattleStatistics.Origin.OTHER, mitigated := 0, relic := 0,
		status_kind := GuildrunBattleStatistics.StatusKind.NONE) -> void:
	if trial_damage_immune:
		return
	var remaining := maxi(0, amount)
	for i in range(shields.size() - 1, -1, -1):
		if remaining == 0:
			break
		var absorbed := mini(remaining, int(shields[i].amount))
		remaining -= absorbed
		shields[i].amount -= absorbed
		if shields[i].amount == 0:
			shields.remove_at(i)
	var health_after_hit := health - remaining
	health = maxi(0, health_after_hit)
	if battle_statistics != null:
		# The native DamageLogEntry records the full post-shield hit, including overkill.
		battle_statistics.damage(source.get_instance_id() if source else 0, get_instance_id(), origin,
				remaining, maxi(0, amount) - remaining, mitigated, relic)
		if not is_hero and status_kind != GuildrunBattleStatistics.StatusKind.NONE:
			battle_statistics.record_status_damage(status_kind, remaining)
	set_meta("health", health)
	if remaining > 0 and health > 0 and passive_id() == 204 and not fury_used and health * 2 <= max_health:
		fury_used = true
		combat_stats.AttackSpeed = int(combat_stats.get("AttackSpeed", 0)) + 25
		gain_shield(max_health >> 2, 10 << 16)
		fury_triggered.emit()
	if remaining > 0 and health > 0 and has_boss_fury and not fury_used and health * 2 <= max_health:
		fury_used = true
		combat_stats.AttackSpeed = int(combat_stats.get("AttackSpeed", 0)) + 20
		gain_shield((max_health * 6554) >> 16, 10 << 16)
	if remaining > 0 and health > 0 and not shadow_triggered and health * 4 < max_health * 3 and passive_id() == 10401:
		shadow_triggered = true
		stealth_remaining_q16 = 4 << 16
		gain_mana(40)
		permanent_stats.Crit = int(permanent_stats.get("Crit", 0)) + 5 * rank
	# Native enemies survive an exact-zero hit. Heroes are defeated at zero.
	if (health_after_hit < 0 or (is_hero and health_after_hit == 0)) and not defeated:
		defeated = true
		stealth_remaining_q16 = 0
		_action_pending = false
		_stop_yuna_skill_effect()
		for effect: Variant in _yuna_basic_effects:
			if is_instance_valid(effect):
				effect.hide()
				effect.queue_free()
		_yuna_basic_effects.clear()
		_play_death_motion(source, remaining)
		_begin_death_appearance()


func total_shield() -> int:
	var total := 0
	for shield in shields:
		total += int(shield.amount)
	return total


func heal(amount: int, source: GuildrunBoardUnit = null) -> void:
	if amount > 0 and not defeated:
		var restored := mini(max_health - health, amount)
		health = mini(max_health, health + amount)
		set_meta("health", health)
		if battle_statistics != null and restored > 0:
			battle_statistics.support(source.get_instance_id() if source else get_instance_id(), restored, 0)


func tick_health_regen(dt: int) -> void:
	var amount := int(stat("HPPerSecond"))
	if passive_id() == 205:
		if (health << 16) <= max_health * 21627:
			hydra_heads = 1
		elif (health << 16) <= max_health * 43254:
			hydra_heads = mini(hydra_heads, 2)
		amount += 15 * hydra_heads
	if amount <= 0:
		return
	heal_remaining_q16 -= dt
	if heal_remaining_q16 <= 0:
		heal_remaining_q16 += 65536
		heal(amount)


func tick_shields(dt: int) -> void:
	for i in range(shields.size() - 1, -1, -1):
		shields[i].remaining -= dt
		if shields[i].remaining <= 0:
			shields.remove_at(i)


func face_point(point: Vector3) -> void:
	var offset := point - position
	if offset.x * offset.x + offset.z * offset.z > 0.00001:
		rotation.y = atan2(-offset.x, -offset.z)


func attack_animation_active() -> bool:
	return _animation_remaining_q16 > 0


func play_state(state: StringName, speed: float = 1.0) -> void:
	for i in _motion_players.size():
		var clip: StringName = _state_clips[i].get(state, &"")
		if clip != &"":
			var replay := _motion_players[i].current_animation == clip
			_motion_players[i].play(clip, -1.0, speed)
			if replay:
				_motion_players[i].seek(0.0, true)


func configure_attack(timings: Array) -> void:
	for timing: Dictionary in timings:
		if int(timing.Type) == 100:
			_basic_hit_q16 = int(timing.Hit.RawValue)
			_basic_duration_q16 = int(timing.Duration.RawValue)
		elif int(timing.Type) == 150:
			cast_duration_q16 = int(timing.Duration.RawValue)


@warning_ignore("integer_division")
func begin_basic_attack(target: GuildrunBoardUnit, speed_multiplier_q16: int) -> void:
	assert(is_instance_valid(target) and speed_multiplier_q16 > 0)
	_attack_target = target
	_action_pending = true
	_hit_remaining_q16 = (_basic_hit_q16 << 16) / speed_multiplier_q16
	_animation_remaining_q16 = (_basic_duration_q16 << 16) / speed_multiplier_q16
	var action_speed := float(speed_multiplier_q16) / GuildrunCombatMath.ONE
	play_state("BasicAttack", action_speed)
	if is_instance_valid(_yuna_basic_mount):
		for i in range(_yuna_basic_effects.size() - 1, -1, -1):
			if not is_instance_valid(_yuna_basic_effects[i]):
				_yuna_basic_effects.remove_at(i)
		_yuna_basic_effects.append(_new_yuna_effect("res://battle/yuna_basic_slash.tscn", _yuna_basic_mount, action_speed))


func reset_basic_attack() -> void:
	attack_cooldown_q16 = 0
	_action_pending = false
	_animation_remaining_q16 = 0


func advance_basic_attack(delta_q16: int) -> void:
	if _action_pending:
		_hit_remaining_q16 -= delta_q16
		if _hit_remaining_q16 <= 0:
			_action_pending = false
			if is_instance_valid(_attack_target):
				basic_attack_action.emit(_attack_target)
	_animation_remaining_q16 = maxi(0, _animation_remaining_q16 - delta_q16)


## Damage after defense only. Effects, shields and final HP application run in
## separate stages of the original DamageHandler.
func damage_after_defense(incoming: int) -> int:
	return GuildrunCombatMath.after_defense(incoming, int(stat("Defense")))

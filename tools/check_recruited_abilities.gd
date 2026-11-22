extends SceneTree


func _initialize() -> void:
	verify.call_deferred()


func require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition


func verify() -> void:
	for id: int in [24, 17, 3, 27, 13, 6]:
		var stage = (load("res://battle/stage.tscn") as PackedScene).instantiate()
		stage.stage_id = 10101
		root.add_child(stage)
		var fight := GuildrunEncounter.new()
		stage.add_child(fight)
		fight.setup(stage)
		fight.first_shop = GuildrunFirstShop.new()
		fight.add_child(fight.first_shop)
		var hero: GuildrunBoardUnit = stage.deploy_hero(id, Vector2i(4, 3))
		fight._register(hero)
		var melee: GuildrunBoardUnit = stage.grid.occupants[Vector2i(4, 4)]
		var archer: GuildrunBoardUnit = stage.grid.occupants[Vector2i(0, 7)]
		melee.health = 10000
		hero.mana = int(hero.stat("MaxMana"))
		fight._tick_unit(hero, fight.BATTLE_STEP_Q16)
		var ally: GuildrunBoardUnit
		var fallen: GuildrunBoardUnit
		if id == 27:
			ally = stage.deploy_hero(26, Vector2i(3, 3))
			fallen = stage.deploy_hero(4, Vector2i(2, 3))
			fight._register(ally)
			fight._register(fallen)
			ally.health = 1
			fight._land(fallen, 100000)
			fight.battle_time_q16 = (20 << 16) - 1
		var delay: int = {24: 32768, 17: 34334, 3: 16384, 27: 62259, 13: 26214, 6: 31654}[id]
		if not require(hero.is_casting() and hero.cast_target == melee and
				hero.cast_release_q16 == delay - fight.BATTLE_STEP_Q16, "Did not advance active on cast entry for hero %d" % id):
			return
		fight._tick_cast(hero, delay - fight.BATTLE_STEP_Q16 - 1)
		if not require(melee.health == 10000 and hero.total_shield() == 0, "Attack released early"):
			return
		if id == 24:
			if not require(hero.stat("OmniVamp") == 0, "Devour must grant vamp after the first hit"):
				return
			# First draw 52909 avoids a critical hit without removing the crit stat used by the effect.
			fight._combat_rng.reseed(500813409)
		else:
			hero.base_stats["<Crit>k__BackingField"] = 0
		fight._tick_cast(hero, 1)
		match id:
			13:
				var damage := melee.damage_after_defense(200)
				if not require(melee.health == 10000 - damage and hero.ability_progress.damage == damage and fight._strike_areas.is_empty(), "Execution baseline and tracking"):
					return
				for threshold: int in [2500, 20000, 40000]:
					hero.ability_progress.damage = threshold - 1
					hero.begin_active_ability(melee)
					fight._tick_cast(hero, delay)
				if not require(hero.stat("Attack") == 75 and hero.stat("Crit") == 30 and hero.stat("OmniVamp") == 10 and fight._strike_areas.size() == 1, "Execution permanent thresholds"):
					return
				fight._advance_strike_areas(9829)
				if not require(melee.stun_remaining_q16 == 0, "Execution area fired early"):
					return
				fight._advance_strike_areas(1)
				if not require(melee.stun_remaining_q16 == 163840 and archer.stun_remaining_q16 == 0, "Execution area placement and stun"):
					return
			6:
				var initial_archer := archer.health
				var defense := int(melee.stat("Defense"))
				var impact := melee.damage_after_defense(43)
				fight._advance_strike_areas(32767)
				if not require(melee.health == 10000, "Beam first pulse early"):
					return
				fight._advance_strike_areas(1)
				if not require(melee.health == 10000 - impact and melee.frost_stacks == 1 and melee.burn_stacks == 2 and archer.health == initial_archer, "Beam aim, damage or stacks"):
					return
				archer.position = hero.transform * Vector3(0, 0, -19)
				fight._advance_strike_areas(4 * 32768)
				if not require(melee.frost_stacks == 5 and melee.burn_stacks == 10 and melee.stat("Defense") == defense - 2 and archer.frost_stacks == 4, "Beam duration or moving target intersection"):
					return
				fight._advance_strike_areas(170394 - 5 * 32768)
				fight._tick_frost(melee, 131071)
				if not require(fight._strike_areas.is_empty() and melee.frost_stacks == 5, "Beam expired incorrectly or frost decayed early"):
					return
				fight._tick_frost(melee, 1)
				if not require(melee.frost_stacks == 4, "Frost dissipation"):
					return
			27:
				if not require(ally.total_shield() == 125 and ally.health == 63 and fallen.defeated and ally.shields[0].remaining == 8 << 16, "Salvation before stall"):
					return
				ally.rank = 2
				fight._land(ally, 100000)
				if not require(not ally._death_blend_times.is_empty() and ally._death_blend_tween != null,
						"The fallen ally must have a running material transition"):
					return
				ally._death_blend_tween.custom_step(0.75)
				var tinted := false
				for mesh: MeshInstance3D in ally._death_blend_times:
					tinted = tinted or float(mesh.get_instance_shader_parameter(&"death_blend")) > 0.0
				if not require(tinted, "The fallen ally must have started the death tint"):
					return
				var cell := ally.grid_cell
				var occupant: GuildrunBoardUnit = stage.deploy_hero(3, cell)
				fight._register(occupant)
				fight.battle_time_q16 += 1
				hero.begin_active_ability(melee)
				fight._tick_cast(hero, delay)
				if not require(not ally.defeated and ally.health == 125 and ally.total_shield() == 125 and fallen.defeated and stage.grid.occupants[ally.grid_cell] == ally and stage.grid.occupants[cell] == occupant, "Salvation revive rank, HP, shield or occupancy"):
					return
				if not require(ally._death_blend_tween == null, "Salvation must cancel the death material transition"):
					return
				for mesh: MeshInstance3D in ally._death_blend_times:
					if not require(is_zero_approx(float(mesh.get_instance_shader_parameter(&"death_blend"))),
							"Salvation must restore the revived ally's material"):
						return
			24:
				if not require(hero.stat("OmniVamp") == 6 and melee.health == 10000 - melee.damage_after_defense(250) and fight.first_shop.shards == 0, "Devour scaling or nonlethal reward"):
					return
				hero.begin_active_ability(melee)
				fight._tick_cast(hero, delay)
				if not require(hero.stat("OmniVamp") == 12 and melee.health == 10000 - melee.damage_after_defense(250) - melee.damage_after_defense(310),
						"The next Devour uses vamp from the previous hit"):
					return
				melee.health = 1
				hero.rank = 2
				hero.begin_active_ability(melee)
				fight._tick_cast(hero, delay)
				fight._tick_cast(hero, delay)
				if not require(melee.defeated and fight.first_shop.shards == 4 and hero.stat("OmniVamp") == 18, "Devour kill reward or stacking"):
					return
			17:
				if not require(melee.health == 10000 - melee.damage_after_defense(227) and hero.stat("Magic") == 25 and archer.stun_remaining_q16 == 0, "Starfall noncritical attack"):
					return
				hero.rank = 2
				hero.base_stats["<Crit>k__BackingField"] = 100
				melee.health = 1
				hero.begin_active_ability(melee)
				fight._tick_cast(hero, delay)
				if not require(melee.defeated and archer.stun_remaining_q16 == 65536 and hero.stat("Magic") == 45, "Starfall kill and global stun"):
					return
				var next: GuildrunBoardUnit = stage.deploy_hero(id, Vector2i(2, 2))
				fight._register(next)
				if not require(next.stat("Magic") == 45, "Lost permanent magic on redeploy"):
					return
			3:
				var hit := melee.damage_after_defense(66)
				if not require(melee.health == 10000 - hit and hero.total_shield() == 21, "Reyna first hit and shield"):
					return
				melee.health = 1
				fight._tick_cast(hero, delay)
				var initial := archer.health
				fight._tick_cast(hero, delay)
				if not require(melee.defeated and archer.health == initial - archer.damage_after_defense(66) and hero.total_shield() == 63 and hero.locked_mana == 0, "Reyna retarget or shield stacking"):
					return
				hero.tick_shields(999 << 16)
				if not require(hero.total_shield() == 0, "Reyna shield expiry"):
					return
		print("stage=10101 hero=", id, " action=", hero.ability_kind, " OK")
		stage.free()
	quit(0)

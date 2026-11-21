extends Control

signal new_run


func setup(stage: Node, party: GuildrunFirstShop) -> void:
	var floor_index := int(stage.endless_floor)
	var summary := $Center/Summary
	summary.get_node("Floor").text = tr("UI.EndScreen.EndlessFloor").format({"floor": floor_index + 1}) if floor_index >= 0 else tr("UI.EndScreen.Defeat")
	if stage.red_rift != null:
		summary.get_node("Floor").text = tr("UI.RiftSealingProtocol.Victory" if stage.red_rift.status == stage.red_rift.Status.COMPLETE else "UI.RiftSealingProtocol.Defeat")
	summary.get_node("Scores").visible = floor_index >= 0
	var difficulty_bonus := int(stage.contract.score_bonus)
	summary.get_node("Scores").text = "     ".join([tr("UI.Endless.Floor").format([floor_index]),
		tr("UI.Endless.BonusScore").format([0]), tr("UI.Endless.DifficultyBonusSCore").format([difficulty_bonus]),
		tr("UI.Endless.TotalScore").format([floor_index + difficulty_bonus])])
	var active := party.deployed_ids()
	for hero in active + party.reserve_slots:
		if int(hero) < 0:
			continue
		var card := VBoxContainer.new()
		var row: HBoxContainer = summary.get_node("Active" if active.has(hero) else "Reserve")
		row.add_child(card)
		var portrait := TextureRect.new()
		portrait.texture = stage.hero_portrait(hero)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(70, 70)
		card.add_child(portrait)
		var caption := Label.new()
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text = "%s · %s" % [tr("Heroes.Hero_%d.Name" % int(hero)), ["C", "B", "A", "S"][int(party.hero_ranks[hero]) - 1]]
		card.add_child(caption)
	summary.get_node("ReserveTitle").visible = summary.get_node("Reserve").get_child_count() > 0
	summary.get_node("NewRun").pressed.connect(func(): new_run.emit(), CONNECT_ONE_SHOT)

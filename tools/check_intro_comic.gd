extends SceneTree

var failed := false


func _initialize() -> void:
	verify.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func open_menu(path: String) -> Control:
	var menu: Control = load("res://UI/contracts.tscn").instantiate()
	menu.progress_path = path
	root.add_child(menu)
	current_scene = menu
	return menu


func click_comic() -> void:
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.position = root.get_visible_rect().get_center()
	input.pressed = true
	root.push_input(input, true)
	input.pressed = false
	root.push_input(input, true)


func verify() -> void:
	var path := "user://intro-comic-test-%d.cfg" % OS.get_process_id()
	var rules: GDScript = load("res://battle/difficulty_rules.gd")
	var menu := open_menu(path)
	var comic: Control = menu.get_node_or_null("Canvas_Comic")
	expect(comic != null, "Fresh title must play the introduction before Start")
	if comic == null:
		quit(1)
		return
	menu.get_node("TitleMenu/Start").pressed.emit()
	expect(current_scene == menu and not menu.selecting, "Comic must block Start")
	var first_caption: Control = comic._nodes[1743]
	expect(first_caption.get_node("UnityText").text == TranslationServer.translate("Comics.Introduction.Panel1.1"),
			"Opening caption was not localized")
	click_comic()
	expect(is_instance_valid(comic) and not comic._animation.is_running(), "First advance must reveal the comic")
	click_comic()
	await comic.completed
	await process_frame
	expect(menu.get_node_or_null("Canvas_Comic") == null and not menu.selecting, "Intro must finish on the title")
	expect(bool(rules.read_progress(path).get_value("opening", "intro_comic_seen", false)), "Intro completion must persist")
	menu.get_node("TitleMenu/Start").pressed.emit()
	await process_frame
	await process_frame
	expect(current_scene != menu and current_scene.stage_id == 10000 and not current_scene.normal_opening,
			"Fresh Start must go directly to the first tutorial battle")
	var fight: GuildrunEncounter = current_scene.encounter
	var founding := fight._founding_comic
	expect(founding != null and not fight._choices.visible, "Founding must precede the first hero picker")
	if founding != null:
		click_comic()
		click_comic()
		await founding.completed
		expect(fight._choices.visible, "Founding must reveal the pending hero picker")
		await process_frame
	current_scene.free()
	var saved: ConfigFile = rules.read_progress(path)
	saved.set_value("opening", "tutorial_checkpoint", true)
	saved.save(path)
	menu = open_menu(path)
	expect(menu.get_node_or_null("Canvas_Comic") == null, "Returning title must skip the watched introduction")
	menu.get_node("TitleMenu/Start").pressed.emit()
	expect(menu.selecting and menu.get_node("Panel/Actions/Play").visible, "Returning Start must offer contracts")
	menu.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("INTRO_COMIC template and localized text, advance and persistence, tutorial and contract routing")
	quit(1 if failed else 0)

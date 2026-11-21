extends SceneTree

const SPEED_AUTO := "Canvas/Root/CoreGameUI/SpeedControls/Root/ButtonPanel/SpeedButton_Auto"
const TUTORIAL_TIMED := 77122
const TUTORIAL_PROMPT := 65348

var _failed := false


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var old_locale := TranslationServer.get_locale()
	for locale: String in ["zh_Hans", "zh_Hant"]:
		TranslationServer.set_locale(locale)
		await verify_locale(locale)
	TranslationServer.set_locale(old_locale)
	if not _failed:
		print("Noto TC and SC glyphs shape in the battle button, tutorial, and speed views.")
	quit(1 if _failed else 0)


func verify_locale(locale: String) -> void:
	var stage := (load("res://battle/stage.tscn") as PackedScene).instantiate()
	stage.show_first_fight_tutorial = true
	root.add_child(stage)
	await process_frame
	var encounter: GuildrunEncounter = stage.encounter
	var views := encounter._ui
	var button: Label = views.get_node("StartBattleView").text
	var button_font := verify_font(button, "Bold")
	verify_glyphs(button_font, button.text, button.get_theme_font_size("font_size"), locale, true)

	var speed := views.get_node("BattleSpeedView/" + SPEED_AUTO)
	var speed_label := speed.get_node("Text/UnityText") as Label
	var accessible_text: String = speed.get_node("SelectSpeed").accessibility_name
	var speed_font := verify_font(speed_label, "Regular")
	verify_glyphs(speed_font, accessible_text, speed_label.get_theme_font_size("font_size"), locale)

	var tutorial := views.get_node("FirstTutorialView")
	encounter._process(0.5)
	for _page in range(3):
		click_viewport()
	encounter.select_hero(26)
	click_viewport()
	var timed: Label = tutorial._panels[TUTORIAL_TIMED].get_node("TutorialText/UnityText")
	expect(timed.text == tr("Tutorial.NTUT-A02.InfoText2").strip_edges(), "Real placement tutorial displays its second caption")
	verify_glyphs(verify_font(timed, "Regular"), timed.text, timed.get_theme_font_size("font_size"), locale)
	click_viewport()
	var prompt: Label = tutorial._panels[TUTORIAL_PROMPT].get_node("TutorialText/UnityText")
	expect(prompt.text == tr("Tutorial.NTUT-A02.PromptText1").strip_edges(), "Real deployment tutorial displays its prompt")
	verify_glyphs(verify_font(prompt, "Regular"), prompt.text, prompt.get_theme_font_size("font_size"), locale)
	stage.free()


func verify_font(label: Label, weight: String) -> FontVariation:
	var font := label.get_theme_font("font") as FontVariation
	if font == null or font.fallbacks.size() != 2:
		expect(false, "%s needs two controlled CJK fallbacks" % label.get_path())
		return null
	expect(font.base_font != null, "The base label font is retained")
	expect(font.fallbacks[0].resource_path.ends_with("NotoSansTC-%s.ttf" % weight), "TC uses the expected weight and priority")
	expect(font.fallbacks[1].resource_path.ends_with("NotoSansSC-%s.ttf" % weight), "SC uses the expected weight and priority")
	return font


func verify_glyphs(font: FontVariation, caption: String, size: int, locale: String, fight_button := false) -> void:
	expect(not caption.is_empty(), "Expected a real localized caption")
	if font == null or caption.is_empty():
		return
	var text_server := TextServerManager.get_primary_interface()
	var shaped := text_server.create_shaped_text()
	text_server.shaped_text_add_string(shaped, caption, font.get_rids(), size, {}, locale)
	var glyphs := text_server.shaped_text_get_glyphs(shaped)
	expect(not glyphs.is_empty(), "TextServer shaped the actual caption")
	var tc := font.fallbacks[0].get_rids()[0]
	var sc := font.fallbacks[1].get_rids()[0]
	var cjk_count := 0
	for glyph: Dictionary in glyphs:
		var unicode := caption.unicode_at(glyph.start)
		if unicode < 0x3400 or unicode > 0x9fff:
			continue
		cjk_count += 1
		expect(glyph.font_rid == tc or glyph.font_rid == sc, "CJK uses a bundled face for U+%04X" % unicode)
		if fight_button:
			var expected := sc if unicode == 0x6218 else tc
			expect(glyph.font_rid == expected, "Each battle button glyph selects the expected bold face")
	expect(cjk_count > 0, "The localized caption contains CJK")
	text_server.free_rid(shaped)


func click_viewport() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = root.get_visible_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

extends RefCounted

const NOTO_DIRECTORY := "res://fonts/noto/"


static func apply_to(label: Label, bold: bool = false) -> void:
	var weight := "Bold" if bold else "Regular"
	var traditional := load(NOTO_DIRECTORY + "NotoSansTC-%s.ttf" % weight) as Font
	var simplified := load(NOTO_DIRECTORY + "NotoSansSC-%s.ttf" % weight) as Font
	var font := FontVariation.new()
	font.base_font = label.get_theme_font("font")
	font.fallbacks = [traditional, simplified]
	label.add_theme_font_override("font", font)

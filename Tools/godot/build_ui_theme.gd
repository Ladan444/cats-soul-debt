extends SceneTree
## Собирает тему интерфейса res://assets/ui/theme.tres (UI_SPEC, разделы 1 и 6).
## Запуск: Game/Godot_v4.7.2-stable_win64_console.exe --headless --path Game/CatsSoulDebt -s Tools/godot/build_ui_theme.gd

const OUT := "res://assets/ui/theme.tres"


func _initialize() -> void:
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/public_pixel/PublicPixel.ttf")
	theme.default_font_size = 8

	theme.set_color("font_color", "Label", Color("e6d6b0"))
	theme.set_color("font_outline_color", "Label", Color("2a1e18"))

	# Деревянная панель (PanelContainer) и пергамент (вариант "ParchmentPanel").
	theme.set_stylebox("panel", "PanelContainer", _slice("res://assets/ui/panel_wood.png", 6, 8))
	theme.set_type_variation("ParchmentPanel", "PanelContainer")
	theme.set_stylebox("panel", "ParchmentPanel", _slice("res://assets/ui/panel_parchment.png", 5, 7))
	theme.set_color("font_color", "ParchmentLabel", Color("2a1e18"))
	theme.set_type_variation("ParchmentLabel", "Label")

	var err := ResourceSaver.save(theme, OUT)
	print("сохранено: ", OUT, " (код ", err, ")")
	quit(err)


## 9-slice из текстуры: margin — неизменяемые поля, padding — отступ содержимого.
func _slice(path: String, margin: int, padding: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, margin)
		sb.set_content_margin(side, padding)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb

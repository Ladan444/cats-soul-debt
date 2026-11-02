extends Node
## Автозагрузка InputGlyphs: каким устройством сейчас играют (клавиатура/мышь, геймпад или касание)
## и как подписать действие — для картинок клавиш в подсказках (KeyGlyph, HUD).
## При касании подписи клавиш скрываются (label() пустой): на экране свои кнопки.

signal device_changed(gamepad: bool)

const KEY_NAMES := {"Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "Space": "Пробел",
	"Escape": "Esc", "Shift": "Shift", "Tab": "Tab", "Enter": "Enter"}
const PAD_BUTTONS := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "View", 6: "Start", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "↑", 12: "↓", 13: "←", 14: "→"}
const PAD_AXES := {4: "LT", 5: "RT"}

var gamepad: bool = false
## Последний ввод — касание экрана (мышь, эмулированная касанием, не считается мышью).
var touch: bool = false


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)
	var screen := event is InputEventScreenTouch
	var real_mouse := (event is InputEventMouseButton or event is InputEventMouseMotion) \
			and event.device != InputEvent.DEVICE_ID_EMULATION
	var kb := event is InputEventKey or (real_mouse and event is InputEventMouseButton)
	if pad or kb or screen:
		var new_touch := screen or (touch and not pad and not kb)
		if pad != gamepad or new_touch != touch:
			gamepad = pad
			touch = new_touch
			device_changed.emit(gamepad)


## Показывать ли экранные кнопки (настройка «Сенсорное управление»).
func touch_controls_visible() -> bool:
	match int(Settings.get_value("touch_controls")):
		1: return true
		2: return false
	return touch


## Подпись действия для текущего устройства: "Q", "Esc", "ЛКМ", "A", "LB"... Пусто — если привязки нет
## или играют касанием.
func label(action: StringName) -> String:
	if touch or not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if gamepad:
			if e is InputEventJoypadButton:
				return PAD_BUTTONS.get(e.button_index, "?")
			if e is InputEventJoypadMotion and PAD_AXES.has(e.axis):
				return PAD_AXES[e.axis]
		else:
			if e is InputEventKey:
				var n := OS.get_keycode_string(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
				return KEY_NAMES.get(n, n)
			if e is InputEventMouseButton:
				return {1: "ЛКМ", 2: "ПКМ", 3: "СКМ"}.get(e.button_index, "Мышь")
	return ""


## Цвет кнопки геймпада в стиле Xbox (A — зелёная, B — красная, X — синяя, Y — жёлтая).
func pad_color(text: String) -> Color:
	return {"A": Color("4e9a4a"), "B": Color("b23a3a"), "X": Color("3a6ab2"), "Y": Color("c9a040")}.get(text, Color("3a2e2a"))

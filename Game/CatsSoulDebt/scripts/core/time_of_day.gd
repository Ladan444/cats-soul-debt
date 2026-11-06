extends Node
## Время суток (решение автора 2026-10-22: сутки — 24 минуты, день ~14, ночь ~7, рассвет и закат по ~1,5).
## Идёт всегда (кроме паузы игры); сцены под открытым небом применяют его через DayNightCycle.
## Мастер-меню: поставить час, остановить, ускорить. Сохраняется в SaveGame (ключ «time_of_day»).

signal changed(hour: float)

## Реальных минут на игровые сутки.
const DAY_MINUTES := 24.0
const START_HOUR := 9.0

var hour: float = START_HOUR
## Сколько раз часы переходили через полночь (для заданий «спустя сутки»); сохраняется.
var day: int = 0
var paused: bool = false
var speed: float = 1.0


func _process(delta: float) -> void:
	if paused or get_tree().paused:
		return
	set_hour(hour + delta * speed * 24.0 / (DAY_MINUTES * 60.0))


func set_hour(value: float) -> void:
	if value >= 24.0:
		day += int(value / 24.0)
	hour = fposmod(value, 24.0)
	changed.emit(hour)


## 0 — глубокая ночь, 1 — полный день (с плавными рассветом 4:30–6:00 и закатом 20:00–21:30).
func daylight() -> float:
	if hour < 4.5 or hour >= 21.5:
		return 0.0
	if hour < 6.0:
		return smoothstep(4.5, 6.0, hour)
	if hour < 20.0:
		return 1.0
	return 1.0 - smoothstep(20.0, 21.5, hour)


func is_night() -> bool:
	return daylight() < 0.35


## Сейчас час в окне [от, до) — окно может проходить через полночь (22 → 5).
func in_window(from_hour: float, to_hour: float) -> bool:
	if from_hour <= to_hour:
		return hour >= from_hour and hour < to_hour
	return hour >= from_hour or hour < to_hour


## «ЧЧ:ММ» для отладки и интерфейса.
func clock() -> String:
	var h := int(hour)
	return "%02d:%02d" % [h, int((hour - h) * 60.0)]


func to_dict() -> Dictionary:
	return {"hour": hour, "day": day}


func from_dict(data: Dictionary) -> void:
	day = int(data.get("day", 0))
	set_hour(float(data.get("hour", START_HOUR)))

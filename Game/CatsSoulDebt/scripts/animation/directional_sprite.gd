class_name DirectionalSprite
extends Sprite3D
## Спрайт персонажа с анимациями по направлениям из одного листа.
##
## Формат листа (общий для всех персонажей, его же собирают Tools/make_placeholder_anim.py,
## Tools/build_combat_sheets.py и будущий настоящий арт): столбцы — кадры (до 4),
## строки — анимация x направление в порядке down, up, side (directions = 3)
## или по строке на анимацию (directions = 1 — существа с одним видом, «вбок»).
## Пример для ANIMATIONS по умолчанию: строка 0 — idle вниз, 1 — idle вверх, 2 — idle вбок, 3 — walk вниз...
## Влево = отражённое «вбок». Размер ячейки — из размера листа, hframes и vframes.

## Неповторяющаяся анимация дошла до последнего кадра.
signal animation_finished(anim_name: String)

enum Facing { DOWN, UP, SIDE }

## Порядок анимаций в листе и параметры: количество кадров, кадров в секунду, зациклена ли.
@export var animations: Array[Dictionary] = [
	{"name": "idle", "frames": 4, "fps": 4.0, "loop": true},
	{"name": "walk", "frames": 4, "fps": 8.0, "loop": true},
	{"name": "run", "frames": 4, "fps": 12.0, "loop": true},
	{"name": "dash", "frames": 1, "fps": 1.0, "loop": false},
]
@export var columns: int = 4
## 3 — виды down, up, side; 1 — один вид.
@export var directions: int = 3

var current_animation: String = ""
var speed_scale: float = 1.0
## true — кадры не листаются сами, их ставит код (show_frame): удары, синхронные с логикой.
var manual: bool = false

var _index: Dictionary = {}
var _facing: Facing = Facing.DOWN
var _frame: int = 0
var _time: float = 0.0


func _ready() -> void:
	for i in animations.size():
		_index[animations[i]["name"]] = i
	hframes = columns
	vframes = animations.size() * directions
	play("idle")


## Запускает анимацию; если она уже играет, не сбрасывает её (restart — начать заново).
func play(anim_name: String, restart: bool = false) -> void:
	manual = false
	if anim_name == current_animation and not restart:
		return
	assert(_index.has(anim_name), "Нет анимации: %s" % anim_name)
	current_animation = anim_name
	_frame = 0
	_time = 0.0
	_apply_frame()


## Показывает конкретный кадр анимации и останавливает автолистание.
func show_frame(anim_name: String, index: int) -> void:
	assert(_index.has(anim_name), "Нет анимации: %s" % anim_name)
	manual = true
	current_animation = anim_name
	_frame = clampi(index, 0, animations[_index[anim_name]]["frames"] - 1)
	_apply_frame()


func has_animation(anim_name: String) -> bool:
	return _index.has(anim_name)


## Номер кадра листа для анимации и кадра в текущем направлении (для «призраков» спрайта).
func frame_of(anim_name: String, index: int) -> int:
	var view: int = 0 if directions == 1 else _facing
	return (_index[anim_name] * directions + view) * columns + index


func frame_count(anim_name: String) -> int:
	return animations[_index[anim_name]]["frames"]


## Поворачивает спрайт по направлению в плоскости XZ.
func face(direction: Vector3) -> void:
	if direction.length_squared() == 0.0:
		return
	if directions == 1 or absf(direction.x) > absf(direction.z):
		_facing = Facing.SIDE
		if absf(direction.x) > 0.01 or directions == 3:
			flip_h = direction.x < 0.0
	else:
		_facing = Facing.UP if direction.z < 0.0 else Facing.DOWN
		flip_h = false
	_apply_frame()


func _process(delta: float) -> void:
	if manual or current_animation.is_empty():
		return
	var anim: Dictionary = animations[_index[current_animation]]
	if anim["frames"] <= 1:
		return
	_time += delta * speed_scale
	var duration := 1.0 / float(anim["fps"])
	while _time >= duration:
		_time -= duration
		if anim["loop"]:
			_frame = (_frame + 1) % anim["frames"]
		elif _frame < anim["frames"] - 1:
			_frame += 1
			if _frame == anim["frames"] - 1:
				animation_finished.emit.call_deferred(current_animation)
	_apply_frame()


func _apply_frame() -> void:
	if current_animation.is_empty():
		return
	var view: int = 0 if directions == 1 else _facing
	var row: int = _index[current_animation] * directions + view
	frame = row * columns + _frame

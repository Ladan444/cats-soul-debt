class_name LevelDoor
extends Interactable
## Дверь серых блоков (меш Door-<вид>-<из>-<в> из Blender). Виды (Tools/blender/rubezh_layout.py):
##   key, bigkey — открывается ключом из инвентаря (ключ тратится);
##   oneway      — засов: отодвигается только со стороны комнаты «из» (короткий путь назад);
##   secret      — ложная стена: рушится от удара мечом, подсказки нет;
##   story       — открывается, когда задание главы дошло до нужного шага (Глава 1 — «к кругу печати»);
##   soul        — пока только надпись (печати душ — позже).
## Открытая дверь уходит в пол, коллизия выключается; состояние — в PlayerState.taken.

## Какой предмет открывает дверь — по подписи из планировки.
const KEY_ITEMS := {"К1": &"key_rubezh_k1", "К2": &"key_rubezh_k2", "К3": &"key_rubezh_k3"}

var kind: String
var label: String
var mesh: MeshInstance3D
## Центр комнаты «из» — сторона, с которой открывается засов.
var from_point: Vector3
## Для удара по ложной стене: стена 3 м шириной — достаём до её края.
var hit_radius: float = 1.5
## Проход для врагов сквозь открытую дверь (см. _add_nav_link).
var nav_link: NavigationLink3D
var _open: bool = false


## Настройка из скрипта уровня: меш двери из glb и его свойства (extras).
func setup(door_mesh: MeshInstance3D, extras: Dictionary, from_center: Vector3, scene_path: String) -> void:
	mesh = door_mesh
	kind = extras.get("kind", "")
	label = String(extras.get("label", ""))
	from_point = from_center
	persist_id = "%s:%s" % [scene_path, door_mesh.name]
	var aabb := door_mesh.get_aabb()
	position = aabb.get_center() - Vector3(0, aabb.size.y / 2.0, 0)
	prompt_height = aabb.size.y + 0.4
	interact_range = 2.4
	if kind == "secret":
		add_to_group("breakable")
	_add_nav_link(aabb)


## Навигация Рубежа запечена при закрытых дверях — проём для врагов открывает мостик через дверь
## (по тонкой оси). Включается вместе с дверью. Концы — у самых граней двери, внутри проёма: сетка
## кончается в ~0,35 м от двери и подхватывает их (радиус связи 1 м). Если конец уйти вглубь сетки,
## враг, шагнув за её край, каждый перерасчёт пути получает «назад к началу мостика» и топчется на месте.
func _add_nav_link(aabb: AABB) -> void:
	var across := Vector3(1, 0, 0) if aabb.size.x < aabb.size.z else Vector3(0, 0, 1)
	var reach := minf(aabb.size.x, aabb.size.z) / 2.0 + 0.1
	nav_link = NavigationLink3D.new()
	nav_link.name = "NavLink"
	nav_link.bidirectional = true
	nav_link.start_position = -across * reach
	nav_link.end_position = across * reach
	nav_link.enabled = false
	add_child(nav_link)


func _ready() -> void:
	super()
	if is_done():
		_set_open(true, false)


func key_item() -> ItemData:
	if kind == "bigkey":
		return ContentDB.item(&"key_treasury")
	return ContentDB.item(KEY_ITEMS.get(label, &""))


func _from_side() -> bool:
	if _player == null:
		return false
	var to_from := from_point - global_position
	var to_player := _player.global_position - global_position
	to_from.y = 0
	to_player.y = 0
	return to_from.dot(to_player) > 0.0


func prompt_text() -> String:
	if _open:
		return ""
	match kind:
		"key", "bigkey":
			var item := key_item()
			if item and PlayerState.count_of(item) > 0:
				return with_key("открыть: " + item.name.to_lower())
			return "Заперто. Нужен: " + (item.name.to_lower() if item else label)
		"oneway":
			return with_key("отодвинуть засов") if _from_side() else "Заперто с той стороны"
		"soul":
			return "Печать души"
		"story":
			return with_key("войти") if _story_ready() else "Закрыто до финала главы"
	return ""


## Сюжетная дверь (мост → Большой зал) открывается, когда задание Главы 1 дошло до шага «к кругу».
func _story_ready() -> bool:
	if not QuestState.active.has("chapter1"):
		return false
	return QuestState.is_done("chapter1") or QuestState.waiting_for("chapter1") in ["place:great_hall", "chapter_end"]


func can_interact() -> bool:
	if _open:
		return false
	match kind:
		"key", "bigkey":
			var item := key_item()
			return item != null and PlayerState.count_of(item) > 0
		"oneway":
			return _from_side()
		"story":
			return _story_ready()
	return false


func interact() -> void:
	if kind in ["key", "bigkey"]:
		var item := key_item()
		PlayerState.remove_item(item, 1)
		CombatFX.float_text(global_position + Vector3(0, 2.6, 0), "Открыто", Color("e6d6b0"))
		Audio.play("locked", global_position)
	Audio.play("door_open", global_position)
	_set_open(true, true)


## Ложная стена: удар мечом обрушивает её.
func take_hit(info: Dictionary) -> float:
	if _open or kind != "secret":
		return 0.0
	CombatFX.burst(global_position + Vector3(0, 1.4, 0), Color(0.35, 0.38, 0.45), info.get("dir", Vector3.ZERO), 24, 4.0, 10.0, 0.12, 0.8)
	CombatFX.shake(0.3)
	Audio.play("break", global_position)
	CombatFX.float_text(global_position + Vector3(0, 2.6, 0), "Тайник!", Color("8fd8d0"))
	_set_open(true, true)
	return 1.0


func is_alive() -> bool:
	return not _open


func _set_open(open: bool, animate: bool) -> void:
	_open = open
	if not open:
		return
	mark_done()
	remove_from_group("breakable")
	if nav_link:
		nav_link.enabled = true
	for body in mesh.find_children("*", "CollisionShape3D", true, false):
		(body as CollisionShape3D).set_deferred("disabled", true)
	if animate:
		var h := mesh.get_aabb().size.y
		var t := create_tween()
		t.tween_property(mesh, "position:y", mesh.position.y - h, 0.7).set_ease(Tween.EASE_IN)
		t.tween_callback(func(): mesh.visible = false)
		CombatFX.burst(global_position + Vector3(0, 0.3, 0), Color(0.6, 0.58, 0.55), Vector3.ZERO, 12, 2.0, 4.0, 0.1, 0.6)
	else:
		mesh.visible = false

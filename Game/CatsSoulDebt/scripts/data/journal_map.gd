class_name JournalMap
extends Resource
## Карта места для журнала (UI_SPEC, раздел 4): комнаты в мировых координатах XZ.
## Журнал сам переводит их на страницу, поэтому источник правды один — расположение в мире.
##
## Комната: {"id", "name", "world": Rect2 (x, z, ширина, глубина), "note": заметка Рэя,
##           "hinted": bool — набросок с самого начала (обрывок чужой карты),
##           "features": [{"type": "lantern" | "seal" | "door" | "fire", "pos": Vector2(x, z)}]}

@export var id: StringName
@export var title: String
@export var rooms: Array[Dictionary] = []


func room_at(world_xz: Vector2) -> Dictionary:
	for r in rooms:
		if (r["world"] as Rect2).has_point(world_xz):
			return r
	return {}


## Общие границы всех комнат — для масштаба на странице.
func bounds() -> Rect2:
	var b := Rect2()
	for i in rooms.size():
		var w: Rect2 = rooms[i]["world"]
		b = w if i == 0 else b.merge(w)
	return b

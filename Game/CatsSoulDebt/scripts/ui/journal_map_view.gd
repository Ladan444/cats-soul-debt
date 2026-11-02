class_name JournalMapView
extends Control
## Карта в журнале, нарисованная «от руки» (UI_SPEC, раздел 4):
## исследованные комнаты — чернилами со штриховкой и номером, намеченные — карандашным пунктиром,
## неизвестные не видны. Поверх — фонари душ, печать, двери, огонь, крестики смертей с номером,
## утерянные гелиосы и «лапа» — где сейчас Рэй.

const INK := Color("2a1e18")
const PENCIL := Color("8a8478")
const FILL := Color("d8c49a")
const DEATH := Color("7a2a24")
const BRASS := Color("c9a040")
const SOUL := Color("7a3cb0")
const GREEN := Color("3f6a4a")
const MARGIN := 8.0

var map: JournalMap:
	set(value):
		map = value
		queue_redraw()
## Позиция Рэя в мире (null — не показывать).
var player_position: Variant = null:
	set(value):
		player_position = value
		queue_redraw()

var _scale: float = 1.0
var _origin: Vector2


func _draw() -> void:
	if map == null or map.rooms.is_empty():
		return
	var b := map.bounds()
	var avail := size - Vector2(MARGIN, MARGIN) * 2
	_scale = floorf(minf(avail.x / b.size.x, avail.y / b.size.y) * 2.0) / 2.0
	var drawn := b.size * _scale
	_origin = (Vector2(MARGIN, MARGIN) + (avail - drawn) / 2.0).floor()

	# Сначала проходы (коридоры, дороги) — под залами, без номеров и обводки.
	for r in map.rooms:
		if r.get("passage", false) and JournalState.room_state(map.id, r["id"]) != 0:
			var p := _to_page_rect(r["world"])
			if JournalState.room_state(map.id, r["id"]) == 2:
				draw_rect(p, FILL.darkened(0.08))
			else:
				_dashed_rect(p, PENCIL.lightened(0.25))
	var number := 0
	for r in map.rooms:
		if r.get("passage", false):
			continue
		number += 1
		var state := JournalState.room_state(map.id, r["id"])
		if state == 0:
			continue
		var rect := _to_page_rect(r["world"])
		if state == 2:
			draw_rect(rect, FILL)
			_hatch(rect)
			draw_rect(rect, INK, false, 1.0)
			TinyFont.draw(self, str(number), rect.position + Vector2(2, 2), INK)
		else:
			_dashed_rect(rect, PENCIL)
			TinyFont.draw(self, str(number), rect.position + Vector2(2, 2), PENCIL)
		for f in r.get("features", []):
			_feature(f["type"], _to_page(f["pos"]), state == 2)

	var here := get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	for m in PlayerState.death_marks:
		if String(m.get("scene", "")) not in ["", here]:
			continue   # смерть в другой локации — на этой карте её крестику не место
		var p := _to_page(Vector2(m["pos"].x, m["pos"].z))
		_cross(p, DEATH)
		TinyFont.draw(self, str(m["number"]), p + Vector2(3, -6), DEATH)
		if m["helios"] > 0:
			draw_rect(Rect2(p + Vector2(-5, -1), Vector2(2, 2)), BRASS)

	if player_position != null:
		_paw(_to_page(Vector2(player_position.x, player_position.z)))


func _to_page(world_xz: Vector2) -> Vector2:
	return (_origin + (world_xz - map.bounds().position) * _scale).floor()


func _to_page_rect(world: Rect2) -> Rect2:
	var p := _to_page(world.position)
	return Rect2(p, (world.size * _scale).floor())


## Штриховка по диагонали — как карандашная тень на референсе skullfungus.
func _hatch(rect: Rect2) -> void:
	var color := Color(INK, 0.18)
	var w := int(rect.size.x)
	var h := int(rect.size.y)
	for k in range(0, w + h, 4):
		for t in range(0, h):
			var x := k - t
			if x >= 0 and x < w:
				draw_rect(Rect2(rect.position + Vector2(x, t), Vector2.ONE), color)


func _dashed_rect(rect: Rect2, color: Color) -> void:
	for x in range(0, int(rect.size.x), 3):
		draw_rect(Rect2(rect.position + Vector2(x, 0), Vector2(2, 1)), color)
		draw_rect(Rect2(rect.position + Vector2(x, rect.size.y - 1), Vector2(2, 1)), color)
	for y in range(0, int(rect.size.y), 3):
		draw_rect(Rect2(rect.position + Vector2(0, y), Vector2(1, 2)), color)
		draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1, y), Vector2(1, 2)), color)


func _feature(type: String, p: Vector2, inked: bool) -> void:
	var outline := INK if inked else PENCIL
	match type:
		"lantern":  # фонарь душ
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), outline)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), SOUL if inked else PENCIL.lightened(0.3))
		"seal":  # круг печати
			for a in 12:
				var ang := a * TAU / 12.0
				draw_rect(Rect2(p + Vector2(cos(ang), sin(ang)) * 4.0 - Vector2(0.5, 0.5), Vector2.ONE), outline)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), SOUL if inked else outline)
		"fire":
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color("c86a2a") if inked else outline)
		"door":
			draw_rect(Rect2(p - Vector2(1, 2), Vector2(3, 5)), FILL)
			draw_rect(Rect2(p - Vector2(1, 2), Vector2(1, 5)), outline)
			draw_rect(Rect2(p + Vector2(1, -2), Vector2(1, 5)), outline)


func _cross(p: Vector2, color: Color) -> void:
	for i in range(-2, 3):
		draw_rect(Rect2(p + Vector2(i, i), Vector2.ONE), color)
		draw_rect(Rect2(p + Vector2(i, -i), Vector2.ONE), color)


## Кошачья лапа: подушечка и четыре пальца.
func _paw(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 2)), GREEN)
	for o in [Vector2(-3, -2), Vector2(-1, -3), Vector2(1, -3), Vector2(3, -2)]:
		draw_rect(Rect2(p + o, Vector2.ONE), GREEN)

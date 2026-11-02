extends Interactable
## Заколоченный дом Лиары: у двери Рэй вспоминает слова соседей — по одному воспоминанию за подход
## (village_quests.gd → LIARA_MEMORIES), по кругу. Номер следующего — в PlayerState.taken («liara_memory:<n>»).

const DATA := preload("res://scripts/data/village_quests.gd")

var _busy := false
var _repeat := 0


func _ready() -> void:
	prompt_height = 1.6
	interact_range = 2.0
	super()


func prompt_text() -> String:
	return "" if _busy else "Заколоченная дверь\n" + with_key("постоять у двери")


func can_interact() -> bool:
	return not _busy


func interact() -> void:
	var box := get_tree().current_scene.get_node_or_null("DialogueBox")
	if box == null:
		return   # без окна реплик воспоминание не тратим
	# Сначала — ещё не услышанные (запоминаются в сохранении), потом по кругу.
	var n := 0
	while PlayerState.is_taken("liara_memory:%d" % n) and n < DATA.LIARA_MEMORIES.size():
		n += 1
	if n >= DATA.LIARA_MEMORIES.size():
		n = _repeat % DATA.LIARA_MEMORIES.size()
		_repeat += 1
	else:
		PlayerState.take("liara_memory:%d" % n)
	var memory: Array = DATA.LIARA_MEMORIES[n]
	var player := get_tree().get_first_node_in_group("player")
	_busy = true
	if player:
		player.set("input_locked", true)
	box.finished.connect(func():
		_busy = false
		if player:
			player.set("input_locked", false), CONNECT_ONE_SHOT)
	box.play(memory[0], PackedStringArray(["(Рэй вспоминает…)", memory[1]]))

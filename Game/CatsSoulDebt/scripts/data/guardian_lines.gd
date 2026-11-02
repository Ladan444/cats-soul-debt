class_name GuardianLines
extends Resource
## Реплики Стража Перекрёстка на одну главу (res://data/crossroads/chapter_<N>.tres).
## Каждый визит на Перепутье — одна «беседа» по очереди; когда беседы кончатся, идут по кругу.
## Править можно прямо в инспекторе Godot: одна строка массива — одна реплика (одно окно текста).

@export var chapter: int = 1
@export var conversations: Array[PackedStringArray] = []


## Беседа для visit-го визита (с нуля).
func conversation(visit: int) -> PackedStringArray:
	if conversations.is_empty():
		return PackedStringArray(["…"])
	return conversations[visit % conversations.size()]

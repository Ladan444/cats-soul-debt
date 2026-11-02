extends Npc
## Граф Вельмор за стойкой таверны (CANON: вежлив, печёт пироги, ни разу не взял плату вперёд).
## Ведёт Главу 1 (Литература/CHAPTER1.md, черновик): реплики по шагу задания chapter1, поручения,
## приём знамени, выбор — отдать душу или оставить, шкатулка, приглашение в Большой зал.
## Каждый разговор на ожидаемом шаге — событие «talk:velmor» для QuestState.
## Долг — строки в PlayerState.taken («debt:<что>»), видны в разговоре.

const Q := "chapter1"


func _ready() -> void:
	npc_id = "velmor"
	display_name = "Граф Вельмор"
	super()


func talk() -> void:
	if QuestState.step(Q) < 0:
		QuestState.start(Q)
	var step := QuestState.step(Q)
	match step:
		0:
			say(PackedStringArray([
				"А, Рэй. Проснулся. Пирог ещё тёплый — бери, за счёт заведения.",
				"Долг? Пустое. Долг подождёт до вечера, как и всё в этой деревне.",
				"Но раз уж ты на ногах… В казарме Рубежа осталось знамя третьей роты.",
				"Принеси его. Вдовам будет что повесить над дверью.",
			]), _advance)
		1:
			say(PackedStringArray(["Знамя третьей роты, Рэй. Казарма — за двором стражи, налево.",
				"И не торопись умирать. Тебе это… дорого обходится."]))
		2:
			if PlayerState.count_of(ContentDB.item(&"banner_third_company")) > 0:
				PlayerState.remove_item(ContentDB.item(&"banner_third_company"), 1)
				_debt("Знамя третьей роты")
				_advance()   # шаг закрывается вместе с отдачей вещи — сохранение посреди реплик не застрянет
				say(PackedStringArray([
					"Обгорел только край. Ильза узнает вышивку — это её работа.",
					"Видишь, Рэй, долг — это не цепь. Это просто счёт. Строчка за строчкой.",
					"А теперь — дело потруднее. В Рубеже бродят те, кто не ушёл.",
					"Принеси их мне. Им холодно одним. Я знаю, как с ними обойтись.",
				]))
			else:
				say(PackedStringArray(["Где же знамя, Рэй? Без него вдовам нечего вешать."]))
		3:
			say(PackedStringArray(["Души, Рэй. Хотя бы одну. Трапезная, водостоки, склеп — они там, где их застала ночь."]))
		4:
			_offer_souls(PackedStringArray([
				"Последнее, и я вычеркну почти всё.",
				"В сокровищнице есть шкатулка с моим гербом. Я оставлял её коменданту на хранение.",
				"Ключ… ключа нет. Есть части. Комендант любил прятать вещи по разным углам.",
			]))
		5:
			say(PackedStringArray(["Шкатулка, Рэй. Чёрное дерево, серебряные уголки. Три части ключа — и она твоя. То есть моя."]))
		6:
			if PlayerState.count_of(ContentDB.item(&"velmor_casket")) > 0:
				PlayerState.remove_item(ContentDB.item(&"velmor_casket"), 1)
				_debt("Шкатулка графа")
				_advance()
				var lines_after := PackedStringArray([
					"Благодарю. Ты не открывал её? Правильно. Не всё, что запечатано, стоит открывать.",
					"(Граф больше не улыбается.)",
					"Почти всё, Рэй. Осталась одна подпись.",
					"Встретимся в Большом зале. У круга.",
				])
				if PlayerState.count_of(ContentDB.item(&"liara_medallion")) > 0:
					lines_after.insert(1, "…Медальон? Оставь себе. Он тебе ещё понадобится.")
				say(lines_after)
			else:
				say(PackedStringArray(["Шкатулка, Рэй. Без неё я не могу закрыть твой счёт."]))
		7:
			say(PackedStringArray(["Большой зал. Мост над пропастью теперь открыт. Я буду ждать у круга."]))
		_:
			say(PackedStringArray(["…"]))


## Шаг пройден: событие для задания.
func _advance() -> void:
	QuestState.notify("talk:velmor")


## Строка долга (видна в следующих разговорах; позже — в журнале).
func _debt(what: String) -> void:
	PlayerState.take("debt:" + what)


## Выбор по каждой душе, что ещё с Рэем: отдать графу или оставить. Сила остаётся в любом случае (CANON).
## Шаг закрывается сразу после выбора (вместе с отдачей души), потом — ответ графа и следующее поручение (next).
func _offer_souls(next: PackedStringArray) -> void:
	var souls: Array = PlayerState.souls_with_ray()
	if souls.is_empty():
		say(PackedStringArray(["Ни одной? Значит, плохо искал. Трапезная, Рэй. Там держали дверь до последнего."]))
		return
	var soul: SoulData = souls[0]
	ask("%s… Я чувствую. Отдашь мне — запишу в счёт. Им со мной будет теплее." % soul.name,
		PackedStringArray(["Отдать душу графу", "Оставить себе"]),
		func(i):
			var reply := "Не спеши. Я подожду. Я вообще умею ждать."
			if i == 0:
				PlayerState.set_soul_state(soul, SoulData.State.GIVEN)
				_debt("Душа: " + soul.name)
				reply = "Спасибо, Рэй. Сила останется с тобой — ты её уже впитал. А душа… душа отдохнёт."
			_advance()
			var lines := PackedStringArray([reply])
			lines.append_array(next)
			say(lines))

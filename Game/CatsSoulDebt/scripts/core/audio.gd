extends Node
## Автозагрузка Audio: музыка и фон по локации (плавная смена), звуки событий (в мире — с положением),
## шаги Рэя по поверхности. Шины Music / Ambient / SFX создаёт Settings. Источники звука — assets/audio/SOURCES.md.
##
## Музыка выбирается по сцене (SCENES): днём — music, ночью (TimeOfDay) — night, когда враги заметили Рэя — battle;
## после боя прежняя дорожка продолжается с того же места. Сцена может переопределить дорожку метаданными «music» (id).
## Мастер-меню «Музыка» ставит любую дорожку поверх (override) — прослушать кандидатов на слух.

const DIR := "res://assets/audio/"
const FADE := 1.6
## Общая громкость музыки, дБ; у каждой дорожки — своя поправка (замер `python Tools/music_pick.py --measure`).
const MUSIC_DB := -10.0
const COMBAT_RANGE := 22.0
const WORLD_BUS := "SFXWorld"
## Сколько секунд после боя ещё звучит боевая музыка (чтобы не дёргалась между ударами).
const COMBAT_HOLD := 5.0
## Музыка: id → [файл в music/, название, автор, лицензия, поправка громкости дБ].
const TRACKS := {
	"bards_tale": ["bards_tale_loop.wav", "Medieval: The Bard's Tale", "RandomMind", "CC0", -6.2],
	"old_tower_inn": ["old_tower_inn_loop.wav", "Medieval: The Old Tower Inn", "RandomMind", "CC0", -0.7],
	"dungeon": ["dungeon_music.ogg", "Dungeon Ambience", "yd", "CC0", 10.0],
	"death_path": ["death_is_just_another_path.ogg", "Death Is Just Another Path", "Otto Halmén", "CC-BY 3.0", -0.1],
	"sylvan_waltz": ["sylvan_waltz.mp3", "Sylvan Waltz", "Otto Halmén", "CC-BY 3.0", -1.6],
	"peaceful_place": ["peaceful_place.ogg", "Peaceful Place", "Alexandr Zhelanov", "CC-BY 3.0", 0.6],
	"winds_of_stories": ["winds_of_stories.ogg", "Winds Of Stories", "HorrorPen", "CC-BY 3.0", -1.4],
	"silent_woods": ["secret_within_the_woods.ogg", "The Secret Within The Silent Woods", "Hitctrl", "CC-BY 3.0", -2.0],
	"beyond_the_stars": ["beyond_the_stars.ogg", "Beyond the Stars (Ambient)", "Hitctrl", "CC-BY 3.0", 0.9],
	"spirit_waltz": ["spirit_waltz.ogg", "Spirit Waltz", "HorrorPen", "CC-BY 3.0", -1.0],
	"trading_memories": ["trading_for_memories.mp3", "Trading It For The Memories", "jimbeamdiablo", "CC-BY 3.0", 0.0],
	"dark_descent": ["dark_descent.mp3", "Dark Descent", "Matthew Pablo", "CC-BY 3.0", -8.5],
	"cave_theme": ["cave_theme.ogg", "Cave Theme", "HaelDB", "CC0", -5.7],
	"town_in_ruins": ["town_in_ruins.ogg", "Town in Ruins", "HaelDB", "CC0", 10.0],
	"midnight_creeping": ["midnight_creeping.mp3", "Midnight Creeping", "InspectorJ", "CC-BY 3.0", -3.2],
	"dark_forest": ["dark_forest.mp3", "Dark Forest Theme", "cynicmusic", "CC0", -1.8],
	"regular_battle": ["regular_battle.mp3", "A Regular Battle", "Telaron", "CC-BY 3.0", -0.9],
	"battle_theme_a": ["battle_theme_a.mp3", "Battle Theme A", "cynicmusic", "CC0", -6.5],
	"small_loss": ["small_loss.ogg", "Small Loss", "HorrorPen", "CC-BY 3.0", -3.3],
	"vampires_piano": ["vampires_piano.mp3", "Vampire's Piano", "TAD", "CC0", -1.5],
	"lurid_delusion": ["lurid_delusion.mp3", "Lurid Delusion", "Matthew Pablo", "CC-BY 3.0", -2.8],
}
const _WORLD := {"music": "sylvan_waltz", "night": "beyond_the_stars", "battle": "regular_battle",
	"ambient": "ambient/birds_and_wind_ambient.ogg", "ambient_db": -6.0}
## Сцена → music (днём), night (ночью), battle (бой), ambient (фон, файл) и ambient_db, reverb — эхо на шине SFX
## (шаги, удары): [размер помещения 0…1, доля эха 0…1]. Пусто — тишина / без эха.
const SCENES := {
	"main_menu": {"music": "death_path"},
	"world": _WORLD,
	"tavern": {"music": "old_tower_inn", "reverb": [0.35, 0.08]},
	"rubezh_f1": {"music": "dark_descent", "battle": "regular_battle", "ambient": "ambient/dungeon_ambient_loop.ogg",
		"ambient_db": -4.0, "reverb": [0.75, 0.22]},
	"crossroads": {"music": "small_loss", "ambient": "ambient/dungeon_ambient_loop.ogg", "ambient_db": -8.0,
		"reverb": [0.9, 0.3]},
	"test_arena": {"music": "bards_tale", "battle": "regular_battle", "ambient": "ambient/forest_ambience.mp3",
		"ambient_db": -8.0},
}
## Звуки событий: имя → файлы (выбирается случайный; без расширения — .ogg в sfx/), громкость, дБ, [высота тона].
const SFX := {
	"step_grass": [["footstep_grass_000", "footstep_grass_001", "footstep_grass_002", "footstep_grass_003", "footstep_grass_004"], -14.0],
	"step_wood": [["footstep_wood_000", "footstep_wood_001", "footstep_wood_002", "footstep_wood_003", "footstep_wood_004"], -12.0],
	"step_stone": [["footstep_concrete_000", "footstep_concrete_001", "footstep_concrete_002", "footstep_concrete_003", "footstep_concrete_004"], -12.0],
	"swing": [["oga/swish_1.wav", "oga/swish_3.wav", "oga/swish_5.wav", "oga/swish_7.wav", "oga/swish_9.wav", "oga/swing_swing2.wav", "oga/swing_swing3.wav"], -9.0],
	"hit": [["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002", "impactPunch_medium_003"], -4.0],
	"hit_heavy": [["impactPlate_heavy_000", "impactPlate_heavy_001", "impactPlate_heavy_002"], -4.0],
	"hurt": [["impactSoft_medium_000", "impactSoft_medium_001", "impactSoft_medium_002"], -2.0],
	"break": [["impactMining_000", "impactMining_001", "impactMining_002"], -3.0],
	"coins": [["handleCoins", "handleCoins2"], -6.0],
	"door_open": [["doorOpen_1", "doorOpen_2"], -4.0],
	"door_close": [["doorClose_1", "doorClose_2", "doorClose_3"], -4.0],
	"locked": [["metalLatch"], -4.0],
	"chest": [["creak1", "creak2", "creak3"], -4.0],
	"pickup": [["metalClick", "cloth1", "cloth2"], -6.0],
	"lantern": [["impactMetal_light_000", "impactMetal_light_001"], -8.0],
	"dash": [["cloth3", "cloth4"], -6.0],
	"book_open": [["bookOpen"], -6.0],
	"book_close": [["bookClose"], -6.0],
	"page": [["bookFlip1", "bookFlip2", "bookFlip3"], -8.0],
	# Враги (Enemy.hit_sound / attack_sound / aggro_sound / death_sound); третье число — высота тона.
	"enemy_swing": [["oga/swing_swing.wav", "oga/swish_4.wav", "oga/swish_6.wav", "oga/swish_8.wav"], -6.0, 0.75],
	"hit_armor": [["oga/clash_1.wav", "oga/clash_3.wav", "oga/clash_4.wav", "oga/clash_5.wav"], -12.0, 0.9],
	"soldier_moan": [["oga/giant_1.wav", "oga/giant_2.wav", "oga/giant_3.wav", "oga/giant_4.wav", "oga/giant_5.wav"], -8.0, 0.7],
	"soldier_death": [["oga/giant_2.wav", "oga/giant_4.wav"], -5.0, 0.55],
	"creature_growl": [["oga/monster_1.wav", "oga/monster_2.wav", "oga/monster_3.wav", "oga/monster_7.wav", "oga/monster_9.wav"], -8.0],
	"creature_leap": [["oga/monster_10.wav", "oga/monster_12.wav", "oga/monster_13.wav"], -6.0, 1.1],
	"creature_death": [["oga/monster_5.wav", "oga/monster_14.wav"], -5.0],
	# Окружение: капли в Рубеже (Ambience.dungeon).
	"drip": [["oga/drip_1.wav", "oga/drip_2.wav", "oga/drip_3.wav"], -16.0],
}

## Дорожка поверх сцены (мастер-меню «Музыка»); пусто — по сцене.
var override := ""

var _music: Array[AudioStreamPlayer] = []
var _ambient: Array[AudioStreamPlayer] = []
var _music_i := 0
var _ambient_i := 0
var _scene := ""
var _cfg: Dictionary = {}
var _track := ""                  # id дорожки, которая звучит (или разгорается)
var _positions: Dictionary = {}   # файл → где остановилась: после боя дорожка продолжается с того же места
var _combat_left := 0.0
var _tick := 0.0
var _cache: Dictionary = {}
var _fades: Dictionary = {}   # плеер → его текущее затухание (Tween)
var _reverb: AudioEffectReverb


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		_music.append(_player("Music"))
		_ambient.append(_player("Ambient"))


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	# Зацикливание: файлы разных форматов — просто запускаем заново.
	p.finished.connect(func(): if p.volume_db > -79.0: p.play())
	add_child(p)
	return p


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene else ""
	if path != _scene:
		_scene = path
		_cfg = SCENES.get(path.get_file().get_basename(), {})
		if scene and scene.has_meta("music"):
			_cfg = _cfg.duplicate()
			_cfg["music"] = scene.get_meta("music")
		_combat_left = 0.0
		_set_reverb(_cfg.get("reverb", []))
		_switch(_ambient, "_ambient_i", _cfg.get("ambient", ""), _cfg.get("ambient_db", -6.0))
		_update_music()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	_combat_left = COMBAT_HOLD if _in_combat() else maxf(_combat_left - 0.5, 0.0)
	_update_music()


## Какая дорожка должна звучать сейчас: поверх (отладка) → бой → ночь → день.
func wanted_track() -> String:
	if override != "":
		return override
	if _combat_left > 0.0 and _cfg.has("battle"):
		return _cfg["battle"]
	if _cfg.has("night") and TimeOfDay.is_night():
		return _cfg["night"]
	return _cfg.get("music", "")


func current_track() -> String:
	return _track


## «Название — автор» для подписи (мастер-меню).
func track_title(id: String) -> String:
	var t: Array = TRACKS.get(id, [])
	return "%s — %s" % [t[1], t[2]] if not t.is_empty() else "тишина"


## Авторы музыки для экрана «Авторы»: каждая дорожка — название, автор, лицензия.
func music_credits() -> String:
	var lines := PackedStringArray()
	for id in TRACKS:
		var t: Array = TRACKS[id]
		lines.append("«%s» — %s (%s)" % [t[1], t[2], t[3]])
	return "
".join(lines)


func _update_music() -> void:
	var id := wanted_track()
	if id == _track:
		return
	_track = id
	var t: Array = TRACKS.get(id, [""])
	var file: String = ("music/" + t[0]) if t[0] != "" else ""
	_switch(_music, "_music_i", file, MUSIC_DB + (t[4] if t.size() > 4 else 0.0), id != _cfg.get("battle", ""))


## Шина звуков в мире (шаги, удары, капли) — посылает в SFX (её громкость — из настроек). Эхо только на ней:
## звуки интерфейса (книга, лавка) идут прямо в SFX и в подземелье не гулкие.
func _world_bus() -> int:
	var bus := AudioServer.get_bus_index(WORLD_BUS)
	if bus < 0 and AudioServer.get_bus_index("SFX") >= 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, WORLD_BUS)
		AudioServer.set_bus_send(bus, "SFX")
	return bus


## Эхо каменных залов: реверберация на шине SFXWorld, включается по сцене ([размер, доля] или пусто — выключить).
func _set_reverb(cfg: Array) -> void:
	var bus := _world_bus()
	if bus < 0:
		return
	if _reverb == null:
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		_reverb.damping = 0.55
		_reverb.predelay_msec = 45.0
		_reverb.hipass = 0.15
		AudioServer.add_bus_effect(bus, _reverb)
	if not cfg.is_empty():
		_reverb.room_size = cfg[0]
		_reverb.wet = cfg[1]
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == _reverb:
			AudioServer.set_bus_effect_enabled(bus, i, not cfg.is_empty())


func reverb_on() -> bool:
	var bus := AudioServer.get_bus_index(WORLD_BUS)
	if bus < 0 or _reverb == null:
		return false
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == _reverb:
			return AudioServer.is_bus_effect_enabled(bus, i)
	return false


## Враги, заметившие Рэя (не «idle»), рядом с ним — бой.
func _in_combat() -> bool:
	if not _cfg.has("battle"):
		return false
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and not e.get("dead") and e.get("state") not in [null, "idle"] 				and (e as Node3D).global_position.distance_to(p.global_position) < COMBAT_RANGE:
			return true
	return false

## Плавная смена дорожки: старый плеер гаснет, новый разгорается. Тот же файл — без перезапуска.
## resume — продолжить файл с места, где он остановился в прошлый раз (не для боевой дорожки).
func _switch(players: Array[AudioStreamPlayer], index_var: String, file: String, db: float, resume := false) -> void:
	var i: int = get(index_var)
	var current := players[i]
	var other := players[1 - i]
	# Тот же файл уже звучит — только громкость (остановленный плеер с тем же файлом сюда не попадает:
	# после сцены без фона его надо запустить заново, иначе фон молчал до конца игры).
	if file != "" and current.playing and current.stream and current.stream.resource_path == DIR + file:
		_fade(current).tween_property(current, "volume_db", db, FADE)
		return
	if current.playing:
		_positions[current.stream.resource_path] = current.get_playback_position()
		var t := _fade(current)
		t.tween_property(current, "volume_db", -80.0, FADE)
		t.tween_callback(current.stop)
	if file == "":
		return
	set(index_var, 1 - i)
	# Нужная дорожка ещё гаснет на втором плеере (смена туда-обратно) — вернуть её громкость, без перезапуска.
	if other.playing and other.stream and other.stream.resource_path == DIR + file:
		_fade(other).tween_property(other, "volume_db", db, FADE)
		return
	other.stream = _load(DIR + file)
	other.volume_db = -80.0
	other.play(_positions.get(DIR + file, 0.0) if resume else 0.0)
	_fade(other).tween_property(other, "volume_db", db, FADE)


## Новое затухание плеера отменяет прежнее: при быстрой смене сцен старое «погасить и остановить»
## иначе догоняло плеер, в котором уже играла новая дорожка, и глушило её.
func _fade(p: AudioStreamPlayer) -> Tween:
	var old: Tween = _fades.get(p)
	if old and old.is_valid():
		old.kill()
	var t := create_tween()
	_fades[p] = t
	return t


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Звук события. at — точка в мире (звук с положением); без неё — «в голове» (интерфейс).
func play(name: String, at: Variant = null, pitch_jitter: float = 0.08) -> void:
	if not SFX.has(name):
		return
	var spec: Array = SFX[name]
	var files: Array = spec[0]
	var file: String = files[randi() % files.size()]
	var stream := _load(DIR + "sfx/" + file + ("" if "." in file else ".ogg"))
	var pitch: float = (spec[2] if spec.size() > 2 else 1.0) + randf_range(-pitch_jitter, pitch_jitter)
	if at is Vector3 and get_tree().current_scene is Node3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.bus = WORLD_BUS if _world_bus() >= 0 else "SFX"
		p3.volume_db = spec[1]
		p3.unit_size = 6.0
		p3.max_distance = 40.0
		p3.pitch_scale = pitch
		get_tree().current_scene.add_child(p3)
		p3.global_position = at
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.bus = "SFX"
		p2.volume_db = spec[1]
		p2.pitch_scale = pitch
		p2.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p2)
		p2.finished.connect(p2.queue_free)
		p2.play()


## Поверхность под точкой: трава / дерево / камень (по имени меша под ногами).
func surface_at(world: World3D, at: Vector3) -> String:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at - Vector3(0, 1.0, 0), 1)
	var hit := world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "step_stone"
	var node := hit["collider"] as Node
	var name := ""
	for i in 3:
		if node == null:
			break
		name += String(node.name)
		node = node.get_parent()
	if "Terrain" in name:
		return "step_grass"
	if "Wood" in name or "Plank" in name or "TavernFloor" in name:
		return "step_wood"
	return "step_stone"

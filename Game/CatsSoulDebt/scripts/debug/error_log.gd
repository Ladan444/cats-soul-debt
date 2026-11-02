class_name ErrorLog
extends Logger
## Перехват ошибок и предупреждений движка и скриптов (для «Лога ошибок» в мастер-меню отладки).
## Вызовы могут приходить из других потоков — запись под мьютексом.

const MAX_LINES := 60

var lines: PackedStringArray = PackedStringArray()
var count: int = 0
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind := "ПРЕДУПР." if error_type == ERROR_TYPE_WARNING else "ОШИБКА"
	var text := rationale if rationale != "" else code
	_add("[%s] %s  (%s:%d %s)" % [kind, text, file.get_file(), line, function])


func _log_message(message: String, error: bool) -> void:
	if error:
		_add("[stderr] " + message.strip_edges())


func _add(text: String) -> void:
	_mutex.lock()
	lines.append(text)
	count += 1
	if lines.size() > MAX_LINES:
		lines.remove_at(0)
	_mutex.unlock()


func snapshot() -> PackedStringArray:
	_mutex.lock()
	var copy := lines.duplicate()
	_mutex.unlock()
	return copy


func clear() -> void:
	_mutex.lock()
	lines.clear()
	count = 0
	_mutex.unlock()

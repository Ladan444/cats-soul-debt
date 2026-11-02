class_name SoulData
extends Resource
## Душа павшего товарища (вкладка «Души», UI_SPEC раздел 3). Даёт Рэю силу владельца — скилл.
## Если душу отдать графу или освободить, скилл остаётся (CANON).

enum State { COLLECTED, GIVEN, FREED }
const STATE_NAMES := ["С Рэем", "Отдана графу", "Освобождена"]

@export var id: StringName
@export var name: String
## Рота гарнизона.
@export var company: String
@export_multiline var memory: String
@export var skill: SkillData

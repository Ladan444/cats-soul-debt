class_name SkillData
extends Resource
## Скилл — сила собранной души (CANON: «Бой, силы душ и деньги»). Сами эффекты — в боевой системе (6.2).

@export var id: StringName
@export var name: String
@export var icon: Texture2D
@export_multiline var description: String
@export var energy_cost: float = 25.0
@export var cooldown: float = 3.0

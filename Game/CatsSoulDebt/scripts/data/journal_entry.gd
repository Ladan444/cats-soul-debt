class_name JournalEntry
extends Resource
## Запись журнала Рэя (UI_SPEC, раздел 4): своя или вклеенная чужая страница.
## Почерк автора — часть расследования (Лиара, командиры, граф — красными чернилами, появляется поздно).

enum Author { RAY, LIARA, COMMANDER, VELMOR, UNKNOWN }
enum Section { RECORDS, PEOPLE }

const AUTHOR_NAMES := ["Рэй", "Лиара", "Командир", "Граф", "Незнакомый почерк"]
## Цвет чернил каждого почерка (до появления отдельных рукописных шрифтов).
const AUTHOR_INK := [Color("2a1e18"), Color("2e4a6e"), Color("141414"), Color("8a1e1e"), Color("4a3a2e")]

@export var id: StringName
@export var title: String
@export var section: Section = Section.RECORDS
@export var author: Author = Author.RAY
@export var chapter: int = 1
## Порядок внутри главы.
@export var order: int = 0
@export_multiline var text: String
## Открыта с начала игры; иначе — открывается событием (JournalState.unlock).
@export var unlocked_by_default: bool = true
## Для раздела «Люди»: лист спрайтов для наброска-портрета (кадр «вниз»).
@export var portrait_sheet: Texture2D
## Казённые бумаги — с сургучной печатью внизу.
@export var sealed: bool = false

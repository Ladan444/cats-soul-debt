class_name KitDress
## «Одежда» мешей из готовых наборов: модули Quaternius (дома, стены таверны) и мебель KayKit.
## Quaternius — поверхность на материал пака (MI_*), пиксельные текстуры 40 px/м (Tools/kit_textures.py)
## по развёртке пака, окно вокруг Рэя (wall_xray); вьюны — шейдер листвы.
## KayKit — одна палитра-текстура (assets/textures/kaykit/dungeon_texture.png), фильтр nearest.

const WALL_SHADER := preload("res://assets/shaders/wall_xray.gdshader")
const FOLIAGE_SHADER := preload("res://assets/shaders/foliage.gdshader")
const KIT_TEX := "res://assets/textures/village_kit/"
const KAYKIT_TEX := "res://assets/textures/kaykit/dungeon_texture.png"
## Варианты черепицы: та же текстура, обесцвеченная и подкрашенная (сланец, бурая) — [цвет, обесцвечивание].
const KIT_TINT := {"MI_RoundTiles_slate": [Vector3(0.78, 0.9, 1.12), 0.9],
	"MI_RoundTiles_brown": [Vector3(1.05, 0.8, 0.6), 0.75]}

## Изнанка стен и крыш (материалы «…_inside», village_houses.py): та же текстура, но в тени — в «окне»
## вокруг Рэя видно тёмное нутро дома с полом, а не светлую коробку.
const INSIDE_TINT := Vector3(0.32, 0.29, 0.27)

static var _kit_info: Dictionary = {}


## Модули Quaternius; xray_radius 0 — окно вокруг Рэя не режется.
static func quaternius(node: MeshInstance3D, xray_radius: float = 2.2) -> void:
	if _kit_info.is_empty():
		_kit_info = JSON.parse_string(FileAccess.get_file_as_string(KIT_TEX + "kit.json"))
	var images: Dictionary = _kit_info.get("materials", {})
	for i in node.mesh.get_surface_count():
		var src := node.mesh.surface_get_material(i)
		var mat_name := src.resource_name.get_slice(".", 0) if src else ""
		var inside := mat_name.ends_with("_inside")
		mat_name = mat_name.trim_suffix("_inside")
		var img: String = images.get(mat_name, "")
		var m := ShaderMaterial.new()
		if mat_name == "MI_Vine":
			m.shader = FOLIAGE_SHADER
			m.set_shader_parameter("albedo_texture", load(KIT_TEX + img + ".png"))
			m.set_shader_parameter("tint", Color(0.42, 0.6, 0.28))
			m.set_shader_parameter("xray", false)
			m.set_shader_parameter("sway", 0.01)
		else:
			m.shader = WALL_SHADER
			m.set_shader_parameter("radius", xray_radius)
			if img != "" and ResourceLoader.exists(KIT_TEX + img + ".png"):
				m.set_shader_parameter("albedo_texture", load(KIT_TEX + img + ".png"))
				m.set_shader_parameter("use_texture", true)
				m.set_shader_parameter("use_uv", true)
				m.set_shader_parameter("texture_meters", 1.0)
				var tint: Array = KIT_TINT.get(mat_name, [Vector3.ONE, 0.0])
				m.set_shader_parameter("texture_tint", tint[0] * (INSIDE_TINT if inside else Vector3.ONE))
				m.set_shader_parameter("texture_desaturate", tint[1])
			else:
				m.set_shader_parameter("albedo", Color(0.22, 0.28, 0.32) * (0.4 if inside else 1.0))   # стекло окон
		node.set_surface_override_material(i, m)


## Крупная архитектура KayKit (арки в проёмах Рубежа): та же палитра, но шейдер стен — окно вокруг Рэя,
## чтобы перемычка арки не закрывала его в проходе.
static func kaykit_xray(node: MeshInstance3D, xray_radius: float = 2.2) -> void:
	var m := ShaderMaterial.new()
	m.shader = WALL_SHADER
	m.set_shader_parameter("radius", xray_radius)
	m.set_shader_parameter("albedo_texture", load(KAYKIT_TEX))
	m.set_shader_parameter("use_texture", true)
	m.set_shader_parameter("use_uv", true)
	m.set_shader_parameter("texture_meters", 1.0)
	node.material_override = m


## Мебель и детали KayKit: палитра-текстура без размытия.
static func kaykit(node: MeshInstance3D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(KAYKIT_TEX)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	node.material_override = m

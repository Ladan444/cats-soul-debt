// Стены уровня: если стена стоит между камерой и Рэем, в ней прорезается «окно» вокруг линии взгляда,
// с пиксельной шахматной кромкой. Рэй не теряется за стенами коридоров, идущих к камере.
// Позицию Рэя (уровень груди) каждый кадр пишет скрипт уровня в глобальный параметр player_world_position.
shader_type spatial;

global uniform vec3 player_world_position;
uniform vec4 albedo : source_color = vec4(0.18, 0.2, 0.24, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform bool use_texture = false;
// Подкраска текстуры (светлее/темнее того же камня, например блоки арки моста).
uniform vec3 texture_tint = vec3(1.0);
// Обесцветить текстуру перед подкраской (0 — нет, 1 — полностью): так из рыжей черепицы получается сланец.
uniform float texture_desaturate = 0.0;
// Развёртка меша в метрах вместо проекции по миру (мост: свод арки, брёвна — без перескоков проекции).
uniform bool use_uv = false;
// Нижняя полоса стены — мох и подтёки (до moss_line метров по миру); пусто — без неё.
uniform sampler2D moss_texture : source_color, filter_nearest, repeat_enable;
uniform bool use_moss = false;
uniform float moss_line = 0.9;
// Тайл 128 пикселей = 3,2 м (40 пикселей на метр, как у спрайтов).
uniform float texture_meters = 3.2;
// Цвет вершин из Blender (умножается на albedo) — для мешей мира вокруг Брода, где цвет задан в вершинах.
uniform bool use_vertex_color = false;
// > 0 — текстура как детализация поверх цвета (яркость текстуры / её средняя яркость), а не вместо него.
uniform float detail_mean = 0.0;
uniform float detail_strength = 0.8;
uniform float radius = 1.8;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 v_color;

void vertex() {
	v_color = COLOR.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Мох и сырость поверх той же кладки (ряды камней не сбиваются): из текстуры мха берутся только
// зелёные пиксели, плотность падает кверху. Граница — рваная, по клеткам пикселей текстуры
// (40 на метр) с шумом и упорядоченным дизерингом, без прямой линии.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

vec3 mossy(vec3 base, vec2 uv) {
	vec2 cell = floor(uv * 40.0);          // клетка-пиксель текстуры
	float y = (cell.y + 0.5) / 40.0;       // высота по пикселям, не по фрагментам
	// Крупный шум (клетки 6 пикселей) — «языки» мха разной высоты.
	float blob = hash(floor(cell / 6.0)) * 0.5 + hash(floor(cell / 3.0)) * 0.25;
	float t = clamp((moss_line + 0.35 - y) / 0.7 + blob - 0.35, 0.0, 1.0);
	vec3 moss = texture(moss_texture, uv / texture_meters).rgb;
	float green = moss.g - max(moss.r, moss.b);
	vec3 color = base;
	if (green > 0.005 && t > bayer4(cell)) {
		color = moss;
	}
	// Сырость: темнее у пола, ступенями по 3 уровня (пиксельно, без плавного градиента).
	float wet = floor(clamp((moss_line + 0.6 - y) / 1.2, 0.0, 1.0) * 3.0 + bayer4(cell) * 0.99) / 3.0;
	return color * (1.0 - 0.22 * wet);
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_player = player_world_position - cam;
	float len = length(to_player);
	vec3 dir = to_player / max(len, 0.001);
	float along = dot(world_pos - cam, dir);
	// Ниже колен Рэя (позиция — уровень груди, 0,8 м над ногами) ничто его не закрывает — не резать
	// (иначе окно дырявит настил моста и низкие бордюры у него под ногами).
	bool above_feet = world_pos.y > player_world_position.y - 0.5;
	if (above_feet && along > 0.0 && along < len - 0.6) {
		float dist = length(world_pos - cam - dir * along);
		// Окно шире у Рэя, уже у камеры; кромка — шахматкой.
		float r = radius * clamp(along / len, 0.35, 1.0);
		if (dist < r) {
			bool checker = mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 1.0;
			if (dist < r - 0.35 || checker) {
				discard;
			}
		}
	}
	vec3 color = use_vertex_color ? v_color * albedo.rgb : albedo.rgb;
	if (use_texture) {
		// Трипланарно по миру: на стенах — по оси, к которой стена обращена.
		vec3 n = abs(world_normal);
		vec2 uv = n.x > n.z ? world_pos.zy : world_pos.xy;
		if (n.y > 0.7) {
			uv = world_pos.xz;
		}
		if (use_uv) {
			uv = UV;
		}
		vec3 tex = texture(albedo_texture, uv / texture_meters).rgb;
		float lum = dot(tex, vec3(0.3, 0.55, 0.15));
		if (detail_mean > 0.0) {
			color *= mix(1.0, clamp(lum / detail_mean, 0.5, 1.6), detail_strength) * texture_tint;
		} else {
			color = mix(tex, vec3(lum), texture_desaturate) * texture_tint;
		}
		if (use_moss) {
			color = mossy(color, uv);
		}
	}
	ALBEDO = color;
	ROUGHNESS = 0.9;
}

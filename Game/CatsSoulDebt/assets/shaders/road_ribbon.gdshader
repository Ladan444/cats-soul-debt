// Дороги-ленты мира вокруг Брода (Tools/blender/build_world.py, меш Roads): цвет профиля — в вершинах
// (обочина, колеи, травяная полоса, у тракта — камень на грань), пиксельная текстура дороги — детализацией
// по развёртке ленты: UV.y — метры вдоль дороги, UV.x — 0…1 поперёк. Колеи текстуры идут вдоль её оси u,
// поэтому u берётся вдоль дороги. Края ленты растворяются в траве по клеткам-пикселям (40 на метр) с
// упорядоченным дизерингом и шумом — без прямой линии (под лентой земля уже подкрашена дорогой).
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D road_texture : source_color, filter_nearest, repeat_enable;
uniform float texture_meters = 6.4;
// Ширина ленты в метрах для поперечной оси текстуры (у тракта 5,6, у троп меньше — берём среднее).
uniform float across_meters = 4.0;
// Средняя яркость текстуры (считает скрипт уровня) и сила детализации.
uniform float detail_mean = 0.3;
uniform float detail_strength = 0.75;
// Доля полуширины ленты, на которой край растворяется (замечание автора 2026-10-29: переход мягче).
uniform float edge_fade = 0.7;
// Оттенок как у подложки (замечание автора 2026-10-29): у края лента берёт ту же текстуру в тех же мировых
// координатах, что и шейдер рельефа terrain_splat, к середине — свою (колеи вдоль дороги); профиль из Blender
// только слегка меняет тон относительно среднего цвета дороги. Мощёный тракт (серые цвета) — как раньше.
uniform vec3 profile_ref = vec3(0.48, 0.41, 0.27);
uniform float profile_strength = 0.7;
uniform float terrain_meters = 6.4;          // как texture_meters у terrain_splat
uniform vec3 cloud_shadow = vec3(0.78, 0.8, 0.88);
// Насколько край «гуляет» по крупному шуму (языки травы на дороге и дороги в траве), в долях полуширины.
uniform float edge_wobble = 0.55;

varying vec3 v_color;
varying vec3 world_pos;

void vertex() {
	v_color = COLOR.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[x + y * 4]) + 0.5) / 16.0;
}

void fragment() {
	vec2 cell = floor(world_pos.xz * 40.0);
	float edge = min(UV.x, 1.0 - UV.x) * 2.0;           // 0 — край, 1 — середина
	// Граница гуляет: крупный шум (~1,5 м) и мелкий (~0,4 м), отдельно для каждой стороны ленты.
	vec2 q = world_pos.xz + (UV.x < 0.5 ? vec2(0.0) : vec2(37.0, 11.0));
	float wob = vnoise(q * 0.65) * 0.7 + vnoise(q * 2.5) * 0.3;
	float t = (edge - (wob - 0.35) * edge_wobble) / edge_fade;
	float ragged = bayer4(cell) * 0.6 + hash(floor(cell / 4.0)) * 0.4;
	if (t < ragged) {
		discard;
	}
	vec2 uv = vec2(UV.y, UV.x * across_meters) / texture_meters;
	vec3 tex = texture(road_texture, uv).rgb;
	float lum = dot(tex, vec3(0.3, 0.55, 0.15));
	vec3 col;
	float sat = max(v_color.r, max(v_color.g, v_color.b)) - min(v_color.r, min(v_color.g, v_color.b));
	if (sat < 0.08) {
		col = v_color * mix(1.0, clamp(lum / detail_mean, 0.5, 1.6), detail_strength);   // мощёный тракт
	} else {
		vec3 prof = mix(vec3(1.0), clamp(v_color / profile_ref, vec3(0.6), vec3(1.4)), profile_strength);
		vec3 tex_world = texture(road_texture, world_pos.xz / terrain_meters).rgb;
		col = smoothstep(0.4, 1.8, t) > bayer4(cell) ? tex * prof : tex_world;
	}
	// Тени облаков — те же, что у рельефа (иначе под облаком лента светлее подложки).
	vec2 cp = vec2(world_pos.x, -world_pos.z) * 0.018 + vec2(TIME * 0.012, TIME * 0.004);
	vec2 ci = floor(cp);
	vec2 cf = fract(cp);
	cf = cf * cf * (3.0 - 2.0 * cf);
	float cloud = mix(mix(hash(ci), hash(ci + vec2(1, 0)), cf.x), mix(hash(ci + vec2(0, 1)), hash(ci + vec2(1, 1)), cf.x), cf.y);
	if (smoothstep(0.58, 0.72, cloud) > bayer4(cell)) {
		col *= cloud_shadow;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}

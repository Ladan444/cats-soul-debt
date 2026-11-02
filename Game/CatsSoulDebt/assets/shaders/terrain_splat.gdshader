// Земля Ивового Брода: пиксельные текстуры (40 пикселей на метр) по карте смешивания из Blender
// (Tools/blender/build_village.py → splat_a/splat_b, 1 пиксель = 1 м). Слои не смешиваются полупрозрачно:
// на границе текстура меняется по клеткам-пикселям с упорядоченным дизерингом и шумом, как мох на стенах.
// На кручах — проекция по оси, к которой склон обращён (скала не растягивается).
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D splat_a : filter_linear, repeat_disable; // R дорога, G сухая трава, B скала, A пашня
uniform sampler2D splat_b : filter_linear, repeat_disable; // R брусчатка, G галька, B тёмное ущелье, A тень леса
uniform sampler2D splat_c : filter_linear, repeat_disable; // R дорога вдоль z (колеи вдоль неё), G дно под водой, B снег
uniform vec2 splat_origin = vec2(-150.0, -140.0);          // Blender (x, y) первого пикселя
uniform vec2 splat_size = vec2(281.0, 291.0);
uniform float splat_step = 1.0;                             // метров на пиксель карты (у мира вокруг Брода — 2)
// Снег на вершинах (канал C.b; у деревни его нет): цвет с пиксельным шумом.
uniform vec3 snow_color = vec3(0.88, 0.9, 0.95);

uniform sampler2D tex_grass : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_dry : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_road : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_cobble : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_soil : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_pebbles : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_pebbles_small : source_color, filter_nearest, repeat_enable;
// Дно под водой: мелкая галька (48 пикселей = 1,2 м) и холодное затемнение.
uniform float pebbles_small_meters = 1.2;
uniform vec3 underwater_tint = vec3(0.7, 0.8, 0.84);
// Тени облаков (плывут по земле).
uniform vec3 cloud_shadow = vec3(0.78, 0.8, 0.88);
// Плитка 256 пикселей = 6,4 м; галька — 96 пикселей = 2,4 м.
uniform float texture_meters = 6.4;
uniform float pebbles_meters = 2.4;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[x + y * 4]) + 0.5) / 16.0;
}

void fragment() {
	// Мировые координаты Godot (x, z) → Blender (x, y = −z) → пиксель карты.
	vec2 bl = vec2(world_pos.x, -world_pos.z);
	vec2 suv = ((bl - splat_origin) / splat_step + 0.5) / splat_size;
	vec4 a = texture(splat_a, suv);
	vec4 b = texture(splat_b, suv);
	vec4 c3 = texture(splat_c, suv);
	// Проекция текстуры — по ближайшей оси нормали (на берегах и кручах не растягивается больше чем в 1,4 раза).
	vec3 n = abs(world_normal);
	vec2 uv = world_pos.xz;
	if (n.x > n.y && n.x >= n.z) {
		uv = world_pos.zy;
	} else if (n.z > n.y && n.z > n.x) {
		uv = world_pos.xy;
	}
	vec2 tuv = uv / texture_meters;
	// Дорога вдоль z — текстура повёрнута на 90°, колеи идут вдоль дороги, а не поперёк.
	vec2 road_uv = c3.r > 0.5 ? tuv.yx : tuv;
	// Порог для слоя — по клетке-пикселю текстуры (40 на метр): дизеринг + крупный шум, граница рваная.
	vec2 cell = floor(uv * 40.0);
	float th = bayer4(cell) * 0.6 + hash(floor(cell / 5.0)) * 0.4;
	vec3 c = texture(tex_grass, tuv).rgb;
	if (a.g > th) c = texture(tex_dry, tuv).rgb;
	// Тень леса — темнее и холоднее подстилка (ступенями, без плавного градиента).
	c *= mix(vec3(1.0), vec3(0.62, 0.7, 0.62), step(th, b.a));
	if (a.a > th) c = texture(tex_soil, tuv).rgb;
	if (a.r > th) c = texture(tex_road, road_uv).rgb;
	if (b.r > th) c = texture(tex_cobble, tuv).rgb;
	if (b.g > th) c = texture(tex_pebbles, uv / pebbles_meters).rgb;
	if (c3.g > th) c = texture(tex_pebbles_small, uv / pebbles_small_meters).rgb * underwater_tint;
	if (a.b > th) c = texture(tex_rock, tuv).rgb;
	if (b.b > th) c *= vec3(0.55, 0.58, 0.66);
	if (c3.b > th) c = snow_color * (0.92 + 0.08 * hash(cell));
	// Тени облаков: крупные пятна плывут по ветру; край — дизерингом по клеткам-пикселям.
	vec2 cp = bl * 0.018 + vec2(TIME * 0.012, TIME * 0.004);
	vec2 ci = floor(cp);
	vec2 cf = fract(cp);
	cf = cf * cf * (3.0 - 2.0 * cf);
	float cloud = mix(mix(hash(ci), hash(ci + vec2(1, 0)), cf.x), mix(hash(ci + vec2(0, 1)), hash(ci + vec2(1, 1)), cf.x), cf.y);
	float shade_amt = smoothstep(0.58, 0.72, cloud);
	if (shade_amt > bayer4(cell)) {
		c *= cloud_shadow;
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
}

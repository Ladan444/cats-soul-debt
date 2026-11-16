// Растительность из пака (деревья, кусты, трава, камни) — пиксельные текстуры 40 пикселей на метр,
// листья вырезаются по альфе, обе стороны. Если крона между камерой и Рэем, в ней открывается окно
// с мягким краем: листва редеет дизерингом (по просьбе автора — не резкий круг, как у стен). Лёгкий ветер — для травы и крон (sway).
// Яркость экземпляра — INSTANCE_CUSTOM.r (MultiMesh), чтобы одинаковые деревья не выглядели клонами.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

global uniform vec3 player_world_position;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.5;
uniform bool xray = true;
// Окно: внешний радиус и ширина мягкого края (внутри radius − soft_edge листвы нет совсем).
uniform float radius = 3.0;
uniform float soft_edge = 1.5;
// Амплитуда ветра на метр высоты от основания модели.
uniform float sway = 0.0;
// Листва у самой камеры растворяется (ближе near_fade_from — нет совсем, дальше near_fade_to — целая; доли расстояния
// камера—Рэй). Иначе кроны перед камерой закрывают полэкрана и всё, что на земле. 0 — выключено.
uniform float near_fade_from = 0.0;
uniform float near_fade_to = 0.0;
// Плоскости травы и папоротника: нормаль тянется вверх, чтобы освещались как земля, а не темнели от низкого угла к солнцу.
uniform float up_normal = 0.0;

varying vec3 world_pos;
varying float shade;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[x + y * 4]) + 0.5) / 16.0;
}

void vertex() {
	shade = INSTANCE_CUSTOM.r > 0.0 ? INSTANCE_CUSTOM.r : 1.0;
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (sway > 0.0) {
		float k = max(VERTEX.y, 0.0) * sway;
		float t = TIME * 1.4 + origin.x * 0.31 + origin.z * 0.17;
		VERTEX.x += sin(t) * k;
		VERTEX.z += cos(t * 0.8) * k * 0.6;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	if (tex.a < alpha_cut) {
		discard;
	}
	// Тень от солнца считается ортографической камерой (у игровой — перспектива): в тени окна нет,
	// иначе под кроной на земле — дырявый ореол.
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	if (xray && !shadow_pass) {
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 to_player = player_world_position - cam;
		float len = length(to_player);
		vec3 dir = to_player / max(len, 0.001);
		float along = dot(world_pos - cam, dir);
		if (near_fade_to > 0.0 && smoothstep(near_fade_from * len, near_fade_to * len, along) < bayer4(floor(FRAGCOORD.xy / 2.0))) {
			discard;
		}
		if (along > 0.0 && along < len - 0.6) {
			float dist = length(world_pos - cam - dir * along);
			float r = radius * clamp(along / len, 0.35, 1.0);
			// Мягкий край: листва редеет к центру окна упорядоченным дизерингом (пиксельно, без полупрозрачности).
			float keep = smoothstep(r - soft_edge, r, dist);
			// Клетки дизеринга — по 2 пикселя экрана, чтобы узор читался как пиксель-арт, а не как шум.
			if (keep < bayer4(floor(FRAGCOORD.xy / 2.0))) {
				discard;
			}
		}
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	if (up_normal > 0.0) {
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, up_normal));
	}
	ALBEDO = tex.rgb * tint.rgb * shade;
	ROUGHNESS = 0.95;
}

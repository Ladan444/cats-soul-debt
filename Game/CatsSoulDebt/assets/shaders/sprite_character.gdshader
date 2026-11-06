// Персонажи и враги (Sprite3D): то же, что встроенный материал спрайта (билборд по Y, освещение,
// отсечение прозрачности, пиксели без сглаживания), плюс вспышка попадания и «призрачность».
// Встроенный modulate у Sprite3D не поднимается выше 1 — белой вспышки им не сделать.
// Текстуру листа передаёт CombatFX.setup_sprite (и обновляет при смене листа).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest;
// 0..1: насколько спрайт залит цветом вспышки (белый — попадание, красный — урон по Рэю).
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
// 0..1: призрачность — шахматное прореживание и холодный оттенок («Призрачный шаг»).
uniform float ghost : hint_range(0.0, 1.0) = 0.0;
// Собственный свет спрайта: персонаж читается и в тёмных зонах (Рубеж), не сливаясь с фоном.
uniform float self_light : hint_range(0.0, 1.0) = 0.22;
// 0..1: контур по краю силуэта — для тёмных спрайтов на тёмном полу (Утопший солдат). 0 — выключен.
uniform float rim : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(0.5, 0.62, 0.8, 1.0);

void vertex() {
	// Билборд по оси Y, как у Sprite3D.billboard = Y.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 tex = texture(sprite_texture, UV);
	vec3 color = tex.rgb * COLOR.rgb;
	if (ghost > 0.0) {
		if (mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 1.0) {
			discard;
		}
		color = mix(color, vec3(0.6, 0.95, 1.0), 0.5 * ghost);
	}
	float edge = 0.0;
	if (rim > 0.0) {
		// Непрозрачный пиксель с прозрачным соседом — край силуэта.
		vec2 t = 1.0 / vec2(textureSize(sprite_texture, 0));
		float n = min(min(texture(sprite_texture, UV + vec2(t.x, 0.0)).a, texture(sprite_texture, UV - vec2(t.x, 0.0)).a),
			min(texture(sprite_texture, UV + vec2(0.0, t.y)).a, texture(sprite_texture, UV - vec2(0.0, t.y)).a));
		edge = n < 0.5 ? rim : 0.0;
		color = mix(color, rim_color.rgb, edge);
	}
	ALBEDO = mix(color, flash_color.rgb, flash);
	// Вспышка светится сама — видна и в тёмном Рубеже.
	EMISSION = flash_color.rgb * flash * 1.5 + color * self_light + rim_color.rgb * edge * 0.5;
	ALPHA = tex.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

// Вода реки: пиксельная рябь, бегущая по течению, блики солнца отдельными пикселями, светлая кромка у берега.
// Течение — к ущелью (Godot −z). Клетки — 40 на метр (как вся пиксельная графика), по ним квантуется всё.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec4 deep_color : source_color = vec4(0.13, 0.30, 0.42, 0.78);
uniform vec4 light_color : source_color = vec4(0.30, 0.52, 0.62, 0.78);
uniform vec4 sparkle_color : source_color = vec4(1.0, 0.97, 0.86, 1.0);
uniform vec2 flow = vec2(0.0, -0.45);       // м/с по (x, z)
uniform float edge_width = 0.6;             // светлая пена у берега, м
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 cell = floor(p * 20.0) / 20.0;          // клетки по 2 пикселя текстуры — рябь читается крупнее
	vec2 q = cell - flow * TIME;
	// Мелкая рябь: штрихи поперёк течения (вытянуты по x), бегут по течению.
	float r1 = vnoise(vec2(q.x * 3.0, q.y * 7.0));
	float r2 = vnoise(vec2(q.x * 5.0 + 3.1, q.y * 11.0 - TIME * 0.6));
	float ripple = r1 * 0.6 + r2 * 0.4;
	vec4 col = deep_color;
	// Светлые штрихи гребней — две ступени, без плавного градиента.
	if (ripple > 0.62) {
		col = mix(deep_color, light_color, 0.55);
	}
	if (ripple > 0.74) {
		col = light_color;
	}
	// Блики: редкие пиксели гребней ряби, мерцают.
	vec2 sc = floor(p * 40.0);
	float tw = hash(sc + floor(TIME * 3.0 + hash(sc) * 7.0));
	if (ripple > 0.7 && tw > 0.9) {
		col = sparkle_color;
	}
	// Светлая кромка у берега: где под водой близко дно (по буферу глубины).
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float thickness = -view.z - (-VERTEX.z);
	float foam = 1.0 - smoothstep(0.0, edge_width, thickness);
	float foam_px = step(hash(sc + floor(TIME * 2.0)) * 0.6 + 0.4, foam);
	col = mix(col, vec4(0.80, 0.88, 0.86, 0.9), foam_px);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 0.15;
	METALLIC = 0.1;
	SPECULAR = 0.6;
}

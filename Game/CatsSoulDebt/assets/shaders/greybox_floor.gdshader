// Пол уровня: пиксельная текстура по миру (40 пикселей на метр, тайл 128 = 3,2 м).
// Без текстуры — сетка серых блоков: тонкие линии каждый метр, яркие каждые 4 м.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.3, 0.32, 0.36, 1.0);
uniform vec4 line_color : source_color = vec4(0.22, 0.24, 0.28, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform bool use_texture = false;
uniform float texture_meters = 3.2;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 color;
	if (use_texture) {
		color = texture(albedo_texture, p / texture_meters).rgb;
	} else {
		vec2 m1 = abs(fract(p) - 0.5);
		vec2 m4 = abs(fract(p / 4.0) - 0.5) * 4.0;
		float line1 = step(0.47, max(m1.x, m1.y));
		float line4 = step(1.92, max(m4.x, m4.y));
		color = mix(albedo.rgb, line_color.rgb, max(line1 * 0.6, line4));
	}
	ALBEDO = color;
	ROUGHNESS = 0.95;
}

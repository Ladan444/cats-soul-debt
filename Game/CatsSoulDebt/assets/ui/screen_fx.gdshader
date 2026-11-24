shader_type canvas_item;
render_mode unshaded;
// Экранные эффекты (C06, C08): Y-tilt-shift «миниатюра», виньетка, зерно, хроматика и цветокор.
// Живёт на CanvasLayer 0 — ниже HUD, поэтому интерфейс не размывается и не зернится.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

// Y-tilt-shift: резкая полоса вокруг tilt_center, размытие к верху и низу кадра.
uniform float tilt_strength : hint_range(0.0, 1.0) = 0.0;
uniform float tilt_band : hint_range(0.05, 0.5) = 0.34;
uniform float tilt_center : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.0;
uniform float chroma_strength : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
// Цветокор (C09): тон, насыщенность, контраст, подъём теней.
uniform vec3 grade_tint = vec3(1.0);
uniform float grade_saturation = 1.0;
uniform float grade_contrast = 1.0;
uniform float grade_lift = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;

	// Хроматика: каналы чуть расходятся от центра кадра.
	if (chroma_strength > 0.001) {
		vec2 dir = uv - vec2(0.5);
		float k = chroma_strength * 0.008;
		col.r = texture(screen_tex, uv + dir * k).r;
		col.b = texture(screen_tex, uv - dir * k).b;
	}

	// Y-tilt-shift: девять выборок по вертикали, сила растёт к краям полосы.
	if (tilt_strength > 0.001) {
		float d = abs(uv.y - tilt_center);
		float f = smoothstep(tilt_band, tilt_band + 0.26, d);
		if (f > 0.001) {
			float radius = f * tilt_strength * 0.016;
			vec3 acc = col;
			float wsum = 1.0;
			for (int i = 1; i <= 4; i++) {
				float o = float(i) / 4.0;
				float w = 1.0 - o * 0.65;
				acc += texture(screen_tex, uv + vec2(0.0, radius * o)).rgb * w;
				acc += texture(screen_tex, uv - vec2(0.0, radius * o)).rgb * w;
				wsum += w * 2.0;
			}
			col = acc / wsum;
		}
	}

	col *= grade_tint;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, grade_saturation);
	col = (col - vec3(0.5)) * grade_contrast + vec3(0.5 + grade_lift);
	col = max(col, vec3(0.0));

	if (vignette_strength > 0.001) {
		vec2 v = (uv - vec2(0.5)) * vec2(1.0, 1.12);
		float edge = smoothstep(0.34, 0.78, length(v));
		col *= 1.0 - edge * vignette_strength * 0.7;
	}

	if (grain_strength > 0.001) {
		float n = hash(uv * vec2(1920.0, 1080.0) + vec2(time * 60.0, time * 37.0));
		col += (n - 0.5) * grain_strength * 0.16;
	}

	COLOR = vec4(col, 1.0);
}

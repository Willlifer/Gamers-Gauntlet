shader_type canvas_item;
// TourneyTile's surface (G27): one muted tint, slow diagonal brush streaks
// (two noise octaves stretched along the slant), darker toward the bottom,
// a faint sheen that sweeps across every few seconds. Restrained on purpose:
// the streaks move the eye, the colour stays quiet.

uniform vec4 tint : source_color = vec4(0.16, 0.2, 0.27, 1.0);
uniform float hover = 0.0;
uniform float flash = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * (0.035 + 0.05 * hover) + seed;
	// brush strokes run along the slant
	vec2 d = vec2(uv.x * 0.85 + uv.y * 0.6, uv.y - uv.x * 0.45);
	float n = noise(vec2(d.x * 1.4 + t, d.y * 11.0 + seed)) * 0.62
		+ noise(vec2(d.x * 3.6 - t * 1.6, d.y * 31.0)) * 0.38;
	float streak = smoothstep(0.5, 0.86, n);
	float dark = smoothstep(0.08, 0.32, 1.0 - n) * 0.25;
	vec3 col = tint.rgb * (1.12 - uv.y * 0.5);
	col = mix(col, col * 0.62, dark);
	col += mix(tint.rgb, vec3(1.0), 0.55) * streak * (0.16 + 0.12 * hover);
	// the sheen
	float s = fract(TIME / 6.5 + seed * 0.37) * 3.0 - 1.0;
	float band = 1.0 - smoothstep(0.0, 0.05, abs(uv.x + uv.y * 0.4 - s));
	col += vec3(band * (0.05 + 0.06 * hover));
	col += vec3(0.04 * hover + 0.35 * flash);
	COLOR = vec4(col, 1.0);
}

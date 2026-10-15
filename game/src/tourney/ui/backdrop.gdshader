shader_type canvas_item;
// TourneyBackdrop (G27): the circling map, pushed back behind the UI: a soft
// gaussian blur (defocus), a little colour taken out, an ink-blue grade, and
// a vignette. Strengths are uniforms for tuning by eye.

uniform float blur = 1.4;
uniform float keep_colour = 0.6;
uniform float grade = 0.32;
uniform float bright = 0.78;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur;
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float k = exp(-float(x * x + y * y) / 4.5);
			c += texture(TEXTURE, UV + vec2(float(x), float(y)) * px).rgb * k;
			w += k;
		}
	}
	c /= w;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, keep_colour);
	c = mix(c, vec3(0.04, 0.06, 0.1), grade);
	c *= bright;
	vec2 q = UV - 0.5;
	c *= clamp(1.0 - dot(q, q) * 1.5, 0.0, 1.0);
	COLOR = vec4(c, 1.0);
}

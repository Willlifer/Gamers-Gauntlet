// MOBA boulders (MobaView._rock): smooth-shaded stone, with moss on whatever
// faces the sky (world normal, broken by noise), so every rock in a cluster
// mosses the same way however it is turned. `shade` darkens one rock.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 stone : source_color = vec3(0.47, 0.45, 0.41);
uniform vec3 moss : source_color = vec3(0.24, 0.33, 0.15);
instance uniform float shade = 1.0;

varying vec3 wn;
varying vec3 wp;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(wp * 2.2);
	float m = smoothstep(0.45, 0.75, wn.y + (n - 0.5) * 0.5);
	vec3 st = stone * (0.82 + 0.3 * vnoise(wp * 5.0)) * shade;
	st *= mix(0.75, 1.0, smoothstep(-0.6, 0.4, wn.y));       // undersides darker
	ALBEDO = mix(st, moss * (0.8 + 0.4 * n), m);
	ROUGHNESS = 1.0;
}

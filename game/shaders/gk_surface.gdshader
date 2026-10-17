// Gauntlet Kit surfaces (GKMaterials), opaque: the patterns and the relief
// live in gk_surface.gdshaderinc (shared with gk_surface_clear.gdshader).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/gk_surface.gdshaderinc"

void vertex() {
	if (world) {
		P = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		N = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	} else {
		P = VERTEX;
		N = NORMAL;
	}
}

void fragment() {
	vec3 c;
	float r;
	float m;
	float hgt;
	gk_surface(P, normalize(N), c, r, m, hgt);
	NORMAL = gk_bump(VERTEX, NORMAL, hgt);
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
	SPECULAR = spec;
}

// Gauntlet Kit surfaces (GKMaterials), see-through (G61): smoked polymer
// magazines, lenses. The same patterns as gk_surface.gdshader; `alpha` is
// the face-on transparency, the edges go opaque (fresnel), so a magazine's
// rounds and ribs show through its front wall. Draws after the opaque parts
// and writes depth, so it sorts against the gun it sits in.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, blend_mix, depth_draw_always, depth_prepass_alpha;

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
	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
	SPECULAR = spec;
	ALPHA = clamp(mix(alpha, 1.0, grazing), 0.0, 1.0);
}

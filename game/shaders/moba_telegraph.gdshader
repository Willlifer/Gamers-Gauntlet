// MOBA telegraphs (MobaView), League's way: a bright crisp edge, a faint
// fill that thickens toward the rim, and an inner fill that grows to the
// edge as the blast comes due (`progress` 0..1). UV.x = radius 0..1 from the
// centre (discs: computed from UV; cones: the fan mesh writes it), UV.y =
// across the cone 0..1 (cones only, for the side edges).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 col : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform bool cone = false;
uniform float progress = 0.0;
uniform float edge_px = 0.035;       // the rim's width, as a share of the radius

void fragment() {
	float d;
	float side = 1.0;
	if (cone) {
		d = UV.x;
		side = min(UV.y, 1.0 - UV.y);
	} else {
		d = length(UV - 0.5) * 2.0;
	}
	if (d > 1.0) discard;
	float rim = smoothstep(1.0 - edge_px * 2.0, 1.0 - edge_px, d);
	if (cone) {
		rim = max(rim, 1.0 - smoothstep(0.0, edge_px * 0.6 / max(d, 0.05), side));
	}
	float fill = 0.16 + 0.2 * d * d;
	float inner = step(d, progress) * (0.18 + 0.12 * smoothstep(progress - 0.08, progress, d));
	float a = clamp(fill + inner + rim * 0.85, 0.0, 1.0);
	ALBEDO = mix(col.rgb * 0.55, col.rgb * 1.2 + 0.25, rim);   // dark fill, hot rim
	ALPHA = a * col.a;
}

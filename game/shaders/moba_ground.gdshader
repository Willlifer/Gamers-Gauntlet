// The MOBA ground (MobaView): one shader for the walkable stone and the
// grass and earth around it, in world space so meshes can be any shape.
//   paved (0..1 mask)  where the stone is: a rectangle (the lane, `lane`
//                      = half length, half width) or a disc (`disc` = radius)
//   tiles              flagstones in staggered rows, each its own tone, dark
//                      grout, worn lighter toward the middle, moss creeping
//                      in from the edges and along the grout
//   off the paving     grass with darker clumps and bare earth patches
// No textures: value noise only. Lit (the sun and the towers' lights).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec2 lane = vec2(22.0, 5.2);        // half extents of the paved lane (x, z)
uniform float disc = 0.0;                   // > 0: paved disc of this radius instead
uniform float tile = 0.7;                   // flagstone size
uniform vec3 stone_a : source_color = vec3(0.47, 0.47, 0.45);
uniform vec3 stone_b : source_color = vec3(0.36, 0.37, 0.38);
uniform vec3 grout : source_color = vec3(0.24, 0.23, 0.21);
uniform vec3 moss : source_color = vec3(0.25, 0.34, 0.16);
uniform vec3 grass_a : source_color = vec3(0.2, 0.33, 0.15);
uniform vec3 grass_b : source_color = vec3(0.11, 0.21, 0.1);
uniform vec3 earth : source_color = vec3(0.33, 0.27, 0.19);

varying vec3 wp;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);   // sin-free: no banding far from the origin
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float n = fbm(p * 0.35);
	// how far inside the paving (negative = outside), edges broken by noise
	float inside;
	if (disc > 0.0) {
		inside = disc - length(p);
	} else {
		vec2 d = lane - abs(p);
		inside = min(d.x, d.y);
	}
	inside += (n - 0.5) * 2.2 + (fbm(p * 1.3 + 3.0) - 0.5) * 0.9;
	float paved = smoothstep(-0.15, 0.25, inside);

	// flagstones: irregular cells (Voronoi), so they read as laid stone, not tile
	vec2 tp = p / tile;
	vec2 ip = floor(tp);
	vec2 fp = fract(tp);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 cell = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 c = o + 0.12 + 0.76 * vec2(hash(ip + o), hash(ip + o + 17.3));
			float dd = length(c - fp);
			if (dd < d1) {
				d2 = d1;
				d1 = dd;
				cell = ip + o;
			} else if (dd < d2) {
				d2 = dd;
			}
		}
	}
	float edge = (d2 - d1) * 0.5;
	float h = hash(cell);
	float gw = 0.02 + 0.015 * vnoise(p * 3.0);
	float g = 1.0 - smoothstep(gw, gw + 0.025, edge);
	vec3 st = mix(stone_a, stone_b, h);
	st *= 0.86 + 0.24 * vnoise(p * 2.2 + h * 9.0);
	st *= 0.8 + 0.36 * hash(cell + 3.1);                       // every stone its own shade
	st = mix(st, vec3(0.5, 0.45, 0.37), hash(cell + 5.3) * 0.4);  // some warmer
	st *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.12, edge));   // every stone's rim a touch darker (height AO)
	if (disc <= 0.0) {                                         // the trodden middle of the lane
		float worn = 1.0 - smoothstep(0.6, 2.6, abs(p.y + (vnoise(p * 0.3) - 0.5) * 1.2));
		st = mix(st, st * 1.14 + vec3(0.03, 0.02, 0.0), worn * 0.55);
	}
	// worn: lighter toward the middle of the paving, chips and stains
	st = mix(st, st * 1.12, smoothstep(1.0, 4.0, inside) * 0.6);
	st = mix(st, st * 0.72, smoothstep(0.62, 0.8, fbm(p * 1.3 + 4.0)) * 0.7);
	// cracks
	float cr = abs(vnoise(p * 1.7 + h * 13.0) - 0.5);
	st = mix(st, grout, (1.0 - smoothstep(0.0, 0.025, cr)) * 0.6 * step(0.55, h));
	vec3 pav = mix(st, grout, g * 0.6);
	// worn dirt down the busy middle (and the pit's outer ring): packed earth through the stone
	float dirt = smoothstep(0.58, 0.7, fbm(p * 0.45 + 21.0));
	if (disc > 0.0) {
		dirt = max(dirt, smoothstep(disc * 0.5, disc * 0.72, length(p) + (n - 0.5) * 2.0) * 0.85);
	}
	pav = mix(pav, earth * (0.85 + 0.3 * vnoise(p * 2.0)), dirt * 0.35);
	// moss: in the grout everywhere, over the stones near the edge
	float mz = smoothstep(2.2, 0.0, inside) * smoothstep(0.35, 0.65, fbm(p * 0.9 + 2.0));
	pav = mix(pav, moss * (0.8 + 0.4 * n), clamp(g * smoothstep(3.0, 0.5, inside) * 0.6 + mz * 0.75, 0.0, 1.0));

	// the ground off the paving
	float clump = fbm(p * 1.1 + 7.0);
	vec3 gr = mix(grass_b, grass_a, smoothstep(0.3, 0.7, clump));
	gr *= 0.85 + 0.3 * vnoise(p * 6.0);
	float bare = smoothstep(0.6, 0.72, fbm(p * 0.22 + 11.0));
	gr = mix(gr, earth * (0.8 + 0.3 * n), bare * 0.85);
	gr *= mix(0.8, 0.45, smoothstep(1.0, 16.0, -inside));       // the jungle darkens away from the lane

	ALBEDO = mix(gr, pav, paved);
	ROUGHNESS = 0.95;
}

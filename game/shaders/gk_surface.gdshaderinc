// Gauntlet Kit surfaces (GKMaterials): the one surface function behind
// gk_surface.gdshader (opaque) and gk_surface_clear.gdshader (see-through
// polymer, G61). Patterns are procedural in object space (items: the pattern
// rides with the gun) or world space (environments: pieces line up), so no
// textures are needed and every role is a handful of numbers.
//   0 plain      noise-mottled colour (rubber, glass, paint)
//   1 grain      wood: long streaks along `axis` with darker rings
//   2 plaster    blotchy render, chipped patches showing col_c, ground grime
//   3 blocks     dressed stone / brick courses (col_c = mortar)
//   4 cobble     Voronoi paving stones on the ground plane (col_c = joints)
//   5 siding     horizontal lap boards (shadow line under each lap)
//   6 membrane   flat-roof sheet: seams every `scale` m, patches, stains
//   7 stipple    moulded polymer: fine grit that breaks up the highlight
//   8 brushed    metal: fine streaks along `axis` (two octaves, G61)
//   9 asphalt    speckled tarmac with patches
//  10 grass      clumped lawn
//  11 concrete   cast panels with joints and stains
//  12 pavers     pale rectangular flagstones in running bond on the ground
//                plane, each its own size and tone, sand-coloured joints
//  13 checker    diamond checkering (grip panels): pyramids `scale` per metre
//  14 speckle    webbed stock: col_a/col_b mottle with col_c flecks
// `relief` (metres, G61) is the height of the pattern's grit, checkering or
// flecks; the main shader bends the normal by it (no tangents needed), and
// fades it out where a pixel covers more than a feature, so far guns stay
// clean. Vertex COLOR multiplies the result (GKMesh tints). `wear` lightens
// what faces up and darkens what faces down, a cheap stand-in for baked AO.

uniform vec3 col_a : source_color = vec3(0.5);
uniform vec3 col_b : source_color = vec3(0.4);
uniform vec3 col_c : source_color = vec3(0.3);
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform float spec = 0.5;
uniform int pat = 0;
uniform float scale = 1.0;
uniform float amt = 0.2;
uniform float wear = 0.0;
uniform float relief = 0.0;
uniform float alpha = 1.0;
uniform bool world = false;
uniform vec3 axis = vec3(0.0, 0.0, 1.0);

varying vec3 P;
varying vec3 N;

float h3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += vn(p) * a;
		p = p * 2.03 + 7.1;
		a *= 0.5;
	}
	return v;
}

// Voronoi on a plane: x = distance to the edge, y = cell id hash
vec2 voro(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 cell = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 c = o + 0.15 + 0.7 * vec2(h2(ip + o), h2(ip + o + 17.3));
			float dd = length(c - fp);
			if (dd < d1) { d2 = d1; d1 = dd; cell = ip + o; }
			else if (dd < d2) { d2 = dd; }
		}
	}
	return vec2((d2 - d1) * 0.5, h2(cell));
}

// the plane a wall pattern lies in: (along the wall, up)
vec2 wall_uv(vec3 p, vec3 n) {
	return abs(n.x) > abs(n.z) ? vec2(p.z, p.y) : vec2(p.x, p.y);
}

// the plane an item's face lies in, by its dominant normal axis
vec2 face_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	if (an.x >= an.y && an.x >= an.z) { return p.zy; }
	if (an.y >= an.z) { return p.xz; }
	return p.xy;
}

float tri(float x) {
	return 1.0 - 2.0 * abs(fract(x) - 0.5);
}

// The surface at P with normal n: colour, roughness, metallic and the
// pattern's height (metres) for the normal bend.
void gk_surface(vec3 p, vec3 n, out vec3 c, out float r, out float m, out float hgt) {
	c = col_a;
	r = rough;
	m = metal;
	hgt = 0.0;
	float big = fbm(p * scale * 0.25);
	if (pat == 0) {
		c = mix(col_a, col_b, smoothstep(0.3, 0.7, fbm(p * scale)) * amt * 2.0);
	} else if (pat == 1) {
		vec3 ax = normalize(axis);
		float along = dot(p, ax);
		vec3 perp = p - ax * along;
		// long streaks along the grain, fine dark lines, blotchy weathering
		float streak = fbm(perp * scale * 14.0 + ax * along * scale * 0.4);
		float fine = vn(perp * scale * 60.0 + ax * along * scale * 1.5);
		float g = smoothstep(0.3, 0.8, streak);
		c = mix(col_a, col_b, g);
		c *= 0.85 + 0.25 * fine;
		c = mix(c, col_c, smoothstep(0.55, 0.85, fbm(p * scale * 1.6 + 3.0)) * amt);   // dark mottling
		r = rough - 0.1 * g;
		hgt = (g - 0.5) * relief;
	} else if (pat == 2) {
		float bl = fbm(p * scale);
		c = mix(col_a, col_b, smoothstep(0.42, 0.78, bl) * 0.8);
		float stre = fbm(vec3(p.x * 6.0 * scale, p.y * 0.6 * scale, p.z * 6.0 * scale));
		c *= 1.0 - 0.12 * smoothstep(0.5, 0.8, stre);                          // run streaks
		// flaked patches: the render gone, the tan base coat showing, a darker rim
		float fl = fbm(p * scale * 0.7 + 13.0) + 0.1 * vn(p * scale * 9.0);
		float chip = smoothstep(0.68, 0.71, fl);
		float rim = smoothstep(0.655, 0.68, fl) - chip;
		c = mix(c, col_c * (0.9 + 0.2 * vn(p * scale * 6.0)), chip * amt * 2.0);
		c *= 1.0 - rim * 0.25 * amt * 2.0;
		c = mix(c, c * 0.82, smoothstep(0.55, 0.9, fbm(p * scale * 0.3 + 2.0)) * 0.6);   // big soft stains
		if (world) {
			c *= mix(0.72, 1.0, smoothstep(0.0, 1.4, p.y));                    // grime at the foot
		}
	} else if (pat == 3) {
		vec2 uv = abs(n.y) > 0.7 ? p.xz : wall_uv(p, n);
		vec2 b = uv / vec2(scale * 2.0, scale);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 id = floor(b);
		vec2 f = fract(b);
		float e = min(f.x * scale * 2.0, min((1.0 - f.x) * scale * 2.0, min(f.y * scale, (1.0 - f.y) * scale)));
		float mort = 1.0 - smoothstep(0.012, 0.03, e);
		vec3 st = mix(col_a, col_b, h2(id));
		st *= 0.86 + 0.24 * fbm(p * 3.0);
		st *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.08, e));                 // eroded arrises
		c = mix(st, col_c, mort);
		c = mix(c, c * 0.75, smoothstep(0.6, 0.8, big) * amt);
	} else if (pat == 4) {
		vec2 v = voro(p.xz / scale);
		float h = v.y;
		float g = 1.0 - smoothstep(0.03, 0.07, v.x);
		vec3 st = mix(col_a, col_b, h);
		st *= 0.84 + 0.3 * vn(p * 4.0 + h * 9.0);
		st *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.16, v.x));               // worn round tops
		c = mix(st, col_c, g);
		c = mix(c, c * 0.78, smoothstep(0.55, 0.78, big) * amt);             // grime pools
		r = mix(rough, 1.0, g);
	} else if (pat == 5) {
		float y = p.y / scale;
		float f = fract(y);
		c = col_a * (0.82 + 0.18 * smoothstep(0.0, 0.25, f));                // the lap's shadow line
		c = mix(c, col_b, smoothstep(0.55, 0.8, fbm(p * 1.3)) * amt);
	} else if (pat == 6) {
		vec2 uv = p.xz / scale;
		vec2 f = fract(uv);
		float seam = 1.0 - smoothstep(0.004, 0.012, min(f.x, 1.0 - f.x));
		c = mix(col_a, col_b, smoothstep(0.4, 0.8, fbm(p * 0.6)) * 0.7);
		c = mix(c, col_c, seam * 0.5);
		c = mix(c, col_b * 0.7, smoothstep(0.7, 0.85, fbm(p * 0.25 + 3.0)) * amt);   // ponding stains
	} else if (pat == 7) {
		float g = vn(p * scale);
		float g2 = vn(p * scale * 2.7 + 5.0);
		c = mix(col_a, col_b, smoothstep(0.2, 0.8, fbm(p * scale * 0.08)) * amt);
		r = rough + (g - 0.5) * 0.25;
		hgt = (g - 0.5 + (g2 - 0.5) * 0.5) * relief;
	} else if (pat == 8) {
		vec3 ax = normalize(axis);
		float along = dot(p, ax);
		vec3 perp = p - ax * along;
		// streaks: fine across the brushing, long along it, two octaves (no 3 mm cells)
		float s = vn(perp * scale * 2.5 + ax * along * scale * 0.015) * 0.6 + vn(perp * scale * 9.0 + ax * along * scale * 0.05 + 3.0) * 0.4;
		c = mix(col_a, col_b, s * amt * 2.0);
		r = rough + (s - 0.5) * 0.15;
	} else if (pat == 9) {
		float s = h3(floor(p * 90.0));
		c = mix(col_a, col_b, smoothstep(0.35, 0.75, fbm(p * scale)) * 0.6);
		c *= 0.88 + 0.24 * step(0.82, s);
		c = mix(c, col_c, smoothstep(0.62, 0.66, fbm(p * scale * 0.3 + 5.0)) * amt);
	} else if (pat == 10) {
		float cl = fbm(p * scale);
		c = mix(col_b, col_a, smoothstep(0.3, 0.7, cl));
		c *= 0.85 + 0.3 * vn(p * scale * 12.0);
		c = mix(c, col_c, smoothstep(0.62, 0.72, fbm(p * scale * 0.3 + 11.0)) * amt);
	} else if (pat == 11) {
		vec2 uv = abs(n.y) > 0.7 ? p.xz : wall_uv(p, n);
		vec2 f = fract(uv / scale);
		float j = 1.0 - smoothstep(0.004, 0.01, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		c = mix(col_a, col_b, smoothstep(0.35, 0.8, fbm(p * 0.8)) * 0.8);
		c = mix(c, col_c, j * 0.6);
		c = mix(c, c * 0.8, smoothstep(0.6, 0.8, big) * amt);
	} else if (pat == 12) {
		// rows along z, stones of three lengths, every row offset
		vec2 uv = p.xz / scale;
		float row = floor(uv.y);
		float rh = h2(vec2(row, 3.0));
		float x = uv.x * (0.45 + 0.45 * rh) + rh * 7.0 + 0.3 * vn(vec3(uv * 0.7, row));
		float id_x = floor(x);
		float fx = fract(x);
		float fy = fract(uv.y);
		vec2 id = vec2(id_x, row);
		float hs = h2(id);
		float e = min(min(fx, 1.0 - fx) / (0.55 + 0.3 * rh), min(fy, 1.0 - fy)) * scale;
		float joint = 1.0 - smoothstep(0.006, 0.016, e);
		vec3 st = mix(col_a, col_b, hs);
		st *= 0.82 + 0.3 * h2(id + 5.1);                                  // every flag its own shade
		st *= 0.9 + 0.16 * fbm(p * 4.0 + hs * 9.0);
		st *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.05, e));             // worn edges
		c = mix(st, col_c, joint * 0.45);
		c = mix(c, c * 0.84, smoothstep(0.55, 0.8, big) * amt);           // traffic grime
		c = mix(c, col_c * 0.9, smoothstep(0.6, 0.75, fbm(p * 0.9 + 6.0)) * 0.35);   // sand drifted over
		r = mix(rough, 1.0, joint);
	} else if (pat == 13) {
		// diamond checkering: pyramids on a lattice turned 45 degrees, `scale` per metre
		vec2 uv = face_uv(p, n) * scale;
		vec2 d = vec2(uv.x + uv.y, uv.x - uv.y) * 0.5;
		float pyr = min(tri(d.x), tri(d.y));
		c = mix(col_a * 0.78, col_a, pyr);                                  // dark in the grooves
		c = mix(c, col_b, smoothstep(0.3, 0.7, fbm(p * scale * 0.1)) * amt);
		r = rough + (1.0 - pyr) * 0.1;
		hgt = pyr * relief;
	} else if (pat == 14) {
		// webbed polymer stock: a two-tone mottle, light flecks of col_c and a few dark ones
		float g = fbm(p * scale * 0.35);
		c = mix(col_a, col_b, smoothstep(0.35, 0.7, g));
		float f1 = vn(p * scale * 1.0 + 9.0);
		float f2 = vn(p * scale * 1.9 + 21.0);
		float fleck = smoothstep(0.66, 0.74, f1) + smoothstep(0.7, 0.78, f2) * 0.7;
		c = mix(c, col_c, clamp(fleck, 0.0, 1.0) * amt);
		float dark = smoothstep(0.72, 0.8, vn(p * scale * 1.4 + 40.0));
		c = mix(c, col_b * 0.6, dark * amt * 0.6);
		r = rough + (vn(p * scale * 3.0) - 0.5) * 0.2;
		hgt = (clamp(fleck, 0.0, 1.0) * 0.6 + (vn(p * scale * 4.0) - 0.5) * 0.5) * relief;
	}
	if (wear > 0.0) {
		c *= mix(1.0 - wear * 0.35, 1.0 + wear * 0.12, n.y * 0.5 + 0.5);
	}
}

// The pattern's relief bent into the view-space normal from the height's
// screen derivatives (Mikkelsen's unparametrized bump mapping: no tangents),
// faded where a pixel spans more than one feature so distant parts stay clean.
vec3 gk_bump(vec3 vtx, vec3 nrm, float hgt) {
	if (relief <= 0.0) {
		return nrm;
	}
	vec3 sx = dFdx(vtx);
	vec3 sy = dFdy(vtx);
	float px = max(length(sx), length(sy)) * scale;
	float fade = 1.0 - smoothstep(0.25, 0.9, px);
	if (fade <= 0.0) {
		return nrm;
	}
	vec3 r1 = cross(sy, nrm);
	vec3 r2 = cross(nrm, sx);
	float det = dot(sx, r1);
	vec3 grad = sign(det) * (dFdx(hgt) * r1 + dFdy(hgt) * r2) * fade;
	return normalize(abs(det) * nrm - grad);
}

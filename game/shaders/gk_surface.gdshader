// Gauntlet Kit surfaces (GKMaterials): one lit shader for every kit material,
// switched by `pat`. Patterns are procedural in object space (items: the
// pattern rides with the gun) or world space (environments: pieces line up),
// so no textures are needed and every role is a handful of numbers.
//   0 plain      noise-mottled colour (rubber, glass, paint)
//   1 grain      wood: long streaks along `axis` with darker rings
//   2 plaster    blotchy render, chipped patches showing col_c, ground grime
//   3 blocks     dressed stone / brick courses (col_c = mortar)
//   4 cobble     Voronoi paving stones on the ground plane (col_c = joints)
//   5 siding     horizontal lap boards (shadow line under each lap)
//   6 membrane   flat-roof sheet: seams every `scale` m, patches, stains
//   7 stipple    moulded polymer: fine grit that breaks up the highlight
//   8 brushed    metal: fine streaks along `axis`
//   9 asphalt    speckled tarmac with patches
//  10 grass      clumped lawn
//  11 concrete   cast panels with joints and stains
//  12 pavers     pale rectangular flagstones in running bond on the ground
//                plane, each its own size and tone, sand-coloured joints
// Vertex COLOR multiplies the result (GKMesh tints). `wear` lightens what
// faces up and darkens what faces down, a cheap stand-in for baked AO.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

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
	vec3 c = col_a;
	float r = rough;
	float m = metal;
	vec3 n = normalize(N);
	float big = fbm(P * scale * 0.25);
	if (pat == 0) {
		c = mix(col_a, col_b, smoothstep(0.3, 0.7, fbm(P * scale)) * amt * 2.0);
	} else if (pat == 1) {
		vec3 ax = normalize(axis);
		float along = dot(P, ax);
		vec3 perp = P - ax * along;
		// long streaks along the grain, fine dark lines, blotchy weathering
		float streak = fbm(perp * scale * 14.0 + ax * along * scale * 0.4);
		float fine = vn(perp * scale * 60.0 + ax * along * scale * 1.5);
		float g = smoothstep(0.3, 0.8, streak);
		c = mix(col_a, col_b, g);
		c *= 0.85 + 0.25 * fine;
		c = mix(c, col_c, smoothstep(0.55, 0.85, fbm(P * scale * 1.6 + 3.0)) * amt);   // dark mottling
		r = rough - 0.1 * g;
	} else if (pat == 2) {
		float bl = fbm(P * scale);
		c = mix(col_a, col_b, smoothstep(0.42, 0.78, bl) * 0.8);
		float stre = fbm(vec3(P.x * 6.0 * scale, P.y * 0.6 * scale, P.z * 6.0 * scale));
		c *= 1.0 - 0.12 * smoothstep(0.5, 0.8, stre);                          // run streaks
		// flaked patches: the render gone, the tan base coat showing, a darker rim
		float fl = fbm(P * scale * 0.7 + 13.0) + 0.1 * vn(P * scale * 9.0);
		float chip = smoothstep(0.68, 0.71, fl);
		float rim = smoothstep(0.655, 0.68, fl) - chip;
		c = mix(c, col_c * (0.9 + 0.2 * vn(P * scale * 6.0)), chip * amt * 2.0);
		c *= 1.0 - rim * 0.25 * amt * 2.0;
		c = mix(c, c * 0.82, smoothstep(0.55, 0.9, fbm(P * scale * 0.3 + 2.0)) * 0.6);   // big soft stains
		if (world) {
			c *= mix(0.72, 1.0, smoothstep(0.0, 1.4, P.y));                    // grime at the foot
		}
	} else if (pat == 3) {
		vec2 uv = abs(n.y) > 0.7 ? P.xz : wall_uv(P, n);
		vec2 b = uv / vec2(scale * 2.0, scale);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 id = floor(b);
		vec2 f = fract(b);
		float e = min(f.x * scale * 2.0, min((1.0 - f.x) * scale * 2.0, min(f.y * scale, (1.0 - f.y) * scale)));
		float mort = 1.0 - smoothstep(0.012, 0.03, e);
		vec3 st = mix(col_a, col_b, h2(id));
		st *= 0.86 + 0.24 * fbm(P * 3.0);
		st *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.08, e));                 // eroded arrises
		c = mix(st, col_c, mort);
		c = mix(c, c * 0.75, smoothstep(0.6, 0.8, big) * amt);
	} else if (pat == 4) {
		vec2 v = voro(P.xz / scale);
		float h = v.y;
		float g = 1.0 - smoothstep(0.03, 0.07, v.x);
		vec3 st = mix(col_a, col_b, h);
		st *= 0.84 + 0.3 * vn(P * 4.0 + h * 9.0);
		st *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.16, v.x));               // worn round tops
		c = mix(st, col_c, g);
		c = mix(c, c * 0.78, smoothstep(0.55, 0.78, big) * amt);             // grime pools
		r = mix(rough, 1.0, g);
	} else if (pat == 5) {
		float y = P.y / scale;
		float f = fract(y);
		c = col_a * (0.82 + 0.18 * smoothstep(0.0, 0.25, f));                // the lap's shadow line
		c = mix(c, col_b, smoothstep(0.55, 0.8, fbm(P * 1.3)) * amt);
	} else if (pat == 6) {
		vec2 uv = P.xz / scale;
		vec2 f = fract(uv);
		float seam = 1.0 - smoothstep(0.004, 0.012, min(f.x, 1.0 - f.x));
		c = mix(col_a, col_b, smoothstep(0.4, 0.8, fbm(P * 0.6)) * 0.7);
		c = mix(c, col_c, seam * 0.5);
		c = mix(c, col_b * 0.7, smoothstep(0.7, 0.85, fbm(P * 0.25 + 3.0)) * amt);   // ponding stains
	} else if (pat == 7) {
		float g = vn(P * scale);
		c = mix(col_a, col_b, smoothstep(0.2, 0.8, fbm(P * scale * 0.08)) * amt);
		r = rough + (g - 0.5) * 0.25;
	} else if (pat == 8) {
		vec3 ax = normalize(axis);
		float along = dot(P, ax);
		vec3 perp = P - ax * along;
		float s = vn(perp * scale + ax * along * scale * 0.02);
		c = mix(col_a, col_b, s * amt * 2.0);
		r = rough + (s - 0.5) * 0.15;
	} else if (pat == 9) {
		float s = h3(floor(P * 90.0));
		c = mix(col_a, col_b, smoothstep(0.35, 0.75, fbm(P * scale)) * 0.6);
		c *= 0.88 + 0.24 * step(0.82, s);
		c = mix(c, col_c, smoothstep(0.62, 0.66, fbm(P * scale * 0.3 + 5.0)) * amt);
	} else if (pat == 10) {
		float cl = fbm(P * scale);
		c = mix(col_b, col_a, smoothstep(0.3, 0.7, cl));
		c *= 0.85 + 0.3 * vn(P * scale * 12.0);
		c = mix(c, col_c, smoothstep(0.62, 0.72, fbm(P * scale * 0.3 + 11.0)) * amt);
	} else if (pat == 11) {
		vec2 uv = abs(n.y) > 0.7 ? P.xz : wall_uv(P, n);
		vec2 f = fract(uv / scale);
		float j = 1.0 - smoothstep(0.004, 0.01, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		c = mix(col_a, col_b, smoothstep(0.35, 0.8, fbm(P * 0.8)) * 0.8);
		c = mix(c, col_c, j * 0.6);
		c = mix(c, c * 0.8, smoothstep(0.6, 0.8, big) * amt);
	}
	if (pat == 12) {
		// rows along z, stones of three lengths, every row offset
		vec2 uv = P.xz / scale;
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
		st *= 0.9 + 0.16 * fbm(P * 4.0 + hs * 9.0);
		st *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.05, e));             // worn edges
		c = mix(st, col_c, joint * 0.45);
		c = mix(c, c * 0.84, smoothstep(0.55, 0.8, big) * amt);           // traffic grime
		c = mix(c, col_c * 0.9, smoothstep(0.6, 0.75, fbm(P * 0.9 + 6.0)) * 0.35);   // sand drifted over
		r = mix(rough, 1.0, joint);
	}
	if (wear > 0.0) {
		c *= mix(1.0 - wear * 0.35, 1.0 + wear * 0.12, n.y * 0.5 + 0.5);
	}
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
	SPECULAR = spec;
}

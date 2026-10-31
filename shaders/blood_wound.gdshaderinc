// Gunshot wounds at arm's length (blood-gore-2, docs/HANDOFF.md "Blood and gore at arm's length"),
// included by character.gdshader after its wound_* uniforms and stain_noise(). Each of the four
// stains Ragdoll._place_stain() books can carry a HOLE (wound_holes, its radius in skeleton units:
// an entry is a punched hole in a dark abraded ring, an exit a bigger ragged tear, 0 a stump's
// soak with no hole) and a RUN (wound_dir_i.w, its length in skeleton units): blood that left the
// hole and ran down the body the way gravity pulls (wound_down, skeleton space, set every frame
// while it creeps) over the side the hole is on (wound_dir_i.xyz, its outward normal: a run on
// the chest of somebody lying on their back runs round the ribs, not through them to the back).
// Fresh blood is glossy (wet in the soak's inner half), the hole a dark wet crater lit by its own
// normal (wb_bump()). wound_gore 0 (BLOOD_GORE_2=0) is the old soak alone.

uniform float wound_gore = 0.0;
uniform vec4 wound_holes = vec4(0.0);
uniform vec4 wound_dir_0 = vec4(0.0);
uniform vec4 wound_dir_1 = vec4(0.0);
uniform vec4 wound_dir_2 = vec4(0.0);
uniform vec4 wound_dir_3 = vec4(0.0);
uniform vec3 wound_down = vec3(0.0, -1.0, 0.0);
// Skeleton units per metre (the crowd rigs are centimetres under a 0.01 armature).
uniform float wound_unit = 100.0;

// The posed vertex normal in skeleton space (set in vertex()).
varying vec3 v_skel_n;


// One wound at `p` (skeleton space) with the surface facing `n`: x the hole (0..1), y the abraded
// ring round it, z fresh wet blood, w the run below it. `w` is wound_i (centre, soak radius),
// `hr` the hole radius, `wd` wound_dir_i (outward normal, run length), all skeleton units.
vec4 wb_one(vec4 w, float hr, vec4 wd, vec3 p, vec3 n) {
	if (w.w <= 0.0) {
		return vec4(0.0);
	}
	vec3 q = p - w.xyz;
	float d3 = length(q);
	vec4 o = vec4(0.0);
	// Wet over the soak's inner half, drying (rougher, darker) toward its edge.
	o.z = 1.0 - smoothstep(w.w * 0.22, w.w * 0.62, d3 + (stain_noise(p * 0.3) - 0.5) * w.w * 0.4);
	if (dot(wd.xyz, wd.xyz) < 0.01) {
		return o;
	}
	// The hole and the run are drawn like a decal projected along the hole's normal: the stain's
	// centre is inside the body (the round's path), and the skin is wherever the line through it
	// comes out on the hole's side. `h` is height along the normal, `t` the offset across it.
	vec3 wn = normalize(wd.xyz);
	float h = dot(q, wn);
	vec3 t = q - wn * h;
	float side = smoothstep(-0.25, 0.35, dot(normalize(n), wn)) * smoothstep(-0.05 * wound_unit, -0.01 * wound_unit, h)
		* (1.0 - smoothstep(0.16 * wound_unit, 0.24 * wound_unit, h));
	if (side <= 0.0) {
		return o;
	}
	float d = length(t);
	if (hr > 0.0 && d < hr * 3.2) {
		// Ragged outline: two octaves of the stain noise at about the hole's own size.
		float k = 1.6 / max(hr, 0.05);
		float nz = stain_noise(p * k) * 0.6 + stain_noise(p * k * 2.7 + 7.0) * 0.4;
		float dd = d + (nz - 0.5) * hr * 0.7;
		o.x = (1.0 - smoothstep(hr * 0.62, hr * 1.0, dd)) * side;
		o.y = (1.0 - smoothstep(hr * 1.05, hr * 2.5, dd + (stain_noise(p * k * 0.8 + 3.0) - 0.5) * hr * 0.9)) * side;
	}
	// The run: from the hole down the way gravity pulls across the skin, a ribbon that narrows
	// and wanders. None when gravity points straight into the hole (it pools there instead).
	vec3 g = normalize(wound_down);
	vec3 gp = g - wn * dot(g, wn);
	float glen = length(gp);
	if (wd.w > 0.0 && glen > 0.25) {
		gp /= glen;
		float along = dot(t, gp);
		if (along > -hr && along < wd.w) {
			float tt = clamp(along / max(wd.w, 0.001), 0.0, 1.0);
			float wob = (stain_noise(vec3(along * 0.35, w.x * 0.1, w.z * 0.1)) - 0.5) * max(hr, 0.006 * wound_unit) * 2.4;
			float width = mix(max(hr * 1.1, 0.012 * wound_unit), 0.004 * wound_unit, tt * tt);
			float off = dot(t, cross(wn, gp)) - wob * tt;
			// The tip is a bead of blood that has not got there yet.
			float tip = 1.0 - smoothstep(wd.w * 0.9, wd.w, along);
			o.w = (1.0 - smoothstep(width * 0.6, width, abs(off))) * tip * side * glen;
		}
	}
	return o;
}


// All four wounds: the max of each term.
vec4 wb_wounds(vec3 p, vec3 n) {
	vec4 a = max(wb_one(wound_0, wound_holes.x, wound_dir_0, p, n), wb_one(wound_1, wound_holes.y, wound_dir_1, p, n));
	vec4 b = max(wb_one(wound_2, wound_holes.z, wound_dir_2, p, n), wb_one(wound_3, wound_holes.w, wound_dir_3, p, n));
	return max(a, b);
}


// The crater's normal: the hole sinks `depth` metres and its ring rises a little, laid on NORMAL
// by the surface gradient of that height (view-space derivatives, so no tangents are needed).
vec3 wb_bump(vec3 normal, vec3 view_pos, float height) {
	vec3 dpx = dFdx(view_pos);
	vec3 dpy = dFdy(view_pos);
	float dhx = dFdx(height);
	float dhy = dFdy(height);
	vec3 r1 = cross(dpy, normal);
	vec3 r2 = cross(normal, dpx);
	float det = dot(dpx, r1);
	if (abs(det) < 1e-12) {
		return normal;
	}
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * normal - grad);
}

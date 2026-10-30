// A helicopter's rotor wash (FlyableHeli / HeliDownwash): the hub's position in the scene's frame
// in xyz, the wash's strength 0..1 in w (0 = no helicopter low over anything). Plants under it
// are blown away from under the rotor, crowns flattened round their trunks, everything shivering
// in the gusts; it reaches about 24 m out and stops a few tens of metres down.
global uniform vec4 heli_downwash;

// Model-space offset for a plant vertex. `h` its height over the instance origin, `radial` /
// `around` its distance and direction from the trunk axis (model space), `bend` the plant's own
// bend per metre squared (its sway's scale; the wash bends it several times harder).
vec3 heli_wash_offset(mat4 model, float h, float radial, vec2 around, float bend, float t, float phase) {
	if (heli_downwash.w < 0.001) {
		return vec3(0.0);
	}
	vec3 origin = model[3].xyz;
	vec2 away = origin.xz - heli_downwash.xz;
	float dist = length(away);
	float above = heli_downwash.y - origin.y;
	float f = heli_downwash.w * (1.0 - smoothstep(5.0, 24.0, dist)) * (1.0 - smoothstep(16.0, 50.0, above)) * step(-1.0, above);
	if (f < 0.001) {
		return vec3(0.0);
	}
	float gust = 0.8 + 0.15 * sin(t * 11.0 + phase * 5.0) + 0.08 * sin(t * 23.0 + phase * 2.0);
	vec3 dir_m = transpose(mat3(model)) * vec3(away.x, 0.0, away.y);
	vec2 d2 = normalize(dir_m.xz + vec2(1e-6));
	// Off to one side it leans away; right under the rotor there is no "away" and the crown is
	// pressed down and out round the trunk instead.
	float side = smoothstep(1.0, 6.0, dist);
	float lean = min(h * h * bend * f * gust, h * 0.35);
	vec3 off = vec3(d2.x, 0.0, d2.y) * lean * side;
	float press = radial * f * (1.0 - side * 0.5) * 0.3 * gust;
	off += vec3(around.x * press * 0.4, -press, around.y * press * 0.4);
	off.y += sin(t * 31.0 + radial * 3.0 + phase) * radial * 0.03 * f;
	return off;
}

// Grass: a blade laid flat away from under the rotor, in rings that run outward. `world` the
// vertex in the scene's frame, `height_t` 0 at the root .. 1 at the tip, `blade` its height (m).
vec3 heli_wash_grass(mat4 model, vec3 world, float height_t, float blade, float t) {
	if (heli_downwash.w < 0.001) {
		return vec3(0.0);
	}
	vec2 away = world.xz - heli_downwash.xz;
	float dist = length(away);
	float above = heli_downwash.y - world.y;
	float f = heli_downwash.w * (1.0 - smoothstep(4.0, 30.0, dist)) * (1.0 - smoothstep(12.0, 40.0, above)) * step(-1.0, above);
	if (f < 0.001) {
		return vec3(0.0);
	}
	float ripple = 0.75 + 0.25 * sin(t * 13.0 - dist * 0.9);
	vec3 dir_m = transpose(mat3(model)) * vec3(away.x, 0.0, away.y);
	vec2 d2 = normalize(dir_m.xz + vec2(1e-6));
	float lay = height_t * height_t * blade * 0.8 * f * ripple * smoothstep(0.5, 3.0, dist);
	return vec3(d2.x * lay, -lay * 0.45, d2.y * lay);
}

// Which colour space this renderer works in, for shaders that do arithmetic on colours rather
// than pass one straight through.
//
// The two renderers disagree (the repo's two-renderer probe, foliage_tex.gdshader's header,
// re-run for the hills on 2026-10-04 - HANDOFF 9au):
//   * Forward+ (the Mac) decodes `source_color` uniforms (their defaults too) and `source_color`
//     textures from sRGB to linear, and lights in linear.
//   * Compatibility (the web build, the opengl3 stills) hands both over RAW and lights the raw
//     numbers: it works in sRGB.
//   * Plain uniforms' DEFAULTS, vertex colours, MultiMesh instance colours and `color` shader
//     globals (sky_tint) arrive raw on both. But a Color SET from script is decoded on Forward+
//     even into a plain vec3 uniform (only a Vector3 is not).
//   (Probe, 2026-10-04, one quad per case read back: 0.5 drew 127 where it was decoded and 187
//   where it was not on Forward+, 128 for everything on Compatibility. Lit, both renderers give
//   albedo x light energy x N.L, no 1/pi.)
// So a number in a plain uniform means a LINEAR albedo on Forward+ and an sRGB one on
// Compatibility, and a `source_color` uniform written as a linear number is decoded a SECOND
// time on Forward+: 0.150 becomes 0.020, seven times darker and far more saturated. That was the
// horizon plane's whole palette until 2026-10-04 - the far mountains drew near-black olive on the
// Mac against the near hills' straw.
//
// The rule for any shader that includes this: work in LINEAR on both renderers - colour
// constants in plain uniforms written as linear numbers, every `source_color` texture sample and
// uniform passed through cs_in() - and hand the renderer its own space at the very end with
// cs_out() (ALBEDO, EMISSION, BACKLIGHT). On Forward+ both are no-ops; on Compatibility they are
// the sRGB transfer function, so the web draws the albedo the Mac does.
// Include it once per shader. Shader includes use // comments.

// Which renderer this is, at compile time (Godot's own CURRENT_RENDERER, as road.gdshader and the
// car cabin use it): no uniform, no branch per fragment, nothing to go wrong if a material ever
// set a probe value. The Mobile renderer is a RenderingDevice one and decodes like Forward+.
bool cs_linear_renderer() {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return false;
#else
	return true;
#endif
}


vec3 cs_srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}


vec3 cs_linear_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}


// A `source_color` texture sample or uniform, as linear light, on either renderer.
vec3 cs_in(vec3 c) {
	return cs_linear_renderer() ? c : cs_srgb_to_linear(c);
}


// A linear albedo or emission, in the space this renderer lights and writes.
vec3 cs_out(vec3 c) {
	return cs_linear_renderer() ? c : cs_linear_to_srgb(c);
}


// An sRGB-authored colour as a `source_color` uniform set from script reaches a shader on this
// renderer: decoded on Forward+, raw on Compatibility - the renderer's own space, the one every
// StandardMaterial and building.gdshader work in. For a shader that has to draw exactly what one
// of those draws from a colour it is handed some other way (a MultiMesh instance colour, a
// palette copied into the shader): building_lod.gdshader, the far copies of the near buildings.
// Not for linear-on-both shaders, which take cs_in() and hand back cs_out().
vec3 cs_as_uniform(vec3 srgb) {
	return cs_linear_renderer() ? cs_srgb_to_linear(srgb) : srgb;
}

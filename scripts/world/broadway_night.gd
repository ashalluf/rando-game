class_name BroadwayNight
extends RefCounted
## Broadway at 22:00 (wave 6 refcam `broadway_night`, docs/HANDOFF.md "Broadway's theatre district
## at night"): what read as a game at eye level on the theatre district, fixed in the pieces that
## draw it. Every hook is one line in the owning file and does nothing with `BROADWAY_NIGHT=0`
## (the A/B: the old look bit for bit).
## - the blade signs hold their names lit most of the cycle (broadway_sign.gdshader `look3`):
##   the old sequence spent half of every nine seconds half-spelt, flashing or dark;
## - the marquees blaze: bulbs, soffit and the board's lightbox brighter at night, the pavement
##   pool and the light under each marquee stronger and wider (`marquee()`);
## - the palaces' brick auditoriums are brick-red, not pale plaster (`BRICK_TINT`), and their
##   exposed side walls carry pilasters, a painted ghost sign, exit doors with caged lamps and a
##   fire stair (BroadwayTheatre._auditorium hands over to `side_dress()`);
## - the searchlights' shafts are a soft haze from the street, not solid white rods
##   (nightlife_beam.gdshader `look3`, `beam()`).

static var enabled: bool = OS.get_environment("BROADWAY_NIGHT") != "0"

## The auditorium's brick (sRGB, a source_color tint divided by the texture's own mean in
## landmark_facade): a fired red-brown, where the old (0.86, 0.74, 0.66) drew a pale pink plaster.
const BRICK_TINT := Color(0.56, 0.34, 0.26)
const OLD_BRICK_TINT := Color(0.86, 0.74, 0.66)
## The marquee's night levels (broadway_sign.gdshader uniforms) with the pass on.
const SIGN_NIGHT := {"bulb_night": 8.0, "soffit_night": 6.0, "board_night": 2.6, "letter_night": 4.2}
## The pavement pools under a marquee: warm pool gain and size multiplier, and the omni's energy
## multiplier (DayNight reads meta `lamp_gain`) and range.
const POOL_GAIN := 1.45
const POOL_GROW := 1.25
const LIGHT_GAIN := 2.2
const LIGHT_RANGE := 17.0


static func brick_tint() -> Color:
	return BRICK_TINT if enabled else OLD_BRICK_TINT


## The sign material's look (BroadwayTheatre.sign_material()).
static func sign(m: ShaderMaterial) -> void:
	if not enabled:
		return
	m.set_shader_parameter("look3", 1.0)
	for k: String in SIGN_NIGHT:
		m.set_shader_parameter(k, SIGN_NIGHT[k])


## A searchlight shaft's material (SkyBeam._ready()).
static func beam(m: ShaderMaterial) -> void:
	if enabled:
		m.set_shader_parameter("look3", 1.0)


## The light under a marquee (BroadwayTheatre.build()).
static func marquee_light(light: OmniLight3D) -> void:
	if not enabled:
		return
	light.omni_range = LIGHT_RANGE
	light.set_meta("lamp_gain", LIGHT_GAIN)


## A pavement pool's [size, alpha] under a marquee.
static func pool(size: Vector2, alpha: float) -> Array:
	if not enabled:
		return [size, alpha]
	return [size * POOL_GROW, minf(alpha * POOL_GAIN, 1.0)]


## The auditorium's two long side walls (x = +-aw/2, z from -fd to -fd - depth, ha high): the
## blank brick box that rose over a low neighbour read as an untextured block. A real palace's
## side wall: brick pilasters on the bents with a stepped coping, a faded painted name high up,
## steel exit doors at the foot under caged lamps, a fire stair up the front end. All on the
## palace's own surfaces (brick, trim, the sign shader), so it costs no draw.
static func side_dress(g: LandmarkGeo, spec: Dictionary, aw: float, ha: float, fd: float, depth: float) -> void:
	if not enabled or depth < 8.0:
		return
	var z0 := -fd
	var z1 := -fd - depth
	var name := str(spec.name).replace("THE ", "")
	for sx: float in [-1.0, 1.0]:
		var x := sx * aw * 0.5
		var n := Vector3(sx, 0.0, 0.0)
		# Pilasters every ~6.5 m, a plinth course and a stepped coping along the top.
		var bays := maxi(2, int(round(depth / 6.5)))
		for i in bays + 1:
			var z := lerpf(z0 - 0.4, z1 + 0.4, float(i) / float(bays))
			g.box("brick", Vector3(x + sx * 0.17, ha * 0.5, z), Vector3(0.36, ha, 0.7))
			g.box("trim", Vector3(x + sx * 0.22, ha - 0.25, z), Vector3(0.46, 0.5, 0.82))
		g.box("trim", Vector3(x + sx * 0.08, 0.45, (z0 + z1) * 0.5), Vector3(0.18, 0.9, depth - 0.2))
		g.box("trim", Vector3(x + sx * 0.1, ha + 0.12, (z0 + z1) * 0.5), Vector3(0.36, 0.24, depth))
		# The painted name, faded cream on the brick, high on the front half of the wall.
		var paint := Color(0.70, 0.64, 0.52)
		var basis := Basis(Vector3(0.0, 0.0, -sx), Vector3.UP, Vector3(sx, 0.0, 0.0))
		var sign_z := z0 - minf(depth * 0.45, 14.0)
		var cap := clampf(ha * 0.11, 1.8, 3.0)
		BroadwayTheatre.text(g, name, Transform3D(basis, Vector3(x + sx * 0.03, ha * 0.62, sign_z)), cap, minf(depth * 0.8, 24.0),
			BroadwayTheatre.kc(paint, BroadwayTheatre.K_ENAMEL), n)
		BroadwayTheatre.text(g, "THEATRE", Transform3D(basis, Vector3(x + sx * 0.03, ha * 0.62 - cap * 1.25, sign_z)), cap * 0.55, minf(depth * 0.6, 16.0),
			BroadwayTheatre.kc(paint.darkened(0.12), BroadwayTheatre.K_ENAMEL), n)
		# Exit doors at the foot, each under a caged lamp (a small warm glow).
		for k in 2:
			var dz := lerpf(z0 - depth * 0.3, z1 + depth * 0.25, float(k))
			g.box("sign", Vector3(x + sx * 0.04, 1.15, dz), Vector3(0.1, 2.3, 1.9), BroadwayTheatre.kc(Color(0.16, 0.18, 0.17), BroadwayTheatre.K_IRON))
			g.box("trim", Vector3(x + sx * 0.12, 2.42, dz), Vector3(0.24, 0.16, 2.2))
			g.box("sign", Vector3(x + sx * 0.2, 2.9, dz), Vector3(0.22, 0.26, 0.22), BroadwayTheatre.kc(Color(1.0, 0.78, 0.48), BroadwayTheatre.K_NEON))
			g.box("sign", Vector3(x + sx * 0.06, 3.05, dz), Vector3(0.14, 0.08, 0.3), BroadwayTheatre.kc(BroadwayTheatre.IRON, BroadwayTheatre.K_IRON))
		# A steel fire stair up the front end: landings every 5 m, the flights between, rails.
		var fz := z0 - 3.2
		var y := 5.0
		while y < ha - 3.0:
			g.box("sign", Vector3(x + sx * 0.75, y, fz), Vector3(1.3, 0.08, 3.6), BroadwayTheatre.kc(BroadwayTheatre.IRON, BroadwayTheatre.K_IRON))
			g.box("sign", Vector3(x + sx * 1.38, y + 0.5, fz), Vector3(0.05, 1.0, 3.6), BroadwayTheatre.kc(BroadwayTheatre.IRON, BroadwayTheatre.K_IRON))
			var a := Vector3(x + sx * 0.75, y + 0.05, fz - 1.6)
			var b := Vector3(x + sx * 0.75, y + 5.0, fz + 1.6)
			var dvec := b - a
			var yy := dvec.normalized()
			var xx := Vector3(sx, 0.0, 0.0)
			var zz := xx.cross(yy).normalized()
			g.box("sign", (a + b) * 0.5, Vector3(1.1, dvec.length(), 0.06), BroadwayTheatre.kc(BroadwayTheatre.IRON, BroadwayTheatre.K_IRON), Basis(xx, yy, zz))
			y += 5.0

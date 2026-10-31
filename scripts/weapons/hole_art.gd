class_name HoleArt
extends RefCounted
## The bullet marks' maps, painted in code (GunplayFeel.hole_textures). One height field per mark,
## and from it the albedo, the normal map and the ORM, so the light falls into a crater the way it
## is shaped. Every surface reads as what it is from a few metres:
##   CONCRETE a dark pit in a spalled crater of fresh lighter concrete with flecks of aggregate,
##            a jagged rim and hairline cracks running off it, a halo of dust;
##   METAL    a clean punched hole, its lip petalled up in bare steel (metallic in the ORM, so it
##            glints), a ring of paint chipped back to the steel round it;
##   WOOD     a tear along the grain: a dark split, pale fresh fibres splintered out above and
##            below it;
##   DIRT     a soft dark crater and a ring of thrown clods;
##   GLASS    a crack star with its rings, different spokes every variant;
## and the shotgun's pattern smudge (build_pattern). The alpha always reaches zero well inside the
## edge. Normal maps OpenGL-style (green = the row below minus the row above, CLAUDE.md's
## fwd-review-b note). No rng: a variant is a seed.


static func build(surf: int, variant: int, px: int) -> Array:
	var seed := surf * 131 + variant * 17 + 5
	var n1 := FastNoiseLite.new()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.seed = seed
	n1.frequency = 0.9
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.seed = seed + 3
	n2.frequency = 9.0
	n2.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var col := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var orm := Image.create(px, px, false, Image.FORMAT_RGB8)
	var h := PackedFloat32Array()
	h.resize(px * px)
	# Variant knobs.
	var turn := float(variant) * 2.1 + float(surf) * 0.7
	var cracks := 3 + (variant + surf) % 3
	for y in px:
		for x in px:
			var u := (float(x) + 0.5) / float(px) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(px) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u) + turn
			var c := Color(0, 0, 0, 0)
			var height := 0.0
			var rough := 0.9
			var metal := 0.0
			var ao := 1.0
			match surf:
				WeaponFX.Surface.METAL:
					var rp := 0.1 + 0.012 * sin(ang * 5.0)
					var petal := 0.17 + 0.03 * sin(ang * 6.0 + 1.0) + 0.02 * n1.get_noise_2d(ang * 3.0, 0.0)
					var chip := 0.30 + 0.07 * n1.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0) + 0.03 * absf(sin(ang * 9.0))
					if r < rp:
						c = Color(0.02, 0.02, 0.022, 1.0)
						height = -1.0
						ao = 0.2
					elif r < petal:
						var k := (r - rp) / (petal - rp)
						var bright := 0.55 + 0.25 * (1.0 - k) + 0.1 * n2.get_noise_2d(u, v)
						c = Color(bright, bright * 0.99, bright * 0.96, 1.0)
						height = 0.6 * sin(k * PI) * (0.6 + 0.4 * absf(sin(ang * 6.0 + 1.0)))
						rough = 0.3
						metal = 1.0
					elif r < chip:
						var scuff := 0.42 + 0.12 * n2.get_noise_2d(u * 1.7, v * 1.7)
						c = Color(scuff, scuff * 0.98, scuff * 0.95, 1.0)
						height = -0.08
						rough = 0.42
						metal = 1.0
					else:
						# A faint burn of hot lead round the chipped ring.
						var a := (1.0 - smoothstep(chip, chip + 0.16, r)) * 0.35
						c = Color(0.12, 0.11, 0.1, a)
				WeaponFX.Surface.WOOD:
					# Along the grain (the texture's v): the split is long and narrow, the fibres
					# torn out of it pale and stringy above and below.
					var gu := u * 1.0
					var gv := v * 0.42
					var gr := sqrt(gu * gu + gv * gv)
					var split := 0.075 + 0.02 * n1.get_noise_2d(v * 4.0, 1.0)
					var fib := absf(n1.get_noise_2d(u * 26.0, v * 1.6))
					var reach := 0.24 + 0.1 * n1.get_noise_2d(u * 3.0, 7.0)
					if gr < split:
						c = Color(0.05, 0.035, 0.02, 1.0)
						height = -1.0
						ao = 0.3
					elif gr < reach:
						var k := (gr - split) / maxf(reach - split, 0.01)
						var strand := smoothstep(0.15, 0.5, fib + 0.35 * (1.0 - k))
						var pale := 0.7 - 0.2 * k + 0.1 * fib
						c = Color(pale, pale * 0.8, pale * 0.57, strand * (1.0 - smoothstep(0.6, 1.0, k)))
						height = 0.5 * (1.0 - k) * strand
						rough = 0.75
					else:
						var a := (1.0 - smoothstep(reach, reach + 0.12, gr)) * 0.3
						c = Color(0.16, 0.11, 0.07, a)
				WeaponFX.Surface.DIRT:
					var rp := 0.2 + 0.05 * n1.get_noise_2d(cos(ang) * 1.5, sin(ang) * 1.5)
					var clod := n2.get_noise_2d(u * 1.3, v * 1.3)
					if r < rp:
						var k := r / rp
						c = Color(0.1, 0.075, 0.055, 1.0 - smoothstep(0.85, 1.0, k) * 0.3)
						height = -(1.0 - k * k)
						ao = 0.5 + 0.5 * k
					elif r < 0.62 and clod > 0.35 - r * 0.4:
						c = Color(0.16, 0.12, 0.085, (1.0 - smoothstep(0.4, 0.62, r)))
						height = 0.35
					else:
						c = Color(0.14, 0.11, 0.08, (1.0 - smoothstep(rp, 0.55, r)) * 0.45)
				WeaponFX.Surface.GLASS:
					var spokes := absf(sin(ang * (3.5 + float(variant) * 0.5) + sin(ang * 3.0) * 0.4 + 0.08 * sin(r * 40.0)))
					var split := pow(clampf(1.0 - spokes * 6.0, 0.0, 1.0), 0.6)
					var ring_a := clampf(1.0 - absf(r - 0.28 - 0.03 * float(variant)) * 26.0, 0.0, 1.0) * 0.45
					var ring_b := clampf(1.0 - absf(r - 0.55) * 30.0, 0.0, 1.0) * 0.26
					var hub := pow(clampf(1.0 - r * 7.0, 0.0, 1.0), 1.5)
					var a := clampf((split + ring_a + ring_b) * (1.0 - smoothstep(0.30, 0.9, r)) + hub, 0.0, 1.0)
					c = Color(0.9, 0.95, 1.0, a)
					height = -0.3 * split - hub
					rough = 0.1
				_:
					# Concrete (and anything else hard).
					var rp := 0.11 + 0.025 * n1.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0)
					# The rim breaks in facets: the angle in steps, each its own radius.
					var facet := floorf((ang + PI) / TAU * float(9 + variant * 2))
					var rs := 0.34 + 0.08 * sin(facet * 2.7 + float(variant)) + 0.05 * n1.get_noise_2d(cos(ang) * 3.0, sin(ang) * 3.0)
					var agg := n2.get_noise_2d(u, v)
					if r < rp:
						c = Color(0.035, 0.033, 0.03, 1.0)
						height = -1.0
						ao = 0.25
					elif r < rs:
						var k := (r - rp) / maxf(rs - rp, 0.01)
						# Fresh concrete, in shadow down the crater's wall, bright on its rim.
						var fresh := lerpf(0.22, 0.6, smoothstep(0.0, 0.8, k)) + 0.08 * agg
						c = Color(fresh, fresh * 0.97, fresh * 0.92, 1.0)
						height = -0.65 * (1.0 - k) + 0.12 * agg
						ao = 0.55 + 0.45 * k
					else:
						var crack := 0.0
						for i in cracks:
							var ca := float(i) / float(cracks) * TAU + sin(float(i) * 4.3 + float(variant)) * 0.5
							# Straight with a jag in it, the way concrete splits.
							var wob := ca + 0.05 * sin(r * 37.0 + float(i) * 2.0) + 0.03 * signf(sin(r * 11.0 + float(i)))
							var d := absf(sin((ang - turn) - wob)) * r
							var reach := 0.48 + 0.3 * absf(sin(float(i) * 1.9 + float(variant)))
							crack = maxf(crack, (1.0 - smoothstep(0.004, 0.016, d)) * (1.0 - smoothstep(reach * 0.7, reach, r)))
						var dust := (1.0 - smoothstep(rs, 0.72, r)) * 0.28
						if crack > dust:
							c = Color(0.08, 0.075, 0.07, crack * 0.9)
							height = -0.25 * crack
						else:
							c = Color(0.62, 0.6, 0.57, dust * 0.7)
			# Nothing within a few pixels of the border.
			c.a *= 1.0 - smoothstep(0.86, 0.98, maxf(absf(u), absf(v)))
			col.set_pixel(x, y, c)
			orm.set_pixel(x, y, Color(ao, rough, metal))
			h[y * px + x] = height
	return [_tex(col), _tex(_normal(h, px, 3.0)), _tex(orm)]


## The shotgun pattern's smudge: grey lead and powder, darker in the middle, ragged.
static func build_pattern(px: int) -> Array:
	var n1 := FastNoiseLite.new()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.seed = 991
	n1.frequency = 3.0
	var col := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var orm := Image.create(px, px, false, Image.FORMAT_RGB8)
	var h := PackedFloat32Array()
	h.resize(px * px)
	for y in px:
		for x in px:
			var u := (float(x) + 0.5) / float(px) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(px) * 2.0 - 1.0
			var r := sqrt(u * u + v * v) * (1.0 + 0.18 * n1.get_noise_2d(u, v))
			var a := (1.0 - smoothstep(0.35, 0.92, r)) * (0.42 + 0.2 * n1.get_noise_2d(u * 3.0, v * 3.0))
			var g := 0.2 + 0.08 * r
			col.set_pixel(x, y, Color(g, g, g * 1.04, clampf(a, 0.0, 1.0)))
			orm.set_pixel(x, y, Color(1.0, 0.95, 0.0))
	return [_tex(col), _tex(_normal(h, px, 1.0)), _tex(orm)]


static func _normal(h: PackedFloat32Array, px: int, strength: float) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	for y in px:
		for x in px:
			var l := h[y * px + maxi(x - 1, 0)]
			var r := h[y * px + mini(x + 1, px - 1)]
			var up := h[maxi(y - 1, 0) * px + x]
			var dn := h[mini(y + 1, px - 1) * px + x]
			var n := Vector3((l - r) * strength, (dn - up) * strength, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return img


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

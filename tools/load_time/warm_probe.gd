extends Node
## Times the loading screen's CPU warm-ups one by one (headless, under a minute): every kit's
## warm() in LoadingScreen.effect_list(), the camp and beach figure bakes, the trees, the rigs,
## the dogs. What the dummy renderer cannot show is the compile; what it shows is the GDScript.
##   godot --headless --path . res://tools/load_time/warm_probe.tscn

var _rows: Array = []


func _t(name: String, f: Callable) -> void:
	var t := Time.get_ticks_usec()
	f.call()
	_rows.append([float(Time.get_ticks_usec() - t) / 1000.0, name])


func _ready() -> void:
	await get_tree().process_frame
	_t("WeaponFX.warm_materials", func(): WeaponFX.warm_materials())
	_t("PropFactory.kit_materials", func(): PropFactory.kit_materials())
	_t("PropFactory.camp_materials", func(): PropFactory.camp_materials())
	_t("PortKit.warm", func(): PortKit.warm())
	_t("StreetVendors.warm", func(): StreetVendors.warm())
	_t("Parklets.warm", func(): Parklets.warm())
	_t("NightLife.warm", func(): NightLife.warm())
	_t("Valets.warm", func(): Valets.warm())
	_t("BoulevardSigns.warm", func(): BoulevardSigns.warm())
	_t("FarmersMarketKit.warm", func(): FarmersMarketKit.warm())
	_t("FilmShootKit.warm", func(): FilmShootKit.warm())
	_t("Billboards.warm", func(): Billboards.warm())
	_t("BeachLife.warm", func(): BeachLife.warm())
	_t("BeachAmenities.warm", func(): BeachAmenities.warm())
	_t("PierPark.warm", func(): PierPark.warm())
	_t("LaTrees.warm", func(): LaTrees.warm())
	_t("HillShrub.warm", func(): HillShrub.warm())
	_t("HillScatter.warm", func(): HillScatter.warm())
	_t("UtilityPoles.warm", func(): UtilityPoles.warm())
	_t("CarDamage.warm_materials", func(): CarDamage.warm_materials())
	_t("HillHomeKit.warm", func(): HillHomeKit.warm())
	_t("BlastAftermath.warm", func(): BlastAftermath.warm())
	_t("RoadsideKit.warm", func(): RoadsideKit.warm())
	_t("StreetFurniture.warm", func(): StreetFurniture.warm())
	_t("FashionKit.warm", func(): FashionKit.warm())
	_t("BackyardKit.warm", func(): BackyardKit.warm())
	_t("YardSaleKit.warm", func(): YardSaleKit.warm())
	_t("effect_list (again, cached)", func(): LoadingScreen.effect_list())
	_t("camp figures", func():
		for k: Array in CampFigure.kinds():
			CampFigure.mesh_for(CampFigure.seed_for(k[0], k[1], k[2]), k[1]))
	_t("beach figures", func():
		var beach := BeachFigure.kinds()
		beach.append_array(Backyards.figure_kinds())
		for k in beach:
			BeachFigure.warm_kind(k))
	_t("Bonfires + figures", func():
		Bonfires.warm()
		for k: Array in BonfireFigure.kinds():
			BonfireFigure.warm_kind(k))
	_t("StreetClutter2.warm", func(): StreetClutter2.warm())
	_t("DogMesh.warm", func(): DogMesh.warm())
	_t("WildSpecies.warm", func(): WildSpecies.warm())
	_rows.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0.0
	for r in _rows:
		total += r[0]
		print("WARMCPU %8.0f ms  %s" % r)
	print("WARMCPU total %.0f ms" % total)
	get_tree().quit()

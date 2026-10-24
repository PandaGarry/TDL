class_name SevaraSettlementArchitect3D
extends RefCounted
## Процедурно-модульный архитектор поселения Севары (Шаг 4 Look-Dev).
##
## Собирает уникальную горно-речную архитектуру племени Севары у подножия Торамека
## и берегов Ниварели:
## 1) Укреплённый Длинный Дом Вождя (Compound Longhouse Bastion) на каменной террасе
##    с резным рогатым коньком Херуны, каменной трубой и ступенчатым крыльцом;
## 2) Горная Кузня и плотницкий двор (Blacksmith & Craft Yard) с горном и палисадом;
## 3) Укреплённый Каменный Колодец (Well Plaza) на круглом мощёном подиуме;
## 4) Палата Хроники Селимы (Selima's Scriptorium Hall) с каменным архивом и портиком;
## 5) Каменный Круг Совета и Священный Очаг (Hearth Sanctuary) с треногой из жердей
##    торавы, подвешенным на цепи котлом и резными столбами-факелами;
## 6) Водяная Мельница-Лесопилка Ниварели (Nivarel Watermill) с 3D-водяным колесом
##    в потоке реки и деревянным свайным причалом;
## 7) Восточная Мостовая Застава (East Bridge Outpost) и фонарные столбы переправы.


static func populate_settlement(settlement_root: Node3D) -> void:
	# 1. Western Upper Terrace: Fortified Chieftain's Longhouse Bastion
	var lh_pos := Vector2(-13.8, -10.8)
	var longhouse := create_longhouse_bastion_3d()
	longhouse.position = Vector3(
		lh_pos.x, SevaraTerrainGen3D.get_height_at(lh_pos.x, lh_pos.y) - 0.04, lh_pos.y
	)
	longhouse.rotation.y = 0.52
	settlement_root.add_child(longhouse)

	# 2. Western Craft Terrace: Mountain Blacksmith & Timber Yard
	var bs_pos := Vector2(-18.8, -7.2)
	var smithy := create_blacksmith_craft_yard_3d()
	smithy.position = Vector3(
		bs_pos.x, SevaraTerrainGen3D.get_height_at(bs_pos.x, bs_pos.y) - 0.04, bs_pos.y
	)
	smithy.rotation.y = 0.68
	settlement_root.add_child(smithy)

	# 3. Homestead Forecourt: Stone-Plinth Well Plaza
	var well_pos := Vector2(-11.2, -6.2)
	var well_plaza := create_well_plaza_3d()
	well_plaza.position = Vector3(
		well_pos.x, SevaraTerrainGen3D.get_height_at(well_pos.x, well_pos.y) - 0.03, well_pos.y
	)
	well_plaza.rotation.y = 0.38
	settlement_root.add_child(well_plaza)

	# 4. Central Terrace: Selima's Scriptorium & Chronicle Hall
	var pav_pos := Vector2(-4.2, -10.8)
	var scriptorium := create_selima_chronicle_hall_3d()
	scriptorium.position = Vector3(
		pav_pos.x, SevaraTerrainGen3D.get_height_at(pav_pos.x, pav_pos.y) - 0.04, pav_pos.y
	)
	scriptorium.rotation.y = -0.34
	settlement_root.add_child(scriptorium)

	# 5. Riverbank Promontory: Stone Council Ring & Ancestral Hearth Sanctuary
	var hearth_pos := Vector2(-0.2, -6.8)
	var hearth := create_sevara_hearth_sanctuary_3d()
	hearth.position = Vector3(
		hearth_pos.x,
		SevaraTerrainGen3D.get_height_at(hearth_pos.x, hearth_pos.y) - 0.02,
		hearth_pos.y
	)
	settlement_root.add_child(hearth)

	# 6. Nivarel Rapids Bank: Watermill-Sawmill with Oak Waterwheel & Timber River Pier
	var mill_pos := Vector2(2.4, -15.4)
	var watermill := create_nivarel_watermill_3d()
	watermill.position = Vector3(
		mill_pos.x, SevaraTerrainGen3D.get_height_at(mill_pos.x, mill_pos.y) - 0.05, mill_pos.y
	)
	watermill.rotation.y = -0.22
	settlement_root.add_child(watermill)

	# 7. East Bank Crossing: Fortified Bridge Outpost & Trading Homestead
	var east_pos := Vector2(23.4, -5.0)
	var outpost := create_east_bridge_outpost_3d()
	outpost.position = Vector3(
		east_pos.x, SevaraTerrainGen3D.get_height_at(east_pos.x, east_pos.y) - 0.04, east_pos.y
	)
	outpost.rotation.y = -1.08
	settlement_root.add_child(outpost)

	# 8. Carved Sevara Bridge Gate Lantern Pillars flanking the western & eastern bridgeheads
	var gate_posts: Array[Vector3] = [
		Vector3(4.6, -0.28, 0.25),
		Vector3(19.4, -0.42, -0.35),
	]
	for gp: Vector3 in gate_posts:
		var post := create_totem_lantern_pillar_3d(2.35)
		post.position = Vector3(gp.x, SevaraTerrainGen3D.get_height_at(gp.x, gp.y) - 0.03, gp.y)
		post.rotation.y = gp.z
		settlement_root.add_child(post)

	# 9. Southern River Weir Barrier
	var weir_z := 13.8
	var weir := SevaraPropsFactory3D.create_weir_barrier_3d(5.4)
	weir.position = Vector3(
		SevaraTerrainGen3D.river_center_x(weir_z), SevaraTerrainGen3D.WATER_SURFACE_Y - 0.05, weir_z
	)
	weir.rotation.y = -0.18
	settlement_root.add_child(weir)


static func create_longhouse_bastion_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraLonghouseBastion3D"
	var stone_mat := _stone_mat()
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()

	# 1. Terraced Cyclopean Stone Plinth & Stepped Forecourt Stairs
	var plinth := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(5.8, 0.42, 4.2)
	plinth.mesh = pmesh
	plinth.position = Vector3(0.0, 0.14, 0.0)
	plinth.material_override = stone_mat
	root.add_child(plinth)

	for s_idx in range(3):
		var step := MeshInstance3D.new()
		var smesh := BoxMesh.new()
		var sw := 1.85 - float(s_idx) * 0.16
		smesh.size = Vector3(sw, 0.14, 0.46)
		step.mesh = smesh
		step.position = Vector3(0.0, 0.05 + float(2 - s_idx) * 0.11, 2.25 + float(s_idx) * 0.34)
		step.material_override = stone_mat
		root.add_child(step)

	# Corner & retaining wall mossy boulders anchoring the stone bastion into the hillside
	var bastion_rocks: Array[Vector3] = [
		Vector3(-2.85, 0.02, 1.95),
		Vector3(2.85, 0.02, 1.95),
		Vector3(-2.95, 0.04, -1.85),
		Vector3(2.95, 0.04, -1.85),
		Vector3(-1.35, -0.02, 2.25),
		Vector3(1.35, -0.02, 2.25),
	]
	for br: Vector3 in bastion_rocks:
		var rock := SevaraPropsFactory3D.create_boulder_3d(Vector3(0.76, 0.48, 0.68), true)
		rock.position = br
		rock.rotation.y = br.x * 0.9 + br.z * 0.5
		root.add_child(rock)

	# 2. Compound Nordic-Alpine Longhouse Body: Wide Transverse Hall + High Central Gable Keep
	var transverse_hall := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Stable.glb", 2.95, {}, true
	)
	transverse_hall.position = Vector3(0.0, 0.28, -0.18)
	root.add_child(transverse_hall)

	var central_keep := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "House_1.glb", 4.15, {}, true
	)
	central_keep.position = Vector3(0.0, 0.28, 0.12)
	root.add_child(central_keep)

	# 3. Tall Cobble Stone Chimney Stack on the west gable
	var chimney := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(0.62, 3.65, 0.62)
	chimney.mesh = cmesh
	chimney.position = Vector3(-1.28, 2.10, -0.35)
	chimney.material_override = stone_mat
	root.add_child(chimney)

	var chimney_cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.76, 0.14, 0.76)
	chimney_cap.mesh = cap_mesh
	chimney_cap.position = Vector3(-1.28, 3.96, -0.35)
	chimney_cap.material_override = stone_mat
	root.add_child(chimney_cap)

	# 4. Carved Sevara Ridge Beam & Crossed Heruna Antler-Horn Finials on the High Roof Peak
	_add_carved_ridge_crest(root, Vector3(0.0, 4.36, 0.12), 3.35, 0.0, dark_wood_mat, warm_wood_mat)
	_add_carved_ridge_crest(
		root, Vector3(0.0, 3.16, -0.18), 5.65, PI * 0.5, dark_wood_mat, warm_wood_mat
	)

	# 5. Twin Carved Entry Totem Pillars with Lit Torches flanking the front stone steps
	var portal_xs: Array[float] = [-1.18, 1.18]
	for px: float in portal_xs:
		var pillar := create_totem_lantern_pillar_3d(2.15)
		pillar.position = Vector3(px, 0.22, 2.18)
		root.add_child(pillar)

	# 6. Homestead Side Provisions (Stacked Mossy Logs, Barrels & Grain Sacks)
	var log_pile := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.NATURE_DIR + "WoodLog_Moss.glb", 0.44, {}, true
	)
	log_pile.position = Vector3(2.35, 0.30, 1.15)
	log_pile.rotation.y = 0.25
	root.add_child(log_pile)

	var barrel := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Barrel.glb", 0.86, {}, true
	)
	barrel.position = Vector3(-2.15, 0.32, 1.25)
	root.add_child(barrel)

	var sacks := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bags.glb", 0.58, {}, true
	)
	sacks.position = Vector3(-1.55, 0.32, 1.52)
	sacks.rotation.y = 0.65
	root.add_child(sacks)
	return root


static func create_blacksmith_craft_yard_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraBlacksmithYard3D"
	var stone_mat := _stone_mat()

	# Stone foundation pad under the forge
	var pad := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(4.5, 0.28, 3.8)
	pad.mesh = pmesh
	pad.position = Vector3(0.0, 0.08, 0.0)
	pad.material_override = stone_mat
	root.add_child(pad)

	var smithy := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Blacksmith.glb", 3.35, {}, true
	)
	smithy.position = Vector3(0.0, 0.18, 0.0)
	root.add_child(smithy)

	# Outdoor Glowing Stone Forge Hearth & Quenching Barrels
	var forge_ring := MeshInstance3D.new()
	var fmesh := CylinderMesh.new()
	fmesh.top_radius = 0.62
	fmesh.bottom_radius = 0.72
	fmesh.height = 0.52
	fmesh.radial_segments = 12
	forge_ring.mesh = fmesh
	forge_ring.position = Vector3(1.65, 0.36, 1.45)
	forge_ring.material_override = stone_mat
	root.add_child(forge_ring)

	var forge_fire := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bonfire_Lit.glb", 0.52, {}, true
	)
	forge_fire.position = Vector3(1.65, 0.58, 1.45)
	root.add_child(forge_fire)

	var cart := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Cart.glb", 1.24, {}, true
	)
	cart.position = Vector3(-2.35, 0.02, 1.65)
	cart.rotation.y = 0.48
	root.add_child(cart)

	var stump := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.NATURE_DIR + "TreeStump_Moss.glb", 0.62, {}, true
	)
	stump.position = Vector3(-0.85, 0.14, 2.05)
	root.add_child(stump)

	var axe := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Axe_small.glb", 0.48, {}, false
	)
	axe.position = Vector3(-0.82, 0.66, 2.05)
	axe.rotation = Vector3(0.35, 0.8, -0.45)
	root.add_child(axe)

	# Timber Fence linking the Craft Yard toward the Longhouse
	var fence := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Fence.glb", 1.08, {}, true
	)
	fence.position = Vector3(2.85, 0.05, 0.45)
	fence.rotation.y = -0.35
	root.add_child(fence)
	return root


static func create_well_plaza_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraWellPlaza3D"
	var stone_mat := _stone_mat()

	# Circular Stepped Stone Wellhead Platform
	var base_disc := MeshInstance3D.new()
	var dmesh := CylinderMesh.new()
	dmesh.top_radius = 1.42
	dmesh.bottom_radius = 1.56
	dmesh.height = 0.24
	dmesh.radial_segments = 16
	base_disc.mesh = dmesh
	base_disc.position = Vector3(0.0, 0.08, 0.0)
	base_disc.material_override = stone_mat
	root.add_child(base_disc)

	var well := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Well.glb", 2.18, {}, true
	)
	well.position = Vector3(0.0, 0.16, 0.0)
	root.add_child(well)

	for i in range(5):
		var ang := float(i) * TAU / 5.0 + 0.2
		var rim_rock := SevaraPropsFactory3D.create_boulder_3d(Vector3(0.52, 0.34, 0.48), true)
		rim_rock.position = Vector3(cos(ang) * 1.46, 0.02, sin(ang) * 1.46)
		rim_rock.rotation.y = ang
		root.add_child(rim_rock)

	var barrel := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Barrel.glb", 0.78, {}, true
	)
	barrel.position = Vector3(1.05, 0.16, -0.55)
	root.add_child(barrel)
	return root


static func create_selima_chronicle_hall_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "ChroniclePavilion3D"
	var stone_mat := _stone_mat()
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()

	# 1. Raised Stone Scriptorium Foundation Plinth & Front Entry Step
	var plinth := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(3.45, 0.32, 3.65)
	plinth.mesh = pmesh
	plinth.position = Vector3(0.0, 0.10, -0.15)
	plinth.material_override = stone_mat
	root.add_child(plinth)

	# 2. Rear Vaulted Stone Archive Chamber (`House_4`) + Carved Timber Portico (`Gazebo`)
	var stone_archive := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "House_4.glb", 1.72, {}, true
	)
	stone_archive.position = Vector3(0.0, 0.22, -0.92)
	root.add_child(stone_archive)

	var portico := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Gazebo.glb", 3.28, {}, true
	)
	portico.position = Vector3(0.0, 0.22, 0.28)
	root.add_child(portico)

	# Carved Roof Crest with Horned Finials over the Scriptorium Portico
	_add_carved_ridge_crest(root, Vector3(0.0, 3.44, 0.28), 3.05, 0.0, dark_wood_mat, warm_wood_mat)

	# 3. Selima's Heavy Oak Scriptorium Table, Open Chronicle Tome, Bench & Scroll Crates
	var bench := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bench_1.glb", 0.54, {}, true
	)
	bench.position = Vector3(0.0, 0.24, -0.18)
	root.add_child(bench)

	var desk_top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(1.28, 0.08, 0.64)
	desk_top.mesh = top_mesh
	desk_top.position = Vector3(0.0, 0.94, 0.38)
	desk_top.material_override = warm_wood_mat
	root.add_child(desk_top)

	var leg_xs: Array[float] = [-0.48, 0.48]
	for lx: float in leg_xs:
		var leg := MeshInstance3D.new()
		var lmesh := BoxMesh.new()
		lmesh.size = Vector3(0.14, 0.68, 0.50)
		leg.mesh = lmesh
		leg.position = Vector3(lx, 0.58, 0.38)
		leg.material_override = dark_wood_mat
		root.add_child(leg)

	var book := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Book1_Open.glb", 0.09, {}, false
	)
	book.position = Vector3(0.0, 0.99, 0.38)
	root.add_child(book)

	var crate := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Crate.glb", 0.52, {}, true
	)
	crate.position = Vector3(-1.12, 0.24, -0.12)
	crate.rotation.y = 0.42
	root.add_child(crate)

	# Corner Mossy Foundation Boulders & Warm Torch Sconce
	var torch := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "WoodenTorch_Fire.glb", 0.62, {}, false
	)
	torch.position = Vector3(1.18, 1.55, 1.42)
	torch.rotation.x = 0.28
	root.add_child(torch)

	var corner_xs: Array[float] = [-1.68, 1.68]
	for cx: float in corner_xs:
		var c_rock := SevaraPropsFactory3D.create_boulder_3d(Vector3(0.64, 0.42, 0.58), true)
		c_rock.position = Vector3(cx, 0.02, 1.48)
		root.add_child(c_rock)
	return root


static func create_sevara_hearth_sanctuary_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "CommunalHearth3D"
	var dark_wood_mat := _dark_wood_mat()
	var iron_mat := _iron_mat()

	# 1. Central Ancestral Bonfire & Suspended Cast-Iron Cauldron on a 3-Pole Torava Tripod
	root.add_child(
		SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Bonfire_Lit.glb", 0.92, {}, true
		)
	)

	var cauldron := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Cauldron.glb", 0.54, {}, true
	)
	cauldron.position = Vector3(0.58, 0.0, -0.14)
	root.add_child(cauldron)

	# Tall 3-pole timber cooking tripod over the hearth fire with iron ring & chain
	var pole_cyl := CylinderMesh.new()
	pole_cyl.top_radius = 0.036
	pole_cyl.bottom_radius = 0.056
	pole_cyl.height = 1.96
	pole_cyl.radial_segments = 10
	for p_idx in range(3):
		var p_ang := float(p_idx) * TAU / 3.0 + 0.42
		var pole := MeshInstance3D.new()
		pole.mesh = pole_cyl
		var base_r := 0.48
		pole.position = Vector3(cos(p_ang) * base_r, 0.86, sin(p_ang) * base_r)
		pole.rotation = Vector3(-sin(p_ang) * 0.28, 0.0, cos(p_ang) * 0.28)
		pole.material_override = dark_wood_mat
		root.add_child(pole)

	var ring := MeshInstance3D.new()
	var rmesh := CylinderMesh.new()
	rmesh.top_radius = 0.11
	rmesh.bottom_radius = 0.11
	rmesh.height = 0.06
	ring.mesh = rmesh
	ring.position = Vector3(0.0, 1.68, 0.0)
	ring.material_override = iron_mat
	root.add_child(ring)

	# 2. Semicircular Council Ring of Mossy River Boulders, Oak Benches & Totem Lantern Pillars
	var bench_angs: Array[float] = [-1.18, 0.82]
	for ang: float in bench_angs:
		var bench := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Bench_1.glb", 0.56, {}, true
		)
		bench.position = Vector3(cos(ang) * 1.54, 0.0, sin(ang) * 1.54)
		bench.rotation.y = -ang + PI * 0.5
		root.add_child(bench)

	var ring_angs: Array[float] = [-2.05, -1.58, -0.52, 0.18, 1.42]
	for r_ang: float in ring_angs:
		var c_stone := SevaraPropsFactory3D.create_boulder_3d(Vector3(0.62, 0.38, 0.54), true)
		c_stone.position = Vector3(cos(r_ang) * 2.02, -0.02, sin(r_ang) * 2.02)
		c_stone.rotation.y = -r_ang
		root.add_child(c_stone)

	var totem_angs: Array[float] = [-1.62, 1.38]
	for t_ang: float in totem_angs:
		var totem := create_totem_lantern_pillar_3d(2.18)
		totem.position = Vector3(cos(t_ang) * 2.15, -0.02, sin(t_ang) * 2.15)
		totem.rotation.y = -t_ang + PI
		root.add_child(totem)

	var fire_light := OmniLight3D.new()
	fire_light.name = "HearthLight"
	fire_light.position = Vector3(0.0, 1.25, 0.0)
	fire_light.light_color = Color(1.0, 0.64, 0.28)
	fire_light.light_energy = 2.4
	fire_light.omni_range = 12.5
	root.add_child(fire_light)
	return root


static func create_nivarel_watermill_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "NivarelWatermill3D"
	var stone_mat := _stone_mat()
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()
	var iron_mat := _iron_mat()

	# 1. Riverbank Stone Abutment & Sawmill Hall
	var abutment := MeshInstance3D.new()
	var amesh := BoxMesh.new()
	amesh.size = Vector3(4.6, 0.55, 3.5)
	abutment.mesh = amesh
	abutment.position = Vector3(0.0, 0.12, 0.0)
	abutment.material_override = stone_mat
	root.add_child(abutment)

	var sawmill := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Sawmill.glb", 3.05, {}, true
	)
	sawmill.position = Vector3(0.0, 0.34, 0.0)
	root.add_child(sawmill)

	# 2. Procedural 3D Oak Waterwheel (`diameter = 2.45 m`) dipping into the Nivarel River current
	var wheel_grp := Node3D.new()
	wheel_grp.name = "OakWaterwheel3D"
	wheel_grp.position = Vector3(2.42, 0.68, 0.15)
	root.add_child(wheel_grp)

	var axle := MeshInstance3D.new()
	var ax_mesh := CylinderMesh.new()
	ax_mesh.top_radius = 0.14
	ax_mesh.bottom_radius = 0.14
	ax_mesh.height = 1.15
	axle.mesh = ax_mesh
	axle.rotation.z = PI * 0.5
	axle.material_override = dark_wood_mat
	wheel_grp.add_child(axle)

	var hub := MeshInstance3D.new()
	var h_mesh := CylinderMesh.new()
	h_mesh.top_radius = 0.22
	h_mesh.bottom_radius = 0.22
	h_mesh.height = 0.68
	hub.mesh = h_mesh
	hub.rotation.z = PI * 0.5
	hub.material_override = iron_mat
	wheel_grp.add_child(hub)

	var paddle_count := 12
	var wheel_r := 1.18
	for i in range(paddle_count):
		var ang := float(i) * TAU / float(paddle_count)
		var next_ang := float(i + 1) * TAU / float(paddle_count)
		var mid_ang := (ang + next_ang) * 0.5

		# Twin radial oak spokes & rim segments
		var side_xs: Array[float] = [-0.24, 0.24]
		for sx: float in side_xs:
			if i % 2 == 0:
				var spoke := MeshInstance3D.new()
				var sp_mesh := BoxMesh.new()
				sp_mesh.size = Vector3(0.07, wheel_r * 1.96, 0.11)
				spoke.mesh = sp_mesh
				spoke.position = Vector3(sx, 0.0, 0.0)
				spoke.rotation.x = ang
				spoke.material_override = dark_wood_mat
				wheel_grp.add_child(spoke)

			var rim := MeshInstance3D.new()
			var r_mesh := BoxMesh.new()
			r_mesh.size = Vector3(0.09, 0.14, 0.66)
			rim.mesh = r_mesh
			rim.position = Vector3(sx, cos(mid_ang) * wheel_r, sin(mid_ang) * wheel_r)
			rim.rotation.x = -mid_ang
			rim.material_override = warm_wood_mat
			wheel_grp.add_child(rim)

		# Wide water-catching oak paddle blade
		var paddle := MeshInstance3D.new()
		var p_mesh := BoxMesh.new()
		p_mesh.size = Vector3(0.58, 0.26, 0.06)
		paddle.mesh = p_mesh
		paddle.position = Vector3(0.0, cos(ang) * (wheel_r + 0.06), sin(ang) * (wheel_r + 0.06))
		paddle.rotation.x = -ang
		paddle.material_override = warm_wood_mat
		wheel_grp.add_child(paddle)

	# 3. Timber River Pier / Log-Landing Jetty extending over the riverbank
	var pier_planks := 6
	for p_i in range(pier_planks):
		var plank := MeshInstance3D.new()
		var pl_mesh := BoxMesh.new()
		pl_mesh.size = Vector3(1.65, 0.08, 0.32)
		plank.mesh = pl_mesh
		plank.position = Vector3(1.85, 0.24, 1.85 + float(p_i) * 0.36)
		plank.material_override = warm_wood_mat
		root.add_child(plank)

	var piling_zs: Array[float] = [1.95, 3.55]
	for pz: float in piling_zs:
		var piling := MeshInstance3D.new()
		var pil_mesh := CylinderMesh.new()
		pil_mesh.top_radius = 0.09
		pil_mesh.bottom_radius = 0.11
		pil_mesh.height = 1.45
		piling.mesh = pil_mesh
		piling.position = Vector3(2.48, -0.32, pz)
		piling.material_override = dark_wood_mat
		root.add_child(piling)

	var log_stack := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.NATURE_DIR + "WoodLog_Moss.glb", 0.48, {}, true
	)
	log_stack.position = Vector3(-1.45, 0.34, 1.95)
	log_stack.rotation.y = 0.35
	root.add_child(log_stack)
	return root


static func create_east_bridge_outpost_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraEastBridgeOutpost3D"
	var stone_mat := _stone_mat()
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()

	# Stone Plinth Foundation
	var plinth := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(4.2, 0.34, 4.4)
	plinth.mesh = pmesh
	plinth.position = Vector3(0.0, 0.10, 0.0)
	plinth.material_override = stone_mat
	root.add_child(plinth)

	var main_house := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "House_2.glb", 3.78, {}, true
	)
	main_house.position = Vector3(0.0, 0.22, 0.0)
	root.add_child(main_house)

	var stone_annex := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "House_4.glb", 1.68, {}, true
	)
	stone_annex.position = Vector3(-1.55, 0.22, -0.45)
	root.add_child(stone_annex)

	_add_carved_ridge_crest(root, Vector3(0.0, 3.92, 0.0), 3.65, 0.0, dark_wood_mat, warm_wood_mat)

	var market_canopy := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "MarketStand_1.glb", 2.05, {}, true
	)
	market_canopy.position = Vector3(1.85, 0.18, 1.35)
	market_canopy.rotation.y = 0.42
	root.add_child(market_canopy)

	var barrel := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Barrel.glb", 0.84, {}, true
	)
	barrel.position = Vector3(-1.35, 0.22, 1.55)
	root.add_child(barrel)

	var rock := SevaraPropsFactory3D.create_boulder_3d(Vector3(0.72, 0.46, 0.64), true)
	rock.position = Vector3(-2.15, 0.02, 1.65)
	root.add_child(rock)
	return root


static func create_totem_lantern_pillar_3d(height_m: float = 2.25) -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraTotemLantern3D"
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()
	var iron_mat := _iron_mat()

	var post := MeshInstance3D.new()
	var pmesh := CylinderMesh.new()
	pmesh.top_radius = 0.085
	pmesh.bottom_radius = 0.115
	pmesh.height = height_m
	pmesh.radial_segments = 12
	post.mesh = pmesh
	post.position = Vector3(0.0, height_m * 0.5, 0.0)
	post.material_override = dark_wood_mat
	root.add_child(post)

	# Crossbeam arm & carved horn cap
	var arm := MeshInstance3D.new()
	var amesh := BoxMesh.new()
	amesh.size = Vector3(0.68, 0.09, 0.09)
	arm.mesh = amesh
	arm.position = Vector3(0.18, height_m - 0.22, 0.0)
	arm.material_override = warm_wood_mat
	root.add_child(arm)

	var band := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.105
	bmesh.bottom_radius = 0.108
	bmesh.height = 0.06
	band.mesh = bmesh
	band.position = Vector3(0.0, height_m - 0.22, 0.0)
	band.material_override = iron_mat
	root.add_child(band)

	var torch := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "WoodenTorch_Fire.glb", 0.56, {}, false
	)
	torch.position = Vector3(0.42, height_m - 0.52, 0.0)
	root.add_child(torch)
	return root


static func _add_carved_ridge_crest(
	parent: Node3D,
	peak_pos: Vector3,
	length_m: float,
	yaw: float,
	dark_wood_mat: Material,
	warm_wood_mat: Material
) -> void:
	var crest_grp := Node3D.new()
	crest_grp.position = peak_pos
	crest_grp.rotation.y = yaw
	parent.add_child(crest_grp)

	var beam := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.14, 0.16, length_m)
	beam.mesh = bmesh
	beam.material_override = dark_wood_mat
	crest_grp.add_child(beam)

	# Crossed Heruna antler-horn gable finials at both ends of the ridge beam
	var end_zs: Array[float] = [-length_m * 0.48, length_m * 0.48]
	for ez: float in end_zs:
		var side_signs: Array[float] = [-1.0, 1.0]
		for s_sign: float in side_signs:
			var horn := MeshInstance3D.new()
			var hmesh := BoxMesh.new()
			hmesh.size = Vector3(0.07, 0.62, 0.09)
			horn.mesh = hmesh
			horn.position = Vector3(s_sign * 0.12, 0.22, ez)
			horn.rotation.z = -s_sign * 0.52
			horn.material_override = warm_wood_mat
			crest_grp.add_child(horn)


static func _stone_mat() -> Material:
	return SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_cobble_masonry",
		Color(0.44, 0.42, 0.38),
		Color.BLACK,
		0.48,
		0.42,
		0.78,
		0.82,
		0.0,
		0.65
	)


static func _dark_wood_mat() -> Material:
	return SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_village_timber", Color(0.42, 0.31, 0.21), Color.BLACK, 0.48, 0.45, 0.75, 0.80
	)


static func _warm_wood_mat() -> Material:
	return SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_village_timber", Color(0.56, 0.44, 0.30), Color.BLACK, 0.50, 0.46, 0.72, 0.76
	)


static func _iron_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.19)
	m.metallic = 0.80
	m.roughness = 0.36
	return m

class_name SevaraSettlementArchitect3D
extends RefCounted
## Процедурно-модульный архитектор поселения Севары (Шаг 4 v7).
##
## Реализует все 5 этапов технической и художественной полировки:
## 1) Выравнивание зданий по сетке X/Z (Snap to Grid), идеальная центровка двускатных
##    крыш, отсутствие висящих/торчащих балок и физическое погружение колеса мельницы
##    в воду реки Ниварель на 30% диаметра;
## 2) Монолитные каменные фундаменты, утопленные на 8 см в землю, и мягкие контактные
##    тени (50% opacity Contact Shadow Decals + SSAO) под каждым домом и пропсом;
## 3) PBR-материалы: рельефная черепица разных оттенков с Normal Map, матовое дерево
##    с волокнами и матовая штукатурка с приземной грязью (Grime) внизу стен;
## 4) Светящиеся тёплым жёлтым светом окна, костёр на углях (Coal bed) с дымом,
##    котёл, подвешенный на кованой 3D-цепи (Chain) над огнём, и белая пена у колеса;
## 5) Протоптанные тропинки от каждого дома к дороге, разнообразные типы зданий
##    (Длинный Дом, Кузница с дымом и горном, Амбар/Сарай, Павильон Хроники, Мельница,
##    Восточная Застава) и солнечные лучи (God Rays) сквозь деревья.


static func populate_settlement(settlement_root: Node3D) -> void:
	# 1. Western Craft Terrace: Mountain Blacksmith with Forge Glow & Chimney Smoke
	var bs_pos := Vector2(-18.5, -7.5)
	var smithy := create_blacksmith_craft_yard_3d()
	smithy.position = Vector3(
		bs_pos.x, SevaraTerrainGen3D.get_height_at(bs_pos.x, bs_pos.y) - 0.08, bs_pos.y
	)
	smithy.rotation.y = 0.0
	settlement_root.add_child(smithy)

	# 2. Western Upper Terrace: Chieftain's Slate-Roofed Longhouse (Grid-Aligned)
	var lh_pos := Vector2(-13.5, -10.5)
	var longhouse := create_longhouse_bastion_3d()
	longhouse.position = Vector3(
		lh_pos.x, SevaraTerrainGen3D.get_height_at(lh_pos.x, lh_pos.y) - 0.08, lh_pos.y
	)
	longhouse.rotation.y = 0.0
	settlement_root.add_child(longhouse)

	# 3. Homestead Forecourt: Stone Well Plaza
	var well_pos := Vector2(-12.0, -6.0)
	var well_plaza := create_well_plaza_3d()
	well_plaza.position = Vector3(
		well_pos.x, SevaraTerrainGen3D.get_height_at(well_pos.x, well_pos.y) - 0.07, well_pos.y
	)
	well_plaza.rotation.y = 0.0
	settlement_root.add_child(well_plaza)

	# 4. Northern Meadow Terrace: Timber Barn, Stable & Hay Yard
	var barn_pos := Vector2(-7.2, -15.8)
	var barn := create_barn_stable_yard_3d()
	barn.position = Vector3(
		barn_pos.x, SevaraTerrainGen3D.get_height_at(barn_pos.x, barn_pos.y) - 0.08, barn_pos.y
	)
	barn.rotation.y = 0.0
	settlement_root.add_child(barn)

	# 5. Central Terrace: Selima's Chronicle Pavilion
	var pav_pos := Vector2(-5.4, -8.2)
	var scriptorium := create_selima_chronicle_hall_3d()
	scriptorium.position = Vector3(
		pav_pos.x, SevaraTerrainGen3D.get_height_at(pav_pos.x, pav_pos.y) - 0.07, pav_pos.y
	)
	scriptorium.rotation.y = 0.0
	settlement_root.add_child(scriptorium)

	# 6. Nivarel Rapids Bank: Centered-Roof Watermill with Submerged Waterwheel & White Foam
	var mill_pos := Vector2(-0.8, -12.2)
	var watermill := create_nivarel_watermill_3d()
	watermill.position = Vector3(mill_pos.x, SevaraTerrainGen3D.WATER_SURFACE_Y + 0.02, mill_pos.y)
	watermill.rotation.y = 0.0
	settlement_root.add_child(watermill)

	# 7. Riverbank Promontory: Ancestral Hearth with Coal Bed, Smoke & Chain-Suspended Cauldron
	var hearth_pos := Vector2(0.6, -4.8)
	var hearth := create_sevara_hearth_sanctuary_3d()
	hearth.position = Vector3(
		hearth_pos.x,
		SevaraTerrainGen3D.get_height_at(hearth_pos.x, hearth_pos.y) - 0.02,
		hearth_pos.y
	)
	settlement_root.add_child(hearth)

	# 8. East Bank Crossing: Fortified Bridge Outpost & Trading Stand
	var east_pos := Vector2(23.0, -5.0)
	var outpost := create_east_bridge_outpost_3d()
	outpost.position = Vector3(
		east_pos.x, SevaraTerrainGen3D.get_height_at(east_pos.x, east_pos.y) - 0.08, east_pos.y
	)
	outpost.rotation.y = -PI * 0.5
	settlement_root.add_child(outpost)

	# 9. Bridgehead Lantern Pillars & Southern River Weir
	var gate_posts: Array[Vector3] = [
		Vector3(4.6, -0.35, 0.0),
		Vector3(19.4, -0.45, 0.0),
	]
	for gp: Vector3 in gate_posts:
		var post := create_totem_lantern_pillar_3d(1.62)
		post.position = Vector3(gp.x, SevaraTerrainGen3D.get_height_at(gp.x, gp.y) - 0.05, gp.y)
		settlement_root.add_child(post)

	var weir_z := 13.8
	var weir := SevaraPropsFactory3D.create_weir_barrier_3d(5.4)
	weir.position = Vector3(
		SevaraTerrainGen3D.river_center_x(weir_z), SevaraTerrainGen3D.WATER_SURFACE_Y - 0.05, weir_z
	)
	weir.rotation.y = -0.18
	settlement_root.add_child(weir)

	# 10. Atmospheric Volumetric Sunbeams (God Rays) piercing through tree canopies
	settlement_root.add_child(create_sunbeams_god_rays_3d())


static func create_longhouse_bastion_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraLonghouseBastion3D"

	# Deep Mountain Slate Roof & Warm Earth-Toned Plaster (distinct from all other buildings)
	var overrides := {
		"RoofTiles": Color(0.22, 0.27, 0.31),
		"Plaster": Color(0.66, 0.60, 0.50),
	}
	var house := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "House_1.glb", 3.95, overrides, true
	)
	house.scale = Vector3(1.24, 1.0, 1.18)
	root.add_child(house)
	_add_contact_shadow(root, Vector3(0.0, 0.09, 0.0), 3.35, 3.45, 0.58)

	# Warm window glow light & chimney smoke plume
	_add_warm_window_light(root, Vector3(0.0, 1.65, 1.35), Color(1.0, 0.72, 0.30), 1.45, 7.5)
	_add_smoke_plume(root, Vector3(-0.26, 3.85, -0.82), 1.0)

	# Non-overlapping homestead props with individual 50% contact shadows
	var log_pile := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.NATURE_DIR + "WoodLog_Moss.glb", 0.44, {}, true
	)
	log_pile.position = Vector3(1.95, 0.06, 0.65)
	root.add_child(log_pile)
	_add_contact_shadow(root, Vector3(1.95, 0.09, 0.65), 1.15, 0.85, 0.52)

	var barrel := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Barrel.glb", 0.82, {}, true
	)
	barrel.position = Vector3(-1.72, 0.06, 1.15)
	root.add_child(barrel)
	_add_contact_shadow(root, Vector3(-1.72, 0.09, 1.15), 0.72, 0.72, 0.54)

	var sacks := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bags.glb", 0.56, {}, true
	)
	sacks.position = Vector3(-1.72, 0.06, 0.32)
	root.add_child(sacks)
	_add_contact_shadow(root, Vector3(-1.72, 0.09, 0.32), 0.76, 0.68, 0.50)

	var fence := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Fence.glb", 1.12, {}, true
	)
	fence.position = Vector3(-2.45, 0.06, 1.55)
	root.add_child(fence)
	_add_contact_shadow(root, Vector3(-2.45, 0.09, 1.55), 1.55, 0.42, 0.46)
	return root


static func create_blacksmith_craft_yard_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraBlacksmithYard3D"

	# Kiln-Fired Dark Terracotta Roof & Soot-Stained Stone Forge
	var overrides := {
		"RoofTiles_Red": Color(0.48, 0.24, 0.17),
		"Plaster": Color(0.58, 0.52, 0.44),
	}
	var smithy := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Blacksmith.glb", 3.28, overrides, true
	)
	root.add_child(smithy)
	_add_contact_shadow(root, Vector3(0.0, 0.09, 0.0), 4.10, 3.55, 0.58)

	# Glowing outdoor forge coal bed, fire, orange smithy light & double smoke plumes
	var forge_pos := Vector3(1.52, 0.06, 1.38)
	_add_coal_bed(root, forge_pos + Vector3(0.0, 0.02, 0.0), 0.92)
	var forge_fire := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bonfire_Lit.glb", 0.58, {}, true
	)
	forge_fire.position = forge_pos
	root.add_child(forge_fire)

	_add_warm_window_light(root, Vector3(0.95, 1.25, 1.25), Color(1.0, 0.46, 0.14), 2.15, 9.5)
	_add_smoke_plume(root, Vector3(0.32, 3.18, -0.88), 1.15)
	_add_smoke_plume(root, forge_pos + Vector3(0.0, 0.65, 0.0), 0.78)

	var cart := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Cart.glb", 1.18, {}, true
	)
	cart.position = Vector3(-2.35, 0.06, 1.45)
	cart.rotation.y = 0.25
	root.add_child(cart)
	_add_contact_shadow(root, Vector3(-2.35, 0.09, 1.45), 1.65, 1.25, 0.54)

	var stump := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.NATURE_DIR + "TreeStump_Moss.glb", 0.56, {}, true
	)
	stump.position = Vector3(-0.75, 0.06, 1.92)
	root.add_child(stump)
	_add_contact_shadow(root, Vector3(-0.75, 0.09, 1.92), 0.78, 0.78, 0.52)

	var axe := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Axe_small.glb", 0.46, {}, false
	)
	axe.position = Vector3(-0.72, 0.54, 1.92)
	axe.rotation = Vector3(0.35, 0.8, -0.45)
	root.add_child(axe)
	return root


static func create_barn_stable_yard_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraBarnStable3D"

	# Warm Cedar-Shingle Roof & Timber Barn/Stable (`Stable.glb` standalone, grid-aligned)
	var overrides := {
		"RoofTiles": Color(0.42, 0.30, 0.19),
		"Beige": Color(0.62, 0.55, 0.44),
	}
	var stable := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Stable.glb", 2.78, overrides, true
	)
	root.add_child(stable)
	_add_contact_shadow(root, Vector3(0.0, 0.09, 0.0), 4.85, 3.45, 0.58)
	_add_warm_window_light(root, Vector3(0.85, 1.35, 1.25), Color(1.0, 0.72, 0.30), 1.25, 6.8)
	_add_smoke_plume(root, Vector3(1.52, 2.72, 0.68), 0.82)

	var hay := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Hay.glb", 0.78, {}, true
	)
	hay.position = Vector3(-1.35, 0.06, 1.55)
	root.add_child(hay)
	_add_contact_shadow(root, Vector3(-1.35, 0.09, 1.55), 1.15, 0.95, 0.52)

	var fence := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Fence.glb", 1.12, {}, true
	)
	fence.position = Vector3(2.45, 0.06, 1.25)
	root.add_child(fence)
	_add_contact_shadow(root, Vector3(2.45, 0.09, 1.25), 1.55, 0.42, 0.46)
	return root


static func create_well_plaza_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraWellPlaza3D"

	var well := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Well.glb", 2.15, {}, true
	)
	root.add_child(well)
	_add_contact_shadow(root, Vector3(0.0, 0.08, 0.0), 1.85, 1.85, 0.58)

	var barrel := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Barrel.glb", 0.76, {}, true
	)
	barrel.position = Vector3(1.05, 0.06, -0.25)
	root.add_child(barrel)
	_add_contact_shadow(root, Vector3(1.05, 0.08, -0.25), 0.68, 0.68, 0.54)

	var crate := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Crate.glb", 0.52, {}, true
	)
	crate.position = Vector3(-1.05, 0.06, 0.25)
	root.add_child(crate)
	_add_contact_shadow(root, Vector3(-1.05, 0.08, 0.25), 0.68, 0.68, 0.52)
	return root


static func create_selima_chronicle_hall_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "ChroniclePavilion3D"
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()

	# Forest-Olive Shingle Roof over the Centered 4-Pillar Pavilion (`Gazebo.glb`)
	var overrides := {
		"RoofTiles_Red": Color(0.28, 0.35, 0.22),
	}
	var portico := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Gazebo.glb", 2.78, overrides, true
	)
	root.add_child(portico)
	_add_contact_shadow(root, Vector3(0.0, 0.08, 0.0), 2.55, 2.55, 0.56)

	var bench := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bench_1.glb", 0.54, {}, true
	)
	bench.position = Vector3(0.0, 0.06, -0.42)
	root.add_child(bench)
	_add_contact_shadow(root, Vector3(0.0, 0.08, -0.42), 1.15, 0.55, 0.50)

	var desk_top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(1.22, 0.08, 0.62)
	desk_top.mesh = top_mesh
	desk_top.position = Vector3(0.0, 0.76, 0.15)
	desk_top.material_override = warm_wood_mat
	root.add_child(desk_top)

	var leg_xs: Array[float] = [-0.46, 0.46]
	for lx: float in leg_xs:
		var leg := MeshInstance3D.new()
		var lmesh := BoxMesh.new()
		lmesh.size = Vector3(0.13, 0.68, 0.48)
		leg.mesh = lmesh
		leg.position = Vector3(lx, 0.40, 0.15)
		leg.material_override = dark_wood_mat
		root.add_child(leg)
	_add_contact_shadow(root, Vector3(0.0, 0.08, 0.15), 1.35, 0.78, 0.52)

	var book := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Book1_Open.glb", 0.09, {}, false
	)
	book.position = Vector3(0.0, 0.81, 0.15)
	root.add_child(book)

	_add_warm_window_light(root, Vector3(0.0, 1.55, 0.15), Color(1.0, 0.76, 0.36), 1.35, 6.5)
	return root


static func create_sevara_hearth_sanctuary_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "CommunalHearth3D"
	var dark_wood_mat := _dark_wood_mat()
	var iron_mat := _iron_mat()

	# 1. Glowing Ember & Ash Coal Bed under the Central Hearth Fire
	_add_coal_bed(root, Vector3(0.0, 0.02, 0.0), 1.38)
	root.add_child(
		SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Bonfire_Lit.glb", 0.82, {}, true
		)
	)

	# 2. Cast-Iron Cauldron suspended directly over the fire on a Forged 3D Iron Chain
	var cauldron := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Cauldron.glb", 0.52, {}, true
	)
	cauldron.position = Vector3(0.0, 0.34, 0.0)
	root.add_child(cauldron)

	# 3-Pole Timber Tripod + Top Iron Ring + Vertical 8-Link Forged Iron Chain (`TorusMesh`)
	var pole_cyl := CylinderMesh.new()
	pole_cyl.top_radius = 0.034
	pole_cyl.bottom_radius = 0.052
	pole_cyl.height = 1.86
	pole_cyl.radial_segments = 10
	for p_idx in range(3):
		var p_ang := float(p_idx) * TAU / 3.0 + 0.45
		var pole := MeshInstance3D.new()
		pole.mesh = pole_cyl
		var base_r := 0.48
		pole.position = Vector3(cos(p_ang) * base_r, 0.82, sin(p_ang) * base_r)
		pole.rotation = Vector3(-sin(p_ang) * 0.27, 0.0, cos(p_ang) * 0.27)
		pole.material_override = dark_wood_mat
		root.add_child(pole)

	var ring := MeshInstance3D.new()
	var rmesh := TorusMesh.new()
	rmesh.inner_radius = 0.065
	rmesh.outer_radius = 0.105
	rmesh.rings = 12
	rmesh.ring_segments = 8
	ring.mesh = rmesh
	ring.position = Vector3(0.0, 1.62, 0.0)
	ring.material_override = iron_mat
	root.add_child(ring)

	var link_mesh := TorusMesh.new()
	link_mesh.inner_radius = 0.024
	link_mesh.outer_radius = 0.046
	link_mesh.rings = 10
	link_mesh.ring_segments = 6
	for l_i in range(8):
		var link := MeshInstance3D.new()
		link.mesh = link_mesh
		link.position = Vector3(0.0, 1.54 - float(l_i) * 0.095, 0.0)
		link.rotation.z = PI * 0.5
		link.rotation.y = float(l_i % 2) * PI * 0.5
		link.material_override = iron_mat
		root.add_child(link)

	# 3. Rising Hearth Smoke Plume & Warm Fire OmniLight illuminating ground and cauldron
	_add_smoke_plume(root, Vector3(0.0, 0.92, 0.0), 1.22)

	var fire_light := OmniLight3D.new()
	fire_light.name = "HearthLight"
	fire_light.position = Vector3(0.0, 1.18, 0.0)
	fire_light.light_color = Color(1.0, 0.62, 0.24)
	fire_light.light_energy = 2.65
	fire_light.omni_range = 13.5
	root.add_child(fire_light)

	# 4. Council Benches with 50% Contact Shadows
	var bench_angs: Array[float] = [-1.18, 0.86]
	for ang: float in bench_angs:
		var b_pos := Vector3(cos(ang) * 1.56, 0.0, sin(ang) * 1.56)
		var bench := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Bench_1.glb", 0.55, {}, true
		)
		bench.position = b_pos
		bench.rotation.y = -ang + PI * 0.5
		root.add_child(bench)
		_add_contact_shadow(root, b_pos + Vector3(0.0, 0.02, 0.0), 1.15, 0.55, 0.52)

	var totem := create_totem_lantern_pillar_3d(1.62)
	totem.position = Vector3(cos(-1.65) * 2.08, -0.02, sin(-1.65) * 2.08)
	totem.rotation.y = 1.65 + PI
	root.add_child(totem)
	return root


static func create_nivarel_watermill_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "NivarelWatermill3D"
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()
	var iron_mat := _iron_mat()

	# 1. Symmetrical Centered-Roof Mill House (`House_1.glb`) sunk cleanly into the riverbank
	var overrides := {
		"RoofTiles": Color(0.36, 0.27, 0.19),
		"Plaster": Color(0.62, 0.56, 0.47),
	}
	var mill_house := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "House_1.glb", 3.35, overrides, true
	)
	mill_house.scale = Vector3(1.18, 0.96, 1.14)
	mill_house.position = Vector3(0.0, -0.06, 0.0)
	root.add_child(mill_house)
	_add_contact_shadow(root, Vector3(-0.15, 0.03, 0.0), 2.85, 2.95, 0.56)
	_add_warm_window_light(root, Vector3(0.0, 1.35, 1.22), Color(1.0, 0.72, 0.30), 1.35, 6.8)
	_add_smoke_plume(root, Vector3(-0.22, 3.22, -0.72), 0.78)

	# 2. Submerged Oak Waterwheel (`radius = 1.24 m`) attached flush to the right stone wall
	# Mill sits at `y = WATER_SURFACE_Y + 0.02 = 0.44`. Wheel center at `y = 0.42` (`world_y = 0.86`).
	# Bottom of wheel reaches `world_y = 0.86 - 1.24 = -0.38 m` (0.80 m / 32% submerged under water!)
	var wheel_grp := Node3D.new()
	wheel_grp.name = "OakWaterwheel3D"
	wheel_grp.position = Vector3(1.26, 0.42, 0.0)
	root.add_child(wheel_grp)

	var axle := MeshInstance3D.new()
	var ax_mesh := CylinderMesh.new()
	ax_mesh.top_radius = 0.14
	ax_mesh.bottom_radius = 0.14
	ax_mesh.height = 0.95
	axle.mesh = ax_mesh
	axle.position = Vector3(-0.18, 0.0, 0.0)
	axle.rotation.z = PI * 0.5
	axle.material_override = dark_wood_mat
	wheel_grp.add_child(axle)

	var hub := MeshInstance3D.new()
	var h_mesh := CylinderMesh.new()
	h_mesh.top_radius = 0.23
	h_mesh.bottom_radius = 0.23
	h_mesh.height = 0.66
	hub.mesh = h_mesh
	hub.rotation.z = PI * 0.5
	hub.material_override = iron_mat
	wheel_grp.add_child(hub)

	var paddle_count := 12
	var wheel_r := 1.20
	for i in range(paddle_count):
		var ang := float(i) * TAU / float(paddle_count)
		var next_ang := float(i + 1) * TAU / float(paddle_count)
		var mid_ang := (ang + next_ang) * 0.5
		var side_xs: Array[float] = [-0.24, 0.24]
		for sx: float in side_xs:
			if i % 2 == 0:
				var spoke := MeshInstance3D.new()
				var sp_mesh := BoxMesh.new()
				sp_mesh.size = Vector3(0.075, wheel_r * 1.96, 0.11)
				spoke.mesh = sp_mesh
				spoke.position = Vector3(sx, 0.0, 0.0)
				spoke.rotation.x = ang
				spoke.material_override = dark_wood_mat
				wheel_grp.add_child(spoke)

			var rim := MeshInstance3D.new()
			var r_mesh := BoxMesh.new()
			r_mesh.size = Vector3(0.095, 0.15, 0.68)
			rim.mesh = r_mesh
			rim.position = Vector3(sx, cos(mid_ang) * wheel_r, sin(mid_ang) * wheel_r)
			rim.rotation.x = -mid_ang
			rim.material_override = warm_wood_mat
			wheel_grp.add_child(rim)

		var paddle := MeshInstance3D.new()
		var p_mesh := BoxMesh.new()
		p_mesh.size = Vector3(0.58, 0.26, 0.065)
		paddle.mesh = p_mesh
		paddle.position = Vector3(0.0, cos(ang) * (wheel_r + 0.06), sin(ang) * (wheel_r + 0.06))
		paddle.rotation.x = -ang
		paddle.material_override = warm_wood_mat
		wheel_grp.add_child(paddle)

	# 3. White Water Foam & Splash Particles where the wheel paddles enter the river
	_add_waterwheel_foam_particles(root, Vector3(1.26, -0.01, 0.35))

	var sacks := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bags.glb", 0.58, {}, true
	)
	sacks.position = Vector3(-1.45, 0.0, 0.85)
	root.add_child(sacks)
	_add_contact_shadow(root, Vector3(-1.45, 0.02, 0.85), 0.78, 0.68, 0.50)
	return root


static func create_east_bridge_outpost_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraEastBridgeOutpost3D"

	# Warm Red-Ochre Clay Tile Roof (`House_2.glb` standalone, grid-aligned, no protruding beams)
	var overrides := {
		"RoofTiles": Color(0.45, 0.27, 0.19),
		"Beige": Color(0.64, 0.57, 0.47),
	}
	var main_house := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "House_2.glb", 3.68, overrides, true
	)
	root.add_child(main_house)
	_add_contact_shadow(root, Vector3(0.0, 0.09, 0.0), 3.15, 3.85, 0.58)
	_add_warm_window_light(root, Vector3(0.0, 1.55, 1.45), Color(1.0, 0.72, 0.30), 1.45, 7.5)
	_add_smoke_plume(root, Vector3(-0.98, 3.35, -0.35), 0.95)

	var market_canopy := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "MarketStand_1.glb", 1.98, {}, true
	)
	market_canopy.position = Vector3(2.25, 0.06, 1.45)
	root.add_child(market_canopy)
	_add_contact_shadow(root, Vector3(2.25, 0.09, 1.45), 1.95, 1.55, 0.52)

	var barrel := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Barrel.glb", 0.80, {}, true
	)
	barrel.position = Vector3(-1.55, 0.06, 1.45)
	root.add_child(barrel)
	_add_contact_shadow(root, Vector3(-1.55, 0.09, 1.45), 0.72, 0.72, 0.54)
	return root


static func create_totem_lantern_pillar_3d(height_m: float = 1.62) -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraTotemLantern3D"
	var dark_wood_mat := _dark_wood_mat()
	var warm_wood_mat := _warm_wood_mat()
	var iron_mat := _iron_mat()

	_add_contact_shadow(root, Vector3(0.0, 0.06, 0.0), 0.65, 0.65, 0.50)

	var post := MeshInstance3D.new()
	var pmesh := CylinderMesh.new()
	pmesh.top_radius = 0.086
	pmesh.bottom_radius = 0.115
	pmesh.height = height_m
	pmesh.radial_segments = 12
	post.mesh = pmesh
	post.position = Vector3(0.0, height_m * 0.5, 0.0)
	post.material_override = dark_wood_mat
	root.add_child(post)

	var arm := MeshInstance3D.new()
	var amesh := BoxMesh.new()
	amesh.size = Vector3(0.54, 0.08, 0.08)
	arm.mesh = amesh
	arm.position = Vector3(0.15, height_m - 0.18, 0.0)
	arm.material_override = warm_wood_mat
	root.add_child(arm)

	var band := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.104
	bmesh.bottom_radius = 0.108
	band.mesh = bmesh
	bmesh.height = 0.055
	band.position = Vector3(0.0, height_m - 0.18, 0.0)
	band.material_override = iron_mat
	root.add_child(band)

	var torch := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "WoodenTorch_Fire.glb", 0.50, {}, false
	)
	torch.position = Vector3(0.34, height_m - 0.42, 0.0)
	root.add_child(torch)
	return root


static func create_sunbeams_god_rays_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "SunbeamsGodRays3D"
	var mat := ShaderMaterial.new()
	mat.shader = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	mat.set_shader_parameter("vfx_mode", 4)
	mat.set_shader_parameter("tint_color", Color(1.0, 0.92, 0.68, 0.16))
	mat.set_shader_parameter("intensity", 1.0)

	var ray_specs: Array[Vector3] = [
		Vector3(-19.5, 6.2, -14.5),
		Vector3(-9.5, 6.6, -18.5),
		Vector3(3.5, 6.0, -16.5),
		Vector3(18.5, 6.4, -11.5),
	]
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(3.8, 13.5)
	for rs: Vector3 in ray_specs:
		for cross_i in range(2):
			var beam := MeshInstance3D.new()
			beam.mesh = qmesh
			beam.position = rs
			beam.rotation_degrees = Vector3(-28.0, -34.0 + float(cross_i) * 58.0, 22.0)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.material_override = mat
			root.add_child(beam)
	return root


static func _add_contact_shadow(
	parent: Node3D, pos: Vector3, size_x: float, size_z: float, opacity: float = 0.52
) -> void:
	var disc := MeshInstance3D.new()
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(size_x, size_z)
	qmesh.orientation = PlaneMesh.FACE_Y
	disc.mesh = qmesh
	disc.position = pos
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	mat.set_shader_parameter("vfx_mode", 0)
	mat.set_shader_parameter("tint_color", Color(0.02, 0.03, 0.02, opacity))
	disc.material_override = mat
	parent.add_child(disc)


static func _add_coal_bed(parent: Node3D, pos: Vector3, diameter: float) -> void:
	var coal := MeshInstance3D.new()
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(diameter, diameter)
	qmesh.orientation = PlaneMesh.FACE_Y
	coal.mesh = qmesh
	coal.position = pos
	coal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	mat.set_shader_parameter("vfx_mode", 1)
	coal.material_override = mat
	parent.add_child(coal)


static func _add_smoke_plume(parent: Node3D, pos: Vector3, scale_fac: float = 1.0) -> void:
	var smoke_grp := Node3D.new()
	smoke_grp.position = pos
	parent.add_child(smoke_grp)

	var mat := ShaderMaterial.new()
	mat.shader = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	mat.set_shader_parameter("vfx_mode", 2)
	mat.set_shader_parameter("tint_color", Color(0.74, 0.76, 0.78, 0.34))
	mat.set_shader_parameter("intensity", 1.0)

	var puff_mesh := SphereMesh.new()
	puff_mesh.radial_segments = 10
	puff_mesh.rings = 6

	var particles := CPUParticles3D.new()
	particles.amount = 14
	particles.lifetime = 3.2
	particles.preprocess = 2.5
	particles.mesh = puff_mesh
	particles.direction = Vector3(0.18, 1.0, 0.12).normalized()
	particles.spread = 14.0
	particles.gravity = Vector3(0.12, 0.38, 0.06)
	particles.initial_velocity_min = 0.35 * scale_fac
	particles.initial_velocity_max = 0.62 * scale_fac
	particles.scale_amount_min = 0.28 * scale_fac
	particles.scale_amount_max = 0.68 * scale_fac
	particles.material_override = mat
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke_grp.add_child(particles)


static func _add_waterwheel_foam_particles(parent: Node3D, pos: Vector3) -> void:
	var foam_grp := Node3D.new()
	foam_grp.position = pos
	parent.add_child(foam_grp)

	var mat := ShaderMaterial.new()
	mat.shader = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	mat.set_shader_parameter("vfx_mode", 3)
	mat.set_shader_parameter("tint_color", Color(0.92, 0.97, 1.0, 0.68))
	mat.set_shader_parameter("intensity", 1.15)

	var drop_mesh := SphereMesh.new()
	drop_mesh.radial_segments = 8
	drop_mesh.rings = 5

	var spray := CPUParticles3D.new()
	spray.amount = 18
	spray.lifetime = 1.1
	spray.preprocess = 1.0
	spray.mesh = drop_mesh
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spray.emission_box_extents = Vector3(0.32, 0.08, 0.75)
	spray.direction = Vector3(0.25, 0.75, 0.65).normalized()
	spray.spread = 32.0
	spray.gravity = Vector3(0.0, -2.4, 0.85)
	spray.initial_velocity_min = 0.55
	spray.initial_velocity_max = 1.15
	spray.scale_amount_min = 0.16
	spray.scale_amount_max = 0.38
	spray.material_override = mat
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foam_grp.add_child(spray)


static func _add_warm_window_light(
	parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float
) -> void:
	var lgt := OmniLight3D.new()
	lgt.position = pos
	lgt.light_color = col
	lgt.light_energy = energy
	lgt.omni_range = rng
	parent.add_child(lgt)


static func _dark_wood_mat() -> Material:
	return SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_village_timber", Color(0.42, 0.31, 0.21), Color.BLACK, 0.48, 0.45, 0.75, 0.88
	)


static func _warm_wood_mat() -> Material:
	return SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_village_timber", Color(0.56, 0.44, 0.30), Color.BLACK, 0.50, 0.46, 0.72, 0.86
	)


static func _iron_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.19)
	m.metallic = 0.80
	m.roughness = 0.36
	return m

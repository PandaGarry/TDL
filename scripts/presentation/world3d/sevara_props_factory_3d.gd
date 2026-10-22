class_name SevaraPropsFactory3D
extends RefCounted
## Builds 3D nature, MultiMesh meadows, boulders, trees, medieval village structures,
## and river engineering props for the Sevara Valley using CC0 glTF/GLB assets and custom shaders.

const PINE_MODELS: Array[String] = ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
const BROADLEAF_MODELS: Array[String] = [
	"CommonTree_1",
	"CommonTree_2",
	"CommonTree_3",
	"CommonTree_4",
	"TwistedTree_1",
	"TwistedTree_2",
]
const ROCK_MODELS: Array[String] = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]


static func create_tree_3d(variant: int = 0, is_stump: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Stump3D" if is_stump else "Tree3D"
	if is_stump:
		var stump_path := (
			SevaraAssetLibrary3D.NATURE_DIR
			+ ("TreeStump_Moss.glb" if variant % 3 != 2 else "WoodLog_Moss.glb")
		)
		var target_h := 0.85 if variant % 3 != 2 else 0.65
		var stump := SevaraAssetLibrary3D.instantiate_model(stump_path, target_h, {}, true)
		stump.rotation.y = float(variant) * 1.17
		root.add_child(stump)
		return root

	var is_pine := (variant % 3) != 1
	var model_name := (
		PINE_MODELS[posmod(variant, PINE_MODELS.size())]
		if is_pine
		else BROADLEAF_MODELS[posmod(variant, BROADLEAF_MODELS.size())]
	)
	var style := {
		"stiffness": 3.8 if is_pine else 3.2,
		"leaves":
		{
			"color_dark": Color(0.11, 0.27, 0.12) if is_pine else Color(0.15, 0.34, 0.12),
			"color_light": Color(0.28, 0.50, 0.22) if is_pine else Color(0.42, 0.64, 0.22),
			"texture_color_mix": 0.32,
			"snow_cover": 0.14 if is_pine else 0.04,
		},
	}
	var mesh := SevaraAssetLibrary3D.nature_mesh(model_name, style)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var scale_f := 0.88 + float(posmod(variant * 7, 5)) * 0.08
	mi.scale = Vector3(scale_f, scale_f, scale_f)
	mi.rotation.y = float(variant) * 0.93
	root.add_child(mi)
	return root


static func create_boulder_3d(scale_vec: Vector3 = Vector3.ONE, mossy: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Boulder3D"
	var idx := posmod(int(round((scale_vec.x + scale_vec.z) * 10.0)), ROCK_MODELS.size())
	var model_name: String = ROCK_MODELS[idx]
	var style := {
		"rock":
		{
			"moss_amount": 0.65 if mossy else 0.12,
			"snow_amount": 0.18 if scale_vec.y > 1.25 else 0.04,
			"wetness": 0.18 if mossy else 0.45,
			"triplanar": 1.0,
		}
	}
	var mesh := SevaraAssetLibrary3D.nature_mesh(model_name, style)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = scale_vec * 0.92
	root.add_child(mi)
	return root


static func create_kevar_bush_3d(is_kevalu: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "KevaluLocus3D" if is_kevalu else "KevarBush3D"

	# Base botanical bush model from Quaternius Nature kit
	var bush_style := {
		"plant":
		{
			"color_dark": Color(0.24, 0.30, 0.34) if is_kevalu else Color(0.14, 0.34, 0.14),
			"color_light": Color(0.56, 0.68, 0.76) if is_kevalu else Color(0.38, 0.64, 0.26),
			"texture_color_mix": 0.45,
		}
	}
	var base_mesh := SevaraAssetLibrary3D.nature_mesh("Bush_Common_Flowers", bush_style)
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = base_mesh
	base_mi.scale = Vector3(0.68, 0.68, 0.68)
	root.add_child(base_mi)

	# Upright medicinal spikes (Kevar warm cream-green vs Kevalu slate-ash frost)
	var spike_mesh := SevaraAssetLibrary3D.nature_mesh("Proc_Kevalu" if is_kevalu else "Proc_Kevar")
	var spike_mi := MeshInstance3D.new()
	spike_mi.mesh = spike_mesh
	spike_mi.scale = Vector3(0.95, 0.95, 0.95)
	root.add_child(spike_mi)
	return root


static func create_reed_clump_3d(variant: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "ReedClump3D"
	var reed_mesh := SevaraAssetLibrary3D.nature_mesh("Proc_Reeds")
	var mi := MeshInstance3D.new()
	mi.mesh = reed_mesh
	var s := 0.85 + float(posmod(variant, 4)) * 0.12
	mi.scale = Vector3(s, s, s)
	mi.rotation.y = float(variant) * 1.1
	root.add_child(mi)
	return root


static func create_log_house_3d(
	size: Vector3 = Vector3(2.8, 1.5, 2.1), roof_height: float = 1.1, warm_window: bool = true
) -> Node3D:
	var house_idx := posmod(int(round((size.x + size.z) * 3.0)), 4) + 1
	var target_h := maxf(size.y + roof_height, 3.6)
	var overrides := {}
	if not warm_window:
		overrides["Windows"] = Color(0.18, 0.22, 0.26)
	var model := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + ("House_%d.glb" % house_idx), target_h, overrides, true
	)
	model.name = "LogHouse3D"
	return model


static func create_chronicle_pavilion_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "ChroniclePavilion3D"
	var gazebo := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Gazebo.glb", 3.85, {}, true
	)
	root.add_child(gazebo)

	var bench := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bench_1.glb", 0.72, {}, true
	)
	bench.position = Vector3(0.0, 0.05, -0.45)
	root.add_child(bench)

	var book := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Book1_Open.glb", 0.28, {}, false
	)
	book.position = Vector3(0.0, 0.76, 0.05)
	root.add_child(book)
	return root


static func create_hearth_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "CommunalHearth3D"

	var bonfire := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bonfire_Lit.glb", 0.95, {}, true
	)
	root.add_child(bonfire)

	var cauldron := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Cauldron.glb", 0.82, {}, true
	)
	cauldron.position = Vector3(0.65, 0.0, 0.25)
	root.add_child(cauldron)

	for i in range(3):
		var ang := float(i) * TAU / 3.0 + 0.35
		var bench := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + ("Bench_%d.glb" % ((i % 2) + 1)), 0.68, {}, true
		)
		bench.position = Vector3(cos(ang) * 2.1, 0.0, sin(ang) * 2.1)
		bench.rotation.y = -ang + PI * 0.5
		root.add_child(bench)

	var fire_light := OmniLight3D.new()
	fire_light.name = "HearthLight"
	fire_light.position = Vector3(0.0, 1.15, 0.0)
	fire_light.light_color = Color(1.0, 0.64, 0.28)
	fire_light.light_energy = 2.4
	fire_light.omni_range = 11.5
	root.add_child(fire_light)
	return root


static func create_bridge_3d(length_m: float = 7.2, width_m: float = 2.4) -> Node3D:
	var root := Node3D.new()
	root.name = "TimberBridge3D"
	var wood_mat := SevaraVisualTheme.create_structural_material3d(Color(0.54, 0.41, 0.28), 0.84)
	var stone_mat := SevaraVisualTheme.create_structural_material3d(Color(0.50, 0.49, 0.47), 0.90)

	# Heavy stone bridge abutments on both banks
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var abut := MeshInstance3D.new()
		var abut_box := BoxMesh.new()
		abut_box.size = Vector3(1.15, 1.1, width_m + 0.55)
		abut.mesh = abut_box
		abut.position = Vector3(side_f * (length_m * 0.46), -0.15, 0.0)
		abut.material_override = stone_mat
		root.add_child(abut)

	# Arched timber stringers and plank deck
	var plank_count := maxi(int(length_m / 0.36), 10)
	for i in range(plank_count):
		var t := float(i) / float(plank_count - 1)
		var px := lerpf(-length_m * 0.46, length_m * 0.46, t)
		var arch_y := sin(t * PI) * 0.42 + 0.14
		var plank := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.30, 0.10, width_m)
		plank.mesh = pmesh
		plank.position = Vector3(px, arch_y, 0.0)
		plank.material_override = wood_mat
		root.add_child(plank)

	# Timber posts and double railings
	for side_z in [-1.0, 1.0]:
		var sz := float(side_z) * (width_m * 0.46)
		for p in range(5):
			var pt := float(p) / 4.0
			var post_x := lerpf(-length_m * 0.44, length_m * 0.44, pt)
			var post_y := sin(pt * PI) * 0.42 + 0.58
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.14, 0.92, 0.14)
			post.mesh = post_mesh
			post.position = Vector3(post_x, post_y, sz)
			post.material_override = wood_mat
			root.add_child(post)
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(length_m * 0.92, 0.10, 0.10)
		rail.mesh = rail_mesh
		rail.position = Vector3(0.0, 0.96, sz)
		rail.material_override = wood_mat
		root.add_child(rail)
	return root


static func create_weir_barrier_3d(width_m: float = 4.6) -> Node3D:
	var root := Node3D.new()
	root.name = "WeirBarrier3D"
	var wood_mat := SevaraVisualTheme.create_structural_material3d(Color(0.46, 0.34, 0.22), 0.88)
	var stake_count := maxi(int(width_m / 0.34), 8)
	for i in range(stake_count):
		var sx := -width_m * 0.5 + float(i) * (width_m / float(stake_count - 1))
		var stake := MeshInstance3D.new()
		var smesh := CylinderMesh.new()
		smesh.top_radius = 0.07
		smesh.bottom_radius = 0.09
		smesh.height = 0.92
		stake.mesh = smesh
		stake.position = Vector3(sx, 0.28, sin(float(i) * 1.4) * 0.05)
		stake.rotation.z = sin(float(i) * 2.1) * 0.08
		stake.material_override = wood_mat
		root.add_child(stake)
	for r in range(3):
		var wattle := MeshInstance3D.new()
		var wmesh := CylinderMesh.new()
		wmesh.top_radius = 0.05
		wmesh.bottom_radius = 0.05
		wmesh.height = width_m
		wattle.mesh = wmesh
		wattle.rotation.z = PI * 0.5
		wattle.position = Vector3(0.0, 0.14 + float(r) * 0.18, 0.0)
		wattle.material_override = wood_mat
		root.add_child(wattle)
	return root


static func create_supply_crate_3d(
	remaining_count: int = 3, max_count: int = 3, adjacent: bool = false
) -> Node3D:
	var root := Node3D.new()
	root.name = "SupplyCrate3D"
	var crate_model := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Crate.glb", 0.95, {}, true
	)
	root.add_child(crate_model)

	if remaining_count > 0:
		var bags := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Bags.glb",
			0.65 * clampf(float(remaining_count) / float(maxi(max_count, 1)), 0.4, 1.0),
			{},
			true
		)
		bags.position = Vector3(0.58, 0.0, 0.18)
		root.add_child(bags)

	if adjacent:
		var l := OmniLight3D.new()
		l.position = Vector3(0.0, 1.15, 0.0)
		l.light_color = Color(0.96, 0.80, 0.44)
		l.light_energy = 1.4
		l.omni_range = 3.2
		root.add_child(l)
	return root


static func build_dense_meadow_multimeshes(foliage_density: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "DenseMeadowsMultiMesh3D"
	var dens := clampf(foliage_density, 0.25, 2.0)

	# 1. Dense curved-blade grass carpet patches (NatureBlocks / Fern style)
	var patch_mesh := SevaraAssetLibrary3D.build_grass_patch_mesh(68, 2.4, 0.058, 107)
	var patch_transforms: Array[Transform3D] = []
	var patch_customs: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4072026

	var patch_target := int(round(560.0 * dens))
	for _i in range(patch_target * 2):
		if patch_transforms.size() >= patch_target:
			break
		var wx := rng.randf_range(-62.0, 64.0)
		var wz := rng.randf_range(-46.0, 48.0)
		var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
		if wy < SevaraTerrainGen3D.WATER_SURFACE_Y + 0.16 or wy > 4.6:
			continue
		if SevaraTerrainGen3D.get_path_weight_at(wx, wz) > 0.32:
			continue
		var gn := SevaraTerrainGen3D.get_ground_normal(wx, wz)
		if gn.y < 0.76:
			continue
		var basis := _align_up_with_yaw(gn, rng.randf() * TAU, rng.randf_range(0.85, 1.28))
		patch_transforms.append(Transform3D(basis, Vector3(wx, wy - 0.03, wz)))
		var warm := smoothstep(-5.0, 32.0, wx)
		var tip_col := Color(0.32, 0.56, 0.18).lerp(
			Color(0.56, 0.64, 0.22), warm * rng.randf_range(0.3, 0.9)
		)
		patch_customs.append(Color(tip_col.r, tip_col.g, tip_col.b, rng.randf_range(0.75, 1.25)))

	root.add_child(
		_create_multimesh_node("GrassBladeCarpetMM", patch_mesh, patch_transforms, patch_customs)
	)

	# 2. Quaternius Tall & Wispy Grass Tufts MultiMesh
	var tall_grass_mesh := SevaraAssetLibrary3D.nature_mesh("Grass_Common_Tall")
	var wispy_grass_mesh := SevaraAssetLibrary3D.nature_mesh("Grass_Wispy_Tall")
	_scatter_botanical_multimesh(
		root,
		"TallGrassTuftsMM",
		tall_grass_mesh,
		int(round(380.0 * dens)),
		202601,
		Vector2(0.75, 1.35),
		false
	)
	_scatter_botanical_multimesh(
		root,
		"WispyGrassTuftsMM",
		wispy_grass_mesh,
		int(round(320.0 * dens)),
		202602,
		Vector2(0.80, 1.40),
		false
	)

	# 3. Ferns, Clovers & Wildflower Groups across Heravo Meadow & Forest Edges
	var fern_mesh := SevaraAssetLibrary3D.nature_mesh("Fern_1")
	var clover_mesh := SevaraAssetLibrary3D.nature_mesh("Clover_1")
	var flower3_mesh := SevaraAssetLibrary3D.nature_mesh("Flower_3_Group")
	var flower4_mesh := SevaraAssetLibrary3D.nature_mesh("Flower_4_Group")
	_scatter_botanical_multimesh(
		root, "FernsMM", fern_mesh, int(round(160.0 * dens)), 202603, Vector2(0.75, 1.30), false
	)
	_scatter_botanical_multimesh(
		root, "CloversMM", clover_mesh, int(round(210.0 * dens)), 202604, Vector2(0.85, 1.45), false
	)
	_scatter_botanical_multimesh(
		root,
		"Wildflowers3MM",
		flower3_mesh,
		int(round(145.0 * dens)),
		202605,
		Vector2(0.80, 1.35),
		true
	)
	_scatter_botanical_multimesh(
		root,
		"Wildflowers4MM",
		flower4_mesh,
		int(round(135.0 * dens)),
		202606,
		Vector2(0.80, 1.35),
		true
	)

	# 4. Flowering & Common Bushes
	var bush_flower_mesh := SevaraAssetLibrary3D.nature_mesh("Bush_Common_Flowers")
	_scatter_botanical_multimesh(
		root,
		"FloweringBushesMM",
		bush_flower_mesh,
		int(round(78.0 * dens)),
		202607,
		Vector2(0.65, 1.15),
		true
	)

	# 5. Riverbank Pebbles & Stepping Stones along Nivarel
	var pebble_mesh := SevaraAssetLibrary3D.nature_mesh(
		"Pebble_Round_1", {"rock": {"moss_amount": 0.35, "wetness": 0.65, "triplanar": 1.0}}
	)
	_scatter_river_pebbles_multimesh(
		root, "RiverPebblesMM", pebble_mesh, int(round(260.0 * dens)), 202608
	)
	return root


static func _scatter_botanical_multimesh(
	parent: Node3D,
	node_name: String,
	mesh: ArrayMesh,
	target_count: int,
	seed_val: int,
	scale_range: Vector2,
	flower_tint: bool
) -> void:
	if mesh == null or mesh.get_surface_count() == 0 or target_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var blossom_palette: Array[Color] = [
		Color(0.98, 0.94, 0.78),
		Color(0.96, 0.78, 0.28),
		Color(0.72, 0.82, 0.98),
		Color(0.94, 0.66, 0.78),
		Color(0.84, 0.72, 0.96),
	]
	for _i in range(target_count * 3):
		if xforms.size() >= target_count:
			break
		var wx := rng.randf_range(-64.0, 66.0)
		var wz := rng.randf_range(-48.0, 50.0)
		var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
		if wy < SevaraTerrainGen3D.WATER_SURFACE_Y + 0.14 or wy > 4.4:
			continue
		if SevaraTerrainGen3D.get_path_weight_at(wx, wz) > 0.25:
			continue
		var gn := SevaraTerrainGen3D.get_ground_normal(wx, wz)
		if gn.y < 0.78:
			continue
		var sc := rng.randf_range(scale_range.x, scale_range.y)
		var basis := _align_up_with_yaw(gn, rng.randf() * TAU, sc)
		xforms.append(Transform3D(basis, Vector3(wx, wy - 0.02, wz)))
		if flower_tint:
			var bc: Color = blossom_palette[rng.randi_range(0, blossom_palette.size() - 1)]
			customs.append(Color(bc.r, bc.g, bc.b, rng.randf_range(0.55, 0.98)))
		else:
			var gc := Color(0.36, 0.60, 0.20).lerp(Color(0.54, 0.66, 0.24), rng.randf())
			customs.append(Color(gc.r, gc.g, gc.b, rng.randf()))
	parent.add_child(_create_multimesh_node(node_name, mesh, xforms, customs))


static func _scatter_river_pebbles_multimesh(
	parent: Node3D, node_name: String, mesh: ArrayMesh, target_count: int, seed_val: int
) -> void:
	if mesh == null or mesh.get_surface_count() == 0 or target_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	for _i in range(target_count * 2):
		if xforms.size() >= target_count:
			break
		var wz := rng.randf_range(-48.0, 48.0)
		var r_cx := SevaraTerrainGen3D.river_center_x(wz)
		var r_hw := SevaraTerrainGen3D.river_half_width(wz)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var wx := r_cx + side * rng.randf_range(r_hw * 0.65, r_hw * 1.45)
		var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
		var sc := rng.randf_range(0.45, 1.35)
		var basis := (
			Basis
			. from_euler(
				Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
			)
			. scaled(Vector3(sc, sc * rng.randf_range(0.65, 1.1), sc))
		)
		xforms.append(Transform3D(basis, Vector3(wx, wy - 0.04, wz)))
		var shade := rng.randf_range(0.78, 1.12)
		customs.append(Color(shade, shade, shade, rng.randf_range(0.2, 0.75)))
	parent.add_child(_create_multimesh_node(node_name, mesh, xforms, customs))


static func _create_multimesh_node(
	node_name: String, mesh: ArrayMesh, transforms: Array[Transform3D], customs: Array[Color]
) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		if i < customs.size():
			mm.set_instance_custom_data(i, customs[i])
	mmi.multimesh = mm
	return mmi


static func _align_up_with_yaw(normal: Vector3, yaw: float, uniform_scale: float) -> Basis:
	var up := normal.normalized()
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := up.cross(fwd).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	fwd = right.cross(up).normalized()
	return Basis(right * uniform_scale, up * uniform_scale, fwd * uniform_scale)

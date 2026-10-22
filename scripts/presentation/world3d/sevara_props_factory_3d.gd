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
			"texture_color_mix": 0.82,
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
	var bush_model := "Bush_Common_Flowers" if is_kevalu else "Bush_Common"
	var base_mesh := SevaraAssetLibrary3D.nature_mesh(bush_model, bush_style)
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


static func create_talina_willow_3d(variant: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "TalinaWillow3D"
	var model_name := "TwistedTree_1" if (variant % 2) == 0 else "TwistedTree_2"
	var style := {
		"stiffness": 2.6,
		"leaves":
		{
			"color_dark": Color(0.14, 0.32, 0.18),
			"color_light": Color(0.42, 0.62, 0.34),
			"texture_color_mix": 0.82,
			"snow_cover": 0.02,
		},
	}
	var mesh := SevaraAssetLibrary3D.nature_mesh(model_name, style)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var scale_f := 0.42 + float(posmod(variant, 3)) * 0.05
	mi.scale = Vector3(scale_f * 1.05, scale_f * 0.92, scale_f * 1.05)
	mi.rotation = Vector3(0.06, float(variant) * 1.28, -0.05)
	root.add_child(mi)
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

	var desk := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bench_2.glb", 0.78, {}, true
	)
	desk.position = Vector3(0.0, 0.05, 0.12)
	root.add_child(desk)

	var book := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Book1_Open.glb", 0.075, {}, false
	)
	book.position = Vector3(0.0, 0.80, 0.12)
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
	var wood_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber",
		Color(0.56, 0.40, 0.26),
		Color(0.38, 0.26, 0.16),
		0.52,
		0.48,
		0.78,
		0.78,
		0.0,
		0.45,
		0.26
	)
	var dark_beam_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber",
		Color(0.40, 0.28, 0.18),
		Color(0.26, 0.18, 0.11),
		0.48,
		0.45,
		0.80,
		0.82,
		0.0,
		0.52,
		0.24
	)
	var stone_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_cliff_rock",
		Color(0.54, 0.54, 0.52),
		Color(0.38, 0.39, 0.38),
		0.46,
		0.45,
		0.82,
		0.80,
		0.0,
		0.62,
		0.32
	)

	# Heavy stone bridge abutments & wing walls on both banks
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var abut := MeshInstance3D.new()
		var abut_box := BoxMesh.new()
		abut_box.size = Vector3(1.35, 1.25, width_m + 0.65)
		abut.mesh = abut_box
		abut.position = Vector3(side_f * (length_m * 0.46), -0.22, 0.0)
		abut.material_override = stone_mat
		root.add_child(abut)

	# Submerged timber pilings supporting the central span
	for pier_x in [-length_m * 0.20, length_m * 0.20]:
		for side_z in [-1.0, 1.0]:
			var piling := MeshInstance3D.new()
			var p_cyl := CylinderMesh.new()
			p_cyl.top_radius = 0.13
			p_cyl.bottom_radius = 0.16
			p_cyl.height = 1.65
			piling.mesh = p_cyl
			piling.position = Vector3(pier_x, -0.25, float(side_z) * (width_m * 0.42))
			piling.material_override = dark_beam_mat
			root.add_child(piling)

	# Arched longitudinal carrier beams + timber plank deck
	var plank_count := maxi(int(length_m / 0.32), 12)
	for i in range(plank_count):
		var t := float(i) / float(plank_count - 1)
		var px := lerpf(-length_m * 0.46, length_m * 0.46, t)
		var arch_y := sin(t * PI) * 0.44 + 0.14
		var slope_z := -cos(t * PI) * (0.44 * PI / length_m)
		var plank := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		var jitter_w := width_m + sin(float(i) * 2.3) * 0.06
		pmesh.size = Vector3(0.28, 0.11, jitter_w)
		plank.mesh = pmesh
		plank.position = Vector3(px, arch_y, 0.0)
		plank.rotation.z = slope_z * 0.55
		plank.material_override = wood_mat if (i % 3 != 0) else dark_beam_mat
		root.add_child(plank)

	# Timber posts, diagonal knee braces, and arched top/mid rails
	for side_z in [-1.0, 1.0]:
		var sz := float(side_z) * (width_m * 0.46)
		for p in range(5):
			var pt := float(p) / 4.0
			var post_x := lerpf(-length_m * 0.44, length_m * 0.44, pt)
			var post_y := sin(pt * PI) * 0.44 + 0.62
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.16, 1.02, 0.16)
			post.mesh = post_mesh
			post.position = Vector3(post_x, post_y, sz)
			post.material_override = dark_beam_mat
			root.add_child(post)
			if p < 4:
				var next_pt := float(p + 1) / 4.0
				var next_x := lerpf(-length_m * 0.44, length_m * 0.44, next_pt)
				var next_y := sin(next_pt * PI) * 0.44 + 0.62
				var seg_len := Vector2(next_x - post_x, next_y - post_y).length()
				var seg_ang := atan2(next_y - post_y, next_x - post_x)
				for rail_h in [0.38, 0.08]:
					var rail := MeshInstance3D.new()
					var rmesh := BoxMesh.new()
					rmesh.size = Vector3(seg_len + 0.08, 0.09, 0.10)
					rail.mesh = rmesh
					rail.position = Vector3(
						(post_x + next_x) * 0.5, (post_y + next_y) * 0.5 + float(rail_h), sz
					)
					rail.rotation.z = seg_ang
					rail.material_override = wood_mat
					root.add_child(rail)

	for end_x in [-1.0, 1.0]:
		var tx := float(end_x) * (length_m * 0.44)
		var torch := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.ITEMS_DIR + "WoodenTorch_Fire.glb", 0.62, {}, false
		)
		torch.position = Vector3(tx, 1.12, -width_m * 0.46)
		root.add_child(torch)
	return root


static func create_weir_barrier_3d(width_m: float = 4.6) -> Node3D:
	var root := Node3D.new()
	root.name = "WeirBarrier3D"
	var wood_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber",
		Color(0.44, 0.32, 0.20),
		Color(0.28, 0.19, 0.12),
		0.55,
		0.46,
		0.80,
		0.84,
		0.0,
		0.58,
		0.22
	)
	var stake_count := maxi(int(width_m / 0.34), 8)
	for i in range(stake_count):
		var sx := -width_m * 0.5 + float(i) * (width_m / float(stake_count - 1))
		var stake := MeshInstance3D.new()
		var smesh := CylinderMesh.new()
		smesh.top_radius = 0.065
		smesh.bottom_radius = 0.09
		smesh.height = 0.94
		stake.mesh = smesh
		stake.position = Vector3(sx, 0.26, sin(float(i) * 1.4) * 0.08)
		stake.rotation.z = sin(float(i) * 2.1) * 0.10
		stake.material_override = wood_mat
		root.add_child(stake)
	for r in range(3):
		var wattle := MeshInstance3D.new()
		var wmesh := CylinderMesh.new()
		wmesh.top_radius = 0.05
		wmesh.bottom_radius = 0.055
		wmesh.height = width_m
		wattle.mesh = wmesh
		wattle.rotation.z = PI * 0.5
		wattle.position = Vector3(0.0, 0.12 + float(r) * 0.18, sin(float(r)) * 0.04)
		wattle.material_override = wood_mat
		root.add_child(wattle)
	# Add mossy logs & river boulders anchored against the weir
	for side_i in [-1, 1]:
		var log_node := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.NATURE_DIR + "WoodLog_Moss.glb", 0.42, {}, true
		)
		log_node.position = Vector3(float(side_i) * (width_m * 0.26), 0.05, 0.18)
		log_node.rotation.y = float(side_i) * 0.35
		root.add_child(log_node)
		var rock_node := create_boulder_3d(Vector3(0.55, 0.42, 0.52), true)
		rock_node.position = Vector3(float(side_i) * (width_m * 0.42), -0.02, -0.14)
		root.add_child(rock_node)
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
		int(round(420.0 * dens)),
		202601,
		Vector2(0.42, 0.72),
		false
	)
	_scatter_botanical_multimesh(
		root,
		"WispyGrassTuftsMM",
		wispy_grass_mesh,
		int(round(360.0 * dens)),
		202602,
		Vector2(0.45, 0.76),
		false
	)

	# 3. Ferns, Clovers & Wildflower Groups across Heravo Meadow & Forest Edges
	var fern_mesh := SevaraAssetLibrary3D.nature_mesh("Fern_1")
	var clover_mesh := SevaraAssetLibrary3D.nature_mesh("Clover_1")
	var flower3_mesh := SevaraAssetLibrary3D.nature_mesh("Flower_3_Group")
	var flower4_mesh := SevaraAssetLibrary3D.nature_mesh("Flower_4_Group")
	_scatter_botanical_multimesh(
		root, "FernsMM", fern_mesh, int(round(170.0 * dens)), 202603, Vector2(0.42, 0.68), false
	)
	_scatter_botanical_multimesh(
		root, "CloversMM", clover_mesh, int(round(230.0 * dens)), 202604, Vector2(0.46, 0.74), false
	)
	_scatter_botanical_multimesh(
		root,
		"Wildflowers3MM",
		flower3_mesh,
		int(round(160.0 * dens)),
		202605,
		Vector2(0.30, 0.48),
		true
	)
	_scatter_botanical_multimesh(
		root,
		"Wildflowers4MM",
		flower4_mesh,
		int(round(150.0 * dens)),
		202606,
		Vector2(0.28, 0.46),
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
		Vector2(0.46, 0.78),
		true
	)

	# 5. Riverbank Pebbles & Stepping Stones along Nivarel
	var pebble_mesh := SevaraAssetLibrary3D.nature_mesh(
		"Pebble_Round_1", {"rock": {"moss_amount": 0.35, "wetness": 0.65, "triplanar": 1.0}}
	)
	_scatter_river_pebbles_multimesh(
		root, "RiverPebblesMM", pebble_mesh, int(round(260.0 * dens)), 202608
	)

	# 6. Forest floor mushrooms under the Toramek pines
	var mushroom_mesh := SevaraAssetLibrary3D.nature_mesh("Mushroom_Common")
	_scatter_botanical_multimesh(
		root,
		"ForestMushroomsMM",
		mushroom_mesh,
		int(round(65.0 * dens)),
		202609,
		Vector2(0.45, 0.85),
		false
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


static func populate_static_settlement(settlement_root: Node3D) -> void:
	var houses: Array[Dictionary] = [
		{"file": "House_1.glb", "pos": Vector2(-19.5, -12.2), "h": 4.8, "rot": 0.28},
		{"file": "House_2.glb", "pos": Vector2(-11.4, -14.6), "h": 4.5, "rot": -0.18},
		{"file": "House_3.glb", "pos": Vector2(-22.2, -3.4), "h": 4.6, "rot": 0.65},
		{"file": "House_4.glb", "pos": Vector2(-14.5, 1.8), "h": 4.4, "rot": 2.45},
		{"file": "Blacksmith.glb", "pos": Vector2(-24.0, -8.2), "h": 4.3, "rot": 1.15},
		{"file": "Stable.glb", "pos": Vector2(-18.8, 5.2), "h": 3.9, "rot": 0.42},
	]
	for hspec: Dictionary in houses:
		var p2: Vector2 = hspec["pos"]
		var node := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + String(hspec["file"]), float(hspec["h"]), {}, true
		)
		node.position = Vector3(p2.x, SevaraTerrainGen3D.get_height_at(p2.x, p2.y) - 0.06, p2.y)
		node.rotation.y = float(hspec["rot"])
		settlement_root.add_child(node)

	var sawmill_pos := Vector2(-4.8, -12.6)
	var sawmill := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Sawmill.glb", 4.4, {}, true
	)
	sawmill.position = Vector3(
		sawmill_pos.x,
		SevaraTerrainGen3D.get_height_at(sawmill_pos.x, sawmill_pos.y) - 0.08,
		sawmill_pos.y
	)
	sawmill.rotation.y = -0.35
	settlement_root.add_child(sawmill)

	var mill_pos := Vector2(6.8, -15.2)
	var mill := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Mill.glb", 5.4, {}, true
	)
	mill.position = Vector3(
		mill_pos.x, SevaraTerrainGen3D.get_height_at(mill_pos.x, mill_pos.y) - 0.06, mill_pos.y
	)
	mill.rotation.y = -0.55
	settlement_root.add_child(mill)

	var pav_pos := Vector2(-9.2, -8.8)
	var pavilion := create_chronicle_pavilion_3d()
	pavilion.position = Vector3(
		pav_pos.x, SevaraTerrainGen3D.get_height_at(pav_pos.x, pav_pos.y) - 0.03, pav_pos.y
	)
	pavilion.rotation.y = 0.22
	settlement_root.add_child(pavilion)

	var hearth_pos := Vector2(-14.2, -7.6)
	var hearth := create_hearth_3d()
	hearth.position = Vector3(
		hearth_pos.x, SevaraTerrainGen3D.get_height_at(hearth_pos.x, hearth_pos.y), hearth_pos.y
	)
	settlement_root.add_child(hearth)

	var well_pos := Vector2(-16.2, -4.8)
	var well := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Well.glb", 2.35, {}, true
	)
	well.position = Vector3(
		well_pos.x, SevaraTerrainGen3D.get_height_at(well_pos.x, well_pos.y) - 0.03, well_pos.y
	)
	settlement_root.add_child(well)

	var village_props: Array[Dictionary] = [
		{"file": "MarketStand_1.glb", "pos": Vector2(-8.8, 4.8), "h": 2.4, "rot": 0.45},
		{"file": "MarketStand_2.glb", "pos": Vector2(-11.2, 6.2), "h": 2.3, "rot": 0.85},
		{"file": "Cart.glb", "pos": Vector2(-17.5, -1.2), "h": 1.35, "rot": -0.55},
		{"file": "Barrel.glb", "pos": Vector2(-12.6, -11.5), "h": 0.95, "rot": 0.0},
		{"file": "Hay.glb", "pos": Vector2(-16.4, 5.8), "h": 1.45, "rot": 0.3},
		{"file": "Fence.glb", "pos": Vector2(-7.2, 1.5), "h": 1.15, "rot": 1.35},
		{"file": "Fence.glb", "pos": Vector2(-7.8, -1.2), "h": 1.15, "rot": 1.42},
	]
	for p: Dictionary in village_props:
		var v2: Vector2 = p["pos"]
		var prop_node := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + String(p["file"]), float(p["h"]), {}, true
		)
		prop_node.position = Vector3(
			v2.x, SevaraTerrainGen3D.get_height_at(v2.x, v2.y) - 0.02, v2.y
		)
		prop_node.rotation.y = float(p["rot"])
		settlement_root.add_child(prop_node)

	var scout_tent_pos := Vector2(9.4, -9.2)
	var scout_tent := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Tent.glb", 2.05, {}, true
	)
	scout_tent.position = Vector3(
		scout_tent_pos.x,
		SevaraTerrainGen3D.get_height_at(scout_tent_pos.x, scout_tent_pos.y) - 0.03,
		scout_tent_pos.y
	)
	scout_tent.rotation.y = -0.55
	settlement_root.add_child(scout_tent)

	var bridge_z := -4.6
	var bridge_x := SevaraTerrainGen3D.river_center_x(bridge_z)
	var bridge := create_bridge_3d(8.6, 2.6)
	bridge.position = Vector3(bridge_x, SevaraTerrainGen3D.WATER_SURFACE_Y + 0.14, bridge_z)
	bridge.rotation.y = -0.24
	settlement_root.add_child(bridge)

	var weir1_z := -10.2
	var weir1 := create_weir_barrier_3d(5.2)
	weir1.position = Vector3(
		SevaraTerrainGen3D.river_center_x(weir1_z),
		SevaraTerrainGen3D.WATER_SURFACE_Y - 0.05,
		weir1_z
	)
	weir1.rotation.y = 0.22
	settlement_root.add_child(weir1)

	var weir2_z := 5.8
	var weir2 := create_weir_barrier_3d(5.8)
	weir2.position = Vector3(
		SevaraTerrainGen3D.river_center_x(weir2_z),
		SevaraTerrainGen3D.WATER_SURFACE_Y - 0.05,
		weir2_z
	)
	weir2.rotation.y = -0.18
	settlement_root.add_child(weir2)

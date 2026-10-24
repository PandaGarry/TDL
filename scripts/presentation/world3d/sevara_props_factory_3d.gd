class_name SevaraPropsFactory3D
extends RefCounted
## Builds 3D nature, MultiMesh meadows, boulders, trees, medieval village structures,
## and river engineering props for the Sevara Valley using CC0 glTF/GLB assets and custom shaders.

const PINE_MODELS: Array[String] = ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
const BROADLEAF_MODELS: Array[String] = ["TwistedTree_1", "TwistedTree_2"]
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

	var is_pine := (variant % 2) == 0
	var model_name := (
		PINE_MODELS[posmod(variant, PINE_MODELS.size())]
		if is_pine
		else BROADLEAF_MODELS[posmod(variant, BROADLEAF_MODELS.size())]
	)
	var is_twisted := model_name.begins_with("TwistedTree")
	var style := {
		"stiffness": 3.8 if is_pine else 3.1,
		"leaves":
		{
			"color_dark": Color(0.07, 0.16, 0.06) if is_pine else Color(0.08, 0.18, 0.07),
			"color_light": Color(0.22, 0.35, 0.13) if is_pine else Color(0.25, 0.38, 0.14),
			"texture_color_mix": 0.24,
		},
	}
	var mesh := SevaraAssetLibrary3D.nature_mesh(model_name, style)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var base_sc := 0.40 if is_twisted else (0.84 if is_pine else 0.86)
	var scale_f := base_sc * (0.88 + float(posmod(variant * 7, 5)) * 0.06)
	var h_stretch := 1.0 + float(posmod(variant, 3) - 1) * 0.07
	mi.scale = Vector3(scale_f, scale_f * h_stretch, scale_f)
	mi.rotation.y = float(variant) * 0.93
	mi.visibility_range_end = 135.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mi)

	# Root-hugging 3D grass collar + forest fern/clover underbrush at the trunk base
	var collar_mi := MeshInstance3D.new()
	collar_mi.mesh = SevaraAssetLibrary3D.build_grass_patch_mesh(
		34, 0.95, 0.034, 601 + (variant % 5), {"segments": 2}
	)
	collar_mi.scale = Vector3(1.25, 0.65, 1.25)
	collar_mi.position = Vector3(0.0, 0.03, 0.0)
	collar_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(collar_mi)

	if variant % 2 == 0:
		var fern_mesh := (
			SevaraAssetLibrary3D
			. nature_mesh(
				"Fern_1",
				{
					"plant":
					{
						"color_dark": Color(0.11, 0.24, 0.09),
						"color_light": Color(0.29, 0.44, 0.16),
						"texture_color_mix": 0.35,
					}
				}
			)
		)
		if fern_mesh != null:
			var fern_mi := MeshInstance3D.new()
			fern_mi.mesh = fern_mesh
			var f_ang := float(variant) * 1.7
			fern_mi.scale = Vector3.ONE * 0.13
			fern_mi.position = Vector3(cos(f_ang) * 0.58, 0.02, sin(f_ang) * 0.58)
			fern_mi.rotation.y = f_ang
			fern_mi.visibility_range_end = 68.0
			root.add_child(fern_mi)
	return root


static func get_step2_boulder_specs() -> Array[Dictionary]:
	return [
		# West riverbank boulder clusters (kept well clear of bridge deck, railings & road ramps)
		{"pos": Vector2(4.2, -3.8), "sc": Vector3(1.42, 1.02, 1.32), "moss": true},
		{"pos": Vector2(3.8, -8.2), "sc": Vector3(1.22, 0.86, 1.14), "moss": false},
		{"pos": Vector2(2.6, -13.5), "sc": Vector3(1.58, 1.16, 1.46), "moss": true},
		{"pos": Vector2(3.2, -21.5), "sc": Vector3(1.52, 1.10, 1.40), "moss": false},
		{"pos": Vector2(4.8, -30.5), "sc": Vector3(1.68, 1.22, 1.54), "moss": true},
		{"pos": Vector2(7.4, 7.6), "sc": Vector3(1.40, 1.00, 1.28), "moss": true},
		{"pos": Vector2(8.4, 11.8), "sc": Vector3(1.52, 1.12, 1.42), "moss": false},
		{"pos": Vector2(9.6, 16.5), "sc": Vector3(1.38, 0.98, 1.26), "moss": true},
		# East riverbank boulder clusters (kept well clear of bridge deck, railings & road ramps)
		{"pos": Vector2(16.4, -3.8), "sc": Vector3(1.44, 1.04, 1.34), "moss": true},
		{"pos": Vector2(14.8, -8.2), "sc": Vector3(1.28, 0.90, 1.18), "moss": false},
		{"pos": Vector2(13.2, -14.2), "sc": Vector3(1.56, 1.14, 1.44), "moss": true},
		{"pos": Vector2(14.6, -23.5), "sc": Vector3(1.48, 1.06, 1.36), "moss": false},
		{"pos": Vector2(16.2, -32.5), "sc": Vector3(1.64, 1.18, 1.50), "moss": true},
		{"pos": Vector2(18.8, 7.2), "sc": Vector3(1.46, 1.04, 1.34), "moss": false},
		{"pos": Vector2(19.8, 11.5), "sc": Vector3(1.64, 1.18, 1.52), "moss": true},
		{"pos": Vector2(20.6, 16.2), "sc": Vector3(1.40, 1.00, 1.30), "moss": false},
		# In-river wet rocks & mossy island boulders along the shallow shelves (clear of bridge span)
		{"pos": Vector2(8.4, -3.2), "sc": Vector3(1.12, 0.72, 1.04), "moss": false},
		{"pos": Vector2(14.4, -3.5), "sc": Vector3(1.18, 0.78, 1.08), "moss": true},
		{"pos": Vector2(7.4, -8.8), "sc": Vector3(1.08, 0.68, 1.00), "moss": false},
		{"pos": Vector2(12.2, -11.5), "sc": Vector3(1.24, 0.84, 1.14), "moss": true},
		{"pos": Vector2(8.6, -24.5), "sc": Vector3(1.28, 0.86, 1.18), "moss": false},
		{"pos": Vector2(10.2, -33.5), "sc": Vector3(1.34, 0.90, 1.24), "moss": true},
		{"pos": Vector2(9.2, 6.8), "sc": Vector3(1.14, 0.74, 1.06), "moss": false},
		{"pos": Vector2(16.2, 7.6), "sc": Vector3(1.28, 0.86, 1.18), "moss": true},
		{"pos": Vector2(10.8, 12.8), "sc": Vector3(1.16, 0.76, 1.08), "moss": false},
		# Distant meadow & hillside boulders (outside all roadbeds & settlement courtyards)
		{"pos": Vector2(-22.2, -16.8), "sc": Vector3(1.55, 1.12, 1.42), "moss": true},
		{"pos": Vector2(-25.4, -7.2), "sc": Vector3(1.18, 0.84, 1.10), "moss": true},
		{"pos": Vector2(-15.5, -19.5), "sc": Vector3(1.75, 1.26, 1.60), "moss": true},
	]


static func create_boulder_3d(scale_vec: Vector3 = Vector3.ONE, mossy: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Boulder3D"
	var hash_v := scale_vec.x * 17.3 + scale_vec.y * 11.1 + scale_vec.z * 23.7
	var idx := posmod(int(round(hash_v * 10.0)), ROCK_MODELS.size())
	var model_name: String = ROCK_MODELS[idx]
	var style := {
		"rock":
		{
			"moss_amount": 0.88 if mossy else 0.06,
			"snow_amount": 0.0,
			"wetness": 0.20 if mossy else 0.62,
			"triplanar": 1.0,
		}
	}
	var mesh := SevaraAssetLibrary3D.build_bevel_smoothed_rock_mesh(model_name, style)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var body_scale := scale_vec * 0.44
	var body_rot := Vector3(0.07 * sin(hash_v * 1.7), 0.0, -0.07 * cos(hash_v * 2.3))
	mi.scale = body_scale
	mi.rotation = body_rot
	root.add_child(mi)

	if mossy and scale_vec.x > 0.92:
		# Exact triangle-conforming 3D moss fur growing out of the bevel-smoothed rock crown
		var fur_mi := MeshInstance3D.new()
		fur_mi.mesh = SevaraAssetLibrary3D.build_rock_crown_moss_fur_mesh(
			model_name, 701 + idx * 37
		)
		fur_mi.scale = body_scale
		fur_mi.rotation = body_rot
		fur_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fur_mi)

		var sub_idx := (idx + 1) % ROCK_MODELS.size()
		var sub_mi := MeshInstance3D.new()
		sub_mi.mesh = SevaraAssetLibrary3D.build_bevel_smoothed_rock_mesh(
			ROCK_MODELS[sub_idx], style
		)
		var ang := hash_v * 2.4
		var rad := 0.52 * scale_vec.x
		sub_mi.scale = scale_vec * Vector3(0.22, 0.17, 0.22)
		sub_mi.position = Vector3(cos(ang) * rad, -0.04, sin(ang) * rad)
		sub_mi.rotation = Vector3(-0.10 * cos(ang), ang + 1.2, 0.08 * sin(ang))
		root.add_child(sub_mi)

		# Lush 3D clover cluster nestled against the boulder's mossy shoulder
		var clv_mesh := SevaraAssetLibrary3D.nature_mesh("Clover_1", {})
		if clv_mesh != null:
			var clv_mi := MeshInstance3D.new()
			clv_mi.mesh = clv_mesh
			clv_mi.scale = Vector3.ONE * (0.28 * scale_vec.x)
			clv_mi.position = Vector3(-cos(ang) * rad * 0.82, 0.04, -sin(ang) * rad * 0.82)
			clv_mi.rotation.y = ang * 1.7
			root.add_child(clv_mi)

		# Ground-hugging grass tuft collar so the boulder sits nestled in meadow turf
		var collar_mesh := SevaraAssetLibrary3D.build_grass_patch_mesh(
			38, 0.86, 0.032, 503, {"segments": 2}
		)
		var collar_mi := MeshInstance3D.new()
		collar_mi.mesh = collar_mesh
		collar_mi.scale = Vector3(scale_vec.x * 1.18, 0.58, scale_vec.z * 1.18)
		collar_mi.position = Vector3(0.0, 0.04, 0.0)
		collar_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(collar_mi)
	return root


static func create_kevar_bush_3d(is_kevalu: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "KevaluLocus3D" if is_kevalu else "KevarBush3D"
	var leaf_cfg := {
		"color_dark": Color(0.11, 0.18, 0.18) if is_kevalu else Color(0.08, 0.18, 0.07),
		"color_light": Color(0.24, 0.35, 0.34) if is_kevalu else Color(0.24, 0.37, 0.13),
		"texture_color_mix": 0.24,
	}
	var bush_style := {"leaves": leaf_cfg, "plant": leaf_cfg}
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = SevaraAssetLibrary3D.nature_mesh("Bush_Common", bush_style)
	base_mi.scale = Vector3(0.64, 0.54, 0.64)
	base_mi.visibility_range_end = 86.0
	root.add_child(base_mi)
	var fern_mesh := SevaraAssetLibrary3D.nature_mesh("Fern_1", bush_style)
	if fern_mesh != null:
		for f in range(2):
			var fern_mi := MeshInstance3D.new()
			fern_mi.mesh = fern_mesh
			var fang := float(f) * 2.4 + 0.5
			fern_mi.scale = Vector3(0.18, 0.20, 0.18)
			fern_mi.position = Vector3(cos(fang) * 0.34, 0.02, sin(fang) * 0.34)
			fern_mi.rotation = Vector3(0.05, fang, -0.04)
			fern_mi.visibility_range_end = 78.0
			root.add_child(fern_mi)
	var spike_mi := MeshInstance3D.new()
	spike_mi.mesh = SevaraAssetLibrary3D.nature_mesh("Proc_Kevalu" if is_kevalu else "Proc_Kevar")
	spike_mi.scale = Vector3(0.56, 0.52, 0.56)
	spike_mi.visibility_range_end = 68.0
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
			"color_dark": Color(0.08, 0.19, 0.08),
			"color_light": Color(0.25, 0.38, 0.15),
			"texture_color_mix": 0.24,
		},
	}
	var mesh := SevaraAssetLibrary3D.nature_mesh(model_name, style)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var scale_f := 0.36 + float(posmod(variant, 3)) * 0.035
	mi.scale = Vector3(scale_f * 1.04, scale_f * 0.92, scale_f * 1.04)
	mi.rotation = Vector3(0.05, float(variant) * 1.28, -0.04)
	mi.visibility_range_end = 135.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mi)

	var collar_mi := MeshInstance3D.new()
	collar_mi.mesh = SevaraAssetLibrary3D.build_grass_patch_mesh(
		36, 1.05, 0.034, 651 + (variant % 4), {"segments": 2}
	)
	collar_mi.scale = Vector3(1.32, 0.68, 1.32)
	collar_mi.position = Vector3(0.0, 0.03, 0.0)
	collar_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(collar_mi)
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


static func create_chronicle_pavilion_3d() -> Node3D:
	return SevaraSettlementArchitect3D.create_selima_chronicle_hall_3d()


static func create_hearth_3d() -> Node3D:
	return SevaraSettlementArchitect3D.create_sevara_hearth_sanctuary_3d()


static func create_bridge_3d(
	_length_m: float = 7.2, _width_m: float = 2.4, tier: int = 1
) -> Node3D:
	var root := Node3D.new()
	root.name = "TimberBridge3D"
	root.set_meta("building_id", "nivarel_crossing")
	root.set_meta("archetype", "bridge")
	root.set_meta("tier", tier)
	var wood_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.56, 0.45, 0.33), Color.BLACK, 0.56, 0.50, 0.55, 0.84
	)
	var warm_log_alt_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.50, 0.39, 0.28), Color.BLACK, 0.54, 0.48, 0.55, 0.85
	)
	var dark_beam_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.42, 0.32, 0.22), Color.BLACK, 0.52, 0.50, 0.58, 0.86
	)
	var rope_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_wattle_weave", Color(0.68, 0.56, 0.38), Color.BLACK, 0.48, 0.40, 0.25, 0.88
	)
	var stone_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_cliff_rock", Color(0.90, 0.88, 0.84), Color.BLACK, 0.48, 0.45, 0.42, 0.80, 0.0, 0.14
	)

	var x_min := SevaraTerrainGen3D.BRIDGE_X_MIN
	var x_max := SevaraTerrainGen3D.BRIDGE_X_MAX
	var deck_w := 2.68 if tier <= 1 else 2.92

	# 1. Under-Deck Support Pilings strictly BELOW the log deck (`ty <= -0.84`)
	var pier_stone_mesh := (
		SevaraAssetLibrary3D
		. build_bevel_smoothed_rock_mesh(
			"Rock_Medium_2",
			{
				"rock":
				{
					"moss_amount": 0.16,
					"snow_amount": 0.0,
					"wetness": 0.52,
					"triplanar": 1.0,
					"tint": Color(0.90, 0.87, 0.82),
				}
			}
		)
	)
	var piling_cyl := CylinderMesh.new()
	piling_cyl.top_radius = 0.105
	piling_cyl.bottom_radius = 0.125
	piling_cyl.height = 1.15
	piling_cyl.radial_segments = 12
	var lashing_torus := TorusMesh.new()
	lashing_torus.inner_radius = 0.095
	lashing_torus.outer_radius = 0.145
	lashing_torus.rings = 12
	lashing_torus.ring_segments = 10

	var pier_xs: Array[float] = [9.85, 14.15]
	for pier_x: float in pier_xs:
		var pz := SevaraTerrainGen3D._main_road_z(pier_x)
		var py := SevaraTerrainGen3D.get_bridge_deck_y_at_x(pier_x)
		var dz := (
			(
				SevaraTerrainGen3D._main_road_z(pier_x + 0.2)
				- SevaraTerrainGen3D._main_road_z(pier_x - 0.2)
			)
			/ 0.4
		)
		var yaw := -atan2(dz, 1.0)
		var pier_grp := Node3D.new()
		pier_grp.position = Vector3(pier_x, py, pz)
		pier_grp.rotation.y = yaw
		root.add_child(pier_grp)
		for k in range(3):
			var z_off := (float(k) - 1.0) * 0.72
			var piling := MeshInstance3D.new()
			piling.mesh = piling_cyl
			piling.position = Vector3(0.0, -0.78, z_off)
			piling.rotation.x = float(k - 1) * 0.08
			piling.material_override = dark_beam_mat
			pier_grp.add_child(piling)

			var p_lash := MeshInstance3D.new()
			p_lash.mesh = lashing_torus
			p_lash.position = Vector3(0.0, -0.32, z_off)
			p_lash.material_override = rope_mat
			pier_grp.add_child(p_lash)

			var st_mi := MeshInstance3D.new()
			st_mi.mesh = pier_stone_mesh
			st_mi.scale = Vector3(0.28, 0.20, 0.28)
			st_mi.position = Vector3(sin(float(k) * 1.7) * 0.05, -1.18, z_off)
			st_mi.rotation.y = float(k * 2) * 1.1
			st_mi.material_override = stone_mat
			pier_grp.add_child(st_mi)

	# 2. Tier 1 Rough Round-Log Corduroy Deck with Uneven Log Ends & Rope Lashings
	var span_start := x_min
	var span_end := x_max
	var log_count := 32
	var span_dx := (span_end - span_start) / float(log_count)
	var tie_pole_cyl := CylinderMesh.new()
	tie_pole_cyl.top_radius = 0.058
	tie_pole_cyl.bottom_radius = 0.058
	tie_pole_cyl.height = span_dx + 0.05
	tie_pole_cyl.radial_segments = 10
	var carrier_cyl := CylinderMesh.new()
	carrier_cyl.top_radius = 0.095
	carrier_cyl.bottom_radius = 0.095
	carrier_cyl.height = span_dx + 0.06
	carrier_cyl.radial_segments = 10
	var curb_lash_torus := TorusMesh.new()
	curb_lash_torus.inner_radius = 0.055
	curb_lash_torus.outer_radius = 0.092
	curb_lash_torus.rings = 10
	curb_lash_torus.ring_segments = 8

	for i in range(log_count):
		var px := span_start + (float(i) + 0.5) * span_dx
		var pz := SevaraTerrainGen3D._main_road_z(px)
		var py := SevaraTerrainGen3D.get_bridge_deck_y_at_x(px)
		var dy := (
			(
				SevaraTerrainGen3D.get_bridge_deck_y_at_x(px + 0.15)
				- SevaraTerrainGen3D.get_bridge_deck_y_at_x(px - 0.15)
			)
			/ 0.30
		)
		var dz := (
			(
				SevaraTerrainGen3D._main_road_z(px + 0.15)
				- SevaraTerrainGen3D._main_road_z(px - 0.15)
			)
			/ 0.30
		)
		var yaw := -atan2(dz, 1.0)
		var pitch := atan2(dy, 1.0)

		var log_node := MeshInstance3D.new()
		var lmesh := CylinderMesh.new()
		var log_r := span_dx * (0.41 + sin(float(i) * 2.7) * 0.03)
		var jitter_w := deck_w + sin(float(i) * 2.3) * 0.24 + cos(float(i) * 3.9) * 0.12
		var z_shift := sin(float(i) * 1.7) * 0.05
		lmesh.top_radius = log_r * 0.94
		lmesh.bottom_radius = log_r * 1.04
		lmesh.height = jitter_w
		lmesh.radial_segments = 12
		log_node.mesh = lmesh
		log_node.position = Vector3(
			px - sin(yaw) * z_shift,
			py - 0.036 + sin(float(i) * 3.1) * 0.008,
			pz + cos(yaw) * z_shift
		)
		log_node.rotation = Vector3(PI * 0.5, yaw + sin(float(i) * 2.1) * 0.025, pitch)
		log_node.material_override = wood_mat if (i % 2 == 0) else warm_log_alt_mat
		root.add_child(log_node)

		for side_z in [-1.0, 1.0]:
			var off_z := float(side_z) * (deck_w * 0.42)
			var beam := MeshInstance3D.new()
			beam.mesh = carrier_cyl
			beam.position = Vector3(px - sin(yaw) * off_z, py - 0.14, pz + cos(yaw) * off_z)
			beam.rotation = Vector3(0.0, yaw, pitch - PI * 0.5)
			beam.material_override = dark_beam_mat
			root.add_child(beam)

			var c_off := float(side_z) * (deck_w * 0.45)
			var tie_pole := MeshInstance3D.new()
			tie_pole.mesh = tie_pole_cyl
			tie_pole.position = Vector3(px - sin(yaw) * c_off, py + 0.036, pz + cos(yaw) * c_off)
			tie_pole.rotation = Vector3(0.0, yaw, pitch - PI * 0.5)
			tie_pole.material_override = dark_beam_mat
			root.add_child(tie_pole)

			if i % 3 == 1:
				var lash := MeshInstance3D.new()
				lash.mesh = curb_lash_torus
				lash.position = Vector3(px - sin(yaw) * c_off, py + 0.012, pz + cos(yaw) * c_off)
				lash.rotation = Vector3(0.0, yaw, PI * 0.5)
				lash.material_override = rope_mat
				root.add_child(lash)

	# 3. Rough Unbarked Stake Posts with Thick Rope Lashings & Sagging Catenary Hemp Rope Rails
	var stake_cyl := CylinderMesh.new()
	stake_cyl.top_radius = 0.054
	stake_cyl.bottom_radius = 0.086
	stake_cyl.height = 0.96
	stake_cyl.radial_segments = 10
	var post_lash_torus := TorusMesh.new()
	post_lash_torus.inner_radius = 0.052
	post_lash_torus.outer_radius = 0.088
	post_lash_torus.rings = 12
	post_lash_torus.ring_segments = 8

	var post_count := 7
	for side_z in [-1.0, 1.0]:
		for p in range(post_count):
			var pt := float(p) / float(post_count - 1)
			var post_x := lerpf(span_start + 0.22, span_end - 0.22, pt)
			var post_z := SevaraTerrainGen3D._main_road_z(post_x)
			var post_y := SevaraTerrainGen3D.get_bridge_deck_y_at_x(post_x)
			var dz := (
				(
					SevaraTerrainGen3D._main_road_z(post_x + 0.2)
					- SevaraTerrainGen3D._main_road_z(post_x - 0.2)
				)
				/ 0.4
			)
			var yaw := -atan2(dz, 1.0)
			var off_z := float(side_z) * (deck_w * 0.46)
			var w_pos := Vector3(
				post_x - sin(yaw) * off_z, post_y + 0.40, post_z + cos(yaw) * off_z
			)
			var post := MeshInstance3D.new()
			post.mesh = stake_cyl
			post.position = w_pos
			var lean_out := float(side_z) * (0.04 + absf(sin(float(p) * 1.9)) * 0.04)
			var lean_along := sin(float(p * 3 + int(side_z))) * 0.05
			post.rotation = Vector3(lean_out, yaw, lean_along)
			post.material_override = dark_beam_mat
			root.add_child(post)

			var knot_dys: Array[float] = [0.34, 0.02, -0.34]
			for knot_dy: float in knot_dys:
				var knot := MeshInstance3D.new()
				knot.mesh = post_lash_torus
				knot.position = w_pos + Vector3(0.0, knot_dy, 0.0)
				knot.rotation.z = lean_along
				knot.material_override = rope_mat
				root.add_child(knot)

			if p < post_count - 1:
				var next_pt := float(p + 1) / float(post_count - 1)
				var nx := lerpf(span_start + 0.22, span_end - 0.22, next_pt)
				var nz := SevaraTerrainGen3D._main_road_z(nx)
				var ny := SevaraTerrainGen3D.get_bridge_deck_y_at_x(nx)
				var nw_pos := Vector3(nx - sin(yaw) * off_z, ny + 0.40, nz + cos(yaw) * off_z)
				var rope_hs: Array[float] = [0.34, 0.02]
				for rail_h: float in rope_hs:
					var p0 := w_pos + Vector3(0.0, rail_h, 0.0)
					var p1 := nw_pos + Vector3(0.0, rail_h, 0.0)
					var rope_segs := 5
					var sag_depth := 0.11 if rail_h > 0.2 else 0.07
					for rs in range(rope_segs):
						var t0 := float(rs) / float(rope_segs)
						var t1 := float(rs + 1) / float(rope_segs)
						var sag0 := 4.0 * t0 * (1.0 - t0) * sag_depth
						var sag1 := 4.0 * t1 * (1.0 - t1) * sag_depth
						var rp0 := p0.lerp(p1, t0) - Vector3(0.0, sag0, 0.0)
						var rp1 := p0.lerp(p1, t1) - Vector3(0.0, sag1, 0.0)
						var r_delta := rp1 - rp0
						var r_len := r_delta.length()
						var r_pitch := atan2(r_delta.y, Vector2(r_delta.x, r_delta.z).length())
						var r_yaw := -atan2(r_delta.z, r_delta.x)
						var rope_seg := MeshInstance3D.new()
						var rmesh := CylinderMesh.new()
						rmesh.top_radius = 0.028 if rail_h > 0.2 else 0.022
						rmesh.bottom_radius = rmesh.top_radius
						rmesh.height = r_len + 0.02
						rmesh.radial_segments = 8
						rope_seg.mesh = rmesh
						rope_seg.position = (rp0 + rp1) * 0.5
						rope_seg.rotation = Vector3(0.0, r_yaw, r_pitch - PI * 0.5)
						rope_seg.material_override = rope_mat
						root.add_child(rope_seg)
	return root


static func create_weir_barrier_3d(width_m: float = 4.6) -> Node3D:
	var root := Node3D.new()
	root.name = "WeirBarrier3D"
	var wood_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.44, 0.32, 0.20), Color.BLACK, 0.55, 0.46, 0.80, 0.84
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
	var side_is: Array[int] = [-1, 1]
	for side_i: int in side_is:
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
	var is_mobile := OS.has_feature("mobile") or OS.get_name() in ["iOS", "Android"]
	var blade_segs := 2 if is_mobile else 4
	var vis_end := 82.0 if is_mobile else 124.0
	var dens := clampf(foliage_density * (0.78 if is_mobile else 1.0), 0.4, 2.0)

	# 1. Spatial Chunked 4x3 Meadow Carpet across the 136 x 88 m CBT Proving Ground
	#    (per-sector AABBs enable hardware Frustum Culling + distance visibility range fading)
	var patch_mesh := SevaraAssetLibrary3D.build_grass_patch_mesh(
		86, 1.05, 0.036, 107, {"segments": blade_segs}
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4072026

	var step := clampf(0.80 / sqrt(dens), 0.58, 0.96)
	var x_min := -68.0
	var x_max := 68.0
	var z_min := -58.0
	var z_max := 38.0
	var gx_count := int(round((x_max - x_min) / step))
	var gz_count := int(round((z_max - z_min) / step))
	var sector_cols := 4
	var sector_rows := 3
	var sector_w := (x_max - x_min) / float(sector_cols)
	var sector_d := (z_max - z_min) / float(sector_rows)
	var sector_xforms: Array = []
	var sector_customs: Array = []
	for _s in range(sector_cols * sector_rows):
		var xf_arr: Array[Transform3D] = []
		var cu_arr: Array[Color] = []
		sector_xforms.append(xf_arr)
		sector_customs.append(cu_arr)

	for gz in range(gz_count):
		for gx in range(gx_count):
			var wx := x_min + (float(gx) + rng.randf_range(0.18, 0.82)) * step
			var wz := z_min + (float(gz) + rng.randf_range(0.18, 0.82)) * step
			if Vector2(wx, wz).length() > 84.0:
				continue
			var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
			if SevaraTerrainGen3D.is_on_bridge(wx, wz):
				continue
			var r_cx := SevaraTerrainGen3D.river_center_x(wz)
			var r_hw := SevaraTerrainGen3D.river_half_width(wz)
			var in_stream_corridor := absf(wx - r_cx) < r_hw * 1.25
			if (in_stream_corridor and wy < SevaraTerrainGen3D.WATER_SURFACE_Y + 0.14) or wy > 9.2:
				continue
			var path_w := SevaraTerrainGen3D.get_path_weight_at(wx, wz)
			if path_w > 0.22:
				continue
			var gn := SevaraTerrainGen3D.get_ground_normal(wx, wz)
			# Keep all hillside slopes lush with grass (only vertical cliffs >65 deg bare)
			if gn.y < 0.42 and path_w < 0.02:
				continue
			var bank_taper := smoothstep(
				SevaraTerrainGen3D.WATER_SURFACE_Y + 0.12,
				SevaraTerrainGen3D.WATER_SURFACE_Y + 0.30,
				wy
			)
			var edge_taper := (
				(1.0 - smoothstep(0.02, 0.28, path_w) * 0.65) * lerpf(0.45, 1.0, bank_taper)
			)
			var height_mult := clampf(edge_taper * rng.randf_range(0.86, 1.16), 0.26, 1.28)
			var patch_scale := clampf(
				(0.60 + 0.40 * edge_taper) * rng.randf_range(0.92, 1.12), 0.50, 1.15
			)
			var basis := _align_up_with_yaw(gn, rng.randf() * TAU, patch_scale)
			var col_idx := clampi(int(floorf((wx - x_min) / sector_w)), 0, sector_cols - 1)
			var row_idx := clampi(int(floorf((wz - z_min) / sector_d)), 0, sector_rows - 1)
			var s_idx := row_idx * sector_cols + col_idx
			(sector_xforms[s_idx] as Array[Transform3D]).append(
				Transform3D(basis, Vector3(wx, wy - 0.015, wz))
			)
			(sector_customs[s_idx] as Array[Color]).append(Color(0.0, 0.0, 0.0, height_mult))

	for r_i in range(sector_rows):
		for c_i in range(sector_cols):
			var s_idx := r_i * sector_cols + c_i
			var s_xf := sector_xforms[s_idx] as Array[Transform3D]
			var s_cu := sector_customs[s_idx] as Array[Color]
			if s_xf.is_empty():
				continue
			var s_name := (
				"GrassBladeCarpetMM"
				if (c_i == 1 and r_i == 1)
				else ("GrassBladeCarpetMM_%d_%d" % [c_i, r_i])
			)
			var mmi := _create_multimesh_node(s_name, patch_mesh, s_xf, s_cu)
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 6.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(mmi)

	# 2. Roadside Verge Micro-Tufts & Center Median Strip (feathers road edges & between wheel ruts)
	var verge_mesh := SevaraAssetLibrary3D.build_grass_patch_mesh(
		46, 0.42, 0.030, 309, {"segments": blade_segs}
	)
	var verge_transforms: Array[Transform3D] = []
	var verge_customs: Array[Color] = []
	var v_step := 0.34
	var vx_count := int(round(104.0 / v_step))
	var vz_count := int(round(74.0 / v_step))
	for vz in range(vz_count):
		for vx in range(vx_count):
			var wx := -52.0 + (float(vx) + rng.randf_range(0.15, 0.85)) * v_step
			var wz := -44.0 + (float(vz) + rng.randf_range(0.15, 0.85)) * v_step
			var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
			if (
				wy < SevaraTerrainGen3D.WATER_SURFACE_Y + 0.04
				or SevaraTerrainGen3D.is_on_bridge(wx, wz)
			):
				continue
			var pw := SevaraTerrainGen3D.get_path_weight_at(wx, wz)
			var r_cx := SevaraTerrainGen3D.river_center_x(wz)
			var r_hw := SevaraTerrainGen3D.river_half_width(wz)
			var norm_r := absf(wx - r_cx) / maxf(r_hw, 0.5)
			var is_riverbank := norm_r >= 0.86 and norm_r <= 1.22 and pw < 0.14
			var d_main := absf(SevaraTerrainGen3D._main_road_signed_dist(wx, wz))
			var is_median := (
				d_main < 0.23 and absf(wx) > 1.8 and norm_r > 0.95 and rng.randf() < 0.72
			)
			var is_shoulder := pw >= 0.04 and pw <= 0.62 and norm_r > 0.92
			if not is_median and not is_shoulder and not is_riverbank:
				continue
			var gn := SevaraTerrainGen3D.get_ground_normal(wx, wz)
			if gn.y < 0.74:
				continue
			var h_mult := (
				rng.randf_range(0.24, 0.44)
				if (is_median or is_riverbank)
				else lerpf(0.72, 0.22, smoothstep(0.04, 0.62, pw)) * rng.randf_range(0.84, 1.16)
			)
			var sc := rng.randf_range(0.72, 1.12)
			var basis := _align_up_with_yaw(gn, rng.randf() * TAU, sc)
			verge_transforms.append(Transform3D(basis, Vector3(wx, wy - 0.012, wz)))
			verge_customs.append(Color(0.85, 0.0, 0.0, h_mult))

	var verge_mmi := _create_multimesh_node(
		"RoadsideVergeMM", verge_mesh, verge_transforms, verge_customs
	)
	verge_mmi.visibility_range_end = vis_end * 0.85
	verge_mmi.visibility_range_end_margin = 5.0
	verge_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(verge_mmi)

	# 3. Step 2 3D Riverbank Pebbles, Road Cobblestones & Roadside Clover
	var pebble_mesh := SevaraAssetLibrary3D.build_bevel_smoothed_rock_mesh(
		"Pebble_Round_1",
		{"rock": {"moss_amount": 0.24, "snow_amount": 0.0, "wetness": 0.32, "triplanar": 1.0}}
	)
	_scatter_river_pebbles_multimesh(root, "RiverPebblesMM", pebble_mesh, int(420.0 * dens), 407305)
	_scatter_road_cobbles_and_clover(root, pebble_mesh, dens)
	return root


static func _scatter_road_cobbles_and_clover(
	parent: Node3D, _pebble_mesh: ArrayMesh, dens: float
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 618209
	var cob_xf: Array[Transform3D] = []
	var cob_cu: Array[Color] = []
	var clv_xf: Array[Transform3D] = []
	var clv_cu: Array[Color] = []
	var target_cob := int(680.0 * dens)
	var target_clv := int(240.0 * dens)
	var road_stone_mesh := (
		SevaraAssetLibrary3D
		. build_bevel_smoothed_rock_mesh(
			"Pebble_Round_1",
			{
				"rock":
				{
					"moss_amount": 0.04,
					"snow_amount": 0.0,
					"wetness": 0.08,
					"triplanar": 1.0,
					"tint": Color(0.92, 0.85, 0.75),
				}
			}
		)
	)
	for i in range(target_cob * 4):
		if cob_xf.size() >= target_cob and clv_xf.size() >= target_clv:
			break
		var wx := rng.randf_range(-44.0, 44.0)
		var wz := rng.randf_range(-34.0, 26.0)
		if SevaraTerrainGen3D.is_on_bridge(wx, wz):
			continue
		var r_cx := SevaraTerrainGen3D.river_center_x(wz)
		var r_hw := SevaraTerrainGen3D.river_half_width(wz)
		if absf(wx - r_cx) < r_hw * 0.96:
			continue
		var pw := SevaraTerrainGen3D.get_path_weight_at(wx, wz)
		if pw < 0.08:
			continue
		var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
		var gn := SevaraTerrainGen3D.get_ground_normal(wx, wz)
		if pw >= 0.16 and cob_xf.size() < target_cob:
			var is_rut_stone := i % 3 == 0
			var sc := rng.randf_range(0.55, 0.96) if is_rut_stone else rng.randf_range(0.32, 0.58)
			var sy := sc * (0.42 if is_rut_stone else 0.48)
			var b := _align_up_with_yaw(gn, rng.randf() * TAU, 1.0).scaled(Vector3(sc, sy, sc))
			var sink := -0.012 if is_rut_stone else -0.008
			cob_xf.append(Transform3D(b, Vector3(wx, wy + sink, wz)))
			var sh := rng.randf_range(0.88, 1.08)
			cob_cu.append(Color(sh, sh * 0.96, sh * 0.90, rng.randf_range(0.0, 0.10)))
		elif pw <= 0.48 and clv_xf.size() < target_clv:
			var c_sc := rng.randf_range(0.22, 0.38)
			var cb := _align_up_with_yaw(gn, rng.randf() * TAU, c_sc)
			clv_xf.append(Transform3D(cb, Vector3(wx, wy - 0.015, wz)))
			clv_cu.append(Color(0.32, 0.52, 0.18, rng.randf_range(0.35, 0.85)))
	if not cob_xf.is_empty():
		parent.add_child(_create_multimesh_node("RoadCobblesMM", road_stone_mesh, cob_xf, cob_cu))
	var clover_mesh := SevaraAssetLibrary3D.nature_mesh("Clover_1", {})
	if clover_mesh != null and not clv_xf.is_empty():
		parent.add_child(_create_multimesh_node("RoadsideCloverMM", clover_mesh, clv_xf, clv_cu))


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
		var wz := rng.randf_range(-38.0, 26.0)
		var r_cx := SevaraTerrainGen3D.river_center_x(wz)
		var r_hw := SevaraTerrainGen3D.river_half_width(wz)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var wx := r_cx + side * rng.randf_range(r_hw * 0.72, r_hw * 1.14)
		if SevaraTerrainGen3D.is_on_bridge(wx, wz):
			continue
		var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
		var sc := rng.randf_range(0.34, 0.75)
		var basis := (
			Basis
			. from_euler(
				Vector3(
					rng.randf_range(-0.10, 0.10), rng.randf() * TAU, rng.randf_range(-0.10, 0.10)
				)
			)
			. scaled(Vector3(sc, sc * rng.randf_range(0.26, 0.44), sc))
		)
		xforms.append(Transform3D(basis, Vector3(wx, wy - 0.032, wz)))
		var shade := rng.randf_range(0.78, 1.12)
		customs.append(Color(shade, shade, shade, rng.randf_range(0.15, 0.68)))
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
	SevaraSettlementArchitect3D.populate_settlement(settlement_root)

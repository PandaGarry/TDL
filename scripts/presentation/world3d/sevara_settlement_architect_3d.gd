class_name SevaraSettlementArchitect3D
extends RefCounted
## Builds the Step 4 Sevara Sanctuary tribal settlement (`Tier 1: Wattle, Clay Daub & Thatch`).
## Every building is created as a self-contained, relocatable, upgradeable 3D object (`tier = 1..3`)
## that dynamically registers its ground pad, footpath, felled trees, and mined rocks in the world.

static var _decal_shader_cache: Shader = null


static func create_selima_chronicle_hall_3d(tier: int = 1) -> Node3D:
	return create_settlement_building_3d("craft_shed", "craft_shed", tier)


static func create_sevara_hearth_sanctuary_3d(tier: int = 1) -> Node3D:
	return create_settlement_building_3d("tribal_hearth", "hearth", tier)


static func create_watermill_3d(tier: int = 1) -> Node3D:
	return create_settlement_building_3d("river_sluice", "river_sluice", tier)


static func create_settlement_building_3d(
	building_id: String, archetype: String, tier: int = 1
) -> Node3D:
	var root := Node3D.new()
	root.name = "Building_" + building_id
	root.set_meta("building_id", building_id)
	root.set_meta("archetype", archetype)
	root.set_meta("tier", clampi(tier, 1, 3))

	if (
		tier >= 3
		and archetype in ["elder_hut", "worker_hut_round", "worker_hut_oval", "craft_shed"]
	):
		return _build_upgraded_tier3_building(root, archetype)

	match archetype:
		"elder_hut":
			root.set_meta("footprint_radii", Vector2(2.9, 2.6))
			root.set_meta("door_offset", Vector2(0.0, 1.55))
			_assemble_tier1_daub_hut(root, 1.92, 1.46, 1.38, 1.52, true, false, 11)
		"worker_hut_round":
			root.set_meta("footprint_radii", Vector2(2.4, 2.4))
			root.set_meta("door_offset", Vector2(0.0, 1.48))
			_assemble_tier1_daub_hut(root, 1.50, 1.50, 1.28, 1.44, false, true, 23)
		"worker_hut_oval":
			root.set_meta("footprint_radii", Vector2(2.5, 2.3))
			root.set_meta("door_offset", Vector2(0.0, 1.36))
			_assemble_tier1_daub_hut(root, 1.66, 1.28, 1.24, 1.32, false, false, 37)
		"craft_shed":
			root.set_meta("footprint_radii", Vector2(2.4, 2.2))
			root.set_meta("door_offset", Vector2(0.0, 1.25))
			_assemble_tier1_craft_shed(root)
		"well":
			root.set_meta("footprint_radii", Vector2(1.9, 1.9))
			root.set_meta("door_offset", Vector2(0.0, 0.95))
			_assemble_tier1_spring_well(root)
		"hearth":
			root.set_meta("footprint_radii", Vector2(2.5, 2.5))
			root.set_meta("door_offset", Vector2(0.0, 0.0))
			_assemble_tier1_tribal_hearth(root)
		"river_sluice":
			root.set_meta("footprint_radii", Vector2(2.2, 2.2))
			root.set_meta("door_offset", Vector2(-0.6, 1.15))
			_assemble_tier1_fishing_sluice(root)
		_:
			root.set_meta("footprint_radii", Vector2(2.4, 2.4))
			root.set_meta("door_offset", Vector2(0.0, 1.40))
			_assemble_tier1_daub_hut(root, 1.55, 1.35, 1.26, 1.36, false, false, 41)
	return root


static func place_or_relocate_building(
	settlement_root: Node3D,
	building_id: String,
	archetype: String,
	world_xz: Vector2,
	yaw: float,
	road_join_xz: Vector2,
	tier: int = 1
) -> Node3D:
	var existing: Node3D = null
	for child: Node in settlement_root.get_children():
		if child is Node3D and str(child.get_meta("building_id", "")) == building_id:
			existing = child as Node3D
			break
	var prev_tier := int(existing.get_meta("tier", tier)) if existing != null else tier
	if existing != null and prev_tier != tier:
		existing.free()
		existing = null
	if existing == null:
		existing = create_settlement_building_3d(building_id, archetype, tier)
		settlement_root.add_child(existing)

	var wy := SevaraTerrainGen3D.get_height_at(world_xz.x, world_xz.y)
	existing.position = Vector3(world_xz.x, wy - 0.04, world_xz.y)
	existing.rotation = _get_gentle_ground_tilt(world_xz.x, world_xz.y, yaw, 0.16)

	var radii: Vector2 = existing.get_meta("footprint_radii", Vector2(2.4, 2.4))
	var door_off: Vector2 = existing.get_meta("door_offset", Vector2(0.0, 1.2))
	var rot_door := Vector2(
		door_off.x * cos(yaw) + door_off.y * sin(yaw),
		-door_off.x * sin(yaw) + door_off.y * cos(yaw)
	)
	var door_world := world_xz + rot_door
	SevaraTerrainGen3D.register_building_footprint(
		building_id, world_xz, radii, door_world, road_join_xz, tier
	)
	return existing


static func populate_settlement(settlement_root: Node3D) -> void:
	SevaraTerrainGen3D.dynamic_pads.clear()
	SevaraTerrainGen3D.felled_trees.clear()
	SevaraTerrainGen3D.mined_boulders.clear()

	var cleared_stump_coords: Array[Vector2] = [
		Vector2(-24.5, -14.5),
		Vector2(-22.5, -15.8),
		Vector2(-9.5, -19.5),
	]
	for st_pos: Vector2 in cleared_stump_coords:
		SevaraTerrainGen3D.felled_trees.append(st_pos)

	var layout: Array[Array] = [
		["hut_elder", "elder_hut", Vector2(-13.2, -10.2), 0.42, Vector2(-11.8, -6.0)],
		["hut_worker_west", "worker_hut_round", Vector2(-17.8, -7.2), 0.78, Vector2(-11.8, -6.0)],
		["hut_worker_north", "worker_hut_oval", Vector2(-7.8, -13.4), 0.24, Vector2(-5.8, -8.2)],
		["craft_shed", "craft_shed", Vector2(-5.8, -8.2), 0.16, Vector2(-5.8, -5.4)],
		["tribal_well", "well", Vector2(-11.8, -6.0), 0.18, Vector2(-9.2, -5.2)],
		["river_sluice", "river_sluice", Vector2(-1.0, -11.2), 0.38, Vector2(-5.8, -8.2)],
		["tribal_hearth", "hearth", Vector2(-0.4, -5.2), 0.0, Vector2(-2.6, -3.2)],
	]
	for row: Array in layout:
		place_or_relocate_building(
			settlement_root,
			str(row[0]),
			str(row[1]),
			row[2] as Vector2,
			float(row[3]),
			row[4] as Vector2,
			1
		)

	_populate_wattle_fences_and_clearing_details(settlement_root)

	var sunbeams := Node3D.new()
	sunbeams.name = "ValleyGodRays3D"
	var beam_spots: Array[Vector3] = [
		Vector3(-9.5, 4.2, -7.8),
		Vector3(0.2, 4.0, -5.8),
		Vector3(11.5, 4.4, 1.8),
	]
	for b_idx in range(beam_spots.size()):
		var ray := _create_vfx_quad(
			4, Vector2(4.2, 8.8), Color(1.0, 0.90, 0.66, 0.18), 0.35 + float(b_idx) * 0.18
		)
		ray.position = beam_spots[b_idx]
		ray.rotation = Vector3(-0.24, 0.42 - float(b_idx) * 0.22, -0.32)
		sunbeams.add_child(ray)
	settlement_root.add_child(sunbeams)


static func _assemble_tier1_daub_hut(
	root: Node3D,
	rx: float,
	rz: float,
	wall_h: float,
	roof_h: float,
	is_elder: bool,
	is_round: bool,
	seed_val: int
) -> void:
	var ao := _create_vfx_quad(0, Vector2(rx * 3.1, rz * 3.1), Color(0.05, 0.04, 0.03, 0.86), 0.85)
	ao.rotation.x = -PI * 0.5
	ao.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(ao)

	var daub_tint := (
		Color(0.76, 0.64, 0.48)
		if is_elder
		else (Color(0.72, 0.59, 0.44) if is_round else Color(0.74, 0.62, 0.46))
	)
	var daub_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_clay_daub", daub_tint, Color.BLACK, 0.52, 0.38, 0.32, 0.92, 0.0, 0.10
	)
	var timber_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.46, 0.35, 0.24), Color.BLACK, 0.55, 0.48, 0.52, 0.86
	)
	var rope_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_wattle_weave", Color(0.66, 0.54, 0.36), Color.BLACK, 0.48, 0.40, 0.28, 0.88
	)
	var thatch_tint := Color(0.74, 0.62, 0.40) if is_elder else Color(0.70, 0.58, 0.38)
	var thatch_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_thatch_roof", thatch_tint, Color.BLACK, 0.52, 0.36, 0.28, 0.92, 0.0, 0.24
	)
	var stone_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_cliff_rock", Color(0.84, 0.80, 0.74), Color.BLACK, 0.50, 0.44, 0.42, 0.84, 0.0, 0.18
	)

	var wall_mi := MeshInstance3D.new()
	wall_mi.name = "ClayDaubWalls"
	wall_mi.mesh = _build_sculpted_daub_wall_mesh(rx, rz, wall_h, is_round, seed_val)
	wall_mi.material_override = daub_mat
	root.add_child(wall_mi)

	var post_count := 8 if is_round else 10
	for pi in range(post_count):
		var ang := float(pi) * TAU / float(post_count)
		if absf(wrapf(ang - PI * 0.5, -PI, PI)) < 0.34:
			continue
		var p_pt := _eval_hut_perimeter(ang, rx + 0.03, rz + 0.03, is_round)
		var out_dir := p_pt.normalized()
		_add_cyl(
			root,
			0.064,
			0.088,
			wall_h + 0.24,
			Vector3(p_pt.x, wall_h * 0.5 - 0.06, p_pt.y),
			Vector3(-out_dir.y * 0.05, 0.0, out_dir.x * 0.05),
			timber_mat
		)
		_add_torus(
			root, 0.058, 0.094, Vector3(p_pt.x, wall_h - 0.08, p_pt.y), Vector3.ZERO, rope_mat
		)

	_add_tribal_doorway_and_window(
		root, rx, rz, wall_h, is_elder, is_round, timber_mat, rope_mat, stone_mat
	)

	var roof_mi := MeshInstance3D.new()
	roof_mi.name = "LayeredThatchRoof"
	roof_mi.mesh = _build_layered_thatch_roof_mesh(
		rx + 0.38, rz + 0.38, wall_h - 0.08, roof_h, is_round, seed_val
	)
	roof_mi.material_override = thatch_mat
	root.add_child(roof_mi)

	_add_roof_wind_poles_and_smoke(
		root, rx, rz, wall_h, roof_h, is_elder, is_round, timber_mat, rope_mat, daub_mat
	)


static func _eval_hut_perimeter(ang: float, rx: float, rz: float, is_round: bool) -> Vector2:
	var ca := cos(ang)
	var sa := sin(ang)
	if is_round:
		return Vector2(ca * rx, sa * rz)
	var p_exp := 0.76
	return Vector2(signf(ca) * pow(absf(ca), p_exp) * rx, signf(sa) * pow(absf(sa), p_exp) * rz)


static func _build_sculpted_daub_wall_mesh(
	rx: float, rz: float, wall_h: float, is_round: bool, seed_val: int
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	var rings := 7
	for r in range(rings + 1):
		var v := float(r) / float(rings)
		var py := lerpf(-0.12, wall_h, v)
		var batter := 1.0 + (1.0 - v) * 0.09 + sin(v * PI) * 0.02
		for s in range(segs + 1):
			var u := float(s) / float(segs)
			var ang := u * TAU
			var base_xz := _eval_hut_perimeter(ang, rx * batter, rz * batter, is_round)
			var wobble := (
				sin(ang * 5.0 + float(seed_val) * 0.7 + v * 3.2) * 0.022
				+ cos(ang * 8.0 - v * 4.5) * 0.014
			)
			var out_n2 := base_xz.normalized()
			st.set_normal(Vector3(out_n2.x, 0.08 * (1.0 - v), out_n2.y).normalized())
			st.set_uv(Vector2(u * 4.0, v))
			st.add_vertex(Vector3(base_xz.x + out_n2.x * wobble, py, base_xz.y + out_n2.y * wobble))

	var stride := segs + 1
	for r in range(rings):
		for s in range(segs):
			var i00 := r * stride + s
			var i01 := (r + 1) * stride + s
			st.add_index(i00)
			st.add_index(i00 + 1)
			st.add_index(i01)
			st.add_index(i00 + 1)
			st.add_index(i01 + 1)
			st.add_index(i01)
	st.generate_normals()
	return st.commit()


static func _build_layered_thatch_roof_mesh(
	eave_rx: float, eave_rz: float, base_y: float, roof_h: float, is_round: bool, seed_val: int
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tier_count := 3
	var segs := 28
	var rings_per_tier := 6
	var ridge_half_x := 0.06 if is_round else maxf(eave_rx - eave_rz, 0.32) * 0.62

	for t_idx in range(tier_count):
		var t_v0 := float(t_idx) / float(tier_count)
		var v_start := maxf(0.0, t_v0 - (0.06 if t_idx > 0 else 0.0))
		var v_end := float(t_idx + 1) / float(tier_count)
		var tier_bulge := 0.095 - float(t_idx) * 0.012
		var base_vert := (segs + 1) * (rings_per_tier + 1) * t_idx

		for r in range(rings_per_tier + 1):
			var rv := float(r) / float(rings_per_tier)
			var gv := lerpf(v_start, v_end, rv)
			var roll_lip := sin(clampf(rv / 0.25, 0.0, 1.0) * PI * 0.5)
			var step_out := (1.0 - gv) + tier_bulge * roll_lip * (1.0 - gv * 0.45)
			var py := (
				base_y
				+ pow(gv, 0.86) * roof_h
				+ float(t_idx) * 0.045 * (1.0 - rv * 0.5)
				- (1.0 - roll_lip) * 0.055
			)
			for s in range(segs + 1):
				var u := float(s) / float(segs)
				var ang := u * TAU
				var perim := _eval_hut_perimeter(ang, eave_rx, eave_rz, is_round)
				var xz := Vector2(cos(ang) * ridge_half_x, sin(ang) * 0.08).lerp(perim, step_out)
				var fringe := (
					sin(ang * 14.0 + float(seed_val + t_idx * 5)) * 0.028 * (1.0 - gv * 0.6)
				)
				var out_d := perim.normalized()
				var vy := py + cos(ang * 11.0 + float(t_idx * 3)) * 0.016 * (1.0 - rv)
				st.set_normal(
					Vector3(out_d.x * 0.65, 0.55 + 0.25 * roll_lip, out_d.y * 0.65).normalized()
				)
				st.set_uv(Vector2(u * 6.0, gv * 3.0))
				st.add_vertex(Vector3(xz.x + out_d.x * fringe, vy, xz.y + out_d.y * fringe))

		var stride := segs + 1
		for r in range(rings_per_tier):
			for s in range(segs):
				var i00 := base_vert + r * stride + s
				var i01 := base_vert + (r + 1) * stride + s
				st.add_index(i00)
				st.add_index(i00 + 1)
				st.add_index(i01)
				st.add_index(i00 + 1)
				st.add_index(i01 + 1)
				st.add_index(i01)
	st.generate_normals()
	return st.commit()


static func _add_tribal_doorway_and_window(
	root: Node3D,
	rx: float,
	rz: float,
	wall_h: float,
	is_elder: bool,
	is_round: bool,
	timber_mat: Material,
	rope_mat: Material,
	stone_mat: Material
) -> void:
	var dz := rz + 0.04
	var side_xs: Array[float] = [-0.42, 0.42]
	for sx: float in side_xs:
		_add_cyl(root, 0.072, 0.095, 1.24, Vector3(sx, 0.56, dz + 0.06), Vector3.ZERO, timber_mat)
	_add_cyl(
		root, 0.075, 0.078, 1.12, Vector3(0.0, 1.16, dz + 0.08), Vector3(0, 0, PI * 0.5), timber_mat
	)

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.95, 0.54, 0.18)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.96, 0.52, 0.14)
	glow_mat.emission_energy_multiplier = 1.65
	glow_mat.roughness = 0.45
	_add_box(root, Vector3(0.72, 1.06, 0.12), Vector3(0.0, 0.54, dz - 0.02), Vector3.ZERO, glow_mat)
	_add_box(
		root,
		Vector3(0.46, 0.98, 0.06),
		Vector3(-0.14, 0.56, dz + 0.04),
		Vector3(0, 0, 0.12),
		rope_mat
	)
	_add_box(
		root, Vector3(1.06, 0.14, 0.44), Vector3(0.0, 0.03, dz + 0.22), Vector3.ZERO, stone_mat
	)
	_add_box(
		root,
		Vector3(0.10, 0.36, 0.36),
		Vector3(rx - 0.02, wall_h * 0.62, 0.0),
		Vector3.ZERO,
		glow_mat
	)

	var door_light := OmniLight3D.new()
	door_light.position = Vector3(0.0, 0.85, dz + 0.45)
	door_light.light_color = Color(1.0, 0.62, 0.24)
	door_light.light_energy = 1.15 if is_elder else 0.85
	door_light.omni_range = 3.8
	root.add_child(door_light)

	if is_elder:
		var px_list: Array[float] = [-0.58, 0.58]
		for px_s: float in px_list:
			_add_cyl(
				root, 0.052, 0.068, 1.28, Vector3(px_s, 0.58, dz + 0.48), Vector3.ZERO, timber_mat
			)
		_add_cyl(
			root,
			0.048,
			0.048,
			1.42,
			Vector3(0.0, 1.18, dz + 0.48),
			Vector3(0, 0, PI * 0.5),
			timber_mat
		)
		var barrel := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Barrel.glb", 0.36, {}, true
		)
		barrel.position = Vector3(-rx - 0.22, -0.02, 0.45)
		root.add_child(barrel)
	elif is_round:
		var bags := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Bags.glb", 0.38, {}, true
		)
		bags.position = Vector3(rx + 0.18, -0.02, 0.42)
		bags.rotation.y = 0.55
		root.add_child(bags)
	else:
		var hay := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.VILLAGE_DIR + "Hay.glb", 0.44, {}, true
		)
		hay.position = Vector3(-rx - 0.26, -0.03, 0.24)
		hay.rotation.y = 0.48
		root.add_child(hay)


static func _add_roof_wind_poles_and_smoke(
	root: Node3D,
	rx: float,
	rz: float,
	wall_h: float,
	roof_h: float,
	is_elder: bool,
	is_round: bool,
	timber_mat: Material,
	rope_mat: Material,
	daub_mat: Material
) -> void:
	var apex_y := wall_h - 0.08 + roof_h
	var ridge_len := 0.45 if is_round else maxf(rx - rz, 0.45) * 1.45
	_add_cyl(
		root,
		0.058,
		0.062,
		ridge_len + 0.55,
		Vector3(0.0, apex_y + 0.04, 0.0),
		Vector3(0, 0, PI * 0.5),
		timber_mat
	)

	var pair_count := 2 if is_round else 3
	var wp_len := sqrt(rz * rz + roof_h * roof_h) + 0.42
	var wp_slope := atan2(rz + 0.35, roof_h)
	for p_idx in range(pair_count):
		var px := (
			0.0
			if pair_count == 1
			else lerpf(-ridge_len * 0.42, ridge_len * 0.42, float(p_idx) / float(pair_count - 1))
		)
		var side_zs: Array[float] = [-1.0, 1.0]
		for side_z: float in side_zs:
			_add_cyl(
				root,
				0.038,
				0.052,
				wp_len,
				Vector3(px + side_z * 0.04, wall_h + roof_h * 0.52, side_z * (rz + 0.22) * 0.46),
				Vector3(side_z * wp_slope, 0.0, side_z * 0.06),
				timber_mat
			)
		_add_torus(
			root, 0.048, 0.082, Vector3(px, apex_y + 0.06, 0.0), Vector3(0, 0, PI * 0.5), rope_mat
		)

	_add_cyl(root, 0.16, 0.24, 0.34, Vector3(0.0, apex_y + 0.10, -0.05), Vector3.ZERO, daub_mat)
	root.add_child(
		_create_smoke_plume_particles(
			Vector3(0.0, apex_y + 0.28, -0.05), 14 if is_elder else 10, 0.55
		)
	)


static func _assemble_tier1_craft_shed(root: Node3D) -> void:
	var ao := _create_vfx_quad(0, Vector2(5.4, 4.8), Color(0.05, 0.04, 0.03, 0.84), 0.85)
	ao.rotation.x = -PI * 0.5
	ao.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(ao)

	var timber_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.45, 0.34, 0.23), Color.BLACK, 0.55, 0.48, 0.52, 0.86
	)
	var rope_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_wattle_weave", Color(0.66, 0.54, 0.36), Color.BLACK, 0.48, 0.40, 0.28, 0.88
	)
	var thatch_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_thatch_roof", Color(0.72, 0.60, 0.38), Color.BLACK, 0.52, 0.36, 0.28, 0.92, 0.0, 0.22
	)
	var daub_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_clay_daub", Color(0.74, 0.58, 0.42), Color.BLACK, 0.54, 0.42, 0.36, 0.92, 0.0, 0.08
	)
	var stone_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_cliff_rock", Color(0.82, 0.78, 0.72), Color.BLACK, 0.52, 0.45, 0.42, 0.84, 0.0, 0.16
	)

	var xs: Array[float] = [-1.32, 0.0, 1.32]
	var zs: Array[float] = [-0.96, 0.96]
	for px: float in xs:
		for pz: float in zs:
			_add_cyl(root, 0.064, 0.088, 1.86, Vector3(px, 0.84, pz), Vector3.ZERO, timber_mat)
			_add_torus(root, 0.058, 0.094, Vector3(px, 1.66, pz), Vector3.ZERO, rope_mat)

	var screen := _create_wattle_hurdle_3d(2.58, 1.18, timber_mat, rope_mat)
	screen.position = Vector3(0.0, 0.0, -0.96)
	root.add_child(screen)

	var shed_roof := MeshInstance3D.new()
	shed_roof.mesh = _build_layered_thatch_roof_mesh(1.78, 1.38, 1.62, 0.96, false, 53)
	shed_roof.material_override = thatch_mat
	root.add_child(shed_roof)

	_add_cyl(root, 0.68, 0.76, 0.36, Vector3(-0.62, 0.12, -0.22), Vector3.ZERO, stone_mat)
	var kiln_dome := MeshInstance3D.new()
	var kd_sphere := SphereMesh.new()
	kd_sphere.radius = 0.62
	kd_sphere.height = 0.96
	kd_sphere.is_hemisphere = true
	kiln_dome.mesh = kd_sphere
	kiln_dome.position = Vector3(-0.62, 0.28, -0.22)
	kiln_dome.material_override = daub_mat
	root.add_child(kiln_dome)
	_add_cyl(root, 0.16, 0.22, 0.95, Vector3(-0.62, 1.52, -0.22), Vector3.ZERO, daub_mat)

	var ember_mouth := _create_vfx_quad(1, Vector2(0.54, 0.54), Color(1.0, 0.42, 0.08, 0.95), 0.95)
	ember_mouth.rotation.x = -PI * 0.5
	ember_mouth.position = Vector3(-0.62, 0.31, 0.24)
	root.add_child(ember_mouth)

	var kiln_light := OmniLight3D.new()
	kiln_light.position = Vector3(-0.62, 0.62, 0.48)
	kiln_light.light_color = Color(1.0, 0.52, 0.16)
	kiln_light.light_energy = 1.25
	kiln_light.omni_range = 3.6
	root.add_child(kiln_light)
	root.add_child(_create_smoke_plume_particles(Vector3(-0.62, 2.58, -0.22), 14, 0.68))

	var stump := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.NATURE_DIR + "TreeStump_Moss.glb", 0.48, {}, true
	)
	stump.position = Vector3(0.68, -0.04, 0.18)
	root.add_child(stump)
	var axe := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ITEMS_DIR + "Axe_small.glb", 0.34, {}, true
	)
	axe.position = Vector3(0.68, 0.38, 0.18)
	axe.rotation = Vector3(0.35, 0.6, -0.45)
	root.add_child(axe)
	var bags := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + "Bags.glb", 0.38, {}, true
	)
	bags.position = Vector3(0.75, -0.02, -0.48)
	root.add_child(bags)


static func _assemble_tier1_spring_well(root: Node3D) -> void:
	var ao := _create_vfx_quad(0, Vector2(3.4, 3.4), Color(0.05, 0.04, 0.03, 0.82), 0.85)
	ao.rotation.x = -PI * 0.5
	ao.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(ao)

	var timber_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.45, 0.34, 0.23), Color.BLACK, 0.56, 0.48, 0.56, 0.86
	)
	var rope_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_wattle_weave", Color(0.66, 0.54, 0.36), Color.BLACK, 0.48, 0.40, 0.28, 0.88
	)
	var stone_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_cliff_rock", Color(0.82, 0.80, 0.74), Color.BLACK, 0.52, 0.48, 0.55, 0.82, 0.0, 0.26
	)

	var rim_stone_mesh := _make_ring_stone_mesh(Color(0.84, 0.80, 0.75), 0.22)
	for i in range(10):
		var ang := float(i) * TAU / 10.0
		var st := MeshInstance3D.new()
		st.mesh = rim_stone_mesh
		st.scale = Vector3(0.18, 0.16, 0.18)
		st.position = Vector3(cos(ang) * 0.68, 0.08, sin(ang) * 0.68)
		st.rotation.y = ang + 0.5
		st.material_override = stone_mat
		root.add_child(st)

	for tier_i in range(2):
		var ly := 0.24 + float(tier_i) * 0.12
		var dirs: Array[float] = [-1.0, 1.0]
		for d_s: float in dirs:
			var p_x := Vector3(0.0, ly, d_s * 0.52)
			var p_z := Vector3(d_s * 0.52, ly + 0.06, 0.0)
			_add_cyl(root, 0.068, 0.068, 1.42, p_x, Vector3(0, 0, PI * 0.5), timber_mat)
			_add_cyl(root, 0.068, 0.068, 1.42, p_z, Vector3(PI * 0.5, 0, 0), timber_mat)

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.08, 0.18, 0.22)
	water_mat.roughness = 0.12
	_add_cyl(root, 0.48, 0.48, 0.04, Vector3(0.0, 0.18, 0.0), Vector3.ZERO, water_mat)

	var side_xs: Array[float] = [-0.54, 0.54]
	for sx: float in side_xs:
		_add_cyl(root, 0.048, 0.064, 1.36, Vector3(sx, 0.86, 0.0), Vector3.ZERO, timber_mat)
	_add_cyl(root, 0.045, 0.045, 1.28, Vector3(0.0, 1.42, 0.0), Vector3(0, 0, PI * 0.5), timber_mat)
	_add_cyl(root, 0.022, 0.022, 0.68, Vector3(0.0, 1.08, 0.0), Vector3.ZERO, rope_mat)
	_add_cyl(root, 0.14, 0.11, 0.24, Vector3(0.0, 0.68, 0.0), Vector3.ZERO, timber_mat)


static func _assemble_tier1_tribal_hearth(root: Node3D) -> void:
	var ao := _create_vfx_quad(0, Vector2(4.2, 4.2), Color(0.05, 0.04, 0.03, 0.85), 0.85)
	ao.rotation.x = -PI * 0.5
	ao.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(ao)

	var ember_bed := _create_vfx_quad(1, Vector2(1.48, 1.48), Color(1.0, 0.44, 0.08, 0.96), 0.95)
	ember_bed.rotation.x = -PI * 0.5
	ember_bed.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(ember_bed)

	var stone_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_cliff_rock", Color(0.76, 0.72, 0.68), Color.BLACK, 0.55, 0.48, 0.52, 0.85
	)
	var wood_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.44, 0.33, 0.22), Color.BLACK, 0.55, 0.48, 0.55, 0.86
	)
	var rope_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_wattle_weave", Color(0.64, 0.52, 0.34), Color.BLACK, 0.48, 0.40, 0.28, 0.88
	)
	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color(0.14, 0.14, 0.15)
	iron_mat.metallic = 0.78
	iron_mat.roughness = 0.42

	var ring_stone_mesh := _make_ring_stone_mesh(Color(0.78, 0.74, 0.70), 0.12)
	for i in range(10):
		var ang := float(i) * TAU / 10.0
		var st := MeshInstance3D.new()
		st.mesh = ring_stone_mesh
		st.scale = Vector3(0.19, 0.14, 0.19)
		st.position = Vector3(cos(ang) * 0.78, 0.06, sin(ang) * 0.78)
		st.rotation.y = ang + 0.4
		st.material_override = stone_mat
		root.add_child(st)

	for i in range(4):
		var ang := float(i) * PI * 0.5 + 0.35
		_add_cyl(
			root,
			0.068,
			0.078,
			0.94,
			Vector3(cos(ang) * 0.16, 0.14, sin(ang) * 0.16),
			Vector3(PI * 0.38, ang, 0.0),
			wood_mat
		)
	for i in range(3):
		var ang := float(i) * TAU / 3.0 + 0.25
		_add_cyl(
			root,
			0.036,
			0.056,
			2.18,
			Vector3(cos(ang) * 0.46, 0.92, sin(ang) * 0.46),
			Vector3(-sin(ang) * 0.36, 0.0, cos(ang) * 0.36),
			wood_mat
		)
	_add_torus(root, 0.055, 0.095, Vector3(0.0, 1.72, 0.0), Vector3.ZERO, rope_mat)
	_add_cyl(root, 0.020, 0.020, 0.88, Vector3(0.0, 1.28, 0.0), Vector3.ZERO, iron_mat)

	var pot := MeshInstance3D.new()
	var pot_mesh := SphereMesh.new()
	pot_mesh.radius = 0.30
	pot_mesh.height = 0.48
	pot.mesh = pot_mesh
	pot.position = Vector3(0.0, 0.68, 0.0)
	pot.material_override = iron_mat
	root.add_child(pot)

	var log_angles: Array[float] = [-2.25, 0.15, 2.15]
	for l_ang: float in log_angles:
		var sit_log := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.NATURE_DIR + "WoodLog_Moss.glb", 0.54, {}, true
		)
		sit_log.position = Vector3(cos(l_ang) * 1.92, -0.02, sin(l_ang) * 1.92)
		sit_log.rotation.y = -l_ang + PI * 0.5
		root.add_child(sit_log)

	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.vertex_color_use_as_albedo = true
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var flames := CPUParticles3D.new()
	flames.position = Vector3(0.0, 0.22, 0.0)
	flames.amount = 18
	flames.lifetime = 0.9
	flames.preprocess = 1.0
	var f_quad := QuadMesh.new()
	f_quad.size = Vector2(0.40, 0.56)
	f_quad.material = fire_mat
	flames.mesh = f_quad
	flames.direction = Vector3.UP
	flames.spread = 16.0
	flames.gravity = Vector3(0.0, 1.2, 0.0)
	flames.initial_velocity_min = 0.35
	flames.initial_velocity_max = 0.72
	var f_grad := Gradient.new()
	f_grad.set_color(0, Color(1.0, 0.82, 0.28, 0.90))
	f_grad.add_point(0.5, Color(0.98, 0.38, 0.08, 0.72))
	f_grad.set_color(1, Color(0.24, 0.08, 0.04, 0.0))
	flames.color_ramp = f_grad
	root.add_child(flames)

	root.add_child(_create_smoke_plume_particles(Vector3(0.0, 0.88, 0.0), 16, 0.74))
	var f_light := OmniLight3D.new()
	f_light.position = Vector3(0.0, 0.95, 0.0)
	f_light.light_color = Color(1.0, 0.62, 0.22)
	f_light.light_energy = 1.65
	f_light.omni_range = 6.2
	root.add_child(f_light)


static func _assemble_tier1_fishing_sluice(root: Node3D) -> void:
	var timber_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.44, 0.34, 0.23), Color.BLACK, 0.56, 0.50, 0.68, 0.86
	)
	var rope_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_wattle_weave", Color(0.64, 0.52, 0.34), Color.BLACK, 0.48, 0.42, 0.36, 0.88
	)

	var sx_list: Array[float] = [-0.68, 0.68]
	var sz_list: Array[float] = [-0.85, 0.0, 0.85]
	for sx: float in sx_list:
		for sz: float in sz_list:
			_add_cyl(root, 0.052, 0.072, 1.35, Vector3(sx, 0.12, sz), Vector3.ZERO, timber_mat)

	for i in range(11):
		var pz := -0.92 + float(i) * 0.185
		_add_cyl(
			root,
			0.068,
			0.074,
			1.56,
			Vector3(sin(float(i) * 1.9) * 0.04, 0.48, pz),
			Vector3(0, 0, PI * 0.5),
			timber_mat
		)

	var gate_grp := Node3D.new()
	gate_grp.position = Vector3(1.18, 0.08, -0.35)
	gate_grp.rotation = Vector3(0.06, 0.18, -0.09)
	root.add_child(gate_grp)

	var gzs: Array[float] = [-0.72, 0.72]
	for gz: float in gzs:
		_add_cyl(gate_grp, 0.078, 0.095, 1.68, Vector3(0.0, 0.36, gz), Vector3.ZERO, timber_mat)
	_add_cyl(
		gate_grp, 0.072, 0.072, 1.72, Vector3(0.0, 1.12, 0.0), Vector3(PI * 0.5, 0, 0), timber_mat
	)

	for b_i in range(4):
		_add_box(
			gate_grp,
			Vector3(0.08, 0.18, 1.36),
			Vector3(0.0, 0.12 + float(b_i) * 0.20, 0.0),
			Vector3(sin(float(b_i) * 2.1) * 0.05, 0, 0),
			timber_mat
		)

	var jammed_log := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.NATURE_DIR + "WoodLog_Moss.glb", 0.48, {}, true
	)
	jammed_log.position = Vector3(0.85, -0.05, 0.35)
	jammed_log.rotation.y = 0.65
	root.add_child(jammed_log)

	_add_cyl(
		root, 0.12, 0.28, 0.78, Vector3(-0.35, 0.64, -0.45), Vector3(0.25, 0.4, PI * 0.44), rope_mat
	)


static func _populate_wattle_fences_and_clearing_details(settlement_root: Node3D) -> void:
	var timber_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_aged_timber", Color(0.45, 0.34, 0.23), Color.BLACK, 0.55, 0.48, 0.52, 0.86
	)
	var rope_mat := SevaraAssetLibrary3D._make_arch_shader_material(
		"pbr_wattle_weave", Color(0.62, 0.50, 0.33), Color.BLACK, 0.48, 0.40, 0.28, 0.88
	)

	var hurdle_specs: Array[Dictionary] = [
		{"pos": Vector2(-16.2, -10.8), "yaw": 0.62, "len": 3.2},
		{"pos": Vector2(-10.8, -13.2), "yaw": 0.25, "len": 3.0},
		{"pos": Vector2(-19.6, -4.8), "yaw": 1.18, "len": 2.8},
	]
	for hs: Dictionary in hurdle_specs:
		var hp: Vector2 = hs["pos"]
		var hurdle := _create_wattle_hurdle_3d(float(hs["len"]), 0.88, timber_mat, rope_mat)
		hurdle.position = Vector3(hp.x, SevaraTerrainGen3D.get_height_at(hp.x, hp.y) - 0.04, hp.y)
		hurdle.rotation = _get_gentle_ground_tilt(hp.x, hp.y, float(hs["yaw"]), 0.18)
		settlement_root.add_child(hurdle)

	var clearing_stumps: Array[Vector2] = [
		Vector2(-20.4, -9.8),
		Vector2(-15.4, -13.8),
		Vector2(-4.4, -14.8),
	]
	for i in range(clearing_stumps.size()):
		var sp: Vector2 = clearing_stumps[i]
		var stump := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.NATURE_DIR + "TreeStump_Moss.glb", 0.58, {}, true
		)
		stump.position = Vector3(sp.x, SevaraTerrainGen3D.get_height_at(sp.x, sp.y) - 0.04, sp.y)
		stump.rotation.y = float(i) * 1.4
		settlement_root.add_child(stump)


static func _create_wattle_hurdle_3d(
	length_m: float, height_m: float, timber_mat: Material, wattle_mat: Material
) -> Node3D:
	var grp := Node3D.new()
	grp.name = "WattleHurdle3D"
	var stake_count := maxi(int(round(length_m / 0.52)) + 1, 4)
	for i in range(stake_count):
		var sx := -length_m * 0.5 + float(i) * (length_m / float(stake_count - 1))
		_add_cyl(
			grp,
			0.036,
			0.052,
			height_m + 0.22,
			Vector3(sx, height_m * 0.5 - 0.04, 0.0),
			Vector3(0, 0, sin(float(i) * 2.1) * 0.04),
			timber_mat
		)
	_add_box(
		grp,
		Vector3(length_m - 0.08, height_m * 0.84, 0.09),
		Vector3(0.0, height_m * 0.45, 0.0),
		Vector3.ZERO,
		wattle_mat
	)
	return grp


static func _build_upgraded_tier3_building(root: Node3D, archetype: String) -> Node3D:
	var model_file := "House_1.glb"
	match archetype:
		"worker_hut_round":
			model_file = "Blacksmith.glb"
		"worker_hut_oval":
			model_file = "Stable.glb"
		"craft_shed":
			model_file = "Gazebo.glb"
	var upgraded := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.VILLAGE_DIR + model_file, 0.62, {}, true
	)
	upgraded.position.y = -0.05
	root.add_child(upgraded)
	return root


static func _make_ring_stone_mesh(tint: Color, moss: float) -> Mesh:
	var cfg := {
		"moss_amount": moss, "snow_amount": 0.0, "wetness": 0.3, "triplanar": 1.0, "tint": tint
	}
	return SevaraAssetLibrary3D.build_bevel_smoothed_rock_mesh("Rock_Medium_2", {"rock": cfg})


static func _add_cyl(
	parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, rot: Vector3, mat: Material
) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bot
	cyl.height = h
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)


static func _add_box(
	parent: Node3D, sz: Vector3, pos: Vector3, rot: Vector3, mat: Material
) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)


static func _add_torus(
	parent: Node3D, r_in: float, r_out: float, pos: Vector3, rot: Vector3, mat: Material
) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 10
	tm.ring_segments = 8
	mi.mesh = tm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)


static func _create_vfx_quad(
	mode: int, quad_size: Vector2, tint: Color, softness: float = 0.85
) -> MeshInstance3D:
	if _decal_shader_cache == null:
		_decal_shader_cache = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = quad_size
	mi.mesh = qm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat := ShaderMaterial.new()
	smat.shader = _decal_shader_cache
	smat.set_shader_parameter("effect_mode", mode)
	smat.set_shader_parameter("tint_color", tint)
	smat.set_shader_parameter("intensity", 1.0)
	smat.set_shader_parameter("softness", softness)
	mi.material_override = smat
	return mi


static func _create_smoke_plume_particles(
	origin: Vector3, amount_count: int = 16, quad_scale: float = 0.72
) -> CPUParticles3D:
	if _decal_shader_cache == null:
		_decal_shader_cache = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	var smat := ShaderMaterial.new()
	smat.shader = _decal_shader_cache
	smat.set_shader_parameter("effect_mode", 2)
	smat.set_shader_parameter("tint_color", Color(0.76, 0.78, 0.82, 0.34))
	smat.set_shader_parameter("intensity", 0.92)
	smat.set_shader_parameter("softness", 0.92)

	var smoke := CPUParticles3D.new()
	smoke.position = origin
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.amount = amount_count
	smoke.lifetime = 3.2
	smoke.preprocess = 2.0
	var s_quad := QuadMesh.new()
	s_quad.size = Vector2(quad_scale, quad_scale)
	s_quad.material = smat
	smoke.mesh = s_quad
	smoke.direction = Vector3(0.18, 1.0, 0.08).normalized()
	smoke.spread = 14.0
	smoke.gravity = Vector3(0.08, 0.36, 0.04)
	smoke.initial_velocity_min = 0.24
	smoke.initial_velocity_max = 0.48
	smoke.scale_amount_min = 0.65
	smoke.scale_amount_max = 1.65
	var s_grad := Gradient.new()
	s_grad.set_color(0, Color(0.68, 0.68, 0.72, 0.0))
	s_grad.add_point(0.22, Color(0.74, 0.75, 0.78, 0.36))
	s_grad.add_point(0.68, Color(0.80, 0.82, 0.86, 0.22))
	s_grad.set_color(1, Color(0.86, 0.88, 0.92, 0.0))
	smoke.color_ramp = s_grad
	return smoke


static func _get_gentle_ground_tilt(
	wx: float, wz: float, yaw: float, max_tilt_factor: float = 0.18
) -> Vector3:
	var nrm := SevaraTerrainGen3D.get_ground_normal(wx, wz)
	var pitch_x := clampf(nrm.z * max_tilt_factor, -0.05, 0.05)
	var roll_z := clampf(-nrm.x * max_tilt_factor, -0.05, 0.05)
	return Vector3(pitch_x, yaw, roll_z)

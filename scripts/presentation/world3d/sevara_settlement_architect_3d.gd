class_name SevaraSettlementArchitect3D
extends RefCounted
## Builds the Step 4 Sevara Sanctuary tribal settlement (`Tier 1: Wattle, Clay Daub & Thatch`).
## Every building is created as a self-contained, relocatable, upgradeable 3D object (`tier = 1..3`)
## that dynamically registers its ground pad, footpath, felled trees, and mined rocks in the world.

const V0 := Vector3.ZERO
const VDIR := "res://assets/models/village/"
const NDIR := "res://assets/nature/"
const IDIR := "res://assets/models/items/"

static var _decal_shader_cache: Shader = null
static var _water_shader_cache: Shader = null


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
			_assemble_tier1_daub_hut(root, 1.92, 1.46, 1.38, 1.56, true, false, 11)
		"worker_hut_round":
			root.set_meta("footprint_radii", Vector2(2.4, 2.4))
			root.set_meta("door_offset", Vector2(0.0, 1.48))
			_assemble_tier1_daub_hut(root, 1.50, 1.50, 1.28, 1.48, false, true, 23)
		"worker_hut_oval":
			root.set_meta("footprint_radii", Vector2(2.5, 2.3))
			root.set_meta("door_offset", Vector2(0.0, 1.36))
			_assemble_tier1_daub_hut(root, 1.66, 1.28, 1.24, 1.36, false, false, 37)
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
			_assemble_tier1_daub_hut(root, 1.55, 1.35, 1.26, 1.40, false, false, 41)
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
	var is_new := existing == null
	if is_new:
		existing = create_settlement_building_3d(building_id, archetype, tier)

	var wy := SevaraTerrainGen3D.get_height_at(world_xz.x, world_xz.y)
	existing.position = _v3(world_xz.x, wy - 0.03, world_xz.y)
	existing.rotation = _get_gentle_ground_tilt(world_xz.x, world_xz.y, yaw, 0.16)
	if is_new:
		settlement_root.add_child(existing)

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

	for st_pos: Vector2 in [Vector2(-24.5, -14.5), Vector2(-22.5, -15.8), Vector2(-9.5, -19.5)]:
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

	_populate_fences_and_stumps(settlement_root)
	_populate_east_bank_wild_landmarks(settlement_root)

	var sunbeams := Node3D.new()
	sunbeams.name = "ValleyGodRays3D"
	var beam_spots: Array[Vector3] = [
		_v3(-19.5, 6.2, -14.5), _v3(-9.5, 6.6, -18.5), _v3(3.5, 6.0, -16.5)
	]
	for b_idx in range(beam_spots.size()):
		var ray := _create_vfx_quad(4, Vector2(3.8, 12.5), Color(1.0, 0.92, 0.68, 0.15), 0.85)
		ray.position = beam_spots[b_idx]
		ray.rotation_degrees = _v3(-28.0, -34.0 + float(b_idx) * 28.0, 22.0)
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
	_add_prop_ao(root, _v3(0.0, 0.09, 0.0), Vector2(rx * 2.95, rz * 2.95), 0.78)

	var daub_tint := (
		Color(0.58, 0.46, 0.34)
		if is_elder
		else (Color(0.52, 0.41, 0.30) if is_round else Color(0.55, 0.44, 0.32))
	)
	var d_mat := _arch_mat("pbr_clay_daub", daub_tint, 0.56, 0.44, 0.36, 0.99, 0.0, 0.14)
	var t_mat := _arch_mat("pbr_aged_timber", Color(0.42, 0.32, 0.21), 0.55, 0.48, 0.52, 0.88)
	var r_mat := _arch_mat("pbr_wattle_weave", Color(0.60, 0.48, 0.32), 0.48, 0.40, 0.28, 0.88)
	var thatch_tint := (
		Color(0.60, 0.48, 0.31)
		if is_elder
		else (Color(0.53, 0.42, 0.27) if is_round else Color(0.57, 0.46, 0.29))
	)
	var th_mat := _arch_mat("pbr_thatch_roof", thatch_tint, 0.56, 0.42, 0.32, 1.0, 0.0, 0.30)
	var s_mat := _arch_mat("pbr_cliff_rock", Color(0.76, 0.72, 0.66), 0.50, 0.44, 0.42, 0.86, 0.22)

	var wall_mi := MeshInstance3D.new()
	wall_mi.name = "ClayDaubWalls"
	wall_mi.mesh = _build_daub_wall_mesh(rx, rz, wall_h, is_round, seed_val)
	wall_mi.material_override = d_mat
	root.add_child(wall_mi)

	var post_count := 8 if is_round else 10
	for pi in range(post_count):
		var ang := float(pi) * TAU / float(post_count)
		if absf(wrapf(ang - PI * 0.5, -PI, PI)) < 0.34:
			continue
		var p_pt := _eval_hut_perimeter(ang, rx + 0.03, rz + 0.03, is_round)
		var out_d := p_pt.normalized()
		var p_pos := _v3(p_pt.x, wall_h * 0.5 - 0.06, p_pt.y)
		var p_rot := _v3(-out_d.y * 0.05, 0.0, out_d.x * 0.05)
		_add_cyl(root, 0.064, 0.088, wall_h + 0.24, p_pos, p_rot, t_mat)
		_add_torus(root, 0.058, 0.094, _v3(p_pt.x, wall_h - 0.08, p_pt.y), V0, r_mat)

	_add_hut_openings(root, rx, rz, wall_h, is_elder, is_round, t_mat, r_mat, s_mat, th_mat)

	var roof_mi := MeshInstance3D.new()
	roof_mi.name = "LayeredThatchRoof"
	roof_mi.mesh = _build_thatch_roof_mesh(
		rx + 0.42, rz + 0.42, wall_h - 0.08, roof_h, is_round, seed_val
	)
	roof_mi.material_override = th_mat
	root.add_child(roof_mi)

	_add_hut_ridge_and_smoke(root, rx, rz, wall_h, roof_h, is_elder, is_round, t_mat, r_mat, d_mat)


static func _eval_hut_perimeter(ang: float, rx: float, rz: float, is_round: bool) -> Vector2:
	var ca := cos(ang)
	var sa := sin(ang)
	if is_round:
		return Vector2(ca * rx, sa * rz)
	var p_exp := 0.76
	return Vector2(signf(ca) * pow(absf(ca), p_exp) * rx, signf(sa) * pow(absf(sa), p_exp) * rz)


static func _build_daub_wall_mesh(
	rx: float, rz: float, wall_h: float, is_round: bool, seed_val: int
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	var rings := 8
	for r in range(rings + 1):
		var v := float(r) / float(rings)
		var py := lerpf(-0.14, wall_h, v)
		var batter := 1.0 + (1.0 - v) * 0.11 + sin(v * PI) * 0.025
		for s in range(segs + 1):
			var u := float(s) / float(segs)
			var ang := u * TAU
			var base_xz := _eval_hut_perimeter(ang, rx * batter, rz * batter, is_round)
			var wobble := (
				sin(ang * 5.0 + float(seed_val) * 0.7 + v * 3.2) * 0.028
				+ cos(ang * 8.0 - v * 4.5) * 0.018
			)
			var out_n2 := base_xz.normalized()
			st.set_normal(_v3(out_n2.x, 0.09 * (1.0 - v), out_n2.y).normalized())
			st.set_uv(Vector2(u * 4.0, v))
			st.add_vertex(_v3(base_xz.x + out_n2.x * wobble, py, base_xz.y + out_n2.y * wobble))

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


static func _build_thatch_roof_mesh(
	eave_rx: float, eave_rz: float, base_y: float, roof_h: float, is_round: bool, seed_val: int
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tier_count := 4
	var segs := 32
	var rings_per_tier := 6
	var ridge_half_x := 0.05 if is_round else maxf(eave_rx * 0.48, 0.42)

	for t_idx in range(tier_count):
		var t_v0 := float(t_idx) / float(tier_count)
		var v_start := maxf(0.0, t_v0 - (0.06 if t_idx > 0 else 0.0))
		var v_end := float(t_idx + 1) / float(tier_count)
		var tier_bulge := 0.088 - float(t_idx) * 0.012
		var base_vert := (segs + 1) * (rings_per_tier + 1) * t_idx

		for r in range(rings_per_tier + 1):
			var rv := float(r) / float(rings_per_tier)
			var gv := lerpf(v_start, v_end, rv)
			var roll_lip := sin(clampf(rv / 0.25, 0.0, 1.0) * PI * 0.5)
			var step_out := (1.0 - gv) + tier_bulge * roll_lip * (1.0 - gv * 0.45)
			var py := (
				base_y
				+ pow(gv, 0.90) * roof_h
				+ float(t_idx) * 0.042 * (1.0 - rv * 0.45)
				- (1.0 - roll_lip) * 0.064
			)
			for s in range(segs + 1):
				var u := float(s) / float(segs)
				var ang := u * TAU
				var perim := _eval_hut_perimeter(ang, eave_rx, eave_rz, is_round)
				var xz := Vector2(cos(ang) * ridge_half_x, sin(ang) * 0.08).lerp(perim, step_out)
				var fringe := (
					(
						sin(ang * 16.0 + float(seed_val + t_idx * 5)) * 0.045
						+ cos(ang * 24.0 - float(t_idx * 3)) * 0.024
					)
					* (1.0 - gv * 0.55)
				)
				var out_d := perim.normalized()
				var vy := py + cos(ang * 12.0 + float(t_idx * 3)) * 0.026 * (1.0 - rv)
				st.set_normal(
					_v3(out_d.x * 0.65, 0.48 + 0.35 * roll_lip, out_d.y * 0.65).normalized()
				)
				st.set_uv(Vector2(u * 6.0, gv * 4.0))
				st.add_vertex(_v3(xz.x + out_d.x * fringe, vy, xz.y + out_d.y * fringe))

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


static func _add_hut_openings(
	root: Node3D,
	rx: float,
	rz: float,
	wall_h: float,
	is_elder: bool,
	is_round: bool,
	t_mat: Material,
	r_mat: Material,
	s_mat: Material,
	th_mat: Material
) -> void:
	var dz := rz + 0.04
	var rot_z90 := _v3(0.0, 0.0, PI * 0.5)
	var rot_x90 := _v3(PI * 0.5, 0.0, 0.0)
	for sx: float in [-0.42, 0.42]:
		_add_cyl(root, 0.072, 0.095, 1.24, _v3(sx, 0.56, dz + 0.06), V0, t_mat)
	_add_cyl(root, 0.075, 0.078, 1.12, _v3(0.0, 1.16, dz + 0.08), rot_z90, t_mat)

	var in_mat := StandardMaterial3D.new()
	in_mat.albedo_color = Color(0.07, 0.05, 0.03)
	in_mat.roughness = 0.95
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.84, 0.42, 0.12)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.92, 0.44, 0.10)
	glow_mat.emission_energy_multiplier = 0.68
	glow_mat.roughness = 0.65
	_add_box(root, _v3(0.72, 1.06, 0.10), _v3(0.0, 0.54, dz - 0.03), V0, in_mat)
	_add_box(root, _v3(0.56, 0.42, 0.08), _v3(0.0, 0.28, dz - 0.01), V0, glow_mat)
	_add_box(root, _v3(0.46, 0.98, 0.06), _v3(-0.14, 0.56, dz + 0.04), _v3(0, 0, 0.12), r_mat)
	_add_box(root, _v3(1.06, 0.14, 0.44), _v3(0.0, 0.03, dz + 0.22), V0, s_mat)
	_add_box(root, _v3(0.10, 0.34, 0.34), _v3(rx - 0.02, wall_h * 0.62, 0.0), V0, glow_mat)

	_add_light(
		root, _v3(0.0, 0.68, dz + 0.55), Color(1.0, 0.58, 0.20), 0.95 if is_elder else 0.72, 3.8
	)

	if is_elder:
		var r_raf := _v3(PI * 0.5 + 0.24, 0.0, 0.0)
		var r_brc := _v3(-0.65, 0.0, 0.0)
		for px_s: float in [-0.58, 0.58]:
			_add_cyl(root, 0.056, 0.072, 1.12, _v3(px_s, 0.50, dz + 0.88), V0, t_mat)
			_add_torus(root, 0.048, 0.086, _v3(px_s, 1.04, dz + 0.88), rot_z90, r_mat)
			_add_cyl(root, 0.048, 0.054, 1.06, _v3(px_s, 1.16, dz + 0.42), r_raf, t_mat)
			_add_torus(root, 0.046, 0.082, _v3(px_s, 1.26, dz - 0.02), rot_x90, r_mat)
			_add_cyl(root, 0.036, 0.042, 0.46, _v3(px_s, 0.86, dz + 0.72), r_brc, t_mat)
		_add_cyl(root, 0.052, 0.052, 1.46, _v3(0.0, 1.04, dz + 0.88), rot_z90, t_mat)
		_add_box(root, _v3(1.56, 0.14, 0.96), _v3(0.0, 1.22, dz + 0.44), _v3(0.24, 0, 0), th_mat)
		_add_prop_ao(root, _v3(0.0, 0.08, dz + 0.52), Vector2(1.75, 1.35), 0.76)

		var barrel := _inst_model(VDIR + "Barrel.glb", 0.36)
		barrel.position = _v3(-rx - 0.26, -0.02, 0.45)
		root.add_child(barrel)
		_add_prop_ao(root, _v3(-rx - 0.26, 0.09, 0.45), Vector2(1.05, 1.05), 0.86)
	elif is_round:
		var bags := _inst_model(VDIR + "Bags.glb", 0.38)
		bags.position = _v3(rx + 0.22, -0.02, 0.42)
		bags.rotation.y = 0.55
		root.add_child(bags)
		_add_prop_ao(root, _v3(rx + 0.22, 0.09, 0.42), Vector2(1.15, 1.15), 0.86)
	else:
		var hay := _inst_model(VDIR + "Hay.glb", 0.44)
		hay.position = _v3(-rx - 0.30, -0.03, 0.24)
		hay.rotation.y = 0.48
		root.add_child(hay)
		_add_prop_ao(root, _v3(-rx - 0.30, 0.09, 0.24), Vector2(1.35, 1.35), 0.86)


static func _add_hut_ridge_and_smoke(
	root: Node3D,
	rx: float,
	rz: float,
	wall_h: float,
	roof_h: float,
	is_elder: bool,
	is_round: bool,
	t_mat: Material,
	r_mat: Material,
	d_mat: Material
) -> void:
	var apex_y := wall_h - 0.08 + roof_h
	var ridge_len := 0.45 if is_round else maxf(rx - rz, 0.45) * 1.45
	var rot_z90 := _v3(0.0, 0.0, PI * 0.5)
	_add_cyl(root, 0.058, 0.062, ridge_len + 0.55, _v3(0.0, apex_y + 0.04, 0.0), rot_z90, t_mat)

	var pair_count := 2 if is_round else 3
	var wp_len := sqrt(rz * rz + roof_h * roof_h) + 0.42
	var wp_slope := atan2(rz + 0.35, roof_h)
	for p_idx in range(pair_count):
		var px := (
			0.0
			if pair_count == 1
			else lerpf(-ridge_len * 0.42, ridge_len * 0.42, float(p_idx) / float(pair_count - 1))
		)
		for side_z: float in [-1.0, 1.0]:
			var w_pos := _v3(
				px + side_z * 0.04, wall_h + roof_h * 0.52, side_z * (rz + 0.22) * 0.46
			)
			var w_rot := _v3(side_z * wp_slope, 0.0, side_z * 0.06)
			_add_cyl(root, 0.038, 0.052, wp_len, w_pos, w_rot, t_mat)
		_add_torus(root, 0.048, 0.082, _v3(px, apex_y + 0.06, 0.0), rot_z90, r_mat)

	_add_cyl(root, 0.16, 0.24, 0.34, _v3(0.0, apex_y + 0.10, -0.05), V0, d_mat)
	root.add_child(_make_smoke_plume(_v3(0.0, apex_y + 0.28, -0.05), 22 if is_elder else 18, 0.68))


static func _assemble_tier1_craft_shed(root: Node3D) -> void:
	_add_prop_ao(root, _v3(0.0, 0.08, 0.0), Vector2(4.8, 4.4), 0.78)

	var t_mat := _arch_mat("pbr_aged_timber", Color(0.42, 0.32, 0.21), 0.55, 0.48, 0.52, 0.88)
	var r_mat := _arch_mat("pbr_wattle_weave", Color(0.58, 0.46, 0.30), 0.48, 0.40, 0.28, 0.88)
	var th_mat := _arch_mat("pbr_thatch_roof", Color(0.56, 0.45, 0.28), 0.56, 0.42, 0.32, 1.0, 0.28)
	var d_mat := _arch_mat("pbr_clay_daub", Color(0.50, 0.36, 0.25), 0.56, 0.44, 0.36, 0.99, 0.10)
	var s_mat := _arch_mat("pbr_cliff_rock", Color(0.74, 0.70, 0.64), 0.52, 0.45, 0.42, 0.86, 0.18)

	for px: float in [-1.32, 0.0, 1.32]:
		for pz: float in [-0.96, 0.96]:
			_add_cyl(root, 0.064, 0.088, 1.86, _v3(px, 0.84, pz), V0, t_mat)
			_add_torus(root, 0.058, 0.094, _v3(px, 1.66, pz), V0, r_mat)

	var screen := _create_wattle_hurdle_3d(2.58, 1.18, t_mat, r_mat)
	screen.position = _v3(0.0, 0.0, -0.96)
	root.add_child(screen)

	var shed_roof := MeshInstance3D.new()
	shed_roof.mesh = _build_thatch_roof_mesh(1.82, 1.42, 1.62, 0.96, false, 53)
	shed_roof.material_override = th_mat
	root.add_child(shed_roof)

	_add_prop_ao(root, _v3(-0.62, 0.09, -0.22), Vector2(1.65, 1.65), 0.88)
	var kiln_stone_mesh := _make_ring_stone_mesh(Color(0.74, 0.70, 0.65), 0.14)
	for i in range(8):
		var ang := float(i) * TAU / 8.0
		var ks := MeshInstance3D.new()
		ks.mesh = kiln_stone_mesh
		ks.scale = _v3(0.22, 0.18, 0.22)
		ks.position = _v3(-0.62 + cos(ang) * 0.58, 0.12, -0.22 + sin(ang) * 0.58)
		ks.rotation.y = ang
		ks.material_override = s_mat
		root.add_child(ks)

	var kiln_dome := MeshInstance3D.new()
	var kd_sphere := SphereMesh.new()
	kd_sphere.radius = 0.56
	kd_sphere.height = 0.82
	kd_sphere.is_hemisphere = true
	kiln_dome.mesh = kd_sphere
	kiln_dome.position = _v3(-0.62, 0.18, -0.22)
	kiln_dome.material_override = d_mat
	root.add_child(kiln_dome)
	_add_cyl(root, 0.15, 0.20, 0.72, _v3(-0.62, 1.18, -0.22), V0, d_mat)

	var ember_mouth := _create_vfx_quad(1, Vector2(0.56, 0.56), Color(1.0, 0.42, 0.08, 0.95), 0.95)
	ember_mouth.rotation.x = -PI * 0.5
	ember_mouth.position = _v3(-0.62, 0.16, 0.22)
	root.add_child(ember_mouth)

	_add_light(root, _v3(-0.62, 0.52, 0.42), Color(1.0, 0.50, 0.14), 1.05, 3.8)
	root.add_child(_make_smoke_plume(_v3(-0.62, 2.52, -0.22), 18, 0.62))

	var stump := _inst_model(NDIR + "TreeStump_Moss.glb", 0.48)
	stump.position = _v3(0.68, -0.03, 0.18)
	root.add_child(stump)
	_add_prop_ao(root, _v3(0.68, 0.09, 0.18), Vector2(1.08, 1.08), 0.88)

	var axe := _inst_model(IDIR + "Axe_small.glb", 0.38)
	axe.position = _v3(0.68, 0.16, 0.18)
	axe.rotation = _v3(0.24, 0.65, -0.58)
	root.add_child(axe)

	_add_cyl(root, 0.055, 0.062, 0.46, _v3(0.96, 0.06, 0.34), _v3(0.15, 0.42, PI * 0.5), t_mat)
	_add_cyl(root, 0.052, 0.058, 0.44, _v3(0.42, 0.06, 0.42), _v3(-0.18, -0.52, PI * 0.5), t_mat)

	var bags := _inst_model(VDIR + "Bags.glb", 0.38)
	bags.position = _v3(0.75, -0.02, -0.48)
	root.add_child(bags)
	_add_prop_ao(root, _v3(0.75, 0.09, -0.48), Vector2(1.08, 1.08), 0.86)


static func _assemble_tier1_spring_well(root: Node3D) -> void:
	_add_prop_ao(root, _v3(0.0, 0.08, 0.0), Vector2(3.6, 3.6), 0.88)

	var t_mat := _arch_mat("pbr_aged_timber", Color(0.45, 0.34, 0.23), 0.56, 0.48, 0.56, 0.86)
	var r_mat := _arch_mat("pbr_wattle_weave", Color(0.66, 0.54, 0.36), 0.48, 0.40, 0.28, 0.88)
	var s_mat := _arch_mat("pbr_cliff_rock", Color(0.82, 0.80, 0.74), 0.52, 0.48, 0.55, 0.82, 0.26)

	var rim_stone_mesh := _make_ring_stone_mesh(Color(0.84, 0.80, 0.75), 0.22)
	for i in range(10):
		var ang := float(i) * TAU / 10.0
		var st := MeshInstance3D.new()
		st.mesh = rim_stone_mesh
		st.scale = _v3(0.19, 0.17, 0.19)
		st.position = _v3(cos(ang) * 0.68, 0.09, sin(ang) * 0.68)
		st.rotation.y = ang + 0.5
		st.material_override = s_mat
		root.add_child(st)

	var rot_z90 := _v3(0.0, 0.0, PI * 0.5)
	var rot_x90 := _v3(PI * 0.5, 0.0, 0.0)
	for tier_i in range(3):
		var ly := 0.16 + float(tier_i) * 0.12
		for d_s: float in [-1.0, 1.0]:
			_add_cyl(root, 0.070, 0.070, 1.44, _v3(0.0, ly, d_s * 0.52), rot_z90, t_mat)
			_add_cyl(root, 0.070, 0.070, 1.44, _v3(d_s * 0.52, ly + 0.06, 0.0), rot_x90, t_mat)

	if _water_shader_cache == null:
		_water_shader_cache = SevaraAssetLibrary3D.load_shader("sevara_water_3d.gdshader")
	var water_mat := ShaderMaterial.new()
	water_mat.shader = _water_shader_cache
	water_mat.set_shader_parameter("shallow_color", Color(0.12, 0.36, 0.34, 0.92))
	water_mat.set_shader_parameter("deep_color", Color(0.04, 0.14, 0.18, 0.98))
	water_mat.set_shader_parameter("foam_color", Color(0.76, 0.88, 0.86, 0.65))
	water_mat.set_shader_parameter("flow_speed", 0.22)
	water_mat.set_shader_parameter("wave_height", 0.012)
	_add_cyl(root, 0.48, 0.48, 0.06, _v3(0.0, 0.26, 0.0), V0, water_mat)

	for sx: float in [-0.52, 0.52]:
		_add_cyl(root, 0.056, 0.074, 1.56, _v3(sx, 0.76, 0.0), V0, t_mat)
		_add_torus(root, 0.052, 0.092, _v3(sx, 0.46, 0.0), V0, r_mat)
		_add_torus(root, 0.048, 0.086, _v3(sx, 1.44, 0.0), rot_z90, r_mat)
		for bz_s: float in [-1.0, 1.0]:
			var b_pos := _v3(sx, 0.56, bz_s * 0.24)
			_add_cyl(root, 0.038, 0.046, 0.54, b_pos, _v3(-bz_s * 0.62, 0, 0), t_mat)

	_add_cyl(root, 0.052, 0.052, 1.32, _v3(0.0, 1.44, 0.0), rot_z90, t_mat)
	_add_cyl(root, 0.082, 0.082, 0.36, _v3(0.0, 1.44, 0.0), rot_z90, r_mat)
	_add_cyl(root, 0.028, 0.028, 0.28, _v3(0.66, 1.34, 0.08), _v3(0.45, 0, 0), t_mat)
	_add_cyl(root, 0.024, 0.024, 0.74, _v3(0.0, 1.06, 0.0), V0, r_mat)
	_add_cyl(root, 0.14, 0.11, 0.24, _v3(0.0, 0.68, 0.0), V0, t_mat)
	_add_torus(root, 0.020, 0.135, _v3(0.0, 0.78, 0.0), V0, r_mat)


static func _assemble_tier1_tribal_hearth(root: Node3D) -> void:
	_add_prop_ao(root, _v3(0.0, 0.06, 0.0), Vector2(3.8, 3.8), 0.90)
	var ash_pit := _create_vfx_quad(0, Vector2(2.65, 2.65), Color(0.03, 0.02, 0.02, 0.94), 0.85)
	ash_pit.rotation.x = -PI * 0.5
	ash_pit.position = _v3(0.0, 0.07, 0.0)
	root.add_child(ash_pit)

	var ember_bed := _create_vfx_quad(1, Vector2(1.62, 1.62), Color(1.0, 0.44, 0.08, 0.98), 0.95)
	ember_bed.rotation.x = -PI * 0.5
	ember_bed.position = _v3(0.0, 0.09, 0.0)
	root.add_child(ember_bed)

	var s_mat := _arch_mat("pbr_cliff_rock", Color(0.42, 0.38, 0.34), 0.56, 0.48, 0.46, 0.90, 0.12)
	var hearth_stone_mesh := _make_ring_stone_mesh(Color(0.46, 0.42, 0.38), 0.08)
	for s_i in range(12):
		var s_ang := float(s_i) * TAU / 12.0
		var hs := MeshInstance3D.new()
		hs.mesh = hearth_stone_mesh
		hs.scale = _v3(0.22, 0.16, 0.22)
		hs.position = _v3(cos(s_ang) * 0.78, 0.08, sin(s_ang) * 0.78)
		hs.rotation.y = s_ang + 0.4
		hs.material_override = s_mat
		root.add_child(hs)

	root.add_child(_inst_model(VDIR + "Bonfire_Lit.glb", 0.78))
	var cauldron := _inst_model(VDIR + "Cauldron.glb", 0.50)
	cauldron.position = _v3(0.0, 0.34, 0.0)
	root.add_child(cauldron)

	var wood_mat := _arch_mat("pbr_aged_timber", Color(0.44, 0.33, 0.22), 0.55, 0.48, 0.55, 0.86)
	var r_mat := _arch_mat("pbr_wattle_weave", Color(0.64, 0.52, 0.34), 0.48, 0.40, 0.28, 0.88)
	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color(0.14, 0.14, 0.15)
	iron_mat.metallic = 0.78
	iron_mat.roughness = 0.42

	for i in range(3):
		var ang := float(i) * TAU / 3.0 + 0.45
		var t_pos := _v3(cos(ang) * 0.36, 0.82, sin(ang) * 0.36)
		var t_rot := _v3(-sin(ang) * 0.44, 0.0, cos(ang) * 0.44)
		_add_cyl(root, 0.036, 0.056, 1.96, t_pos, t_rot, wood_mat)

	for c_i in range(3):
		var l_pos := _v3(0.0, 1.54 + float(c_i) * 0.035, 0.0)
		var l_rot := _v3(float(c_i) * 0.22, float(c_i) * 0.8, 0.0)
		_add_torus(root, 0.038, 0.105 - float(c_i) * 0.008, l_pos, l_rot, r_mat)
	var rot_z90 := _v3(0.0, 0.0, PI * 0.5)
	_add_torus(root, 0.024, 0.062, _v3(0.0, 1.50, 0.0), rot_z90, iron_mat)
	_add_cyl(root, 0.018, 0.018, 0.16, _v3(0.0, 1.44, 0.0), V0, iron_mat)
	for l_i in range(9):
		var rot_l := _v3(0.0, float(l_i % 2) * PI * 0.5, PI * 0.5)
		_add_torus(root, 0.022, 0.046, _v3(0.0, 1.38 - float(l_i) * 0.088, 0.0), rot_l, iron_mat)
	_add_torus(root, 0.018, 0.22, _v3(0.0, 0.58, 0.0), rot_z90, iron_mat)

	for l_ang: float in [-2.20, 0.20, 2.15]:
		var seat_grp := Node3D.new()
		seat_grp.position = _v3(cos(l_ang) * 1.56, 0.0, sin(l_ang) * 1.56)
		seat_grp.rotation.y = -l_ang + PI * 0.5
		root.add_child(seat_grp)
		_add_prop_ao(seat_grp, _v3(0.0, 0.07, 0.0), Vector2(1.48, 0.68), 0.86)
		_add_cyl(seat_grp, 0.135, 0.145, 1.18, _v3(0.0, 0.22, 0.0), rot_z90, wood_mat)
		for ch_x: float in [-0.38, 0.38]:
			_add_cyl(
				seat_grp, 0.09, 0.10, 0.28, _v3(ch_x, 0.08, 0.0), _v3(PI * 0.5, 0, 0), wood_mat
			)

	var stump_seat := _inst_model(NDIR + "TreeStump_Moss.glb", 0.42)
	stump_seat.position = _v3(-1.12, -0.03, 1.18)
	root.add_child(stump_seat)
	_add_prop_ao(root, _v3(-1.12, 0.07, 1.18), Vector2(0.95, 0.95), 0.86)

	root.add_child(_make_smoke_plume(_v3(0.0, 0.92, 0.0), 22, 0.68))
	_add_light(root, _v3(0.0, 1.05, 0.0), Color(1.0, 0.60, 0.20), 1.75, 8.2)


static func _assemble_tier1_fishing_sluice(root: Node3D) -> void:
	var t_mat := _arch_mat("pbr_aged_timber", Color(0.44, 0.34, 0.23), 0.56, 0.50, 0.68, 0.86)
	var r_mat := _arch_mat("pbr_wattle_weave", Color(0.64, 0.52, 0.34), 0.48, 0.42, 0.36, 0.88)

	for sx: float in [-0.68, 0.68]:
		for sz: float in [-0.85, 0.0, 0.85]:
			_add_cyl(root, 0.052, 0.072, 1.35, _v3(sx, 0.12, sz), V0, t_mat)

	var rot_z90 := _v3(0.0, 0.0, PI * 0.5)
	for i in range(11):
		var pz := -0.92 + float(i) * 0.185
		var p_pos := _v3(sin(float(i) * 1.9) * 0.04, 0.48, pz)
		_add_cyl(root, 0.068, 0.074, 1.56, p_pos, rot_z90, t_mat)

	var gate_grp := Node3D.new()
	gate_grp.position = _v3(1.18, 0.08, -0.35)
	gate_grp.rotation = _v3(0.06, 0.18, -0.09)
	root.add_child(gate_grp)

	for gz: float in [-0.72, 0.72]:
		_add_cyl(gate_grp, 0.078, 0.095, 1.68, _v3(0.0, 0.36, gz), V0, t_mat)
	_add_cyl(gate_grp, 0.072, 0.072, 1.72, _v3(0.0, 1.12, 0.0), _v3(PI * 0.5, 0, 0), t_mat)

	for b_i in range(4):
		var b_pos := _v3(0.0, 0.12 + float(b_i) * 0.20, 0.0)
		var b_rot := _v3(sin(float(b_i) * 2.1) * 0.05, 0.0, 0.0)
		_add_box(gate_grp, _v3(0.08, 0.18, 1.36), b_pos, b_rot, t_mat)

	var jammed_log := _inst_model(NDIR + "WoodLog_Moss.glb", 0.48)
	jammed_log.position = _v3(0.85, -0.05, 0.35)
	jammed_log.rotation.y = 0.65
	root.add_child(jammed_log)

	var t_rot := _v3(0.25, 0.4, PI * 0.44)
	_add_cyl(root, 0.12, 0.28, 0.78, _v3(-0.35, 0.64, -0.45), t_rot, r_mat)


static func _populate_fences_and_stumps(settlement_root: Node3D) -> void:
	var t_mat := _arch_mat("pbr_aged_timber", Color(0.45, 0.34, 0.23), 0.55, 0.48, 0.52, 0.86)
	var r_mat := _arch_mat("pbr_wattle_weave", Color(0.62, 0.50, 0.33), 0.48, 0.40, 0.28, 0.88)

	var fence_runs: Array[Array] = [
		[Vector2(-16.8, -13.4), Vector2(-14.4, -14.2), Vector2(-12.2, -14.0)],
		[Vector2(-22.2, -9.2), Vector2(-22.0, -6.8), Vector2(-21.0, -5.0)],
		[Vector2(-10.8, -16.4), Vector2(-8.2, -17.0), Vector2(-5.4, -16.2)],
	]
	for run_pts: Array in fence_runs:
		_add_terrain_fitted_wattle_run(settlement_root, run_pts, 0.86, t_mat, r_mat)

	var clearing_stumps: Array[Vector2] = [
		Vector2(-20.4, -9.8), Vector2(-15.4, -13.8), Vector2(-4.4, -14.8)
	]
	for i in range(clearing_stumps.size()):
		var sp: Vector2 = clearing_stumps[i]
		var wy := SevaraTerrainGen3D.get_height_at(sp.x, sp.y)
		var stump := SevaraAssetLibrary3D.instantiate_model(NDIR + "TreeStump_Moss.glb", 0.58)
		stump.position = _v3(sp.x, wy - 0.04, sp.y)
		stump.rotation.y = float(i) * 1.4
		settlement_root.add_child(stump)
		_add_prop_ao(settlement_root, _v3(sp.x, wy + 0.05, sp.y), Vector2(1.15, 1.15), 0.82)


static func _add_terrain_fitted_wattle_run(
	parent: Node3D, control_pts: Array, height_m: float, t_mat: Material, w_mat: Material
) -> void:
	var grp := Node3D.new()
	grp.name = "TerrainFittedWattleFence3D"
	parent.add_child(grp)

	var stake_pts: Array[Vector3] = []
	for seg_i in range(control_pts.size() - 1):
		var p0: Vector2 = control_pts[seg_i]
		var p1: Vector2 = control_pts[seg_i + 1]
		var steps := maxi(int(round(p0.distance_to(p1) / 0.46)), 3)
		for s in range(0 if seg_i == 0 else 1, steps + 1):
			var xz := p0.lerp(p1, float(s) / float(steps))
			stake_pts.append(_v3(xz.x, SevaraTerrainGen3D.get_height_at(xz.x, xz.y), xz.y))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(stake_pts.size()):
		var sp := stake_pts[i]
		var s_pos := _v3(sp.x, sp.y + height_m * 0.5 - 0.04, sp.z)
		_add_cyl(grp, 0.038, 0.054, height_m + 0.24, s_pos, _v3(0, float(i) * 0.7, 0.02), t_mat)
		_add_prop_ao(grp, _v3(sp.x, sp.y + 0.05, sp.z), Vector2(0.62, 0.52), 0.72)
		if i == 0:
			continue
		var p_a := stake_pts[i - 1]
		var n2 := Vector2(-(sp.z - p_a.z), sp.x - p_a.x).normalized() * 0.046
		for side: float in [-1.0, 1.0]:
			var off := _v3(n2.x * side, 0.0, n2.y * side)
			var v00 := p_a + off + _v3(0.0, 0.03, 0.0)
			var v10 := sp + off + _v3(0.0, 0.03, 0.0)
			var v01 := p_a + off + _v3(0.0, height_m * 0.86, 0.0)
			var v11 := sp + off + _v3(0.0, height_m * 0.86, 0.0)
			var nrm := _v3(n2.x * side, 0.06, n2.y * side).normalized()
			var verts: Array = (
				[v00, v10, v11, v00, v11, v01] if side > 0.0 else [v00, v11, v10, v00, v01, v11]
			)
			for v_pt: Vector3 in verts:
				st.set_normal(nrm)
				st.set_uv(Vector2(v_pt.x + v_pt.z, v_pt.y - sp.y))
				st.add_vertex(v_pt)
	_add_mesh(grp, st.commit(), V0, V0, w_mat)


static func _populate_east_bank_wild_landmarks(settlement_root: Node3D) -> void:
	var east_grp := Node3D.new()
	east_grp.name = "EastBankWildLandmarks3D"
	settlement_root.add_child(east_grp)

	var s_mat := _arch_mat("pbr_cliff_rock", Color(0.68, 0.72, 0.64), 0.54, 0.48, 0.46, 0.88, 0.58)
	var ring_mesh := _make_ring_stone_mesh(Color(0.72, 0.74, 0.68), 0.56)

	var center := Vector2(22.8, -4.6)
	for i in range(9):
		if i == 3 or i == 6:
			continue
		var ang := float(i) * TAU / 9.0
		var sx := center.x + cos(ang) * 2.05
		var sz := center.y + sin(ang) * 1.95
		var sy := SevaraTerrainGen3D.get_height_at(sx, sz)
		var st := MeshInstance3D.new()
		st.mesh = ring_mesh
		st.scale = _v3(0.38, 0.28 + float(i % 3) * 0.08, 0.36)
		st.position = _v3(sx, sy + 0.04, sz)
		st.rotation = _v3(sin(ang) * 0.14, ang + 0.4, cos(ang) * 0.12)
		st.material_override = s_mat
		east_grp.add_child(st)
		_add_prop_ao(east_grp, _v3(sx, sy + 0.05, sz), Vector2(1.05, 1.05), 0.78)

	var wy_c := SevaraTerrainGen3D.get_height_at(center.x + 0.5, center.y - 0.6)
	var wp_pos := _v3(center.x + 0.5, wy_c + 0.48, center.y - 0.6)
	_add_box(east_grp, _v3(0.42, 1.18, 0.34), wp_pos, _v3(0.16, 0.52, -0.14), s_mat)

	var log_pos := Vector2(22.2, -4.2)
	var log_y := SevaraTerrainGen3D.get_height_at(log_pos.x, log_pos.y)
	var fallen_log := _inst_model(NDIR + "WoodLog_Moss.glb", 0.76)
	fallen_log.position = _v3(log_pos.x, log_y - 0.02, log_pos.y)
	fallen_log.rotation = _v3(0.05, -0.68, 0.08)
	east_grp.add_child(fallen_log)
	_add_prop_ao(east_grp, _v3(log_pos.x, log_y + 0.05, log_pos.y), Vector2(2.2, 0.95), 0.82)

	var berry_red_mat := StandardMaterial3D.new()
	berry_red_mat.albedo_color = Color(0.76, 0.12, 0.14)
	berry_red_mat.roughness = 0.36
	var berry_gold_mat := StandardMaterial3D.new()
	berry_gold_mat.albedo_color = Color(0.88, 0.56, 0.12)
	berry_gold_mat.roughness = 0.38
	var berry_sphere := SphereMesh.new()
	berry_sphere.radius = 0.055
	berry_sphere.height = 0.11

	var berry_spots: Array[Vector2] = [
		Vector2(19.6, -6.4), Vector2(24.4, -3.2), Vector2(21.0, -7.8)
	]
	for b_idx in range(berry_spots.size()):
		var bp: Vector2 = berry_spots[b_idx]
		var by := SevaraTerrainGen3D.get_height_at(bp.x, bp.y)
		var bush := SevaraAssetLibrary3D.instantiate_model(NDIR + "Bush_Common_Flowers.glb", 0.62)
		bush.position = _v3(bp.x, by - 0.03, bp.y)
		bush.rotation.y = float(b_idx) * 1.8
		east_grp.add_child(bush)
		_add_prop_ao(east_grp, _v3(bp.x, by + 0.05, bp.y), Vector2(1.25, 1.25), 0.78)
		for cl_i in range(7):
			var c_ang := float(cl_i) * TAU / 7.0 + float(b_idx)
			var b_mi := MeshInstance3D.new()
			b_mi.mesh = berry_sphere
			b_mi.position = _v3(
				bp.x + cos(c_ang) * 0.34,
				by + 0.28 + float(cl_i % 3) * 0.11,
				bp.y + sin(c_ang) * 0.34
			)
			b_mi.material_override = berry_red_mat if (cl_i + b_idx) % 2 == 0 else berry_gold_mat
			east_grp.add_child(b_mi)


static func _create_wattle_hurdle_3d(
	length_m: float, height_m: float, t_mat: Material, w_mat: Material
) -> Node3D:
	var grp := Node3D.new()
	grp.name = "WattleHurdle3D"
	var stake_count := maxi(int(round(length_m / 0.52)) + 1, 4)
	for i in range(stake_count):
		var sx := -length_m * 0.5 + float(i) * (length_m / float(stake_count - 1))
		var s_pos := _v3(sx, height_m * 0.5 - 0.04, 0.0)
		_add_cyl(
			grp, 0.036, 0.052, height_m + 0.22, s_pos, _v3(0, 0, sin(float(i) * 2.1) * 0.04), t_mat
		)
	_add_box(
		grp, _v3(length_m - 0.08, height_m * 0.84, 0.09), _v3(0.0, height_m * 0.45, 0.0), V0, w_mat
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
	var upgraded := _inst_model(VDIR + model_file, 0.62)
	upgraded.position.y = -0.05
	root.add_child(upgraded)
	return root


static func _make_ring_stone_mesh(tint: Color, moss: float) -> Mesh:
	var cfg := {
		"moss_amount": moss, "snow_amount": 0.0, "wetness": 0.3, "triplanar": 1.0, "tint": tint
	}
	return SevaraAssetLibrary3D.build_bevel_smoothed_rock_mesh("Rock_Medium_2", {"rock": cfg})


static func _add_prop_ao(parent: Node3D, pos: Vector3, sz: Vector2, alpha: float = 0.82) -> void:
	var ao := _create_vfx_quad(0, sz, Color(0.02, 0.02, 0.02, alpha), 0.85)
	ao.rotation.x = -PI * 0.5
	ao.position = pos
	parent.add_child(ao)


static func _add_mesh(parent: Node3D, m: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)


static func _add_cyl(
	parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, rot: Vector3, mat: Material
) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bot
	cyl.height = h
	cyl.radial_segments = 10
	_add_mesh(parent, cyl, pos, rot, mat)


static func _add_box(
	parent: Node3D, sz: Vector3, pos: Vector3, rot: Vector3, mat: Material
) -> void:
	var bm := BoxMesh.new()
	bm.size = sz
	_add_mesh(parent, bm, pos, rot, mat)


static func _add_torus(
	parent: Node3D, r_in: float, r_out: float, pos: Vector3, rot: Vector3, mat: Material
) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 10
	tm.ring_segments = 8
	_add_mesh(parent, tm, pos, rot, mat)


static func _create_vfx_quad(
	mode: int, quad_size: Vector2, tint: Color, _softness: float = 0.85
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
	smat.set_shader_parameter("vfx_mode", mode)
	smat.set_shader_parameter("tint_color", tint)
	smat.set_shader_parameter("intensity", 1.0)
	mi.material_override = smat
	return mi


static func _make_smoke_plume(
	origin: Vector3, amount_count: int = 20, scale_fac: float = 0.65
) -> CPUParticles3D:
	if _decal_shader_cache == null:
		_decal_shader_cache = SevaraAssetLibrary3D.load_shader("sevara_vfx_decal_3d.gdshader")
	var smat := ShaderMaterial.new()
	smat.shader = _decal_shader_cache
	smat.set_shader_parameter("vfx_mode", 2)
	smat.set_shader_parameter("tint_color", Color(0.58, 0.60, 0.64, 0.58))
	smat.set_shader_parameter("intensity", 1.15)

	var puff_mesh := SphereMesh.new()
	puff_mesh.radial_segments = 10
	puff_mesh.rings = 6

	var smoke := CPUParticles3D.new()
	smoke.position = origin
	smoke.local_coords = true
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.amount = amount_count
	smoke.lifetime = 3.2
	smoke.preprocess = 2.2
	smoke.mesh = puff_mesh
	smoke.material_override = smat
	smoke.direction = _v3(0.20, 1.0, 0.12).normalized()
	smoke.spread = 14.0
	smoke.gravity = _v3(0.12, 0.38, 0.06)
	smoke.initial_velocity_min = 0.30 * scale_fac
	smoke.initial_velocity_max = 0.56 * scale_fac
	smoke.scale_amount_min = 0.34 * scale_fac
	smoke.scale_amount_max = 0.78 * scale_fac
	return smoke


static func _get_gentle_ground_tilt(
	wx: float, wz: float, yaw: float, max_tilt_factor: float = 0.18
) -> Vector3:
	var nrm := SevaraTerrainGen3D.get_ground_normal(wx, wz)
	var pitch_x := clampf(nrm.z * max_tilt_factor, -0.05, 0.05)
	var roll_z := clampf(-nrm.x * max_tilt_factor, -0.05, 0.05)
	return Vector3(pitch_x, yaw, roll_z)


static func _inst_model(full_path: String, sc: float) -> Node3D:
	return SevaraAssetLibrary3D.instantiate_model(full_path, sc, {}, true)


static func _arch_mat(
	surf: String,
	tint: Color,
	g: float,
	w: float,
	ao: float,
	r: float,
	_m: float = 0.0,
	ms: float = 0.08
) -> ShaderMaterial:
	return SevaraAssetLibrary3D._make_arch_shader_material(
		surf, tint, Color.BLACK, g, w, ao, r, 0.0, ms
	)


static func _v3(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


static func _add_light(p: Node3D, pos: Vector3, col: Color, e: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = e
	l.omni_range = rng
	p.add_child(l)

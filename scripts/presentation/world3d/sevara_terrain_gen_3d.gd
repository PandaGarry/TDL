class_name SevaraTerrainGen3D
extends RefCounted
## Generates the expanded 3D terrain mesh (160 x 120 m), river/wetland water mesh,
## and distant mountain range rings for the Sevara Valley.

const TILE_SIZE_M := 1.65
const VALLEY_WIDTH_M := 160.0
const VALLEY_DEPTH_M := 120.0
const WATER_SURFACE_Y := 0.42
const WORLD_SCALE := TILE_SIZE_M / 32.0
## Look-Dev mode: CBT proving ground with stepped terraces, two-track roads & Nivarel river bridge.
const STEP1_CLEAN_MEADOW := true
const BRIDGE_X_MIN := 5.6
const BRIDGE_X_MAX := 18.4
const BRIDGE_HALF_WIDTH := 1.68


static func tile_to_world_3d(
	tile: Vector2i, width_tiles: int = 32, height_tiles: int = 24
) -> Vector3:
	var half_w := float(width_tiles) * TILE_SIZE_M * 0.5
	var half_h := float(height_tiles) * TILE_SIZE_M * 0.5
	var wx := (float(tile.x) + 0.5) * TILE_SIZE_M - half_w
	var wz := (float(tile.y) + 0.5) * TILE_SIZE_M - half_h
	var wy := get_height_at(wx, wz)
	return Vector3(wx, wy, wz)


static func pixel_to_world_3d(
	px_pos: Vector2, tile_size_px: float = 32.0, width_tiles: int = 32, height_tiles: int = 24
) -> Vector3:
	var safe_tile_px := maxf(tile_size_px, 1.0)
	var half_w := float(width_tiles) * TILE_SIZE_M * 0.5
	var half_h := float(height_tiles) * TILE_SIZE_M * 0.5
	var wx := (px_pos.x / safe_tile_px) * TILE_SIZE_M - half_w
	var wz := (px_pos.y / safe_tile_px) * TILE_SIZE_M - half_h
	var wy := get_height_at(wx, wz)
	return Vector3(wx, wy, wz)


static func river_center_x(wz: float) -> float:
	# Full-bodied Nivarel mountain river flowing from the northern mountain pass (z = -60)
	# through the valley floor, spanned by the bridge at z ~ +2.35, to the southern basin (z = +60).
	var base_cx := 7.8 + wz * 0.22 + sin(wz * 0.088 + 0.35) * 3.6 + cos(wz * 0.044 - 0.2) * 1.8
	var north_valley_bend := smoothstep(-12.0, -56.0, wz) * 5.2
	return base_cx + north_valley_bend


static func river_half_width(wz: float) -> float:
	# Wide, deep mountain river (total width ~9.6m to 12.6m across the valley floor)
	var base_w := 4.65 + smoothstep(-34.0, 28.0, wz) * 1.10
	var pool_w := exp(-pow((wz - 12.0) / 8.0, 2.0)) * 1.15
	var bank_wave := sin(wz * 0.30 + 0.5) * 0.28 + cos(wz * 0.62 - 0.8) * 0.16
	return base_w + pool_w + bank_wave


static func wetland_pool_factor(wx: float, wz: float) -> float:
	# Secondary Mulane oxbow pool & marsh channels in the SW-South basin
	var dx := wx - (-7.5 + sin(wz * 0.14) * 2.2)
	var dz := wz - 13.5
	var oxbow := exp(-(dx * dx) / 28.0 - (dz * dz) / 46.0)
	var south_pond := exp(-pow(wx - 4.5, 2.0) / 38.0 - pow(wz - 22.0, 2.0) / 32.0)
	return clampf(maxf(oxbow, south_pond * 0.85), 0.0, 1.0)


static func is_water_at(wx: float, wz: float) -> bool:
	var r_cx := river_center_x(wz)
	var r_hw := river_half_width(wz)
	if absf(wx - r_cx) > r_hw * 1.25:
		return false
	return get_height_at(wx, wz) < WATER_SURFACE_Y - 0.03


static func is_on_bridge(wx: float, wz: float) -> bool:
	if wx < BRIDGE_X_MIN or wx > BRIDGE_X_MAX:
		return false
	return absf(_main_road_signed_dist(wx, wz)) <= BRIDGE_HALF_WIDTH


static func get_bridge_deck_y_at_x(wx: float) -> float:
	var t := clampf((wx - BRIDGE_X_MIN) / (BRIDGE_X_MAX - BRIDGE_X_MIN), 0.0, 1.0)
	var west_ground := get_height_at(BRIDGE_X_MIN, _main_road_z(BRIDGE_X_MIN)) + 0.02
	var east_ground := get_height_at(BRIDGE_X_MAX, _main_road_z(BRIDGE_X_MAX)) + 0.02
	var base_line := lerpf(west_ground, east_ground, t)
	# Smoothly rises from flush road grade at both ramps to a level timber deck
	var ramp_env := smoothstep(0.0, 0.14, t) * (1.0 - smoothstep(0.86, 1.0, t))
	var camber := sin(t * PI) * 0.14
	return lerpf(base_line, 1.06 + camber, ramp_env)


static func get_walkable_height_at(wx: float, wz: float) -> float:
	if is_on_bridge(wx, wz):
		return get_bridge_deck_y_at_x(wx)
	return maxf(get_height_at(wx, wz), WATER_SURFACE_Y - 0.16)


static func get_ground_normal(wx: float, wz: float) -> Vector3:
	var eps := 0.45
	var hx := get_height_at(wx + eps, wz) - get_height_at(wx - eps, wz)
	var hz := get_height_at(wx, wz + eps) - get_height_at(wx, wz - eps)
	return Vector3(-hx, 2.0 * eps, -hz).normalized()


static func _main_road_z(wx: float) -> float:
	return -2.2 + sin(wx * 0.085 + 0.35) * 3.8 + cos(wx * 0.045 - 0.4) * 1.9 - wx * 0.06


static func _main_road_signed_dist(wx: float, wz: float) -> float:
	var rz := _main_road_z(wx)
	var dz_dx := cos(wx * 0.085 + 0.35) * 0.323 - sin(wx * 0.045 - 0.4) * 0.0855 - 0.06
	return (wz - rz) / sqrt(1.0 + dz_dx * dz_dx)


static func _north_branch_signed_dist(wx: float, wz: float) -> float:
	var bx := -3.5 + (wz + 3.6) * 0.55 + sin((wz + 3.6) * 0.16) * 2.2
	var dx_dz := 0.55 + cos((wz + 3.6) * 0.16) * 0.352
	return (wx - bx) / sqrt(1.0 + dx_dz * dx_dz)


static func _south_branch_signed_dist(wx: float, wz: float) -> float:
	var sx := -3.8 - (wz + 2.2) * 0.36 + sin((wz + 2.2) * 0.15) * 1.2
	var dx_dz := -0.36 + cos((wz + 2.2) * 0.15) * 0.18
	return (wx - sx) / sqrt(1.0 + dx_dz * dx_dz)


static func get_road_core_at(wx: float, wz: float) -> float:
	var rz := _main_road_z(wx)
	var d_main := absf(_main_road_signed_dist(wx, wz))
	var fade_main := smoothstep(-64.0, -52.0, wx) * (1.0 - smoothstep(52.0, 64.0, wx))
	# Stop the earthen roadbed cleanly at the riverbanks so no dirt path runs underwater
	var r_cx := river_center_x(wz)
	var r_hw := river_half_width(wz)
	var bridge_channel_cut := smoothstep(r_hw * 0.74, r_hw * 0.92, absf(wx - r_cx))
	var m_main := (1.0 - smoothstep(0.68, 1.05, d_main / 1.32)) * fade_main * bridge_channel_cut

	var d_north := absf(_north_branch_signed_dist(wx, wz))
	var fade_north := smoothstep(rz + 0.8, rz - 0.9, wz) * (1.0 - smoothstep(-42.0, -52.0, wz))
	var m_north := (1.0 - smoothstep(0.66, 1.04, d_north / 0.96)) * fade_north

	var d_south := absf(_south_branch_signed_dist(wx, wz))
	var fade_south := smoothstep(rz - 0.8, rz + 0.9, wz) * (1.0 - smoothstep(20.0, 28.0, wz))
	var m_south := (1.0 - smoothstep(0.66, 1.04, d_south / 0.90)) * fade_south
	return clampf(maxf(m_main, maxf(m_north, m_south)), 0.0, 1.0)


static func get_path_weight_at(wx: float, wz: float) -> float:
	if STEP1_CLEAN_MEADOW:
		return get_road_core_at(wx, wz)

	# Main stone-paved settlement courtyard & trails connecting the hearth, well, bridge, and meadow
	var courtyard := exp(-pow(wx - (-14.5), 2.0) / 54.0 - pow(wz - (-7.5), 2.0) / 38.0)
	# Trail from settlement (-15, -7.5) across the bridge (0, -4.5) into Heravo meadow (+16, -2)
	var trail_z := -6.2 + (wx + 15.0) * 0.14 + sin(wx * 0.16) * 1.1
	var main_trail := (
		exp(-pow(wz - trail_z, 2.0) / 2.2)
		* smoothstep(-26.0, -20.0, wx)
		* (1.0 - smoothstep(22.0, 30.0, wx))
	)
	# North trail up toward Toramek slope & watermill
	var north_x := -11.5 + (wz + 7.5) * 0.22
	var north_trail := (
		exp(-pow(wx - north_x, 2.0) / 1.8)
		* smoothstep(-24.0, -18.0, wz)
		* (1.0 - smoothstep(-3.0, 2.0, wz))
	)
	return clampf(maxf(courtyard * 0.92, maxf(main_trail, north_trail * 0.85)), 0.0, 1.0)


static func get_height_at(wx: float, wz: float) -> float:
	if STEP1_CLEAN_MEADOW:
		# Carve a wide natural river-valley pass through the northern hills & outer rim
		# so the Nivarel river visibly enters from the distant mountain gap (never from underground)
		var r_cx := river_center_x(wz)
		var r_hw := river_half_width(wz)
		var dist_river := absf(wx - r_cx)
		var valley_pass_clear := 1.0 - exp(-pow(dist_river / (r_hw * 3.8), 2.0))

		var hill_a := sin(wx * 0.075 + 0.3) * cos(wz * 0.085 - 0.4) * 0.88
		var hill_b := sin(wx * 0.15 - wz * 0.13 + 1.1) * 0.36
		var nw_plateau := smoothstep(4.0, -38.0, wx * 0.38 + wz * 0.85) * 4.2 * valley_pass_clear
		var ne_knoll := (
			exp(-pow((wx - 24.0) / 18.0, 2.0) - pow((wz - (-22.0)) / 15.0, 2.0))
			* 2.65
			* valley_pass_clear
		)

		# Crisp stepped natural terraces on the hillside slopes (rock ledges & grassy shelves)
		var raw_slope_h := nw_plateau + ne_knoll + maxf(hill_a + hill_b, 0.0) * valley_pass_clear
		var terrace_phase := raw_slope_h * 1.35 + sin(wx * 0.12 + wz * 0.09) * 0.22
		var terrace_floor := floorf(terrace_phase)
		var terrace_fract := terrace_phase - terrace_floor
		var terrace_shelf: float = (terrace_floor + smoothstep(0.08, 0.46, terrace_fract)) / 1.35
		var road_c := get_road_core_at(wx, wz)
		var terrace_blend := smoothstep(0.55, 2.1, raw_slope_h) * (1.0 - road_c * 0.90)
		var sculpted_hills := lerpf(
			(hill_a + hill_b) * valley_pass_clear + nw_plateau + ne_knoll,
			terrace_shelf + hill_b * 0.28,
			terrace_blend * 0.76
		)

		var rim_x := smoothstep(46.0, 76.0, absf(wx))
		var rim_z := smoothstep(36.0, 56.0, absf(wz))
		var rim_h := (
			clampf(rim_x + rim_z - rim_x * rim_z * 0.4, 0.0, 1.0)
			* (2.8 + 0.9 * sin(wx * 0.08 + 0.4))
			* valley_pass_clear
		)

		# Twin wheel-rut carving + natural wagon-wheel chatter undulations along the road
		var d_main := absf(_main_road_signed_dist(wx, wz))
		var rut_carve := (
			(exp(-pow((d_main - 0.52) / 0.32, 2.0)) * 0.068 + exp(-pow(d_main / 1.35, 2.0)) * 0.045)
			* smoothstep(-62.0, -50.0, wx)
			* (1.0 - smoothstep(50.0, 62.0, wx))
			* smoothstep(r_hw * 0.88, r_hw * 1.05, dist_river)
		)
		var branch_carve := road_c * 0.055
		var wagon_bumps := (
			(sin(wx * 2.6 + wz * 1.8) * 0.018 + cos(wx * 4.9 - wz * 3.4) * 0.012) * road_c
		)
		var micro := sin(wx * 0.42 + wz * 0.37) * 0.032 + cos(wx * 0.27 - wz * 0.49) * 0.026
		var meadow_h := (
			1.02
			+ maxf(sculpted_hills, -0.24)
			+ rim_h
			+ micro
			+ wagon_bumps
			- maxf(rut_carve, branch_carve)
		)

		# Step 2 Continuous, full-length Nivarel mountain river channel (-60m to +60m)
		var bridge_approach := road_c * exp(-pow((wz - 2.35) / 3.8, 2.0))
		var base_bank_y := WATER_SURFACE_Y + 0.38 + sin(wz * 0.18 + wx * 0.14) * 0.028
		var bank_y := lerpf(
			base_bank_y, WATER_SURFACE_Y + 0.44, clampf(bridge_approach * 0.90, 0.0, 0.90)
		)
		var trough_w := r_hw * lerpf(3.2, 1.95, smoothstep(-34.0, -6.0, wz))
		var trough_blend := exp(-pow(dist_river / trough_w, 2.0))
		var h_bank := lerpf(meadow_h, bank_y, trough_blend)

		var norm_r := dist_river / maxf(r_hw, 0.5)
		var shallow_shelf := clampf(1.0 - pow(norm_r, 1.55), 0.0, 1.0)
		var deep_thalweg := clampf(1.0 - pow(norm_r / 0.82, 2.2), 0.0, 1.0)
		var pool_deepen := 1.0 + exp(-pow((wz - 12.0) / 8.5, 2.0)) * 0.28
		var carve_depth := (shallow_shelf * 0.68 + deep_thalweg * 1.58) * pool_deepen
		return h_bank - carve_depth

	# 1. Toramek NW mountain slope & rocky ridges
	var nw_slope := smoothstep(4.0, -34.0, wx * 0.68 + wz * 0.74)
	var nw_cliff := smoothstep(-14.0, -52.0, wx * 0.62 + wz * 0.78)
	var toramek_h := (
		nw_slope * 2.65
		+ nw_cliff * 6.4
		+ sin(wx * 0.18 + wz * 0.14) * 0.35 * nw_slope
		+ cos(wx * 0.33 - wz * 0.27) * 0.22 * nw_cliff
	)

	# 2. Outer valley rim hills (enclosing the 160x120m valley floor naturally)
	var rim_x := smoothstep(32.0, 76.0, absf(wx))
	var rim_z := smoothstep(24.0, 56.0, absf(wz))
	var rim_factor := clampf(rim_x + rim_z - rim_x * rim_z * 0.4, 0.0, 1.0)
	# Keep the SE river outlet lower so the river flows out naturally
	var outlet_carve := exp(-pow(wx - 16.0, 2.0) / 95.0) * smoothstep(10.0, 45.0, wz)
	var rim_h := (
		rim_factor
		* (1.0 - outlet_carve * 0.82)
		* (3.8 + 1.4 * sin(wx * 0.09 + 0.5) + 1.1 * cos(wz * 0.11 - 0.3))
	)

	# 3. Settlement dry terrace on the western/central bank (around x=-22..-5, z=-16..+4)
	var settle_mask := (
		smoothstep(-30.0, -21.0, wx)
		* (1.0 - smoothstep(-4.5, 1.5, wx))
		* smoothstep(-20.0, -13.0, wz)
		* (1.0 - smoothstep(4.0, 11.0, wz))
	)
	var terrace_h := settle_mask * 0.78

	# 4. Heravo sun-drenched rolling meadows on the eastern bank (x > 5)
	var meadow_mask := smoothstep(3.5, 12.0, wx) * (1.0 - smoothstep(44.0, 66.0, wx))
	var meadow_undulation := (
		(
			sin(wx * 0.11 + 0.4) * cos(wz * 0.12 - 0.2) * 0.48
			+ sin(wx * 0.24 - wz * 0.19) * 0.18
			+ 0.52
		)
		* meadow_mask
	)

	# 5. Nivarel river channel & Mulane wetland basin carving
	var r_cx := river_center_x(wz)
	var r_hw := river_half_width(wz)
	var dist_river := absf(wx - r_cx)
	var channel_carve := exp(-pow(dist_river / maxf(r_hw, 1.2), 2.2)) * 1.38
	var bank_shelf := exp(-pow(dist_river / maxf(r_hw * 1.95, 2.2), 2.0)) * 0.28
	var wetland_carve := wetland_pool_factor(wx, wz) * 0.86

	# 6. Micro-relief undulation
	var micro := sin(wx * 0.42 + wz * 0.37) * 0.045 + cos(wx * 0.27 - wz * 0.51) * 0.035

	var base_y := 0.22 + toramek_h + rim_h + terrace_h + meadow_undulation + micro
	var carved_y := base_y - channel_carve - bank_shelf - wetland_carve
	return carved_y


static func build_terrain_mesh(
	_width_tiles: int = 32, _height_tiles: int = 24, subdiv_x: int = 160, subdiv_z: int = 120
) -> ArrayMesh:
	var half_w := VALLEY_WIDTH_M * 0.5
	var half_d := VALLEY_DEPTH_M * 0.5
	var step_x := VALLEY_WIDTH_M / float(subdiv_x)
	var step_z := VALLEY_DEPTH_M / float(subdiv_z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for gz in range(subdiv_z):
		for gx in range(subdiv_x):
			var x0 := -half_w + float(gx) * step_x
			var z0 := -half_d + float(gz) * step_z
			var x1 := x0 + step_x
			var z1 := z0 + step_z

			var p00 := Vector3(x0, get_height_at(x0, z0), z0)
			var p10 := Vector3(x1, get_height_at(x1, z0), z0)
			var p01 := Vector3(x0, get_height_at(x0, z1), z1)
			var p11 := Vector3(x1, get_height_at(x1, z1), z1)

			_add_terrain_vertex(st, p00, half_w, half_d)
			_add_terrain_vertex(st, p10, half_w, half_d)
			_add_terrain_vertex(st, p01, half_w, half_d)

			_add_terrain_vertex(st, p10, half_w, half_d)
			_add_terrain_vertex(st, p11, half_w, half_d)
			_add_terrain_vertex(st, p01, half_w, half_d)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func build_water_mesh(
	_width_tiles: int = 32, _height_tiles: int = 24, _subdiv_x: int = 128, _subdiv_z: int = 96
) -> ArrayMesh:
	var half_w := VALLEY_WIDTH_M * 0.5
	var half_d := VALLEY_DEPTH_M * 0.5
	# High-precision stream-following ribbon mesh (perfectly smooth banks, 3x fewer triangles)
	var z_start := -60.0
	var z_end := 58.0
	var steps_z := 224
	var steps_u := 44
	var dz := (z_end - z_start) / float(steps_z)
	var u_span := 1.06

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for gz in range(steps_z):
		var z0 := z_start + float(gz) * dz
		var z1 := z0 + dz
		var cx0 := river_center_x(z0)
		var cx1 := river_center_x(z1)
		var hw0 := river_half_width(z0) * u_span
		var hw1 := river_half_width(z1) * u_span

		for gu in range(steps_u):
			var u0 := -1.0 + 2.0 * float(gu) / float(steps_u)
			var u1 := -1.0 + 2.0 * float(gu + 1) / float(steps_u)

			var p00 := Vector3(cx0 + u0 * hw0, WATER_SURFACE_Y, z0)
			var p10 := Vector3(cx0 + u1 * hw0, WATER_SURFACE_Y, z0)
			var p01 := Vector3(cx1 + u0 * hw1, WATER_SURFACE_Y, z1)
			var p11 := Vector3(cx1 + u1 * hw1, WATER_SURFACE_Y, z1)

			_add_water_vertex(st, p00, half_w, half_d)
			_add_water_vertex(st, p10, half_w, half_d)
			_add_water_vertex(st, p01, half_w, half_d)

			_add_water_vertex(st, p10, half_w, half_d)
			_add_water_vertex(st, p11, half_w, half_d)
			_add_water_vertex(st, p01, half_w, half_d)

	st.generate_normals()
	return st.commit()


static func build_mountain_rings() -> Node3D:
	var root := Node3D.new()
	root.name = "DistantMountains3D"
	var ring_mesh := _create_mountain_ring_mesh(256, 10)
	var specs: Array[Dictionary] = [
		{
			"radius": 210.0,
			"height": 26.0,
			"seed": 0.19,
			"haze": 0.38,
			"snow": 0.42,
			"base_color": Color(0.25, 0.34, 0.38),
			"shadow_color": Color(0.17, 0.24, 0.32),
		},
		{
			"radius": 340.0,
			"height": 42.0,
			"seed": 0.63,
			"haze": 0.64,
			"snow": 0.58,
			"base_color": Color(0.32, 0.42, 0.52),
			"shadow_color": Color(0.22, 0.31, 0.42),
		},
	]
	for spec: Dictionary in specs:
		var mat := ShaderMaterial.new()
		mat.shader = SevaraAssetLibrary3D.load_shader("sevara_mountains_3d.gdshader")
		mat.set_shader_parameter("radius", float(spec["radius"]))
		mat.set_shader_parameter("height", float(spec["height"]))
		mat.set_shader_parameter("seed", float(spec["seed"]))
		mat.set_shader_parameter("haze", float(spec["haze"]))
		mat.set_shader_parameter("snow", float(spec["snow"]))
		mat.set_shader_parameter("base_color", spec["base_color"])
		mat.set_shader_parameter("shadow_color", spec["shadow_color"])
		var mi := MeshInstance3D.new()
		mi.mesh = ring_mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-600.0, -100.0, -600.0), Vector3(1200.0, 400.0, 1200.0))
		root.add_child(mi)
	return root


static func _create_mountain_ring_mesh(segments: int, rows: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(segments + 1):
		var ang := float(i) * TAU / float(segments)
		for j in range(rows + 1):
			verts.append(Vector3(ang, float(j) / float(rows), 0.0))
	for i in range(segments):
		for j in range(rows):
			var v := i * (rows + 1) + j
			var w := v + rows + 1
			indices.append_array([v, w, v + 1, v + 1, w, w + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _add_terrain_vertex(
	st: SurfaceTool, pos: Vector3, half_w: float, half_d: float
) -> void:
	var uv := Vector2((pos.x + half_w) / (half_w * 2.0), (pos.z + half_d) / (half_d * 2.0))
	var r_cx := river_center_x(pos.z)
	var r_hw := river_half_width(pos.z)
	var dist_river := absf(pos.x - r_cx)
	var wet_pool := wetland_pool_factor(pos.x, pos.z)

	# R = mud/silt, G = pebbles/shore, B = cliff stone, A = spring snow
	var w_pebbles := clampf(1.0 - (dist_river / maxf(r_hw * 1.45, 1.5)), 0.0, 1.0)
	var w_mud := clampf(
		wet_pool * 0.85 + exp(-pow((dist_river - r_hw) / 2.2, 2.0)) * 0.52, 0.0, 1.0
	)
	if STEP1_CLEAN_MEADOW:
		w_pebbles = 0.0
		w_mud = 0.0
	var w_stone := clampf(smoothstep(2.4, 4.6, pos.y), 0.0, 1.0)
	var w_snow := clampf(
		smoothstep(3.4, 6.2, pos.y) * (0.55 + 0.45 * sin(pos.x * 0.35 + pos.z * 0.42)), 0.0, 0.92
	)

	var path_w := get_path_weight_at(pos.x, pos.z)
	var above_water := maxf(pos.y - WATER_SURFACE_Y, 0.0)

	st.set_color(Color(w_mud, w_pebbles, w_stone, w_snow))
	st.set_uv(uv)
	st.set_uv2(Vector2(path_w, above_water))
	st.add_vertex(pos)


static func _add_water_vertex(st: SurfaceTool, pos: Vector3, half_w: float, half_d: float) -> void:
	var ground_y := get_height_at(pos.x, pos.z)
	var water_depth := clampf((WATER_SURFACE_Y - ground_y) / 1.85, 0.0, 1.0)
	var shore_prox := clampf(1.0 - water_depth * 2.15, 0.0, 1.0)
	var rapids_fac := clampf(
		(
			exp(-pow((pos.z - 2.45) / 3.6, 2.0)) * 0.78
			+ exp(-pow((pos.z - (-15.0)) / 7.5, 2.0)) * 0.70
		),
		0.0,
		1.0
	)
	var uv := Vector2((pos.x + half_w) / (half_w * 2.0), (pos.z + half_d) / (half_d * 2.0))
	st.set_color(Color(shore_prox, water_depth, rapids_fac, 1.0))
	st.set_uv(uv)
	st.add_vertex(pos)

class_name SevaraTerrainGen3D
extends RefCounted
## Generates the expanded 3D terrain mesh (160 x 120 m), river/wetland water mesh,
## and distant mountain range rings for the Sevara Valley.

const TILE_SIZE_M := 1.65
const VALLEY_WIDTH_M := 160.0
const VALLEY_DEPTH_M := 120.0
const WATER_SURFACE_Y := -0.18
const WORLD_SCALE := TILE_SIZE_M / 32.0
## Step 1 Look-Dev mode: clean rolling meadow + single winding footpath.
const STEP1_CLEAN_MEADOW := true


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
	# Nivarel flows from the NW gorge (-24 at z=-55) through the central rapids (x ~ 1.5 at z=0)
	# and winds SE into the broad Mulane floodplain (x ~ 16 at z=+50).
	return 1.8 + wz * 0.28 + sin(wz * 0.085 + 0.35) * 4.2 + cos(wz * 0.042) * 2.1


static func river_half_width(wz: float) -> float:
	var base_w := 3.4 + smoothstep(-25.0, 35.0, wz) * 1.8
	var pool_w := exp(-pow((wz - 11.0) / 9.5, 2.0)) * 2.8
	return base_w + pool_w


static func wetland_pool_factor(wx: float, wz: float) -> float:
	# Secondary Mulane oxbow pool & marsh channels in the SW-South basin
	var dx := wx - (-7.5 + sin(wz * 0.14) * 2.2)
	var dz := wz - 13.5
	var oxbow := exp(-(dx * dx) / 28.0 - (dz * dz) / 46.0)
	var south_pond := exp(-pow(wx - 4.5, 2.0) / 38.0 - pow(wz - 22.0, 2.0) / 32.0)
	return clampf(maxf(oxbow, south_pond * 0.85), 0.0, 1.0)


static func is_water_at(wx: float, wz: float) -> bool:
	return get_height_at(wx, wz) < WATER_SURFACE_Y - 0.03


static func get_ground_normal(wx: float, wz: float) -> Vector3:
	var eps := 0.45
	var hx := get_height_at(wx + eps, wz) - get_height_at(wx - eps, wz)
	var hz := get_height_at(wx, wz + eps) - get_height_at(wx, wz - eps)
	return Vector3(-hx, 2.0 * eps, -hz).normalized()


static func get_path_weight_at(wx: float, wz: float) -> float:
	if STEP1_CLEAN_MEADOW:
		# Single organic winding footpath gently curving across the sun-lit rolling hills
		var trail_z := -3.5 + sin(wx * 0.14 + 0.4) * 2.8 + cos(wx * 0.07 - 0.3) * 1.4
		var main_trail := (
			exp(-pow((wz - trail_z) / 1.05, 2.0))
			* smoothstep(-28.0, -21.0, wx)
			* (1.0 - smoothstep(21.0, 28.0, wx))
		)
		return clampf(main_trail, 0.0, 1.0)

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
		# Soft, harmonious rolling hills across the meadow look-dev sanctuary
		var hill_a := sin(wx * 0.10 + 0.3) * cos(wz * 0.11 - 0.4) * 0.68
		var hill_b := sin(wx * 0.19 - wz * 0.16 + 1.1) * 0.26
		var north_rise := smoothstep(-6.0, -42.0, wz) * 2.8
		var rim_x := smoothstep(28.0, 74.0, absf(wx))
		var rim_z := smoothstep(22.0, 54.0, absf(wz))
		var rim_h := (
			clampf(rim_x + rim_z - rim_x * rim_z * 0.4, 0.0, 1.0)
			* (2.8 + 0.9 * sin(wx * 0.08 + 0.4))
		)
		var path_dip := get_path_weight_at(wx, wz) * 0.07
		var micro := sin(wx * 0.38 + wz * 0.33) * 0.03 + cos(wx * 0.25 - wz * 0.41) * 0.025
		return 0.85 + hill_a + hill_b + north_rise + rim_h + micro - path_dip

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
	_width_tiles: int = 32, _height_tiles: int = 24, subdiv_x: int = 128, subdiv_z: int = 96
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
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5

			# Only generate water quads where the terrain dips near or below the water plane
			var min_ground := minf(
				minf(get_height_at(x0, z0), get_height_at(x1, z0)),
				minf(get_height_at(x0, z1), get_height_at(x1, z1))
			)
			if (
				min_ground > WATER_SURFACE_Y + 0.35
				and absf(cx - river_center_x(cz)) > river_half_width(cz) + 3.5
			):
				continue

			var p00 := Vector3(x0, WATER_SURFACE_Y, z0)
			var p10 := Vector3(x1, WATER_SURFACE_Y, z0)
			var p01 := Vector3(x0, WATER_SURFACE_Y, z1)
			var p11 := Vector3(x1, WATER_SURFACE_Y, z1)

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
			"radius": 175.0,
			"height": 58.0,
			"seed": 0.19,
			"haze": 0.34,
			"snow": 0.48,
			"base_color": Color(0.26, 0.35, 0.34),
			"shadow_color": Color(0.18, 0.24, 0.32),
		},
		{
			"radius": 310.0,
			"height": 105.0,
			"seed": 0.63,
			"haze": 0.58,
			"snow": 0.64,
			"base_color": Color(0.32, 0.40, 0.46),
			"shadow_color": Color(0.22, 0.29, 0.38),
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
	var water_depth := clampf((WATER_SURFACE_Y - ground_y) / 1.15, 0.0, 1.0)
	var shore_prox := clampf(1.0 - water_depth * 1.35, 0.0, 1.0)
	var rapids_fac := clampf(exp(-pow((pos.z - (-8.0)) / 10.0, 2.0)) * 0.85, 0.0, 1.0)
	var uv := Vector2((pos.x + half_w) / (half_w * 2.0), (pos.z + half_d) / (half_d * 2.0))
	st.set_color(Color(shore_prox, water_depth, rapids_fac, 1.0))
	st.set_uv(uv)
	st.add_vertex(pos)

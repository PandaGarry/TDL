class_name SevaraTerrainGen3D
extends RefCounted
## Generates the continuous 3D terrain mesh, heightfield and water meshes for
## the Sevara Valley slice in Godot 4.7.
##
## Maps logical chunk tile coordinates `(0..31, 0..23)` onto continuous 3D
## world coordinates in meters and computes vertex heights, normals and biome
## weights (`COLOR` channels) for `sevara_terrain_3d.gdshader`.

const TILE_METERS := 1.6
const CHUNK_WIDTH_TILES := 32
const CHUNK_HEIGHT_TILES := 24
const TERRAIN_HALF_EXTENT := 68.0
const TERRAIN_STEP := 1.6
const WATER_LEVEL_Y := -0.38
const KEVAR_POOL_CENTER := Vector2(16.5, -10.8)
const KEVAR_POOL_RADIUS := 6.4
const KEVAR_WATER_Y := 1.15


static func tile_to_world_xz(tile: Vector2i) -> Vector2:
	var wx := (float(tile.x) - 15.0) * TILE_METERS
	var wz := (float(tile.y) - 11.5) * TILE_METERS
	return Vector2(wx, wz)


static func tile_to_world_pos3d(tile: Vector2i, y_offset: float = 0.0) -> Vector3:
	var xz := tile_to_world_xz(tile)
	var hy := ground_height_at(xz.x, xz.y)
	return Vector3(xz.x, hy + y_offset, xz.y)


static func river_center_x(z: float) -> float:
	return sin(z * 0.095) * 1.85 + cos(z * 0.045) * 0.75


static func river_half_width(z: float) -> float:
	var wetland_widen := clampf((z - 8.0) / 18.0, 0.0, 1.0) * 3.8
	return 2.85 + wetland_widen


static func ground_height_at(x: float, z: float) -> float:
	var h := raw_terrain_height(x, z)
	# Bridge deck over the Nivarel channel at z ~ 11.2 (tile_y ~ 18..19)
	var rcx := river_center_x(z)
	if absf(z - 11.2) < 1.9 and absf(x - rcx) < 4.2:
		return maxf(h, 0.72)
	return maxf(h, WATER_LEVEL_Y - 0.15)


static func raw_terrain_height(x: float, z: float) -> float:
	var rcx := river_center_x(z)
	var rw := river_half_width(z)
	var dist_river := absf(x - rcx)

	# Base valley floor sloping gently from north (z < 0) to south wetland (z > 0)
	var north_slope := clampf((-z - 6.0) / 38.0, 0.0, 1.4) * 7.8
	var far_west_ridge := clampf((-x - 22.0) / 36.0, 0.0, 1.5) * 12.5
	var far_east_ridge := clampf((x - 26.0) / 36.0, 0.0, 1.5) * 10.5
	var far_north_peaks := clampf((-z - 22.0) / 34.0, 0.0, 1.6) * 15.0
	var rolling := (
		sin(x * 0.14 + z * 0.11) * 0.32
		+ cos(x * 0.27 - z * 0.19) * 0.18
		+ sin(x * 0.51 + z * 0.47) * 0.07
	)

	var base_y := 0.85 + north_slope + far_west_ridge + far_east_ridge + far_north_peaks + rolling

	# Flatten the Nivara settlement terrace on the western bank
	var dist_settlement := Vector2((x + 13.5) * 0.75, (z + 1.0) * 0.65).length()
	if dist_settlement < 11.5:
		var flat_blend := smoothstep(11.5, 4.5, dist_settlement)
		base_y = lerpf(base_y, 1.25, flat_blend)

	# Carve the Kevar anomaly rocky rim and crater basin in the north-east
	var d_kevar := Vector2(x - KEVAR_POOL_CENTER.x, z - KEVAR_POOL_CENTER.y).length()
	if d_kevar < KEVAR_POOL_RADIUS + 4.8:
		if d_kevar < KEVAR_POOL_RADIUS:
			var bowl := smoothstep(KEVAR_POOL_RADIUS, 1.2, d_kevar)
			base_y = lerpf(1.75, 0.25, bowl)
		else:
			var rim := sin(((d_kevar - KEVAR_POOL_RADIUS) / 4.8) * PI)
			base_y += rim * 1.95

	# Carve the Nivarel river channel and Mulane wetland basin
	if dist_river < rw + 2.4:
		var bank_t := smoothstep(rw + 2.4, rw * 0.55, dist_river)
		var bed_y := -1.35 if z < 10.0 else -1.05
		base_y = lerpf(base_y, bed_y, bank_t)

	return base_y


static func terrain_normal_at(x: float, z: float) -> Vector3:
	var eps := 0.45
	var h_l := raw_terrain_height(x - eps, z)
	var h_r := raw_terrain_height(x + eps, z)
	var h_d := raw_terrain_height(x, z - eps)
	var h_u := raw_terrain_height(x, z + eps)
	return Vector3(h_l - h_r, 2.0 * eps, h_d - h_u).normalized()


static func biome_weights_at(x: float, y: float, z: float, normal: Vector3) -> Color:
	var rcx := river_center_x(z)
	var rw := river_half_width(z)
	var dist_river := absf(x - rcx)
	var w_river := clampf(1.0 - (dist_river - rw * 0.65) / 2.8, 0.0, 1.0)
	var d_kevar := Vector2(x - KEVAR_POOL_CENTER.x, z - KEVAR_POOL_CENTER.y).length()
	if d_kevar < KEVAR_POOL_RADIUS + 1.4:
		w_river = maxf(w_river, clampf(1.0 - (d_kevar - KEVAR_POOL_RADIUS) / 1.8, 0.0, 1.0))

	# Cobblestone / packed earth paths around courtyard, sluice and bridge
	var d_yard := Vector2(x + 11.5, z - 2.5).length()
	var d_bridge_road := absf(z - 11.2) + maxf(0.0, absf(x) - 14.0) * 0.4
	var d_sluice_road := absf(z + 1.2) + maxf(0.0, absf(x + 5.0) - 7.0) * 0.5
	var w_path := clampf(
		maxf(1.0 - d_yard / 6.5, maxf(1.0 - d_bridge_road / 2.2, 1.0 - d_sluice_road / 2.0)),
		0.0,
		1.0
	)

	var slope := 1.0 - clampf(normal.y, 0.0, 1.0)
	var w_rock := clampf(smoothstep(0.24, 0.48, slope), 0.0, 1.0)
	if d_kevar >= KEVAR_POOL_RADIUS - 0.6 and d_kevar <= KEVAR_POOL_RADIUS + 4.2:
		w_rock = maxf(w_rock, 0.78)
	var w_snow := clampf((y - 4.8) / 5.5, 0.0, 1.0)
	return Color(w_river, w_path, w_rock, w_snow)


static func build_terrain_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var steps := int(round((TERRAIN_HALF_EXTENT * 2.0) / TERRAIN_STEP))
	for iz in range(steps):
		var z0 := -TERRAIN_HALF_EXTENT + float(iz) * TERRAIN_STEP
		var z1 := z0 + TERRAIN_STEP
		for ix in range(steps):
			var x0 := -TERRAIN_HALF_EXTENT + float(ix) * TERRAIN_STEP
			var x1 := x0 + TERRAIN_STEP

			_emit_terrain_vertex(st, x0, z0)
			_emit_terrain_vertex(st, x1, z0)
			_emit_terrain_vertex(st, x0, z1)

			_emit_terrain_vertex(st, x1, z0)
			_emit_terrain_vertex(st, x1, z1)
			_emit_terrain_vertex(st, x0, z1)

	st.generate_tangents()
	return st.commit()


static func build_water_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1) Main Nivarel river & Mulane wetland water ribbon
	var z_min := -TERRAIN_HALF_EXTENT
	var z_max := TERRAIN_HALF_EXTENT
	var z_step := 1.6
	var z := z_min
	while z < z_max:
		var zn := z + z_step
		var cx0 := river_center_x(z)
		var cx1 := river_center_x(zn)
		var hw0 := river_half_width(z) + 1.35
		var hw1 := river_half_width(zn) + 1.35
		_emit_water_quad(
			st,
			Vector3(cx0 - hw0, WATER_LEVEL_Y, z),
			Vector3(cx0 + hw0, WATER_LEVEL_Y, z),
			Vector3(cx1 - hw1, WATER_LEVEL_Y, zn),
			Vector3(cx1 + hw1, WATER_LEVEL_Y, zn)
		)
		z = zn

	# 2) Elevated Kevar crater pool disc
	var segs := 28
	var center3 := Vector3(KEVAR_POOL_CENTER.x, KEVAR_WATER_Y, KEVAR_POOL_CENTER.y)
	for i in range(segs):
		var a0 := (float(i) / float(segs)) * TAU
		var a1 := (float(i + 1) / float(segs)) * TAU
		var p0 := center3 + Vector3(cos(a0), 0.0, sin(a0)) * (KEVAR_POOL_RADIUS - 0.35)
		var p1 := center3 + Vector3(cos(a1), 0.0, sin(a1)) * (KEVAR_POOL_RADIUS - 0.35)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(center3)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p1.x * 0.1, p1.z * 0.1))
		st.add_vertex(p1)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p0.x * 0.1, p0.z * 0.1))
		st.add_vertex(p0)

	st.generate_tangents()
	return st.commit()


static func _emit_terrain_vertex(st: SurfaceTool, x: float, z: float) -> void:
	var y := raw_terrain_height(x, z)
	var n := terrain_normal_at(x, z)
	var col := biome_weights_at(x, y, z, n)
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(Vector2(x * 0.12, z * 0.12))
	st.add_vertex(Vector3(x, y, z))


static func _emit_water_quad(
	st: SurfaceTool, v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3
) -> void:
	for v in [v00, v10, v01, v10, v11, v01]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v.x * 0.15, v.z * 0.15))
		st.add_vertex(v)

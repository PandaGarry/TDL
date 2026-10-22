class_name SevaraVfx3D
extends RefCounted
## Next-gen 2026 3D Atmospheric & Environmental VFX system (inspired by Bukkbeek EffectBlocks,
## Tiny Glade, and No Rest for the Wicked):
## - Volumetric Sunbeams / God Rays slanting through valley pines
## - 3D dancing fire tongues, rising embers, hearth & chimney smoke plumes
## - Drifting morning river mist over Nivarel rapids and Mulane oxbow pools
## - Concentric animated water ripples around bridge piers, weirs, and river stones
## - Soft ground-contact ambient occlusion shadow decals under settlement buildings
## - Floating sunlit pollen motes and drifting spring leaves across the valley

const CONTACT_SHADOW_SPECS: Array[Dictionary] = [
	{"pos": Vector2(-19.5, -12.2), "rx": 3.4, "rz": 3.2},
	{"pos": Vector2(-11.4, -14.6), "rx": 3.2, "rz": 3.0},
	{"pos": Vector2(-22.2, -3.4), "rx": 3.3, "rz": 3.1},
	{"pos": Vector2(-14.5, 1.8), "rx": 3.2, "rz": 3.0},
	{"pos": Vector2(-24.0, -8.2), "rx": 3.4, "rz": 3.2},
	{"pos": Vector2(-18.8, 5.2), "rx": 3.2, "rz": 2.9},
	{"pos": Vector2(-4.8, -12.6), "rx": 3.5, "rz": 3.2},
	{"pos": Vector2(6.8, -15.2), "rx": 3.2, "rz": 3.2},
	{"pos": Vector2(-9.2, -8.8), "rx": 2.9, "rz": 2.9},
	{"pos": Vector2(-14.2, -7.6), "rx": 2.4, "rz": 2.4},
	{"pos": Vector2(-16.2, -4.8), "rx": 1.8, "rz": 1.8},
	{"pos": Vector2(-8.8, 4.8), "rx": 1.9, "rz": 1.7},
	{"pos": Vector2(-11.2, 6.2), "rx": 1.9, "rz": 1.7},
	{"pos": Vector2(-17.5, -1.2), "rx": 1.6, "rz": 1.3},
	{"pos": Vector2(9.4, -9.2), "rx": 2.1, "rz": 2.1},
]

const CHIMNEY_POSITIONS: Array[Vector3] = [
	Vector3(-19.5, 4.5, -12.2),
	Vector3(-11.4, 4.2, -14.6),
	Vector3(-22.2, 4.3, -3.4),
	Vector3(-14.5, 4.1, 1.8),
	Vector3(-24.0, 3.8, -8.2),
]

const GODRAY_SPECS: Array[Dictionary] = [
	{"pos": Vector3(-11.5, 6.8, -8.5), "w": 6.5, "h": 15.0, "alpha": 0.11},
	{"pos": Vector3(-1.2, 6.4, -6.2), "w": 7.5, "h": 16.0, "alpha": 0.13},
	{"pos": Vector3(12.5, 6.6, -1.8), "w": 8.0, "h": 16.5, "alpha": 0.12},
	{"pos": Vector3(3.5, 6.2, 10.5), "w": 7.0, "h": 15.0, "alpha": 0.10},
	{"pos": Vector3(-18.5, 7.2, -15.0), "w": 6.0, "h": 14.5, "alpha": 0.10},
]


static func build_valley_vfx_root() -> Node3D:
	var root := Node3D.new()
	root.name = "SevaraValleyVFX3D"

	_build_ground_contact_shadows(root)
	_build_fire_and_smoke_vfx(root)
	_build_river_mist_and_ripples(root)
	_build_volumetric_godrays(root)
	_build_floating_pollen_and_leaves(root)
	return root


static func _build_ground_contact_shadows(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "GroundContactShadows3D"
	var sh := SevaraAssetLibrary3D.load_shader("sevara_vfx_mist_3d.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("vfx_mode", 2)
	mat.set_shader_parameter("tint_color", Color(0.05, 0.08, 0.06, 0.56))

	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)

	for spec: Dictionary in CONTACT_SHADOW_SPECS:
		var p: Vector2 = spec["pos"]
		var wy := SevaraTerrainGen3D.get_height_at(p.x, p.y)
		var gn := SevaraTerrainGen3D.get_ground_normal(p.x, p.y)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var up := gn.normalized()
		var right := up.cross(Vector3.BACK).normalized()
		var fwd := right.cross(up).normalized()
		var rx := float(spec["rx"])
		var rz := float(spec["rz"])
		mi.transform = Transform3D(Basis(right * rx, up, fwd * rz), Vector3(p.x, wy + 0.025, p.y))
		group.add_child(mi)
	parent.add_child(group)


static func _build_fire_and_smoke_vfx(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "FireAndSmokeVFX3D"

	# 1. Communal Hearth 3D dancing flames + embers
	var hearth_pos := Vector2(-14.2, -7.6)
	var hearth_y := SevaraTerrainGen3D.get_height_at(hearth_pos.x, hearth_pos.y)
	group.add_child(
		_create_flame_cluster(
			Vector3(hearth_pos.x, hearth_y + 0.52, hearth_pos.y), Vector2(0.82, 1.05), 3
		)
	)
	group.add_child(
		_create_smoke_column(Vector3(hearth_pos.x, hearth_y + 1.25, hearth_pos.y), 5, 0.55, 3.6)
	)

	# 2. Blacksmith forge glowing fire + smoke
	var forge_pos := Vector2(-23.2, -7.6)
	var forge_y := SevaraTerrainGen3D.get_height_at(forge_pos.x, forge_pos.y)
	group.add_child(
		_create_flame_cluster(
			Vector3(forge_pos.x, forge_y + 0.75, forge_pos.y), Vector2(0.52, 0.68), 2
		)
	)

	# 3. Bridge entrance torch flames
	var bridge_z := -4.6
	var bridge_x := SevaraTerrainGen3D.river_center_x(bridge_z)
	for side_x in [-1.0, 1.0]:
		var local_pt := Vector3(float(side_x) * 3.78, 1.48, -1.18).rotated(Vector3.UP, -0.24)
		var world_pt := (
			Vector3(bridge_x, SevaraTerrainGen3D.WATER_SURFACE_Y + 0.14, bridge_z) + local_pt
		)
		group.add_child(_create_flame_cluster(world_pt, Vector2(0.32, 0.45), 2))
		var tl := OmniLight3D.new()
		tl.position = world_pt + Vector3(0.0, 0.2, 0.0)
		tl.light_color = Color(1.0, 0.68, 0.30)
		tl.light_energy = 1.15
		tl.omni_range = 5.5
		group.add_child(tl)

	# 4. Chimney smoke wisps rising above settlement cottages
	for c_pos: Vector3 in CHIMNEY_POSITIONS:
		var ground_y := SevaraTerrainGen3D.get_height_at(c_pos.x, c_pos.z)
		group.add_child(
			_create_smoke_column(Vector3(c_pos.x, ground_y + c_pos.y, c_pos.z), 4, 0.48, 3.2)
		)

	parent.add_child(group)


static func _create_flame_cluster(pos: Vector3, size: Vector2, planes: int) -> Node3D:
	var cluster := Node3D.new()
	cluster.position = pos
	var sh := SevaraAssetLibrary3D.load_shader("sevara_vfx_fire_3d.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = sh

	var qm := QuadMesh.new()
	qm.size = size
	for i in range(planes):
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.y = float(i) * PI / float(planes) + 0.25
		cluster.add_child(mi)
	return cluster


static func _create_smoke_column(
	base_pos: Vector3, puff_count: int, base_radius: float, height_span: float
) -> Node3D:
	var col := Node3D.new()
	col.position = base_pos
	var sh := SevaraAssetLibrary3D.load_shader("sevara_vfx_mist_3d.gdshader")
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)

	for i in range(puff_count):
		var t := float(i) / float(maxi(puff_count - 1, 1))
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("vfx_mode", 0)
		mat.set_shader_parameter("tint_color", Color(0.84, 0.88, 0.92, lerpf(0.22, 0.06, t)))
		mat.set_shader_parameter("drift_speed", 0.35 + t * 0.15)
		var r := lerpf(base_radius, base_radius * 2.2, t)
		for plane_idx in range(2):
			var mi := MeshInstance3D.new()
			mi.mesh = qm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(t * 0.45, t * height_span, -t * 0.25)
			mi.scale = Vector3(r, r, r)
			mi.rotation = Vector3(-0.35, float(plane_idx) * PI * 0.5 + 0.4, 0.0)
			col.add_child(mi)
	return col


static func _build_river_mist_and_ripples(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "RiverMistAndRipples3D"
	var sh := SevaraAssetLibrary3D.load_shader("sevara_vfx_mist_3d.gdshader")

	# 1. Drifting morning mist sheets just above the river & wetland water
	var mist_mat := ShaderMaterial.new()
	mist_mat.shader = sh
	mist_mat.set_shader_parameter("vfx_mode", 0)
	mist_mat.set_shader_parameter("tint_color", Color(0.86, 0.93, 0.98, 0.19))
	mist_mat.set_shader_parameter("drift_speed", 0.22)

	var mist_plane := PlaneMesh.new()
	mist_plane.size = Vector2(7.5, 5.5)
	var mist_z_list: Array[float] = [-22.0, -14.0, -7.5, -1.5, 5.0, 12.0, 19.5]
	for mz: float in mist_z_list:
		var mx := SevaraTerrainGen3D.river_center_x(mz)
		var mi := MeshInstance3D.new()
		mi.mesh = mist_plane
		mi.material_override = mist_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(mx, SevaraTerrainGen3D.WATER_SURFACE_Y + 0.22, mz)
		mi.rotation.y = sin(mz * 0.3) * 0.45
		group.add_child(mi)

	# 2. Animated concentric water ripples around weirs, bridge pilings, and river rocks
	var ripple_mat := ShaderMaterial.new()
	ripple_mat.shader = sh
	ripple_mat.set_shader_parameter("vfx_mode", 1)
	ripple_mat.set_shader_parameter("tint_color", Color(0.94, 0.98, 1.0, 0.42))
	ripple_mat.set_shader_parameter("drift_speed", 0.42)

	var ripple_plane := PlaneMesh.new()
	ripple_plane.size = Vector2(2.4, 2.4)
	var ripple_coords: Array[Vector2] = [
		Vector2(SevaraTerrainGen3D.river_center_x(-10.2), -10.2),
		Vector2(SevaraTerrainGen3D.river_center_x(-4.6) - 1.6, -4.6),
		Vector2(SevaraTerrainGen3D.river_center_x(-4.6) + 1.6, -4.6),
		Vector2(SevaraTerrainGen3D.river_center_x(5.8), 5.8),
		Vector2(-2.2, -16.5),
		Vector2(2.8, -11.5),
		Vector2(-1.8, -1.2),
		Vector2(4.2, 3.4),
		Vector2(-3.8, 13.6),
		Vector2(2.4, 11.4),
	]
	for rc: Vector2 in ripple_coords:
		var rmi := MeshInstance3D.new()
		rmi.mesh = ripple_plane
		rmi.material_override = ripple_mat
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rmi.position = Vector3(rc.x, SevaraTerrainGen3D.WATER_SURFACE_Y + 0.018, rc.y)
		group.add_child(rmi)

	parent.add_child(group)


static func _build_volumetric_godrays(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "VolumetricGodRays3D"
	var sh := SevaraAssetLibrary3D.load_shader("sevara_vfx_godrays_3d.gdshader")
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)

	for spec: Dictionary in GODRAY_SPECS:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("ray_color", Color(1.0, 0.91, 0.66, float(spec["alpha"])))
		var pos: Vector3 = spec["pos"]
		var w := float(spec["w"])
		var h := float(spec["h"])
		for plane_i in range(2):
			var mi := MeshInstance3D.new()
			mi.mesh = qm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = pos
			mi.scale = Vector3(w, h, w)
			mi.rotation_degrees = Vector3(-32.0, -34.0 + float(plane_i) * 52.0, -18.0)
			group.add_child(mi)
	parent.add_child(group)


static func _build_floating_pollen_and_leaves(parent: Node3D) -> void:
	# Sunlit golden pollen motes & drifting spring leaves across the valley
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022

	var mote_mesh := QuadMesh.new()
	mote_mesh.size = Vector2(0.085, 0.085)
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_mat.albedo_color = Color(1.0, 0.94, 0.66, 0.78)
	mote_mesh.material = mote_mat

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FloatingSunPollenMM3D"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mote_mesh
	var count := 160
	mm.instance_count = count
	for i in range(count):
		var wx := rng.randf_range(-28.0, 28.0)
		var wz := rng.randf_range(-22.0, 22.0)
		var wy := SevaraTerrainGen3D.get_height_at(wx, wz) + rng.randf_range(0.6, 4.8)
		var sc := rng.randf_range(0.65, 1.45)
		mm.set_instance_transform(
			i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(wx, wy, wz))
		)
	mmi.multimesh = mm
	parent.add_child(mmi)

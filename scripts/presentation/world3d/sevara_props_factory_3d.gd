class_name SevaraPropsFactory3D
extends RefCounted
## Builds detailed modular 3D architecture, hydro-engineering, trees, shrubs,
## rocks and Kevalu anomaly roots for the Sevara Valley 3D world.

static var _material_cache: Dictionary = {}


static func clear_cache() -> void:
	_material_cache.clear()


static func mat_stone(tint: Color = Color(0.62, 0.64, 0.67)) -> StandardMaterial3D:
	var key := "stone_%s" % tint.to_html(false)
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	var diff := load("res://assets/textures/sevara_p1/tex_stone_and_timber.png") as Texture2D
	var norm := load("res://assets/textures/sevara_p1/tex_stone_and_timber_normal.png") as Texture2D
	if diff != null:
		m.albedo_texture = diff
	if norm != null:
		m.normal_enabled = true
		m.normal_texture = norm
	m.uv1_scale = Vector3(2.2, 2.2, 2.2)
	m.roughness = 0.88
	_material_cache[key] = m
	return m


static func mat_wood(tint: Color = Color(0.46, 0.32, 0.20)) -> StandardMaterial3D:
	var key := "wood_%s" % tint.to_html(false)
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.78
	_material_cache[key] = m
	return m


static func mat_foliage(tint: Color, roughness_val: float = 0.82) -> StandardMaterial3D:
	var key := "foliage_%s_%.2f" % [tint.to_html(false), roughness_val]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = roughness_val
	_material_cache[key] = m
	return m


static func mat_emissive(color: Color, energy: float = 2.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	return m


static func build_longhouse_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "NivaraLonghouse3D"
	var stone := mat_stone(Color(0.55, 0.56, 0.58))
	var log_dark := mat_wood(Color(0.38, 0.25, 0.15))
	var log_warm := mat_wood(Color(0.54, 0.38, 0.23))
	var plaster := mat_stone(Color(0.78, 0.72, 0.60))
	var roof_shingle := mat_wood(Color(0.28, 0.20, 0.14))

	# 1) Stone foundation plinth (9.4m x 7.2m)
	_add_box(root, Vector3(9.4, 0.65, 7.2), Vector3(0.0, 0.32, 0.0), stone)
	# Stone entry steps facing the courtyard (+X / +Z)
	_add_box(root, Vector3(1.6, 0.35, 2.2), Vector3(4.9, 0.17, 0.8), stone)

	# 2) Timber-framed walls (cutaway south-east roof section so hearth & chronicle rack are visible!)
	_add_box(root, Vector3(9.0, 2.9, 0.38), Vector3(0.0, 2.05, -3.3), plaster)
	_add_box(root, Vector3(0.38, 2.9, 6.8), Vector3(-4.3, 2.05, 0.0), plaster)
	_add_box(root, Vector3(5.2, 2.7, 0.36), Vector3(-1.9, 1.95, 3.3), plaster)
	_add_box(root, Vector3(0.36, 2.6, 3.2), Vector3(4.3, 1.90, -1.8), plaster)

	# Corner and wall timber posts + horizontal log beams
	for px in [-4.35, 0.0, 4.35]:
		for pz in [-3.35, 3.35]:
			_add_cylinder(root, 0.18, 3.2, Vector3(px, 2.2, pz), Vector3.ZERO, log_dark)
	for by in [0.85, 2.1, 3.35]:
		_add_box(root, Vector3(9.2, 0.22, 0.26), Vector3(0.0, by, -3.35), log_dark)
		_add_box(root, Vector3(0.26, 0.22, 7.0), Vector3(-4.35, by, 0.0), log_dark)

	# 3) Hearth chimney & glowing fire inside the longhouse
	_add_box(root, Vector3(1.8, 4.8, 1.6), Vector3(-2.6, 2.9, -2.1), stone)
	_add_box(root, Vector3(1.2, 0.45, 1.2), Vector3(-2.6, 0.82, -1.5), stone)
	_add_sphere(root, 0.42, Vector3(-2.6, 1.08, -1.45), mat_emissive(Color(1.0, 0.48, 0.12), 3.4))
	var hearth_light := OmniLight3D.new()
	hearth_light.name = "HearthOmniLight"
	hearth_light.position = Vector3(-2.2, 2.0, -1.1)
	hearth_light.light_color = Color(1.0, 0.64, 0.28)
	hearth_light.light_energy = 2.6
	hearth_light.omni_range = 11.5
	root.add_child(hearth_light)

	# 4) Selima's Chronicle Tablet Rack along the north wall + Sarela's council table
	_add_box(root, Vector3(3.4, 2.1, 0.32), Vector3(1.4, 1.7, -2.95), log_dark)
	for tx in range(6):
		for ty in range(2):
			_add_box(
				root,
				Vector3(0.36, 0.52, 0.08),
				Vector3(0.1 + float(tx) * 0.52, 1.35 + float(ty) * 0.68, -2.74),
				log_warm
			)
	# Council table & benches
	_add_box(root, Vector3(2.6, 0.14, 1.2), Vector3(-0.4, 1.32, 0.2), log_warm)
	_add_box(root, Vector3(2.2, 0.65, 0.8), Vector3(-0.4, 0.96, 0.2), log_dark)

	# 5) Gabled timber roof (covering north-west half, leaving cutaway view into hall)
	var roof_left := _add_box(
		root, Vector3(9.6, 0.24, 4.3), Vector3(0.0, 4.45, -1.65), roof_shingle
	)
	roof_left.rotation_degrees = Vector3(28.0, 0.0, 0.0)
	var roof_right := _add_box(
		root, Vector3(5.4, 0.24, 4.3), Vector3(-2.1, 4.45, 1.65), roof_shingle
	)
	roof_right.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	# Exposed rafters over the cutaway section so 3D depth is unmistakable
	for rx in [0.8, 2.0, 3.2, 4.2]:
		var rafter := _add_box(root, Vector3(0.16, 0.18, 4.2), Vector3(rx, 4.42, 1.65), log_warm)
		rafter.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	_add_cylinder(root, 0.18, 9.8, Vector3(0.0, 5.38, 0.0), Vector3(0.0, 0.0, 90.0), log_dark)
	return root


static func build_herbalist_yard_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "MavenaHerbalistYard3D"
	var wood := mat_wood(Color(0.48, 0.34, 0.21))
	var stone := mat_stone(Color(0.56, 0.58, 0.60))
	var herb_green := mat_foliage(Color(0.26, 0.54, 0.28))
	var herb_gold := mat_foliage(Color(0.84, 0.68, 0.22))
	var clay := mat_wood(Color(0.68, 0.38, 0.24))

	# Worktable & drying pergola
	_add_box(root, Vector3(3.2, 0.14, 1.3), Vector3(0.0, 0.92, 0.0), wood)
	for lx in [-1.4, 1.4]:
		for lz in [-0.5, 0.5]:
			_add_cylinder(root, 0.09, 0.9, Vector3(lx, 0.45, lz), Vector3.ZERO, wood)
	# Clay jars & herb bundles on the table
	_add_cylinder(root, 0.22, 0.46, Vector3(-1.0, 1.22, -0.2), Vector3.ZERO, clay)
	_add_cylinder(root, 0.18, 0.38, Vector3(-0.55, 1.18, 0.25), Vector3.ZERO, clay)
	_add_box(root, Vector3(0.75, 0.16, 0.48), Vector3(0.25, 1.06, -0.1), herb_green)
	_add_box(root, Vector3(0.62, 0.16, 0.42), Vector3(0.95, 1.06, 0.2), herb_gold)

	# Stone-rimmed quarantine basin for inspecting Kevalu samples
	_add_cylinder(root, 1.25, 0.55, Vector3(2.8, 0.28, -0.8), Vector3.ZERO, stone)
	_add_cylinder(
		root,
		0.98,
		0.58,
		Vector3(2.8, 0.30, -0.8),
		Vector3.ZERO,
		mat_foliage(Color(0.16, 0.44, 0.48), 0.18)
	)
	return root


static func build_sluice_and_dam_3d(dams_integrity: float) -> Node3D:
	var root := Node3D.new()
	root.name = "OrunelSluiceAndDam3D"
	var stone := mat_stone(Color(0.54, 0.56, 0.60))
	var timber := mat_wood(Color(0.39, 0.27, 0.17))

	# 1) Massive stone retaining embankments along the Nivarel channel
	for side in [-1.0, 1.0]:
		_add_box(root, Vector3(1.1, 2.2, 22.0), Vector3(side * 3.55, 0.1, 0.0), stone)
		# Sluice gate stone piers at z = 0
		_add_box(root, Vector3(1.9, 3.5, 2.2), Vector3(side * 3.25, 0.95, 0.0), stone)

	# 2) Heavy timber overhead beam & movable sluice gate boards
	_add_box(root, Vector3(7.4, 0.42, 0.48), Vector3(0.0, 2.95, 0.0), timber)
	for gx in [-2.0, -0.7, 0.7, 2.0]:
		_add_box(root, Vector3(0.26, 3.2, 0.32), Vector3(gx, 1.45, 0.0), timber)
	_add_box(root, Vector3(5.6, 2.1, 0.24), Vector3(0.0, 0.65, 0.0), timber)

	# Torch braziers on the sluice piers
	for side in [-1.0, 1.0]:
		var torch_pos := Vector3(side * 3.25, 2.95, 0.95)
		_add_cylinder(root, 0.10, 0.75, torch_pos, Vector3.ZERO, timber)
		_add_sphere(
			root,
			0.22,
			torch_pos + Vector3(0.0, 0.45, 0.0),
			mat_emissive(Color(1.0, 0.56, 0.16), 3.8)
		)
		var light := OmniLight3D.new()
		light.position = torch_pos + Vector3(0.0, 0.65, 0.0)
		light.light_color = Color(1.0, 0.62, 0.24)
		light.light_energy = 1.85
		light.omni_range = 9.5
		root.add_child(light)

	# 3) Upstream Navelu beaver/builder log dam (at z = -8.5 relative to sluice)
	if dams_integrity > 0.12:
		var log_count := int(round(lerpf(3.0, 14.0, clampf(dams_integrity, 0.0, 1.0))))
		for i in range(log_count):
			var t := float(i) / float(maxi(log_count - 1, 1))
			var lx := lerpf(-2.6, 2.6, t)
			var lz := -8.2 + sin(float(i) * 1.9) * 0.55
			var ly := -0.15 + float(i % 3) * 0.18
			var rot_y := sin(float(i) * 2.3) * 28.0
			_add_cylinder(root, 0.18, 2.8, Vector3(lx, ly, lz), Vector3(82.0, rot_y, 15.0), timber)
	return root


static func build_wooden_bridge_3d() -> Node3D:
	var root := Node3D.new()
	root.name = "NivarelWoodenBridge3D"
	var stone := mat_stone(Color(0.56, 0.57, 0.60))
	var plank_mat := mat_wood(Color(0.49, 0.35, 0.22))
	var rail_mat := mat_wood(Color(0.36, 0.24, 0.15))

	# Stone abutments on both riverbanks
	_add_box(root, Vector3(1.8, 1.9, 3.6), Vector3(-4.1, 0.15, 0.0), stone)
	_add_box(root, Vector3(1.8, 1.9, 3.6), Vector3(4.1, 0.15, 0.0), stone)

	# Longitudinal stringer beams & individual deck planks
	for sz in [-1.25, 0.0, 1.25]:
		_add_box(root, Vector3(8.4, 0.26, 0.28), Vector3(0.0, 0.72, sz), rail_mat)
	for i in range(15):
		var px := -3.85 + float(i) * 0.55
		_add_box(root, Vector3(0.46, 0.12, 3.2), Vector3(px, 0.90, 0.0), plank_mat)

	# Bridge posts and handrails
	for sz in [-1.48, 1.48]:
		_add_box(root, Vector3(8.2, 0.14, 0.14), Vector3(0.0, 1.72, sz), rail_mat)
		for px in [-3.8, -1.9, 0.0, 1.9, 3.8]:
			_add_box(root, Vector3(0.18, 1.05, 0.18), Vector3(px, 1.32, sz), rail_mat)
	return root


static func create_torava_pine_3d(scale_factor: float = 1.0, snow_tipped: bool = false) -> Node3D:
	var tree := Node3D.new()
	var trunk_mat := mat_wood(Color(0.34, 0.22, 0.14))
	var pine_dark := mat_foliage(Color(0.14, 0.29, 0.16))
	var pine_mid := mat_foliage(Color(0.19, 0.36, 0.20))
	var snow_mat := mat_foliage(Color(0.86, 0.91, 0.95), 0.65)

	_add_cylinder(
		tree,
		0.26 * scale_factor,
		2.6 * scale_factor,
		Vector3(0.0, 1.3 * scale_factor, 0.0),
		Vector3.ZERO,
		trunk_mat
	)
	var tiers := 4
	for i in range(tiers):
		var frac := float(i) / float(tiers)
		var radius := lerpf(1.85, 0.72, frac) * scale_factor
		var height := lerpf(2.2, 1.45, frac) * scale_factor
		var cy := (2.1 + float(i) * 1.18) * scale_factor
		var mat := (
			snow_mat
			if (snow_tipped and i == tiers - 1)
			else (pine_dark if i % 2 == 0 else pine_mid)
		)
		_add_cone(tree, radius, height, Vector3(0.0, cy, 0.0), mat)
	return tree


static func create_mirval_blossom_bush_3d(scale_factor: float = 1.0) -> Node3D:
	var bush := Node3D.new()
	var leaf_mat := mat_foliage(Color(0.25, 0.45, 0.21))
	var blossom_mat := mat_foliage(Color(0.90, 0.74, 0.18), 0.65)
	_add_sphere(bush, 0.68 * scale_factor, Vector3(0.0, 0.48 * scale_factor, 0.0), leaf_mat)
	_add_sphere(
		bush,
		0.52 * scale_factor,
		Vector3(0.42 * scale_factor, 0.38 * scale_factor, 0.22 * scale_factor),
		leaf_mat
	)
	_add_sphere(
		bush,
		0.48 * scale_factor,
		Vector3(-0.38 * scale_factor, 0.40 * scale_factor, -0.18 * scale_factor),
		leaf_mat
	)
	for offset in [
		Vector3(0.18, 0.82, 0.15),
		Vector3(-0.24, 0.74, -0.12),
		Vector3(0.36, 0.64, -0.18),
		Vector3(-0.10, 0.68, 0.32),
	]:
		_add_sphere(bush, 0.19 * scale_factor, offset * scale_factor, blossom_mat)
	return bush


static func create_selave_reed_clump_3d(vitality: float = 0.75) -> Node3D:
	var clump := Node3D.new()
	var stem_color := Color(0.24, 0.50, 0.26).lerp(
		Color(0.48, 0.44, 0.24), 1.0 - clampf(vitality, 0.0, 1.0)
	)
	var stem_mat := mat_foliage(stem_color)
	var plume_mat := mat_wood(Color(0.42, 0.28, 0.16))
	var count := 5
	for i in range(count):
		var angle := float(i) * (TAU / float(count))
		var offset := Vector3(cos(angle) * 0.22, 0.0, sin(angle) * 0.22)
		var h := (0.95 + float(i % 3) * 0.22) * clampf(0.55 + vitality * 0.6, 0.4, 1.2)
		var tilt := Vector3(sin(angle) * 8.0, 0.0, -cos(angle) * 8.0)
		_add_cylinder(clump, 0.04, h, offset + Vector3(0.0, h * 0.5, 0.0), tilt, stem_mat)
		_add_cylinder(clump, 0.07, 0.22, offset + Vector3(0.0, h * 0.92, 0.0), tilt, plume_mat)
	return clump


static func create_rock_boulder_3d(
	radius: float = 0.85, stretch: Vector3 = Vector3(1.2, 0.75, 1.0)
) -> Node3D:
	var node := Node3D.new()
	var mesh_inst := _add_sphere(
		node,
		radius,
		Vector3(0.0, radius * stretch.y * 0.45, 0.0),
		mat_stone(Color(0.52, 0.54, 0.58)),
		8,
		6
	)
	mesh_inst.scale = stretch
	return node


static func create_kevalu_tendril_cluster_3d(intensity: float = 0.5) -> Node3D:
	var root := Node3D.new()
	var bone_mat := mat_stone(Color(0.84, 0.82, 0.76))
	var branches := int(round(lerpf(4.0, 11.0, clampf(intensity, 0.0, 1.0))))
	for i in range(branches):
		var angle := float(i) * 0.95
		var length := 1.2 + float(i % 3) * 0.65
		var pos := Vector3(
			cos(angle) * (0.4 + float(i) * 0.25), 0.28, sin(angle) * (0.4 + float(i) * 0.22)
		)
		var rot := Vector3(58.0 + float(i % 2) * 14.0, rad_to_deg(angle), 18.0)
		_add_cone(root, 0.14, length, pos, bone_mat, rot)
	return root


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _add_cylinder(
	parent: Node3D, radius: float, height: float, pos: Vector3, rot_deg: Vector3, mat: Material
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.88
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_cone(
	parent: Node3D,
	bottom_radius: float,
	height: float,
	pos: Vector3,
	mat: Material,
	rot_deg: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = bottom_radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_sphere(
	parent: Node3D,
	radius: float,
	pos: Vector3,
	mat: Material,
	radial_segs: int = 14,
	rings_count: int = 8
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = radial_segs
	sm.rings = rings_count
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

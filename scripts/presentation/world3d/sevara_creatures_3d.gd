class_name SevaraCreatures3D
extends RefCounted
## Builds articulated 3D humanoids (6.5–7 head proportions), wildlife (Harune
## grazers, Navelu builders) and interactive supply crates for the 3D world.


static func create_humanoid_3d(
	palette: Dictionary, display_tag: String, is_local_player: bool = false, vitals: Dictionary = {}
) -> Node3D:
	var root := Node3D.new()
	var cloak_col := _color_or(palette.get("cloak"), Color(0.32, 0.39, 0.27))
	var tunic_col := _color_or(palette.get("tunic"), Color(0.70, 0.64, 0.54))
	var trim_col := _color_or(palette.get("trim"), Color(0.86, 0.68, 0.28))
	var prop_kind := String(palette.get("prop", "staff"))

	var wetness := float(vitals.get("wetness", 0.0))
	if wetness > 20.0:
		cloak_col = cloak_col.darkened(clampf(wetness / 180.0, 0.0, 0.35))

	var boot_mat := SevaraPropsFactory3D.mat_wood(Color(0.24, 0.16, 0.11))
	var trousers_mat := SevaraPropsFactory3D.mat_foliage(Color(0.26, 0.25, 0.22), 0.90)
	var tunic_mat := SevaraPropsFactory3D.mat_foliage(tunic_col, 0.86)
	var cloak_mat := SevaraPropsFactory3D.mat_foliage(cloak_col, 0.88)
	var trim_mat := SevaraPropsFactory3D.mat_foliage(trim_col, 0.55)
	var skin_mat := SevaraPropsFactory3D.mat_foliage(Color(0.82, 0.68, 0.56), 0.72)
	var hair_mat := SevaraPropsFactory3D.mat_wood(Color(0.22, 0.16, 0.12))

	# 1) Boots & legs (0.0m .. 0.82m)
	for side in [-1.0, 1.0]:
		SevaraPropsFactory3D._add_cylinder(
			root, 0.085, 0.42, Vector3(side * 0.13, 0.21, 0.0), Vector3.ZERO, boot_mat
		)
		SevaraPropsFactory3D._add_cylinder(
			root, 0.095, 0.44, Vector3(side * 0.13, 0.62, 0.0), Vector3.ZERO, trousers_mat
		)

	# 2) Tunic torso, belt & shoulders (0.80m .. 1.44m)
	SevaraPropsFactory3D._add_box(
		root, Vector3(0.44, 0.64, 0.26), Vector3(0.0, 1.12, 0.0), tunic_mat
	)
	SevaraPropsFactory3D._add_box(
		root, Vector3(0.46, 0.07, 0.28), Vector3(0.0, 0.96, 0.0), trim_mat
	)

	# 3) Heavy Sevaran cloak draped over shoulders and back
	var cloak_back := SevaraPropsFactory3D._add_box(
		root, Vector3(0.52, 0.96, 0.10), Vector3(0.0, 1.00, -0.15), cloak_mat
	)
	cloak_back.rotation_degrees = Vector3(7.0, 0.0, 0.0)
	SevaraPropsFactory3D._add_box(
		root, Vector3(0.54, 0.16, 0.34), Vector3(0.0, 1.40, -0.02), cloak_mat
	)

	# 4) Arms & hands
	for side in [-1.0, 1.0]:
		var arm := SevaraPropsFactory3D._add_cylinder(
			root,
			0.075,
			0.54,
			Vector3(side * 0.29, 1.12, 0.04),
			Vector3(-14.0 if side > 0.0 else 6.0, 0.0, side * -8.0),
			cloak_mat
		)
		arm.name = "Arm_%d" % int(side)
		SevaraPropsFactory3D._add_sphere(
			root, 0.068, Vector3(side * 0.31, 0.85, 0.11 if side > 0.0 else 0.02), skin_mat
		)

	# 5) Head & hair/hood (proportion: 1.76m total height / 0.26m head = 6.77 heads)
	SevaraPropsFactory3D._add_sphere(root, 0.135, Vector3(0.0, 1.61, 0.02), skin_mat)
	SevaraPropsFactory3D._add_sphere(root, 0.142, Vector3(0.0, 1.64, -0.03), hair_mat)

	# 6) Role tool/prop in right hand
	_attach_role_prop_3d(root, prop_kind, trim_mat)

	# 7) Local player ground focus ring
	if is_local_player:
		var ring_mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.56
		torus.outer_radius = 0.66
		ring_mi.mesh = torus
		ring_mi.position = Vector3(0.0, 0.05, 0.0)
		ring_mi.material_override = SevaraPropsFactory3D.mat_emissive(Color(0.95, 0.78, 0.28), 1.8)
		root.add_child(ring_mi)

	# 8) Diegetic 3D billboard nameplate above the character
	if not display_tag.is_empty():
		var lbl := Label3D.new()
		lbl.name = "NameLabel3D"
		lbl.text = display_tag
		lbl.position = Vector3(0.0, 2.15, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = false
		lbl.pixel_size = 0.0085
		lbl.font_size = 34
		lbl.outline_size = 10
		lbl.modulate = (
			Color(1.0, 0.92, 0.62, 1.0) if is_local_player else Color(0.95, 0.94, 0.88, 1.0)
		)
		lbl.outline_modulate = Color(0.04, 0.06, 0.07, 0.96)
		root.add_child(lbl)

	return root


static func create_supply_crate_3d(label_text: String, highlighted: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "SupplyCrate3D"
	var wood_mat := SevaraPropsFactory3D.mat_wood(
		Color(0.62, 0.44, 0.25) if highlighted else Color(0.46, 0.32, 0.19)
	)
	var iron_mat := SevaraPropsFactory3D.mat_stone(Color(0.32, 0.35, 0.38))

	SevaraPropsFactory3D._add_box(
		root, Vector3(0.95, 0.78, 0.95), Vector3(0.0, 0.39, 0.0), wood_mat
	)
	for by in [0.14, 0.64]:
		SevaraPropsFactory3D._add_box(
			root, Vector3(0.99, 0.08, 0.99), Vector3(0.0, by, 0.0), iron_mat
		)
	# Stacked Torava logs beside the supply crate
	for i in range(3):
		SevaraPropsFactory3D._add_cylinder(
			root,
			0.14,
			1.1,
			Vector3(0.0, 0.86, -0.22 + float(i) * 0.22),
			Vector3(0.0, 0.0, 90.0),
			wood_mat
		)

	if not label_text.is_empty():
		var lbl := Label3D.new()
		lbl.text = label_text
		lbl.position = Vector3(0.0, 1.45, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.pixel_size = 0.008
		lbl.font_size = 28
		lbl.outline_size = 8
		lbl.modulate = Color(0.96, 0.88, 0.64, 1.0)
		lbl.outline_modulate = Color(0.05, 0.06, 0.08, 0.94)
		root.add_child(lbl)
	return root


static func create_harune_grazer_3d(scale_factor: float = 1.0) -> Node3D:
	var root := Node3D.new()
	var coat_mat := SevaraPropsFactory3D.mat_wood(Color(0.42, 0.31, 0.22))
	var under_mat := SevaraPropsFactory3D.mat_wood(Color(0.58, 0.48, 0.36))
	var horn_mat := SevaraPropsFactory3D.mat_stone(Color(0.76, 0.73, 0.64))

	# Muscular torso + chest
	var body := SevaraPropsFactory3D._add_sphere(
		root, 0.56 * scale_factor, Vector3(0.0, 0.92 * scale_factor, 0.0), coat_mat
	)
	body.scale = Vector3(0.82, 0.78, 1.48)
	SevaraPropsFactory3D._add_sphere(
		root, 0.44 * scale_factor, Vector3(0.0, 0.98 * scale_factor, 0.48 * scale_factor), under_mat
	)

	# 4 legs
	for lx in [-0.26, 0.26]:
		for lz in [-0.48, 0.46]:
			SevaraPropsFactory3D._add_cylinder(
				root,
				0.08 * scale_factor,
				0.78 * scale_factor,
				Vector3(lx, 0.39, lz) * scale_factor,
				Vector3.ZERO,
				coat_mat
			)

	# Neck, head and curved Sevaran horns
	SevaraPropsFactory3D._add_cylinder(
		root,
		0.18 * scale_factor,
		0.58 * scale_factor,
		Vector3(0.0, 1.32, 0.68) * scale_factor,
		Vector3(32.0, 0.0, 0.0),
		coat_mat
	)
	var head := SevaraPropsFactory3D._add_sphere(
		root, 0.22 * scale_factor, Vector3(0.0, 1.54, 0.92) * scale_factor, coat_mat
	)
	head.scale = Vector3(0.75, 0.78, 1.35)
	for side in [-1.0, 1.0]:
		SevaraPropsFactory3D._add_cone(
			root,
			0.06 * scale_factor,
			0.68 * scale_factor,
			Vector3(side * 0.16, 1.82, 0.72) * scale_factor,
			horn_mat,
			Vector3(-38.0, 0.0, side * -16.0)
		)
	return root


static func create_navelu_builder_3d() -> Node3D:
	var root := Node3D.new()
	var fur_mat := SevaraPropsFactory3D.mat_wood(Color(0.30, 0.21, 0.14))
	var tail_mat := SevaraPropsFactory3D.mat_stone(Color(0.24, 0.20, 0.18))
	var body := SevaraPropsFactory3D._add_sphere(root, 0.32, Vector3(0.0, 0.24, 0.0), fur_mat)
	body.scale = Vector3(0.85, 0.68, 1.35)
	SevaraPropsFactory3D._add_sphere(root, 0.18, Vector3(0.0, 0.30, 0.36), fur_mat)
	var tail := SevaraPropsFactory3D._add_box(
		root, Vector3(0.24, 0.05, 0.42), Vector3(0.0, 0.14, -0.48), tail_mat
	)
	tail.rotation_degrees = Vector3(12.0, 0.0, 0.0)
	return root


static func _attach_role_prop_3d(root: Node3D, prop_kind: String, accent_mat: Material) -> void:
	var wood_mat := SevaraPropsFactory3D.mat_wood(Color(0.44, 0.29, 0.17))
	var iron_mat := SevaraPropsFactory3D.mat_stone(Color(0.58, 0.62, 0.66))
	match prop_kind:
		"staff", "spear":
			SevaraPropsFactory3D._add_cylinder(
				root, 0.032, 1.75, Vector3(0.36, 0.92, 0.18), Vector3(8.0, 0.0, 0.0), wood_mat
			)
			if prop_kind == "spear":
				SevaraPropsFactory3D._add_cone(
					root, 0.06, 0.28, Vector3(0.36, 1.84, 0.28), iron_mat
				)
		"hook", "axe":
			SevaraPropsFactory3D._add_cylinder(
				root, 0.035, 1.05, Vector3(0.35, 0.88, 0.18), Vector3(24.0, 0.0, 0.0), wood_mat
			)
			SevaraPropsFactory3D._add_box(
				root, Vector3(0.22, 0.14, 0.06), Vector3(0.35, 1.32, 0.38), iron_mat
			)
		"tablet":
			SevaraPropsFactory3D._add_box(
				root, Vector3(0.26, 0.34, 0.05), Vector3(0.30, 1.06, 0.22), accent_mat
			)
		_:
			SevaraPropsFactory3D._add_box(
				root, Vector3(0.24, 0.24, 0.20), Vector3(0.32, 0.88, 0.14), wood_mat
			)


static func _color_or(raw: Variant, fallback: Color) -> Color:
	if typeof(raw) == TYPE_COLOR:
		return raw as Color
	return fallback

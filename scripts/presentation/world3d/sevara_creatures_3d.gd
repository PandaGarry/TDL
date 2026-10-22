class_name SevaraCreatures3D
extends RefCounted
## Builds animated 3D human characters (6.5-7 head proportions with modular gear)
## and animated 3D valley fauna (tal_har stags/deer and kor_varn wolves/foxes)
## from CC0 glTF/GLB assets with skeletal AnimationPlayer states.


static func create_human_figure_3d(
	cloak_color: Color = Color(0.22, 0.36, 0.48),
	tunic_color: Color = Color(0.46, 0.40, 0.32),
	is_local_focus: bool = false,
	has_pack: bool = true,
	has_satchel: bool = false,
	has_staff: bool = true,
	has_kevalu_fever: bool = false,
	role_hint: String = ""
) -> Node3D:
	var root := Node3D.new()
	root.name = "HumanFigure3D"

	var model_file := _select_character_model_file(role_hint, has_satchel, is_local_focus)
	var skin_col := Color(0.42, 0.44, 0.40) if has_kevalu_fever else Color(0.46, 0.31, 0.22)
	var hair_col := Color(0.18, 0.11, 0.07)
	if role_hint.contains("selima") or role_hint.contains("sarela"):
		hair_col = Color(0.34, 0.24, 0.15)
	elif role_hint.contains("ilune") or role_hint.contains("evaren"):
		hair_col = Color(0.28, 0.16, 0.09)
	var overrides := {
		"Skin": skin_col,
		"Main": cloak_color,
		"Shirt": tunic_color,
		"Vest": cloak_color.darkened(0.18),
		"Light": tunic_color.darkened(0.06),
		"Pants": Color(0.18, 0.16, 0.14),
		"Hair": hair_col,
		"DarkGreen": cloak_color,
	}

	var char_node := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.CHARACTERS_DIR + model_file, 1.78, overrides, true
	)
	char_node.name = "CharacterRig"
	root.add_child(char_node)

	var default_anims: Array[String] = ["Idle", "Stand"]
	SevaraAssetLibrary3D.play_best_animation(
		char_node, default_anims, 0.92 if has_kevalu_fever else 1.0
	)

	if has_pack:
		var pack := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.ITEMS_DIR + "Backpack.glb", 0.52, {}, true
		)
		pack.position = Vector3(0.0, 0.96, -0.22)
		root.add_child(pack)

	if has_satchel:
		var pouch := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.ITEMS_DIR + "Pouch.glb", 0.28, {}, true
		)
		pouch.position = Vector3(0.24, 0.78, 0.06)
		root.add_child(pouch)

	if has_staff:
		var tool_file := (
			"Bow_Wooden.glb"
			if (role_hint.contains("evaren") or role_hint.contains("tobren"))
			else "Axe_small.glb"
		)
		var tool_node := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.ITEMS_DIR + tool_file, 0.58, {}, true
		)
		tool_node.position = Vector3(-0.28, 0.86, 0.12)
		tool_node.rotation = Vector3(0.25, 0.4, -0.15)
		root.add_child(tool_node)

	if is_local_focus:
		var ring_mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.56
		cyl.bottom_radius = 0.62
		cyl.height = 0.025
		ring_mi.mesh = cyl
		ring_mi.position = Vector3(0.0, 0.015, 0.0)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.86, 0.72, 0.42, 0.42)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.roughness = 0.9
		ring_mi.material_override = rmat
		root.add_child(ring_mi)

	if has_kevalu_fever:
		root.rotation.z = 0.06
		root.rotation.x = 0.08
	return root


static func set_human_motion_state(
	figure_root: Node3D, is_moving: bool, is_running: bool = false
) -> void:
	if figure_root == null:
		return
	var rig := figure_root.get_node_or_null("CharacterRig")
	if rig == null:
		return
	if is_moving:
		if is_running:
			SevaraAssetLibrary3D.play_best_animation(rig, ["Run", "Walk"], 1.15)
		else:
			SevaraAssetLibrary3D.play_best_animation(rig, ["Walk", "Run"], 1.0)
	else:
		SevaraAssetLibrary3D.play_best_animation(rig, ["Idle"], 1.0)


static func create_tal_har_stag_3d(grazing: bool = true, variant: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "TalHarStag3D"
	var is_stag := (variant % 2) == 0
	var file_name := "Stag.glb" if is_stag else "Deer.glb"
	var target_h := 2.15 if is_stag else 1.72
	var animal := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ANIMALS_DIR + file_name, target_h, {}, true
	)
	root.add_child(animal)
	var speed := 0.88 + float(posmod(variant, 3)) * 0.08
	if grazing:
		SevaraAssetLibrary3D.play_best_animation(
			animal, ["Eating", "Idle_Headlow", "Idle_2", "Idle"], speed
		)
	else:
		SevaraAssetLibrary3D.play_best_animation(animal, ["Walk", "Idle", "Eating"], speed)
	return root


static func create_kor_varn_canid_3d(prowling: bool = true, variant: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "KorVarnCanid3D"
	var is_wolf := (variant % 2) == 0
	var file_name := "Wolf.glb" if is_wolf else "Fox.glb"
	var target_h := 1.08 if is_wolf else 0.78
	var animal := SevaraAssetLibrary3D.instantiate_model(
		SevaraAssetLibrary3D.ANIMALS_DIR + file_name, target_h, {}, true
	)
	root.add_child(animal)
	var speed := 0.92 + float(posmod(variant, 3)) * 0.08
	if prowling:
		SevaraAssetLibrary3D.play_best_animation(animal, ["Walk", "Idle_2_HeadLow", "Idle"], speed)
	else:
		SevaraAssetLibrary3D.play_best_animation(
			animal, ["Eating", "Idle_2_HeadLow", "Idle"], speed
		)
	return root


static func _select_character_model_file(
	role_hint: String, has_satchel: bool, _is_local_focus: bool
) -> String:
	var r := role_hint.to_lower()
	if (
		r.contains("selima")
		or r.contains("mavena")
		or r.contains("ilune")
		or r.contains("sarela")
		or (has_satchel and not r.contains("hero"))
	):
		return "Viking_Female.gltf"
	return "Viking_Male.gltf"

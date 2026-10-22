class_name SevaraAssetLibrary3D
extends RefCounted
## Loads, caches, normalizes, and styles 3D glTF/GLB assets (Quaternius CC0 Nature,
## Medieval Village, Animated Animals, Animated Characters) and custom Sevara shaders.

const NATURE_DIR := "res://assets/nature/"
const PBR_TEX_DIR := "res://assets/textures/sevara_p1/"
const VILLAGE_DIR := "res://assets/models/village/"
const ANIMALS_DIR := "res://assets/models/animals/"
const CHARACTERS_DIR := "res://assets/models/characters/"
const ITEMS_DIR := "res://assets/models/items/"
const SHADERS_DIR := "res://assets/shaders/"

static var _textures: Dictionary = {}
static var _scenes: Dictionary = {}
static var _raw_meshes: Dictionary = {}
static var _styled_meshes: Dictionary = {}
static var _shaders: Dictionary = {}
static var _white_tex: ImageTexture


static func clear_caches() -> void:
	_styled_meshes.clear()


static func load_shader(shader_file: String) -> Shader:
	if _shaders.has(shader_file):
		return _shaders[shader_file] as Shader
	var full_path := SHADERS_DIR + shader_file
	var sh := load(full_path) as Shader
	if sh == null:
		var code := FileAccess.get_file_as_string(full_path)
		if not code.is_empty():
			sh = Shader.new()
			sh.code = code
	_shaders[shader_file] = sh
	return sh


static func load_texture(res_path: String) -> Texture2D:
	if _textures.has(res_path):
		return _textures[res_path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		tex = ResourceLoader.load(res_path) as Texture2D
	if tex == null:
		var abs_path := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = white_texture()
	_textures[res_path] = tex
	return tex


static func white_texture() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(4, 4, true, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		img.generate_mipmaps()
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


static func load_scene(res_path: String) -> PackedScene:
	if _scenes.has(res_path):
		return _scenes[res_path] as PackedScene
	var packed: PackedScene = null
	if ResourceLoader.exists(res_path):
		packed = ResourceLoader.load(res_path) as PackedScene
	if packed == null:
		var abs_path := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_path):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			var err := doc.append_from_file(abs_path, state)
			if err == OK:
				var root := doc.generate_scene(state)
				if root != null:
					packed = PackedScene.new()
					packed.pack(root)
					root.free()
	if packed != null:
		_scenes[res_path] = packed
	return packed


static func raw_nature_mesh(model_name: String) -> ArrayMesh:
	if _raw_meshes.has(model_name):
		return _raw_meshes[model_name] as ArrayMesh
	if model_name.begins_with("Proc_"):
		var pm := _build_procedural_plant(model_name)
		_raw_meshes[model_name] = pm
		return pm
	var gltf_path := NATURE_DIR + model_name + ".gltf"
	var glb_path := NATURE_DIR + model_name + ".glb"
	var target_path := (
		gltf_path if FileAccess.file_exists(ProjectSettings.globalize_path(gltf_path)) else glb_path
	)
	var scene := load_scene(target_path)
	if scene == null:
		return ArrayMesh.new()
	var inst := scene.instantiate()
	var mi := _find_first_mesh_instance(inst)
	var mesh: ArrayMesh = null
	if mi != null and mi.mesh is ArrayMesh:
		mesh = (mi.mesh as ArrayMesh).duplicate(true) as ArrayMesh
	inst.free()
	if mesh == null:
		mesh = ArrayMesh.new()
	_raw_meshes[model_name] = mesh
	return mesh


static func nature_mesh(model_name: String, style: Dictionary = {}) -> ArrayMesh:
	var cache_key := model_name + "|" + str(style)
	if _styled_meshes.has(cache_key):
		return _styled_meshes[cache_key] as ArrayMesh
	var src := raw_nature_mesh(model_name)
	if src.get_surface_count() == 0:
		return src
	var m := _strip_leaf_lods(src)
	m.resource_name = model_name
	var aabb := src.get_aabb()
	for s in range(m.get_surface_count()):
		var orig_mat := src.surface_get_material(s)
		var mat_name := orig_mat.resource_name if orig_mat != null else ""
		m.surface_set_material(s, _build_nature_material(src, s, mat_name, style, aabb))
	_styled_meshes[cache_key] = m
	return m


static func build_grass_patch_mesh(
	blade_count: int, patch_size: float, blade_width: float, seed_val: int, style: Dictionary = {}
) -> ArrayMesh:
	var key := (
		"GrassPatch_%d_%.2f_%.3f_%d_%s"
		% [blade_count, patch_size, blade_width, seed_val, str(style)]
	)
	if _styled_meshes.has(key):
		return _styled_meshes[key] as ArrayMesh
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var segments := 3
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for _b in range(blade_count):
		var rx := (rng.randf() - 0.5) * patch_size
		var rz := (rng.randf() - 0.5) * patch_size
		var ang := rng.randf() * TAU
		var perp := Vector3(cos(ang), 0.0, sin(ang))
		var facing := Vector3(-sin(ang), 0.0, cos(ang))
		var w := blade_width * rng.randf_range(0.75, 1.32)
		var rnd_col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var base_idx := verts.size()
		for s in range(segments):
			var t := float(s) / float(segments)
			var half_w := w * 0.5 * (1.0 - pow(t, 1.35))
			for side in [-1.0, 1.0]:
				var side_f := float(side)
				verts.append(Vector3(rx, t, rz) + perp * (side_f * half_w))
				normals.append((facing + perp * (side_f * 0.35)).normalized())
				uvs.append(Vector2(side_f * 0.5 + 0.5, t))
				colors.append(rnd_col)
		verts.append(Vector3(rx, 1.0, rz))
		normals.append(facing)
		uvs.append(Vector2(0.5, 1.0))
		colors.append(rnd_col)
		for s in range(segments - 1):
			var v := base_idx + s * 2
			indices.append_array([v, v + 1, v + 2, v + 1, v + 3, v + 2])
		var last := base_idx + (segments - 1) * 2
		indices.append_array([last, last + 1, last + 2])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mat := ShaderMaterial.new()
	mat.shader = load_shader("sevara_grass_3d.gdshader")
	mat.set_shader_parameter("root_color", style.get("root_color", Color(0.11, 0.25, 0.09)))
	mat.set_shader_parameter("tip_color", style.get("tip_color", Color(0.36, 0.60, 0.19)))
	mat.set_shader_parameter("tip_color_warm", style.get("tip_color_warm", Color(0.62, 0.66, 0.23)))
	mat.set_shader_parameter("blade_height", float(style.get("blade_height", 0.52)))
	mat.set_shader_parameter("wind_strength", float(style.get("wind_strength", 1.0)))
	mesh.surface_set_material(0, mat)
	_styled_meshes[key] = mesh
	return mesh


static func instantiate_model(
	res_path: String,
	target_height: float,
	palette_overrides: Dictionary = {},
	apply_structural_textures: bool = true
) -> Node3D:
	var wrapper := Node3D.new()
	var packed := load_scene(res_path)
	if packed == null:
		return wrapper
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return wrapper
	wrapper.add_child(inst)
	_enhance_materials_recursive(
		inst, palette_overrides, apply_structural_textures, res_path.to_lower()
	)
	if target_height > 0.01:
		_fit_instance_to_height(inst, target_height)
	return wrapper


static func play_best_animation(
	root: Node, preferred_names: Array, speed_scale: float = 1.0
) -> bool:
	var anim_player := _find_animation_player(root)
	if anim_player == null:
		return false
	var available := anim_player.get_animation_list()
	if available.is_empty():
		return false
	var chosen := ""
	for raw_pref in preferred_names:
		var pref := String(raw_pref)
		for anim_name: String in available:
			if (
				anim_name == pref
				or anim_name.ends_with("|" + pref)
				or anim_name.to_lower().contains(pref.to_lower())
			):
				chosen = anim_name
				break
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		chosen = available[0]
	var anim := anim_player.get_animation(chosen)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	anim_player.speed_scale = speed_scale
	if anim_player.current_animation != chosen or not anim_player.is_playing():
		anim_player.play(chosen)
	return true


static func _strip_leaf_lods(src: ArrayMesh) -> ArrayMesh:
	var raw_surfaces: Variant = src.get("_surfaces")
	if not (raw_surfaces is Array):
		return src.duplicate(true) as ArrayMesh
	var surfaces: Array = (raw_surfaces as Array).duplicate(true)
	for s in range(surfaces.size()):
		var mat := src.surface_get_material(s)
		var mname := mat.resource_name if mat != null else ""
		if mname.begins_with("Leaves") and mname != "Leaves" and surfaces[s] is Dictionary:
			(surfaces[s] as Dictionary)["lods"] = []
	var out := ArrayMesh.new()
	out.set("_surfaces", surfaces)
	return out


static func _build_nature_material(
	src: ArrayMesh, surf_idx: int, mat_name: String, style: Dictionary, aabb: AABB
) -> Material:
	var height := maxf(aabb.end.y, 0.5)
	if mat_name.begins_with("Bark"):
		var bark_st: Dictionary = style.get("bark", {})
		var mat := ShaderMaterial.new()
		mat.shader = load_shader("sevara_bark_3d.gdshader")
		var bark_base: String = (
			{
				"Bark_Birch": "Bark_NormalTree",
				"Bark_Pine": "Bark_NormalTree",
			}
			. get(mat_name, mat_name)
		)
		mat.set_shader_parameter("albedo_tex", load_texture(NATURE_DIR + bark_base + ".png"))
		mat.set_shader_parameter("normal_tex", load_texture(NATURE_DIR + bark_base + "_Normal.png"))
		mat.set_shader_parameter("object_height", height)
		mat.set_shader_parameter("stiffness", float(style.get("stiffness", 4.0)))
		for k: String in bark_st.keys():
			mat.set_shader_parameter(k, bark_st[k])
		return mat

	if (
		mat_name in ["Rocks", "PathRocks"]
		or mat_name.begins_with("Rock")
		or mat_name.begins_with("Moss")
	):
		var rock_st: Dictionary = style.get("rock", {})
		var mat := ShaderMaterial.new()
		mat.shader = load_shader("sevara_rock_3d.gdshader")
		var is_path_rock := mat_name == "PathRocks"
		var default_alb := (
			PBR_TEX_DIR + ("pbr_flagstone_path.png" if is_path_rock else "pbr_cliff_rock.png")
		)
		var default_nrm := (
			PBR_TEX_DIR
			+ ("pbr_flagstone_path_normal.png" if is_path_rock else "pbr_cliff_rock_normal.png")
		)
		var custom_tex := String(rock_st.get("texture", ""))
		var alb_path := default_alb if custom_tex.is_empty() else (NATURE_DIR + custom_tex)
		mat.set_shader_parameter("albedo_tex", load_texture(alb_path))
		mat.set_shader_parameter("normal_tex", load_texture(default_nrm))
		mat.set_shader_parameter(
			"moss_tex", load_texture(PBR_TEX_DIR + "tex_meadow_moss_and_snow.png")
		)
		for k: String in rock_st.keys():
			if k != "texture":
				mat.set_shader_parameter(k, rock_st[k])
		return mat

	if mat_name == "Proc":
		var plant_st: Dictionary = style.get("plant", {})
		var pm := ShaderMaterial.new()
		pm.shader = load_shader("sevara_foliage_3d.gdshader")
		pm.set_shader_parameter("mode", 3)
		pm.set_shader_parameter("albedo_tex", white_texture())
		pm.set_shader_parameter("object_height", height)
		pm.set_shader_parameter("alpha_cut", 0.0)
		pm.set_shader_parameter("stiffness", float(plant_st.get("stiffness", 2.4)))
		pm.set_shader_parameter("flutter", 0.035)
		pm.set_shader_parameter("translucency", 0.48)
		for k: String in plant_st.keys():
			if k != "stiffness":
				pm.set_shader_parameter(k, plant_st[k])
		return pm

	if mat_name == "Mushrooms":
		var mmat := StandardMaterial3D.new()
		mmat.albedo_texture = load_texture(NATURE_DIR + "Mushrooms.png")
		mmat.albedo_color = style.get("mushroom_tint", Color(1.12, 0.96, 0.78))
		mmat.roughness = 0.78
		mmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mmat

	var fmat := ShaderMaterial.new()
	fmat.shader = load_shader("sevara_foliage_3d.gdshader")
	fmat.set_shader_parameter("object_height", height)
	fmat.set_shader_parameter("stiffness", float(style.get("stiffness", 3.8)))

	if mat_name == "Grass":
		var gst: Dictionary = style.get("grass", {})
		fmat.set_shader_parameter("mode", 1)
		fmat.set_shader_parameter("albedo_tex", load_texture(NATURE_DIR + "Grass.png"))
		fmat.set_shader_parameter("alpha_cut", 0.35)
		fmat.set_shader_parameter("stiffness", float(gst.get("stiffness", 2.8)))
		fmat.set_shader_parameter("flutter", 0.045)
		fmat.set_shader_parameter("translucency", 0.42)
		fmat.set_shader_parameter("ground_normal", 0.68)
		fmat.set_shader_parameter("color_dark", gst.get("color_dark", Color(0.14, 0.30, 0.10)))
		fmat.set_shader_parameter("color_light", gst.get("color_light", Color(0.42, 0.66, 0.22)))
		return fmat

	var tex_file: String = (
		{
			"Leaves_NormalTree": "Leaves_NormalTree_C.png",
			"Leaves_TwistedTree": "Leaves_TwistedTree_C.png",
			"Leaves_Pine": "Leaf_Pine_C.png",
			"Leaves_GiantPine": "Leaves_GiantPine_C.png",
			"Leaves": "Leaves.png",
			"Flowers": "Flowers.png",
		}
		. get(mat_name, "Leaves.png")
	)
	fmat.set_shader_parameter("albedo_tex", load_texture(NATURE_DIR + tex_file))

	if mat_name in ["Leaves", "Flowers"]:
		var pst: Dictionary = style.get("plant", {})
		fmat.set_shader_parameter("mode", 2)
		fmat.set_shader_parameter("instance_tint", mat_name == "Flowers")
		var default_tex_mix := 0.32 if mat_name == "Flowers" else 0.78
		fmat.set_shader_parameter(
			"texture_color_mix", float(pst.get("texture_color_mix", default_tex_mix))
		)
		fmat.set_shader_parameter("alpha_cut", 0.45)
		fmat.set_shader_parameter("stiffness", float(pst.get("stiffness", 2.5)))
		fmat.set_shader_parameter("flutter", 0.035)
		fmat.set_shader_parameter("translucency", 0.52)
		for k: String in pst.keys():
			if k != "stiffness":
				fmat.set_shader_parameter(k, pst[k])
		return fmat

	var lst: Dictionary = style.get("leaves", {})
	var crown_box := _surface_aabb(src, surf_idx)
	fmat.set_shader_parameter("mode", 0)
	fmat.set_shader_parameter("crown_center", crown_box.get_center())
	fmat.set_shader_parameter("crown_extent", crown_box.size * 0.5)
	fmat.set_shader_parameter("alpha_cut", 0.44)
	fmat.set_shader_parameter("flutter", 0.055)
	for k: String in lst.keys():
		fmat.set_shader_parameter(k, lst[k])
	return fmat


static func _surface_aabb(src: ArrayMesh, surf_idx: int) -> AABB:
	var arrays := src.surface_get_arrays(surf_idx)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var box := AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		box = box.expand(v)
	return box


static func _find_first_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c: Node in n.get_children():
		var found := _find_first_mesh_instance(c)
		if found != null:
			return found
	return null


static func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c: Node in n.get_children():
		var found := _find_animation_player(c)
		if found != null:
			return found
	return null


static func _enhance_materials_recursive(
	node: Node,
	palette_overrides: Dictionary,
	apply_structural_textures: bool,
	model_hint: String = ""
) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var sc := mi.mesh.get_surface_count()
			for s in range(sc):
				var orig := mi.get_active_material(s)
				if orig == null and mi.mesh != null:
					orig = mi.mesh.surface_get_material(s)
				var std := StandardMaterial3D.new()
				var mname := orig.resource_name if orig != null else ""
				var base_col := Color(0.62, 0.56, 0.48)
				if orig is BaseMaterial3D:
					base_col = (orig as BaseMaterial3D).albedo_color
					std.albedo_texture = (orig as BaseMaterial3D).albedo_texture
				if std.albedo_texture == null:
					base_col = Color(
						clampf(pow(maxf(base_col.r, 0.02), 0.52) * 1.16, 0.08, 0.98),
						clampf(pow(maxf(base_col.g, 0.02), 0.52) * 1.16, 0.08, 0.98),
						clampf(pow(maxf(base_col.b, 0.02), 0.52) * 1.16, 0.08, 0.98),
						base_col.a
					)
				var has_override := false
				for key: String in palette_overrides.keys():
					if mname == key or mname.to_lower().contains(key.to_lower()):
						base_col = palette_overrides[key] as Color
						has_override = true
						break
				std.albedo_color = base_col
				std.roughness = 0.82
				std.specular = 0.24
				_apply_pbr_surface_style(
					std, mname, base_col, model_hint, has_override, apply_structural_textures
				)
				mi.set_surface_override_material(s, std)
	for child: Node in node.get_children():
		_enhance_materials_recursive(
			child, palette_overrides, apply_structural_textures, model_hint
		)


static func _bind_triplanar_pbr(
	std: StandardMaterial3D, stem: String, uv_scale: float, nrm_scale: float, tint: Color
) -> void:
	std.albedo_texture = load_texture(PBR_TEX_DIR + stem + ".png")
	std.normal_enabled = true
	std.normal_texture = load_texture(PBR_TEX_DIR + stem + "_normal.png")
	std.normal_scale = nrm_scale
	std.uv1_triplanar = true
	std.uv1_triplanar_sharpness = 4.0
	std.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	std.albedo_color = tint


static func _apply_pbr_surface_style(
	std: StandardMaterial3D,
	mname: String,
	base_col: Color,
	model_hint: String,
	has_override: bool,
	apply_structural_textures: bool
) -> void:
	var ml := mname.to_lower()
	if ml.contains("fire") or ml.contains("yellow") or ml.contains("orange"):
		if model_hint.contains("torch") or model_hint.contains("bonfire") or ml.contains("fire"):
			std.albedo_color = Color(1.0, 0.72, 0.30)
			std.emission_enabled = true
			std.emission = Color(0.98, 0.52, 0.16)
			std.emission_energy_multiplier = 1.75
			return
	if ml.contains("window"):
		std.albedo_color = Color(0.32, 0.26, 0.20)
		std.roughness = 0.26
		std.emission_enabled = true
		std.emission = Color(0.86, 0.60, 0.28)
		std.emission_energy_multiplier = 0.62
		return
	if ml.contains("eye") or ml.contains("nose") or ml.contains("hoov"):
		std.roughness = 0.28 if ml.contains("eye") else 0.68
		return
	if not apply_structural_textures or std.albedo_texture != null:
		return

	var is_animal := (
		model_hint.contains("stag")
		or model_hint.contains("deer")
		or model_hint.contains("wolf")
		or model_hint.contains("fox")
	)
	var is_character := model_hint.contains("viking")
	var is_tent := model_hint.contains("tent")

	if is_animal:
		var fur_tint := base_col.lerp(Color(0.96, 0.92, 0.86), 0.34)
		_bind_triplanar_pbr(std, "pbr_animal_fur", 1.35, 1.22, fur_tint)
		std.roughness = 0.84
		std.rim_enabled = true
		std.rim = 0.28
		std.rim_tint = 0.65
		return

	if is_character:
		if ml.contains("skin"):
			std.roughness = 0.72
			return
		if ml.contains("hair"):
			_bind_triplanar_pbr(
				std, "pbr_animal_fur", 1.6, 1.15, base_col.lerp(Color(0.9, 0.85, 0.8), 0.28)
			)
			return
		var cloth_tint := (
			base_col.lerp(Color(0.96, 0.94, 0.90), 0.32)
			if has_override
			else base_col.lerp(Color(0.92, 0.88, 0.82), 0.38)
		)
		_bind_triplanar_pbr(std, "pbr_woven_fabric", 1.25, 1.12, cloth_tint)
		std.roughness = 0.86
		return

	if ml.contains("roof") or (ml == "red" and not is_tent):
		var is_red_roof := ml.contains("red")
		var roof_tint := Color(1.06, 0.72, 0.64) if is_red_roof else Color(0.78, 0.92, 0.98)
		_bind_triplanar_pbr(std, "pbr_roof_slate", 0.56, 1.35, roof_tint)
		std.roughness = 0.74
		return

	if ml.contains("plaster") or ml.contains("beige") or ml == "white":
		var wall_tint := base_col.lerp(Color(0.98, 0.95, 0.89), 0.62)
		_bind_triplanar_pbr(std, "pbr_lime_plaster", 0.46, 1.20, wall_tint)
		std.roughness = 0.88
		return

	if ml.contains("stone") or ml.contains("grey") or ml.contains("gray"):
		var is_light := ml.contains("light")
		var st_tint := Color(0.98, 0.98, 1.02) if is_light else Color(0.76, 0.80, 0.86)
		_bind_triplanar_pbr(std, "tex_stone_and_timber", 0.48, 1.36, st_tint)
		std.roughness = 0.84
		return

	if ml.contains("metal") or ml.contains("steel") or ml.contains("gold"):
		var met_tint := Color(1.02, 0.86, 0.48) if ml.contains("gold") else Color(0.74, 0.78, 0.84)
		_bind_triplanar_pbr(std, "pbr_cliff_rock", 1.15, 0.58, met_tint)
		std.metallic = 0.78
		std.roughness = 0.32
		return

	if ml.contains("hay"):
		_bind_triplanar_pbr(std, "tex_meadow_moss_and_snow", 0.85, 1.22, Color(1.22, 1.04, 0.58))
		std.roughness = 0.90
		return

	if ml.contains("green") or ml.contains("pink"):
		if is_tent:
			var tent_tint := (
				Color(0.92, 0.90, 0.74) if ml.contains("light") else Color(0.78, 0.84, 0.64)
			)
			_bind_triplanar_pbr(std, "pbr_woven_fabric", 0.78, 1.18, tent_tint)
		elif ml.contains("pink"):
			_bind_triplanar_pbr(std, "pbr_foliage_canopy", 1.2, 0.95, Color(1.06, 0.68, 0.80))
		else:
			var leaf_tint := (
				Color(0.82, 0.94, 0.72) if ml.contains("dark") else Color(0.92, 1.02, 0.80)
			)
			_bind_triplanar_pbr(std, "pbr_foliage_canopy", 0.68, 1.22, leaf_tint)
			std.backlight_enabled = true
			std.backlight = Color(0.22, 0.32, 0.14)
		return

	if ml.contains("bag") or ml.contains("brown") or ml.contains("darkred"):
		var stem := "pbr_woven_fabric" if ml.contains("bag") else "pbr_animal_fur"
		var b_tint := base_col.lerp(Color(0.96, 0.88, 0.74), 0.45)
		_bind_triplanar_pbr(std, stem, 0.95, 1.18, b_tint)
		return

	if ml.contains("wood") or ml.contains("mushroom"):
		var w_tint := Color(0.88, 0.76, 0.64)
		if ml.contains("side"):
			w_tint = Color(1.06, 0.95, 0.78)
		elif ml.contains("light"):
			w_tint = Color(0.98, 0.86, 0.72)
		elif ml.contains("dark"):
			w_tint = Color(0.68, 0.56, 0.48)
		_bind_triplanar_pbr(std, "pbr_aged_timber", 0.54, 1.28, w_tint)
		std.roughness = 0.82
		return

	# Universal fallback for any remaining material
	_bind_triplanar_pbr(
		std, "pbr_aged_timber", 0.65, 1.10, base_col.lerp(Color(0.92, 0.88, 0.82), 0.42)
	)


static func _fit_instance_to_height(inst: Node3D, target_height: float) -> void:
	var bounds := _compute_subtree_aabb(inst, Transform3D.IDENTITY)
	if bounds.size.y <= 0.0001:
		return
	var scale_factor := target_height / bounds.size.y
	inst.scale *= scale_factor
	var scaled_bounds := _compute_subtree_aabb(inst, Transform3D.IDENTITY)
	var center_xz := scaled_bounds.get_center()
	inst.position = Vector3(-center_xz.x, -scaled_bounds.position.y, -center_xz.z)


static func _compute_subtree_aabb(node: Node, parent_xf: Transform3D) -> AABB:
	var cur_xf := parent_xf
	if node is Node3D:
		cur_xf = parent_xf * (node as Node3D).transform
	var has_box := false
	var combined := AABB()
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var mbox := mi.mesh.get_aabb()
			for ix in [0.0, 1.0]:
				for iy in [0.0, 1.0]:
					for iz in [0.0, 1.0]:
						var corner := (
							mbox.position
							+ Vector3(mbox.size.x * ix, mbox.size.y * iy, mbox.size.z * iz)
						)
						var world_pt := cur_xf * corner
						if not has_box:
							combined = AABB(world_pt, Vector3.ZERO)
							has_box = true
						else:
							combined = combined.expand(world_pt)
	for c: Node in node.get_children():
		var child_box := _compute_subtree_aabb(c, cur_xf)
		if child_box.size.length_squared() > 0.000001:
			if not has_box:
				combined = child_box
				has_box = true
			else:
				combined = combined.merge(child_box)
	return combined


static func _build_procedural_plant(model_name: String) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(model_name)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match model_name:
		"Proc_Reeds":
			_proc_reeds(st, rng)
		"Proc_Kevar":
			_proc_kevar(st, rng, false)
		"Proc_Kevalu":
			_proc_kevar(st, rng, true)
		_:
			_proc_reeds(st, rng)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Proc"
	mesh.surface_set_material(0, mat)
	return mesh


static func _proc_blade(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	side: Vector3,
	w_bottom: float,
	w_top: float,
	c_bottom: Color,
	c_top: Color,
	out_dir: Vector3
) -> void:
	var n := (out_dir * 0.75 + Vector3.UP * 1.25).normalized()
	var pts: Array[Vector3] = [
		a - side * w_bottom,
		a + side * w_bottom,
		b + side * w_top,
		b - side * w_top,
	]
	var cols: Array[Color] = [c_bottom, c_bottom, c_top, c_top]
	var tri_order: Array[int] = [0, 1, 2, 0, 2, 3]
	for idx: int in tri_order:
		st.set_color(cols[idx])
		st.set_normal(n)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(pts[idx])


static func _proc_cross(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	w_bottom: float,
	w_top: float,
	c_bottom: Color,
	c_top: Color,
	rot: float
) -> void:
	var out_dir := (
		Vector3(a.x, 0.0, a.z).normalized()
		if Vector2(a.x, a.z).length() > 0.01
		else Vector3(cos(rot), 0.0, sin(rot))
	)
	for k in range(2):
		var ang := rot + float(k) * PI * 0.5
		var side := Vector3(cos(ang), 0.0, sin(ang))
		_proc_blade(st, a, b, side, w_bottom, w_top, c_bottom, c_top, out_dir)


static func _proc_reeds(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var base_c := Color(0.20, 0.34, 0.14)
	for _i in range(18):
		var ang := rng.randf() * TAU
		var r0 := sqrt(rng.randf()) * 0.26
		var base := Vector3(cos(ang) * r0, 0.0, sin(ang) * r0)
		var h := rng.randf_range(1.15, 1.85)
		var lean := rng.randf_range(0.08, 0.26)
		var tip := base + Vector3(cos(ang) * lean * h, h, sin(ang) * lean * h)
		var top_c := Color(0.38, 0.54, 0.22).lerp(Color(0.62, 0.56, 0.30), rng.randf() * 0.35)
		_proc_cross(st, base, tip, 0.024, 0.007, base_c, top_c, ang)
		if rng.randf() < 0.48:
			var c_a := base.lerp(tip, 0.72)
			var c_b := base.lerp(tip, 0.90)
			var brown := Color(0.28, 0.17, 0.10)
			_proc_cross(st, c_a, c_b, 0.036, 0.034, brown, brown.lightened(0.12), ang + 0.3)


static func _proc_kevar(st: SurfaceTool, rng: RandomNumberGenerator, is_kevalu: bool) -> void:
	var stem_dark := Color(0.26, 0.32, 0.34) if is_kevalu else Color(0.20, 0.36, 0.18)
	var stem_mid := Color(0.46, 0.54, 0.58) if is_kevalu else Color(0.34, 0.56, 0.28)
	for _i in range(28):
		var ang := rng.randf() * TAU
		var r0 := sqrt(rng.randf()) * 0.22
		var base := Vector3(cos(ang) * r0, 0.0, sin(ang) * r0)
		var lean := rng.randf_range(0.18, 0.52)
		var h := rng.randf_range(0.55, 0.92)
		var tip := base + Vector3(cos(ang) * lean * h, h, sin(ang) * lean * h)
		var mid := base.lerp(tip, 0.58)
		var blossom := (
			Color(0.66, 0.78, 0.86)
			if is_kevalu
			else Color(0.92, 0.88, 0.72).lerp(Color(0.46, 0.72, 0.42), rng.randf() * 0.45)
		)
		_proc_cross(st, base, mid, 0.018, 0.014, stem_dark, stem_mid, ang)
		_proc_cross(
			st, mid, tip, 0.044, 0.018, blossom.darkened(0.18), blossom.lightened(0.12), ang + 0.4
		)

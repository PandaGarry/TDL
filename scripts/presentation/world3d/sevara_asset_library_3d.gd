class_name SevaraAssetLibrary3D
extends RefCounted
## Loads, caches, normalizes, and styles 3D glTF/GLB assets (Quaternius CC0 Nature,
## Medieval Village, Animated Animals, Animated Characters) and custom Sevara shaders.

const NATURE_DIR := "res://assets/nature/"
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
		for candidate: String in [res_path, ProjectSettings.globalize_path(res_path)]:
			if FileAccess.file_exists(candidate):
				var img := Image.load_from_file(candidate)
				if img != null and not img.is_empty():
					img.generate_mipmaps()
					tex = ImageTexture.create_from_image(img)
					break
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
		for candidate: String in [res_path, ProjectSettings.globalize_path(res_path)]:
			if FileAccess.file_exists(candidate):
				var doc := GLTFDocument.new()
				var state := GLTFState.new()
				var err := doc.append_from_file(candidate, state)
				if err == OK:
					var root := doc.generate_scene(state)
					if root != null:
						packed = PackedScene.new()
						packed.pack(root)
						root.free()
						break
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
	var has_gltf := (
		ResourceLoader.exists(gltf_path)
		or FileAccess.file_exists(gltf_path)
		or FileAccess.file_exists(ProjectSettings.globalize_path(gltf_path))
	)
	var target_path := gltf_path if has_gltf else glb_path
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
	var segments := clampi(int(style.get("segments", 4)), 2, 4)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for _b in range(blade_count):
		var pos_ang := rng.randf() * TAU
		var pos_rad := sqrt(rng.randf()) * (patch_size * 0.5)
		var rx := cos(pos_ang) * pos_rad
		var rz := sin(pos_ang) * pos_rad
		var ang := rng.randf() * TAU
		var perp := Vector3(cos(ang), 0.0, sin(ang))
		var facing := Vector3(-sin(ang), 0.0, cos(ang))
		var lean := rng.randf_range(0.10, 0.28)
		var w := blade_width * rng.randf_range(0.75, 1.25)
		var rnd_col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var base_idx := verts.size()
		for s in range(segments):
			var t := float(s) / float(segments)
			var half_w := w * 0.5 * (1.0 - pow(t, 1.45))
			var arch := facing * (t * t * lean)
			for side in [-1.0, 1.0]:
				var side_f := float(side)
				verts.append(Vector3(rx, t, rz) + arch + perp * (side_f * half_w))
				normals.append(
					(Vector3.UP * 1.6 + facing * 0.4 + perp * (side_f * 0.25)).normalized()
				)
				uvs.append(Vector2(side_f * 0.5 + 0.5, t))
				colors.append(rnd_col)
		var tip_arch := facing * lean
		verts.append(Vector3(rx, 1.0, rz) + tip_arch)
		normals.append(Vector3.UP)
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
	mat.set_shader_parameter("root_color", style.get("root_color", Color(0.10, 0.21, 0.08)))
	mat.set_shader_parameter("tip_color", style.get("tip_color", Color(0.30, 0.48, 0.18)))
	mat.set_shader_parameter("tip_color_warm", style.get("tip_color_warm", Color(0.54, 0.54, 0.24)))
	mat.set_shader_parameter("blade_height", float(style.get("blade_height", 0.52)))
	mat.set_shader_parameter("wind_strength", float(style.get("wind_strength", 1.0)))
	mesh.surface_set_material(0, mat)
	_styled_meshes[key] = mesh
	return mesh


static func _bevel_subdivide_rock_arrays(src: ArrayMesh) -> Array:
	if src == null or src.get_surface_count() == 0:
		return []
	var arrays := src.surface_get_arrays(0)
	var in_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var in_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if in_idx.is_empty():
		in_idx.resize(in_v.size())
		for i in range(in_v.size()):
			in_idx[i] = i
	var mesh_center := Vector3.ZERO
	for v_pt: Vector3 in in_v:
		mesh_center += v_pt
	if not in_v.is_empty():
		mesh_center /= float(in_v.size())
	var n_sum: Dictionary = {}
	var c_sum: Dictionary = {}
	var c_cnt: Dictionary = {}
	var tri_cnt := int(in_idx.size() / 3.0)
	for t in range(tri_cnt):
		var a := in_v[in_idx[t * 3]]
		var b := in_v[in_idx[t * 3 + 1]]
		var c := in_v[in_idx[t * 3 + 2]]
		var fn := (c - a).cross(b - a).normalized()
		var fc := (a + b + c) / 3.0
		if fn.dot(fc - mesh_center) < 0.0:
			fn = -fn
		for p: Vector3 in [a, b, c]:
			var k := Vector3i((p * 200.0).round())
			n_sum[k] = (n_sum.get(k, Vector3.ZERO) as Vector3) + fn
			c_sum[k] = (c_sum.get(k, Vector3.ZERO) as Vector3) + fc
			c_cnt[k] = int(c_cnt.get(k, 0)) + 1
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()
	var out_idx := PackedInt32Array()
	for t in range(tri_cnt):
		var raw_pts: Array[Vector3] = [
			in_v[in_idx[t * 3]], in_v[in_idx[t * 3 + 1]], in_v[in_idx[t * 3 + 2]]
		]
		var fn := (raw_pts[2] - raw_pts[0]).cross(raw_pts[1] - raw_pts[0]).normalized()
		var fc := (raw_pts[0] + raw_pts[1] + raw_pts[2]) / 3.0
		if fn.dot(fc - mesh_center) < 0.0:
			fn = -fn
		var sm_p: Array[Vector3] = []
		var sm_n: Array[Vector3] = []
		for p: Vector3 in raw_pts:
			var k := Vector3i((p * 200.0).round())
			var sn := (n_sum.get(k, fn) as Vector3).normalized()
			var avg_c := (c_sum.get(k, p) as Vector3) / float(max(int(c_cnt.get(k, 1)), 1))
			sm_p.append(p.lerp(avg_c, 0.34))
			sm_n.append(sn)
		var m01 := (sm_p[0] + sm_p[1]) * 0.5 + (sm_n[0] + sm_n[1]).normalized() * 0.035
		var m12 := (sm_p[1] + sm_p[2]) * 0.5 + (sm_n[1] + sm_n[2]).normalized() * 0.035
		var m20 := (sm_p[2] + sm_p[0]) * 0.5 + (sm_n[2] + sm_n[0]).normalized() * 0.035
		var nm01 := (sm_n[0] + sm_n[1]).normalized()
		var nm12 := (sm_n[1] + sm_n[2]).normalized()
		var nm20 := (sm_n[2] + sm_n[0]).normalized()
		var sub_p: Array[Vector3] = [
			sm_p[0], m01, m20, m01, sm_p[1], m12, m20, m12, sm_p[2], m01, m12, m20
		]
		var sub_n: Array[Vector3] = [
			sm_n[0], nm01, nm20, nm01, sm_n[1], nm12, nm20, nm12, sm_n[2], nm01, nm12, nm20
		]
		for j in range(12):
			out_idx.append(out_v.size())
			out_v.append(sub_p[j])
			out_n.append((fn * 0.34 + sub_n[j] * 0.66).normalized())
			out_uv.append(Vector2(sub_p[j].x, sub_p[j].z) * 0.5)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out_v
	arr[Mesh.ARRAY_NORMAL] = out_n
	arr[Mesh.ARRAY_TEX_UV] = out_uv
	arr[Mesh.ARRAY_INDEX] = out_idx
	return arr


static func _get_bevel_rock_arrays(model_name: String) -> Array:
	var base_key := "BevelRockArr_" + model_name
	if _raw_meshes.has(base_key):
		return _raw_meshes[base_key] as Array
	var arr := _bevel_subdivide_rock_arrays(raw_nature_mesh(model_name))
	_raw_meshes[base_key] = arr
	return arr


static func build_bevel_smoothed_rock_mesh(model_name: String, style: Dictionary = {}) -> ArrayMesh:
	var key := "BevelRock_%s_%s" % [model_name, str(style)]
	if _styled_meshes.has(key):
		return _styled_meshes[key] as ArrayMesh
	var arr := _get_bevel_rock_arrays(model_name)
	if arr.is_empty():
		return ArrayMesh.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var rock_st: Dictionary = style.get("rock", {})
	var mat := ShaderMaterial.new()
	mat.shader = load_shader("sevara_rock_3d.gdshader")
	mat.set_shader_parameter("surface_mode", 0)
	mat.set_shader_parameter("albedo_tex", load_texture(NATURE_DIR + "Rocks_Diffuse.png"))
	for k: String in rock_st.keys():
		if k != "texture":
			mat.set_shader_parameter(k, rock_st[k])
	mesh.surface_set_material(0, mat)
	_styled_meshes[key] = mesh
	return mesh


static func build_rock_crown_moss_fur_mesh(model_name: String, seed_val: int) -> ArrayMesh:
	var key := "RockCrownFur_%s_%d" % [model_name, seed_val]
	if _styled_meshes.has(key):
		return _styled_meshes[key] as ArrayMesh
	var arrays := _get_bevel_rock_arrays(model_name)
	if arrays.is_empty():
		return ArrayMesh.new()
	var in_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var in_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var min_v_y := 999.0
	var max_v_y := -999.0
	for v: Vector3 in in_v:
		min_v_y = minf(min_v_y, v.y)
		max_v_y = maxf(max_v_y, v.y)
	var min_y := min_v_y + (max_v_y - min_v_y) * 0.46
	var top_tris: Array[int] = []
	var tri_cnt := int(in_v.size() / 3.0)
	for t in range(tri_cnt):
		var c_y := (in_v[t * 3].y + in_v[t * 3 + 1].y + in_v[t * 3 + 2].y) / 3.0
		var n_y := (in_n[t * 3].y + in_n[t * 3 + 1].y + in_n[t * 3 + 2].y) / 3.0
		if c_y >= min_y and n_y >= 0.42:
			top_tris.append(t)
	if top_tris.is_empty():
		return ArrayMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for _b in range(280):
		var t_idx := top_tris[rng.randi() % top_tris.size()]
		var r1 := sqrt(rng.randf())
		var r2 := rng.randf()
		var w0 := 1.0 - r1
		var w1 := r1 * (1.0 - r2)
		var w2 := r1 * r2
		var surf_n := (
			(in_n[t_idx * 3] * w0 + in_n[t_idx * 3 + 1] * w1 + in_n[t_idx * 3 + 2] * w2)
			. normalized()
		)
		var base_p := (
			in_v[t_idx * 3] * w0
			+ in_v[t_idx * 3 + 1] * w1
			+ in_v[t_idx * 3 + 2] * w2
			- surf_n * 0.025
		)
		var grow_dir := (surf_n * 0.52 + Vector3.UP * 0.68).normalized()
		var ang := rng.randf() * TAU
		var perp := Vector3(cos(ang), 0.0, sin(ang))
		var facing := grow_dir.cross(perp).normalized()
		var h := rng.randf_range(0.18, 0.34)
		var w := rng.randf_range(0.052, 0.088)
		var lean := rng.randf_range(0.05, 0.14)
		var rnd_col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var b_idx := verts.size()
		for s in range(2):
			var t := float(s) * 0.5
			var hw := w * 0.5 * (1.0 - t * 0.55)
			var p_mid := base_p + grow_dir * (t * h) + facing * (t * t * lean)
			for side in [-1.0, 1.0]:
				verts.append(p_mid + perp * (float(side) * hw))
				normals.append((grow_dir + facing * 0.25).normalized())
				uvs.append(Vector2(float(side) * 0.5 + 0.5, t))
				colors.append(rnd_col)
		verts.append(base_p + grow_dir * h + facing * lean)
		normals.append(grow_dir)
		uvs.append(Vector2(0.5, 1.0))
		colors.append(rnd_col)
		indices.append_array([b_idx, b_idx + 1, b_idx + 2, b_idx + 1, b_idx + 3, b_idx + 2])
		indices.append_array([b_idx + 2, b_idx + 3, b_idx + 4])
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
	mat.set_shader_parameter("surface_fur_mode", 1.0)
	mat.set_shader_parameter("root_color", Color(0.12, 0.24, 0.09))
	mat.set_shader_parameter("tip_color", Color(0.26, 0.43, 0.16))
	mat.set_shader_parameter("tip_color_warm", Color(0.38, 0.48, 0.19))
	mat.set_shader_parameter("blade_height", 0.28)
	mat.set_shader_parameter("wind_strength", 0.35)
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
	var out := ArrayMesh.new()
	for s in range(src.get_surface_count()):
		var mat := src.surface_get_material(s)
		var mname := mat.resource_name if mat != null else ""
		var arr := src.surface_get_arrays(s).duplicate(true)
		if mname in ["Leaves_NormalTree", "Leaves_TwistedTree"]:
			_unfold_crossed_leaf_quads(arr, _surface_aabb(src, s))
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if mat != null:
			out.surface_set_material(s, mat)
	return out


static func _unfold_crossed_leaf_quads(arr: Array, crown_box: AABB) -> void:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	if verts.size() < 4 or verts.size() % 4 != 0:
		return
	var c_center := crown_box.get_center()
	var c_ext := Vector3(
		maxf(crown_box.size.x * 0.5, 0.5),
		maxf(crown_box.size.y * 0.5, 0.5),
		maxf(crown_box.size.z * 0.5, 0.5)
	)
	var quad_count := verts.size() / 4
	for q in range(quad_count):
		var i0 := q * 4
		var qc := (verts[i0] + verts[i0 + 1] + verts[i0 + 2] + verts[i0 + 3]) * 0.25
		var dome_n := ((qc - c_center) / c_ext + Vector3(0.0, 0.42, 0.0)).normalized()
		var cur_n := (verts[i0 + 1] - verts[i0]).cross(verts[i0 + 3] - verts[i0]).normalized()
		if cur_n.length_squared() < 0.01:
			cur_n = dome_n
		elif cur_n.dot(dome_n) < 0.0:
			cur_n = -cur_n
		var ref_up := Vector3.FORWARD if absf(dome_n.y) > 0.92 else Vector3.UP
		var tang_u := ref_up.cross(dome_n).normalized()
		var tang_v := dome_n.cross(tang_u).normalized()
		var ang := float(q % 3) * 2.094395 + float(q / 3) * 0.618034
		var petal_dir := tang_u * cos(ang) + tang_v * sin(ang)
		var target_n := (dome_n + petal_dir * 0.40).normalized()
		var rot_q := Quaternion(cur_n, cur_n.slerp(target_n, 0.84).normalized())
		var shift := dome_n * (float((q % 3) - 1) * 0.16) + petal_dir * 0.12
		var card_sc := clampf(2.05 / maxf(verts[i0].distance_to(verts[i0 + 2]), 0.01), 0.72, 0.96)
		for k in range(4):
			verts[i0 + k] = qc + shift + (rot_q * (verts[i0 + k] - qc)) * card_sc
			if normals.size() > i0 + k:
				normals[i0 + k] = target_n
	arr[Mesh.ARRAY_VERTEX] = verts
	if normals.size() == verts.size():
		arr[Mesh.ARRAY_NORMAL] = normals


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
		var custom_tex := String(rock_st.get("texture", ""))
		var alb_file := "Rocks_Diffuse.png" if custom_tex.is_empty() else custom_tex
		mat.set_shader_parameter("albedo_tex", load_texture(NATURE_DIR + alb_file))
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
				var mname := orig.resource_name if orig != null else ""
				var raw_col := Color(0.62, 0.56, 0.48)
				var orig_tex: Texture2D = null
				if orig is BaseMaterial3D:
					raw_col = (orig as BaseMaterial3D).albedo_color
					orig_tex = (orig as BaseMaterial3D).albedo_texture
				var has_override := false
				for key: String in palette_overrides.keys():
					if mname == key or mname.to_lower().contains(key.to_lower()):
						raw_col = palette_overrides[key] as Color
						has_override = true
						break
				var styled_mat := _create_styled_surface_material(
					mname, raw_col, orig_tex, model_hint, has_override, apply_structural_textures
				)
				mi.set_surface_override_material(s, styled_mat)
	for child: Node in node.get_children():
		_enhance_materials_recursive(
			child, palette_overrides, apply_structural_textures, model_hint
		)


static func _make_arch_shader_material(
	stem: String,
	primary_col: Color,
	_secondary_col: Color,
	scale_val: float,
	_detail_mix_val: float,
	_nrm_strength: float,
	rough_val: float,
	metal_val: float = 0.0,
	moss_str: float = 0.45,
	_bevel_str: float = 0.24
) -> Material:
	var mode_map := {
		"pbr_cliff_rock": 0,
		"pbr_aged_timber": 1,
		"pbr_village_timber": 2,
		"pbr_roof_slate": 3,
		"pbr_cobble_masonry": 4,
		"pbr_lime_plaster": 5,
		"pbr_thatch_roof": 6,
		"pbr_clay_daub": 7,
		"pbr_wattle_weave": 8,
	}
	if mode_map.has(stem):
		var rmat := ShaderMaterial.new()
		rmat.shader = load_shader("sevara_rock_3d.gdshader")
		rmat.set_shader_parameter("surface_mode", int(mode_map[stem]))
		rmat.set_shader_parameter("tint", primary_col)
		rmat.set_shader_parameter("moss_amount", moss_str)
		rmat.set_shader_parameter("triplanar_scale", clampf(scale_val, 0.28, 1.25))
		return rmat
	var sm := StandardMaterial3D.new()
	sm.albedo_color = primary_col
	sm.roughness = rough_val
	sm.metallic = metal_val
	return sm


static func _make_creature_shader_material(
	base_col: Color,
	_under_col: Color,
	_rim_col: Color,
	rough_val: float,
	_rim_str: float = 0.28,
	_grain_str: float = 0.07,
	_h_span: float = 1.8
) -> Material:
	var sm := StandardMaterial3D.new()
	sm.albedo_color = base_col
	sm.roughness = rough_val
	return sm


static func _create_styled_surface_material(
	mname: String,
	raw_col: Color,
	orig_tex: Texture2D,
	model_hint: String,
	has_override: bool,
	apply_structural_textures: bool
) -> Material:
	var ml := mname.to_lower()
	if orig_tex != null:
		var tmat := StandardMaterial3D.new()
		tmat.albedo_texture = orig_tex
		tmat.albedo_color = raw_col
		tmat.roughness = 0.78
		return tmat
	var is_animal := (
		model_hint.contains("stag") or model_hint.contains("deer") or model_hint.contains("wolf")
	)
	var is_character := model_hint.contains("viking")
	var is_tent := model_hint.contains("tent")
	var is_fire_model := (
		model_hint.contains("torch")
		or model_hint.contains("bonfire")
		or model_hint.contains("fire")
	)
	if is_fire_model and (ml.contains("fire") or ml.contains("yellow") or ml.contains("orange")):
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.95, 0.45, 0.08)
		fmat.roughness = 0.35
		fmat.emission_enabled = true
		fmat.emission = Color(0.90, 0.34, 0.04)
		fmat.emission_energy_multiplier = 0.65
		return fmat
	if ml.contains("soup") or (model_hint.contains("cauldron") and ml.contains("orange")):
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.76, 0.42, 0.16)
		smat.roughness = 0.24
		return smat
	if ml.contains("window"):
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(1.0, 0.80, 0.34)
		wmat.roughness = 0.18
		wmat.emission_enabled = true
		wmat.emission = Color(1.0, 0.62, 0.16)
		wmat.emission_energy_multiplier = 1.42
		return wmat
	if ml.contains("eye") or ml.contains("nose") or ml.contains("face"):
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(0.11, 0.09, 0.08)
		emat.roughness = 0.22 if (ml.contains("eye") or ml.contains("face")) else 0.55
		return emat
	if ml.contains("hoov") or ml.contains("horn"):
		var h_col := raw_col.lerp(Color(0.32, 0.26, 0.20), 0.35)
		return _make_creature_shader_material(h_col, raw_col, raw_col, 0.52)
	if is_character or is_animal:
		var c_col := raw_col
		if is_character and ml.contains("skin"):
			c_col = raw_col if has_override else Color(0.46, 0.31, 0.22)
		elif is_character and ml.contains("hair"):
			c_col = raw_col if has_override else Color(0.18, 0.11, 0.07)
		elif not has_override:
			c_col = Color(
				clampf(pow(maxf(raw_col.r, 0.02), 0.67), 0.12, 0.90),
				clampf(pow(maxf(raw_col.g, 0.02), 0.67), 0.12, 0.90),
				clampf(pow(maxf(raw_col.b, 0.02), 0.67), 0.12, 0.90)
			)
		return _make_creature_shader_material(c_col, c_col, c_col, 0.74)
	if not apply_structural_textures:
		return _make_creature_shader_material(raw_col, raw_col, raw_col, 0.78)
	if ml.contains("roof") or (ml == "red" and not is_tent):
		var r_def := Color(0.46, 0.27, 0.19) if ml.contains("red") else Color(0.28, 0.31, 0.29)
		var r_pri := raw_col if has_override else r_def
		return _make_arch_shader_material("pbr_roof_slate", r_pri, r_pri, 0.48, 0.46, 0.85, 0.84)
	if ml.contains("plaster") or ml.contains("beige") or ml == "white":
		var w_col := raw_col if has_override else Color(0.64, 0.58, 0.48)
		return _make_arch_shader_material("pbr_lime_plaster", w_col, w_col, 0.42, 0.45, 0.65, 0.93)
	if ml.contains("stone") or ml.contains("grey") or ml.contains("gray"):
		var s_def := Color(0.48, 0.46, 0.42) if ml.contains("light") else Color(0.35, 0.34, 0.32)
		var s_pri := raw_col if has_override else s_def
		return _make_arch_shader_material("pbr_cobble_masonry", s_pri, s_pri, 0.46, 0.42, 0.78, 0.9)
	if ml.contains("metal") or ml.contains("steel") or ml.contains("gold"):
		var mmat := StandardMaterial3D.new()
		var g_col := Color(0.76, 0.62, 0.30)
		mmat.albedo_color = g_col if ml.contains("gold") else Color(0.18, 0.19, 0.21)
		mmat.metallic = 0.78
		mmat.roughness = 0.38
		return mmat
	if ml.contains("green") or ml.contains("pink") or is_tent:
		var tc := Color(0.58, 0.52, 0.40) if is_tent else Color(0.28, 0.44, 0.20)
		return _make_arch_shader_material("pbr_lime_plaster", tc, tc, 0.70, 0.4, 0.65, 0.84)
	var wp := Color(0.50, 0.38, 0.26)
	if ml.contains("hay"):
		wp = Color(0.62, 0.52, 0.28)
	elif ml.contains("side") or ml.contains("light"):
		wp = Color(0.60, 0.47, 0.33)
	elif ml.contains("dark"):
		wp = Color(0.38, 0.28, 0.19)
	return _make_arch_shader_material("pbr_village_timber", wp, wp, 0.48, 0.48, 0.75, 0.78)


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
	var n := (out_dir * 0.75 + Vector3.UP * 1.25).normalized()
	for k in range(2):
		var ang := rot + float(k) * PI * 0.5
		var side := Vector3(cos(ang), 0.0, sin(ang))
		var pts: Array[Vector3] = [
			a - side * w_bottom, a + side * w_bottom, b + side * w_top, b - side * w_top
		]
		var cols: Array[Color] = [c_bottom, c_bottom, c_top, c_top]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(cols[idx])
			st.set_normal(n)
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(pts[idx])


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
	var stem_dark := Color(0.10, 0.18, 0.18) if is_kevalu else Color(0.08, 0.17, 0.07)
	var stem_mid := Color(0.18, 0.28, 0.28) if is_kevalu else Color(0.15, 0.28, 0.11)
	for _i in range(18):
		var ang := rng.randf() * TAU
		var r0 := sqrt(rng.randf()) * 0.22
		var base := Vector3(cos(ang) * r0, 0.0, sin(ang) * r0)
		var lean := rng.randf_range(0.16, 0.42)
		var h := rng.randf_range(0.42, 0.68)
		var tip := base + Vector3(cos(ang) * lean * h, h, sin(ang) * lean * h)
		var mid := base.lerp(tip, 0.58)
		var blossom := (
			Color(0.22, 0.34, 0.38)
			if is_kevalu
			else Color(0.22, 0.34, 0.14).lerp(Color(0.38, 0.32, 0.14), rng.randf() * 0.55)
		)
		_proc_cross(st, base, mid, 0.014, 0.010, stem_dark, stem_mid, ang)
		_proc_cross(st, mid, tip, 0.022, 0.010, blossom.darkened(0.20), blossom, ang + 0.4)

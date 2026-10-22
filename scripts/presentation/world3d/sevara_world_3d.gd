class_name SevaraWorld3D
extends Node3D
## Complete 3D valley world for Sevara (160 x 120 m valley floor + distant mountain rings).
## Built from the ground up with CC0 glTF/GLB models, MultiMesh dense meadows,
## custom spatial shaders, smooth character locomotion, and scenic valley camera lookpoints.

const CAMERA_LOOKPOINTS: Array[String] = [
	"follow",
	"valley_panorama",
	"heravo_meadow",
	"nivarel_rapids",
	"settlement_hearth",
]

const NPC_WORLD_POSITIONS: Dictionary = {
	"npc_sarela": Vector2(-13.2, -6.2),
	"npc_tovan": Vector2(-3.8, -8.8),
	"npc_ilune": Vector2(-9.6, 5.4),
	"npc_mavena": Vector2(-6.4, 8.2),
	"npc_evaren": Vector2(4.2, -4.4),
	"npc_selima": Vector2(-9.2, -8.2),
	"npc_tobren": Vector2(-2.2, 11.4),
	"npc_ruvet": Vector2(-18.5, -16.2),
}

var _env_node: WorldEnvironment
var _environment: Environment
var _sun_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _camera_3d: Camera3D

var _mountains_root: Node3D
var _terrain_mesh_inst: MeshInstance3D
var _water_mesh_inst: MeshInstance3D
var _terrain_shader_mat: ShaderMaterial
var _water_shader_mat: ShaderMaterial
var _terrain_greybox_mat: StandardMaterial3D
var _water_greybox_mat: StandardMaterial3D

var _settlement_root: Node3D
var _meadow_multimesh_root: Node3D
var _ecology_root: Node3D
var _actors_root: Node3D
var _npcs_root: Node3D
var _crates_root: Node3D

var _actor_nodes: Dictionary = {}
var _actor_targets: Dictionary = {}
var _crate_nodes: Dictionary = {}

var _last_eco_signature: String = ""
var _camera_zoom_index: int = 1
var _camera_lookpoint: String = "follow"
var _focus_world_pos: Vector3 = Vector3(-15.6, 1.0, -8.6)
var _camera_target_pos: Vector3 = Vector3(-15.6, 13.2, 5.2)
var _camera_target_look: Vector3 = Vector3(-15.6, 1.0, -8.6)
var _built: bool = false


func _init() -> void:
	name = "SevaraWorld3D"
	_camera_3d = Camera3D.new()
	_camera_3d.name = "ValleyCamera3D"
	_camera_3d.fov = 38.0
	_camera_3d.near = 0.25
	_camera_3d.far = 650.0
	_camera_3d.current = true
	add_child(_camera_3d)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _built:
		return
	var dt := clampf(delta, 0.001, 0.1)
	var local_pos := _focus_world_pos
	for entity_id: int in _actor_nodes.keys():
		var node := _actor_nodes[entity_id] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var target: Vector3 = _actor_targets.get(entity_id, node.position)
		var diff := Vector3(target.x - node.position.x, 0.0, target.z - node.position.z)
		var dist := diff.length()
		if dist > 0.025:
			var step := minf(dist, maxf(dist * 9.5, 4.5) * dt)
			var dir := diff / dist
			var next_xz := Vector2(node.position.x + dir.x * step, node.position.z + dir.z * step)
			node.position = Vector3(
				next_xz.x, SevaraTerrainGen3D.get_height_at(next_xz.x, next_xz.y), next_xz.y
			)
			var desired_yaw := atan2(dir.x, dir.z)
			node.rotation.y = lerp_angle(node.rotation.y, desired_yaw, clampf(dt * 12.0, 0.0, 1.0))
			SevaraCreatures3D.set_human_motion_state(node, true, dist > 2.2)
		else:
			node.position = target
			SevaraCreatures3D.set_human_motion_state(node, false, false)
		if bool(node.get_meta("is_local_focus", false)):
			local_pos = node.position

	_update_grass_player_position(local_pos)
	if _camera_lookpoint == "follow" and _camera_3d != null:
		_focus_world_pos = _focus_world_pos.lerp(local_pos, clampf(dt * 8.5, 0.0, 1.0))
		_apply_camera_transform(false)


func ensure_built() -> void:
	if _built:
		return
	if DisplayServer.get_name() == "headless":
		return
	_built = true
	_build_environment_and_lights()
	_build_terrain_and_water()
	_build_containers()
	_populate_static_settlement()
	_apply_camera_transform(true)


func camera_3d() -> Camera3D:
	return _camera_3d


func current_lookpoint() -> String:
	return _camera_lookpoint


func cycle_camera_lookpoint() -> String:
	var idx := CAMERA_LOOKPOINTS.find(_camera_lookpoint)
	var next_idx := (idx + 1) % CAMERA_LOOKPOINTS.size()
	set_camera_lookpoint(CAMERA_LOOKPOINTS[next_idx])
	return _camera_lookpoint


func set_camera_lookpoint(lookpoint_id: String) -> void:
	ensure_built()
	if not CAMERA_LOOKPOINTS.has(lookpoint_id):
		_camera_lookpoint = "follow"
	else:
		_camera_lookpoint = lookpoint_id
	_apply_camera_transform(true)


func set_camera_preset(zoom_index: int, focus_tile: Vector2i) -> void:
	ensure_built()
	_camera_zoom_index = clampi(zoom_index, 0, 2)
	_camera_lookpoint = "follow"
	_focus_world_pos = _map_tile_to_valley_3d(focus_tile)
	_apply_camera_transform(true)


func focus_on_pixel_position(px_pos: Vector2, tile_size_px: float = 32.0) -> void:
	ensure_built()
	var safe_px := maxf(tile_size_px, 1.0)
	var fx := -18.5 + (px_pos.x / safe_px - 0.5) * 1.45
	var fz := -11.5 + (px_pos.y / safe_px - 0.5) * 1.45
	_focus_world_pos = Vector3(fx, SevaraTerrainGen3D.get_height_at(fx, fz), fz)
	if _camera_lookpoint == "follow":
		_apply_camera_transform(false)


func sync_from_session(session: GameSession) -> Dictionary:
	ensure_built()
	if not _built:
		return {"ok": true, "built": false}
	if (
		session == null
		or session.world_state() == null
		or not session.world_state().is_initialized()
	):
		clear_dynamic_nodes()
		return {"ok": false, "built": true}
	var status: Dictionary = session.session_status()
	if not bool(status.get("running", false)):
		clear_dynamic_nodes()
		return {"ok": false, "built": true}

	var world := session.world_state()
	var is_greybox := SevaraVisualTheme.is_greybox_mode()
	_apply_material_mode(is_greybox)

	var hour := world.clock().hour_of_day()
	var day_phase := "morning"
	if hour >= 11 and hour <= 15:
		day_phase = "noon"
	elif hour >= 16 and hour <= 20:
		day_phase = "dusk"
	elif hour >= 21 or hour <= 4:
		day_phase = "night"
	_apply_day_phase_lighting(day_phase, is_greybox)

	var p1_active := not SevaraEcoChain.find_basin_nodes(world).is_empty()
	var basin: Dictionary = SevaraEcoChain.basin_summary(world) if p1_active else {}
	var slope_node: Dictionary = basin.get(SevaraEcoChain.NODE_TORAMEK_SLOPE, {})
	var channel_node: Dictionary = basin.get(SevaraEcoChain.NODE_NIVAREL_CHANNEL, {})
	var wetland_node: Dictionary = basin.get(SevaraEcoChain.NODE_MULANE_WETLAND, {})
	var meadow_node: Dictionary = basin.get(SevaraEcoChain.NODE_HERAVO_MEADOW, {})
	var avg_silt := (
		(
			(
				float(channel_node.get("silt_load", 0.18))
				+ float(wetland_node.get("silt_load", 0.18))
			)
			* 0.5
		)
		if p1_active
		else 0.16
	)
	var kevalu_wild := (
		bool(channel_node.get("kevalu_wild_spread", false))
		or int(wetland_node.get("kevalu_loci", 0)) > 0
		or avg_silt >= 0.48
	)

	if _terrain_shader_mat != null:
		_terrain_shader_mat.set_shader_parameter("silt_stain", clampf(avg_silt, 0.0, 1.0))
	if _water_shader_mat != null:
		_water_shader_mat.set_shader_parameter("silt_load", clampf(avg_silt, 0.0, 1.0))

	var canopy_q := int(round(float(slope_node.get("torava_canopy", 0.82)) * 10.0))
	var herb_q := int(round(float(meadow_node.get("heruna_grazers", 0.72)) * 10.0))
	var scav_q := int(round(float(meadow_node.get("karune_predators", 0.25)) * 10.0))
	var gfx: Dictionary = SettingsManager.graphics_profile()
	var fol_dens := float(gfx.get("foliage_density", 1.0))
	var eco_sig := (
		"%s|%d|%s|%d|%d|%d|%.2f"
		% [
			str(p1_active),
			int(avg_silt * 20.0),
			str(kevalu_wild),
			canopy_q,
			herb_q,
			scav_q,
			fol_dens,
		]
	)
	if eco_sig != _last_eco_signature:
		_last_eco_signature = eco_sig
		_rebuild_ecology_and_npcs(world, p1_active, basin, kevalu_wild, fol_dens)

	var local_body_entity_id := int(status.get("local_body_entity_id", -1))
	_sync_entities_from_world(world, session, local_body_entity_id)
	return {"ok": true, "built": true, "lookpoint": _camera_lookpoint}


func clear_dynamic_nodes() -> void:
	for id_key: int in _actor_nodes.keys():
		var n := _actor_nodes[id_key] as Node3D
		if n != null and is_instance_valid(n):
			n.free()
	_actor_nodes.clear()
	_actor_targets.clear()
	for cid: int in _crate_nodes.keys():
		var cn := _crate_nodes[cid] as Node3D
		if cn != null and is_instance_valid(cn):
			cn.free()
	_crate_nodes.clear()


func _build_environment_and_lights() -> void:
	_env_node = WorldEnvironment.new()
	_env_node.name = "WorldEnvironment3D"
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.50, 0.72)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.86)
	sky_mat.ground_bottom_color = Color(0.18, 0.24, 0.20)
	sky_mat.ground_horizon_color = Color(0.58, 0.68, 0.74)
	sky_mat.sun_angle_max = 28.0
	sky.sky_material = sky_mat
	_environment.sky = sky

	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_color = Color(0.56, 0.66, 0.76)
	_environment.ambient_light_sky_contribution = 0.55
	_environment.ambient_light_energy = 0.72
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 0.96
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.62, 0.74, 0.86)
	_environment.fog_light_energy = 0.42
	_environment.fog_density = 0.00085
	_environment.fog_sky_affect = 0.15
	_environment.glow_enabled = false
	_env_node.environment = _environment
	add_child(_env_node)

	_sun_light = DirectionalLight3D.new()
	_sun_light.name = "SunDirectionalLight3D"
	_sun_light.rotation_degrees = Vector3(-44.0, -34.0, 0.0)
	_sun_light.light_color = Color(1.0, 0.95, 0.86)
	_sun_light.light_energy = 1.12
	_sun_light.shadow_enabled = true
	_sun_light.shadow_opacity = 0.72
	_sun_light.shadow_blur = 1.25
	_sun_light.directional_shadow_max_distance = 140.0
	add_child(_sun_light)

	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "SkyFillLight3D"
	_fill_light.rotation_degrees = Vector3(-52.0, 145.0, 0.0)
	_fill_light.light_color = Color(0.58, 0.72, 0.88)
	_fill_light.light_energy = 0.28
	_fill_light.shadow_enabled = false
	add_child(_fill_light)

	if _camera_3d == null:
		_camera_3d = Camera3D.new()
		_camera_3d.name = "ValleyCamera3D"
		_camera_3d.fov = 38.0
		_camera_3d.near = 0.25
		_camera_3d.far = 650.0
		_camera_3d.current = true
		add_child(_camera_3d)


func _build_terrain_and_water() -> void:
	_mountains_root = SevaraTerrainGen3D.build_mountain_rings()
	add_child(_mountains_root)

	_terrain_mesh_inst = MeshInstance3D.new()
	_terrain_mesh_inst.name = "ValleyTerrain3D"
	_terrain_mesh_inst.mesh = SevaraTerrainGen3D.build_terrain_mesh(32, 24, 160, 120)

	var t_shader := SevaraAssetLibrary3D.load_shader("sevara_terrain_3d.gdshader")
	_terrain_shader_mat = ShaderMaterial.new()
	_terrain_shader_mat.shader = t_shader
	_terrain_shader_mat.set_shader_parameter(
		"tex_meadow", SevaraVisualTheme.load_diffuse_texture("tex_meadow_moss_and_snow")
	)
	_terrain_shader_mat.set_shader_parameter(
		"tex_meadow_normal", SevaraVisualTheme.load_normal_texture("tex_meadow_moss_and_snow")
	)
	_terrain_shader_mat.set_shader_parameter(
		"tex_mud", SevaraVisualTheme.load_diffuse_texture("tex_spring_mud_and_silt")
	)
	_terrain_shader_mat.set_shader_parameter(
		"tex_mud_normal", SevaraVisualTheme.load_normal_texture("tex_spring_mud_and_silt")
	)
	_terrain_shader_mat.set_shader_parameter(
		"tex_pebbles", SevaraVisualTheme.load_diffuse_texture("tex_riverbed_pebbles")
	)
	_terrain_shader_mat.set_shader_parameter(
		"tex_pebbles_normal", SevaraVisualTheme.load_normal_texture("tex_riverbed_pebbles")
	)
	_terrain_shader_mat.set_shader_parameter(
		"tex_stone",
		SevaraAssetLibrary3D.load_texture(SevaraAssetLibrary3D.NATURE_DIR + "Rocks_Diffuse.png")
	)
	_terrain_shader_mat.set_shader_parameter(
		"tex_stone_normal", SevaraVisualTheme.load_normal_texture("tex_riverbed_pebbles")
	)

	_terrain_greybox_mat = StandardMaterial3D.new()
	_terrain_greybox_mat.albedo_color = Color(0.32, 0.36, 0.34)
	_terrain_greybox_mat.roughness = 0.92
	_terrain_mesh_inst.material_override = _terrain_shader_mat
	add_child(_terrain_mesh_inst)

	_water_mesh_inst = MeshInstance3D.new()
	_water_mesh_inst.name = "NivarelWater3D"
	_water_mesh_inst.mesh = SevaraTerrainGen3D.build_water_mesh(32, 24, 128, 96)
	_water_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var w_shader := SevaraAssetLibrary3D.load_shader("sevara_water_3d.gdshader")
	_water_shader_mat = ShaderMaterial.new()
	_water_shader_mat.shader = w_shader
	_water_greybox_mat = StandardMaterial3D.new()
	_water_greybox_mat.albedo_color = Color(0.18, 0.34, 0.44, 0.82)
	_water_greybox_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_greybox_mat.roughness = 0.25
	_water_mesh_inst.material_override = _water_shader_mat
	add_child(_water_mesh_inst)


func _build_containers() -> void:
	_settlement_root = Node3D.new()
	_settlement_root.name = "SettlementStructures3D"
	add_child(_settlement_root)

	_meadow_multimesh_root = Node3D.new()
	_meadow_multimesh_root.name = "MeadowMultiMeshContainer3D"
	add_child(_meadow_multimesh_root)

	_ecology_root = Node3D.new()
	_ecology_root.name = "EcologyAndFlora3D"
	add_child(_ecology_root)

	_npcs_root = Node3D.new()
	_npcs_root.name = "SettlementNpcs3D"
	add_child(_npcs_root)

	_crates_root = Node3D.new()
	_crates_root.name = "SupplyCrates3D"
	add_child(_crates_root)

	_actors_root = Node3D.new()
	_actors_root.name = "Actors3D"
	add_child(_actors_root)


func _populate_static_settlement() -> void:
	SevaraPropsFactory3D.populate_static_settlement(_settlement_root)


func _rebuild_ecology_and_npcs(
	world: WorldState,
	p1_active: bool,
	basin: Dictionary,
	any_kevalu_wild: bool,
	foliage_density: float
) -> void:
	for child: Node in _meadow_multimesh_root.get_children():
		child.free()
	for child: Node in _ecology_root.get_children():
		child.free()
	for child: Node in _npcs_root.get_children():
		child.free()

	var mm_bundle := SevaraPropsFactory3D.build_dense_meadow_multimeshes(foliage_density)
	_meadow_multimesh_root.add_child(mm_bundle)

	var slope_node: Dictionary = basin.get(SevaraEcoChain.NODE_TORAMEK_SLOPE, {})
	var meadow_node: Dictionary = basin.get(SevaraEcoChain.NODE_HERAVO_MEADOW, {})
	var canopy := float(slope_node.get("torava_canopy", 0.85)) if p1_active else 0.85
	var herb_pop := float(meadow_node.get("heruna_grazers", 0.72)) if p1_active else 0.72
	var scav_press := float(meadow_node.get("karune_predators", 0.22)) if p1_active else 0.22

	var tree_coords: Array[Vector2] = [
		Vector2(-34.0, -28.0),
		Vector2(-28.0, -32.0),
		Vector2(-21.0, -29.0),
		Vector2(-14.0, -31.0),
		Vector2(-38.0, -19.0),
		Vector2(-31.0, -21.0),
		Vector2(-25.0, -22.0),
		Vector2(-17.5, -23.5),
		Vector2(-10.5, -24.0),
		Vector2(-4.5, -26.0),
		Vector2(3.5, -28.0),
		Vector2(11.0, -26.5),
		Vector2(-35.0, -11.0),
		Vector2(-28.5, -14.5),
		Vector2(-22.5, -17.5),
		Vector2(-15.0, -19.0),
		Vector2(-7.8, -18.5),
		Vector2(8.5, -21.0),
		Vector2(16.5, -22.5),
		Vector2(24.5, -24.0),
		Vector2(-36.0, -2.0),
		Vector2(-31.0, 5.5),
		Vector2(-27.0, 13.5),
		Vector2(-22.0, 21.0),
		Vector2(-15.5, 26.5),
		Vector2(-8.5, 31.0),
		Vector2(22.0, -14.5),
		Vector2(29.5, -17.0),
		Vector2(36.0, -11.5),
		Vector2(32.5, -3.5),
		Vector2(38.5, 4.5),
		Vector2(34.0, 14.0),
		Vector2(28.5, 22.5),
		Vector2(21.5, 28.0),
		Vector2(-46.0, -26.0),
		Vector2(-48.0, -12.0),
		Vector2(-44.0, 8.0),
		Vector2(-38.0, 24.0),
		Vector2(44.0, -22.0),
		Vector2(48.0, -6.0),
		Vector2(45.0, 12.0),
		Vector2(39.0, 26.0),
		Vector2(-18.0, -38.0),
		Vector2(-6.0, -39.0),
		Vector2(8.0, -37.0),
		Vector2(22.0, -35.0),
	]
	for i in range(tree_coords.size()):
		var tc: Vector2 = tree_coords[i]
		var is_toramek := tc.x < -4.0 and tc.y < -12.0
		var felled := is_toramek and (float(i % 8) / 8.0) > canopy
		var tree := SevaraPropsFactory3D.create_tree_3d(i, felled)
		tree.position = Vector3(tc.x, SevaraTerrainGen3D.get_height_at(tc.x, tc.y) - 0.06, tc.y)
		_ecology_root.add_child(tree)

	var rock_specs: Array[Dictionary] = [
		{"pos": Vector2(-26.5, -24.5), "sc": Vector3(1.8, 1.5, 1.7), "moss": true},
		{"pos": Vector2(-18.5, -26.0), "sc": Vector3(2.2, 1.8, 1.9), "moss": true},
		{"pos": Vector2(-9.5, -21.5), "sc": Vector3(1.6, 1.3, 1.5), "moss": true},
		{"pos": Vector2(-2.2, -16.5), "sc": Vector3(1.3, 0.9, 1.2), "moss": false},
		{"pos": Vector2(2.8, -11.5), "sc": Vector3(1.2, 0.85, 1.1), "moss": false},
		{"pos": Vector2(-1.8, -1.2), "sc": Vector3(1.1, 0.75, 1.0), "moss": false},
		{"pos": Vector2(4.2, 3.4), "sc": Vector3(1.35, 0.95, 1.25), "moss": true},
		{"pos": Vector2(7.8, 11.2), "sc": Vector3(1.5, 1.05, 1.4), "moss": true},
		{"pos": Vector2(19.5, -8.5), "sc": Vector3(1.4, 1.1, 1.3), "moss": true},
		{"pos": Vector2(27.5, 6.5), "sc": Vector3(1.9, 1.4, 1.7), "moss": true},
		{"pos": Vector2(-29.5, 2.5), "sc": Vector3(1.7, 1.3, 1.6), "moss": true},
		{"pos": Vector2(-12.5, 18.5), "sc": Vector3(1.5, 1.1, 1.4), "moss": true},
	]
	for r_idx in range(rock_specs.size()):
		var rs: Dictionary = rock_specs[r_idx]
		var rp: Vector2 = rs["pos"]
		var boulder := SevaraPropsFactory3D.create_boulder_3d(rs["sc"] as Vector3, bool(rs["moss"]))
		boulder.position = Vector3(rp.x, SevaraTerrainGen3D.get_height_at(rp.x, rp.y) - 0.08, rp.y)
		boulder.rotation.y = float(r_idx) * 1.15
		_ecology_root.add_child(boulder)

	var reed_coords: Array[Vector2] = [
		Vector2(-3.2, 6.5),
		Vector2(-5.8, 9.8),
		Vector2(-8.4, 12.5),
		Vector2(-6.2, 16.2),
		Vector2(-2.4, 14.8),
		Vector2(1.8, 9.2),
		Vector2(5.2, 13.8),
		Vector2(8.4, 17.5),
		Vector2(3.4, 20.5),
		Vector2(-4.5, 21.2),
		Vector2(10.2, 23.5),
		Vector2(6.5, 26.0),
	]
	for ri in range(reed_coords.size()):
		var rc: Vector2 = reed_coords[ri]
		var reed := SevaraPropsFactory3D.create_reed_clump_3d(ri)
		reed.position = Vector3(rc.x, SevaraTerrainGen3D.get_height_at(rc.x, rc.y) - 0.05, rc.y)
		_ecology_root.add_child(reed)

	var willow_coords: Array[Vector2] = [
		Vector2(-8.8, 8.2),
		Vector2(9.6, 5.4),
		Vector2(-7.8, 16.5),
		Vector2(8.4, 15.2),
		Vector2(-3.8, 24.0),
		Vector2(12.2, 21.5),
	]
	for wi in range(willow_coords.size()):
		var wc: Vector2 = willow_coords[wi]
		var willow := SevaraPropsFactory3D.create_talina_willow_3d(wi)
		willow.position = Vector3(wc.x, SevaraTerrainGen3D.get_height_at(wc.x, wc.y) - 0.06, wc.y)
		_ecology_root.add_child(willow)

	var lily_coords: Array[Vector2] = [
		Vector2(-5.2, 11.2),
		Vector2(-3.8, 13.6),
		Vector2(2.4, 11.4),
		Vector2(4.2, 15.2),
		Vector2(1.2, 18.8),
	]
	for li in range(lily_coords.size()):
		var lc: Vector2 = lily_coords[li]
		var lily := SevaraAssetLibrary3D.instantiate_model(
			SevaraAssetLibrary3D.NATURE_DIR + "Lilypad.glb", 0.22, {}, false
		)
		lily.position = Vector3(lc.x, SevaraTerrainGen3D.WATER_SURFACE_Y + 0.01, lc.y)
		lily.rotation.y = float(li) * 1.37
		_ecology_root.add_child(lily)

	var kevar_coords: Array[Vector2] = [
		Vector2(-6.8, 7.8),
		Vector2(-4.2, 11.4),
		Vector2(-1.2, 13.2),
		Vector2(2.6, 11.8),
		Vector2(6.4, 10.2),
		Vector2(9.2, 14.5),
		Vector2(12.4, 8.6),
		Vector2(-9.2, 14.2),
	]
	for ki in range(kevar_coords.size()):
		var kc: Vector2 = kevar_coords[ki]
		var is_kv := any_kevalu_wild and (ki % 2 == 1)
		var kb := SevaraPropsFactory3D.create_kevar_bush_3d(is_kv)
		kb.position = Vector3(kc.x, SevaraTerrainGen3D.get_height_at(kc.x, kc.y) - 0.02, kc.y)
		kb.rotation.y = float(ki) * 0.95
		_ecology_root.add_child(kb)

	var deer_spots: Array[Dictionary] = [
		{"pos": Vector2(11.5, -2.4), "rot": -0.65, "graze": true},
		{"pos": Vector2(14.8, 1.2), "rot": -1.15, "graze": true},
		{"pos": Vector2(17.2, -4.8), "rot": 0.45, "graze": false},
		{"pos": Vector2(21.4, 3.6), "rot": -0.85, "graze": true},
		{"pos": Vector2(13.2, 7.8), "rot": -1.45, "graze": true},
		{"pos": Vector2(24.5, -1.8), "rot": -0.35, "graze": false},
	]
	var deer_count := clampi(int(round(herb_pop * 6.0)), 2, 6)
	for di in range(deer_count):
		var ds: Dictionary = deer_spots[di]
		var dp: Vector2 = ds["pos"]
		var stag := SevaraCreatures3D.create_tal_har_stag_3d(bool(ds["graze"]), di)
		stag.position = Vector3(dp.x, SevaraTerrainGen3D.get_height_at(dp.x, dp.y), dp.y)
		stag.rotation.y = float(ds["rot"])
		_ecology_root.add_child(stag)

	var canid_spots: Array[Dictionary] = [
		{"pos": Vector2(8.8, -11.5), "rot": 0.55},
		{"pos": Vector2(19.2, -12.4), "rot": -0.45},
		{"pos": Vector2(-5.5, 17.5), "rot": 1.25},
	]
	var canid_count := 3 if (scav_press >= 0.40 or any_kevalu_wild) else 2
	for ci in range(canid_count):
		var cs: Dictionary = canid_spots[ci]
		var cp: Vector2 = cs["pos"]
		var canid := SevaraCreatures3D.create_kor_varn_canid_3d(true, ci)
		canid.position = Vector3(cp.x, SevaraTerrainGen3D.get_height_at(cp.x, cp.y), cp.y)
		canid.rotation.y = float(cs["rot"])
		_ecology_root.add_child(canid)

	var npc_roster: Array[Dictionary] = SevaraP1Npcs.npcs_summary(world)
	var idx := 0
	for npc: Dictionary in npc_roster:
		var npc_id := String(npc.get("npc_id", ""))
		var wpos2: Vector2 = NPC_WORLD_POSITIONS.get(
			npc_id, Vector2(-12.0 + float(idx) * 2.2, -6.0)
		)
		var palette := _npc_palette_for_id(npc_id, idx)
		var fig := SevaraCreatures3D.create_human_figure_3d(
			palette["cloak"] as Color,
			palette["tunic"] as Color,
			false,
			bool(palette["pack"]),
			bool(palette["satchel"]),
			bool(palette["staff"]),
			false,
			npc_id
		)
		fig.name = "Npc3D_%s" % npc_id
		fig.position = Vector3(wpos2.x, SevaraTerrainGen3D.get_height_at(wpos2.x, wpos2.y), wpos2.y)
		fig.rotation.y = sin(float(idx) * 1.7) * 0.85
		_npcs_root.add_child(fig)
		idx += 1


func _sync_entities_from_world(
	world: WorldState, session: GameSession, local_body_entity_id: int
) -> void:
	var active_actors: Dictionary = {}
	var active_crates: Dictionary = {}
	var local_tile := Vector2i(-1, -1)
	if local_body_entity_id > 0 and world.has_entity(local_body_entity_id):
		var lpos := world.get_entity_component(
			local_body_entity_id, GreyboxWorld.POSITION_COMPONENT
		)
		local_tile = GreyboxWorld.position_from_component(
			lpos, session.greybox_width_tiles, session.greybox_height_tiles
		)

	for entity_id: int in world.entity_ids():
		var entity: Dictionary = world.get_entity(entity_id)
		var def_id := String(entity.get("definition_id", ""))
		if def_id == GreyboxWorld.BODY_DEFINITION_ID:
			active_actors[entity_id] = true
			var body_comp := world.get_entity_component(entity_id, GreyboxWorld.BODY_COMPONENT)
			var pos_comp := world.get_entity_component(entity_id, GreyboxWorld.POSITION_COMPONENT)
			var tile := GreyboxWorld.position_from_component(
				pos_comp, session.greybox_width_tiles, session.greybox_height_tiles
			)
			var participant_id := String(body_comp.get("participant_id", ""))
			var is_local := entity_id == local_body_entity_id
			var vitals: Dictionary = world.get_entity_component(
				entity_id, BodyVitals.VITALS_COMPONENT
			)
			var has_fever := float(vitals.get("waterborne_malaise", 0.0)) >= 0.35
			var target_pos3 := _map_tile_to_valley_3d(tile)

			var fig := _actor_nodes.get(entity_id, null) as Node3D
			var rebuild_sig := "%s|%s|%s" % [participant_id, str(is_local), str(has_fever)]
			if (
				fig == null
				or not is_instance_valid(fig)
				or String(fig.get_meta("sig", "")) != rebuild_sig
			):
				if fig != null and is_instance_valid(fig):
					fig.free()
				var cloak := Color(0.20, 0.38, 0.54) if is_local else Color(0.24, 0.44, 0.34)
				var tunic := Color(0.48, 0.40, 0.30) if is_local else Color(0.44, 0.38, 0.30)
				fig = SevaraCreatures3D.create_human_figure_3d(
					cloak,
					tunic,
					is_local,
					true,
					true,
					true,
					has_fever,
					"hero_local" if is_local else "hero_coop"
				)
				fig.set_meta("sig", rebuild_sig)
				fig.set_meta("is_local_focus", is_local)
				fig.position = target_pos3
				_actors_root.add_child(fig)
				_actor_nodes[entity_id] = fig

			_actor_targets[entity_id] = target_pos3
			if is_local:
				_focus_world_pos = target_pos3
				if _camera_lookpoint == "follow":
					_apply_camera_transform(false)

		elif def_id == GreyboxWorld.OBJECT_DEFINITION_ID:
			active_crates[entity_id] = true
			var crate_comp := world.get_entity_component(
				entity_id, GreyboxWorld.CONTAINER_COMPONENT
			)
			var pos_comp := world.get_entity_component(entity_id, GreyboxWorld.POSITION_COMPONENT)
			var tile := GreyboxWorld.position_from_component(
				pos_comp, session.greybox_width_tiles, session.greybox_height_tiles
			)
			var rem := int(GreyboxWorld.integral_value(crate_comp.get("count", 0)).get("value", 0))
			var mx := GreyboxWorld.DEFAULT_CONTAINER_COUNT
			var adj := (
				local_tile.x >= 0
				and (absi(local_tile.x - tile.x) + absi(local_tile.y - tile.y)) <= 1
			)
			var sig := "%d|%d|%s" % [rem, mx, str(adj)]
			var crate_node := _crate_nodes.get(entity_id, null) as Node3D
			if (
				crate_node == null
				or not is_instance_valid(crate_node)
				or String(crate_node.get_meta("sig", "")) != sig
			):
				if crate_node != null and is_instance_valid(crate_node):
					crate_node.free()
				crate_node = SevaraPropsFactory3D.create_supply_crate_3d(rem, mx, adj)
				crate_node.set_meta("sig", sig)
				_crates_root.add_child(crate_node)
				_crate_nodes[entity_id] = crate_node
			crate_node.position = _map_tile_to_valley_3d(tile)

	var stale_actors: Array[int] = []
	for existing_id: int in _actor_nodes.keys():
		if not active_actors.has(existing_id):
			stale_actors.append(existing_id)
	for stale_id: int in stale_actors:
		var node := _actor_nodes[stale_id] as Node3D
		if node != null and is_instance_valid(node):
			node.free()
		_actor_nodes.erase(stale_id)
		_actor_targets.erase(stale_id)

	var stale_crates: Array[int] = []
	for existing_id: int in _crate_nodes.keys():
		if not active_crates.has(existing_id):
			stale_crates.append(existing_id)
	for stale_id: int in stale_crates:
		var node := _crate_nodes[stale_id] as Node3D
		if node != null and is_instance_valid(node):
			node.free()
		_crate_nodes.erase(stale_id)


func _map_tile_to_valley_3d(tile: Vector2i) -> Vector3:
	var wx := -18.5 + float(tile.x) * 1.45
	var wz := -11.5 + float(tile.y) * 1.45
	var wy := SevaraTerrainGen3D.get_height_at(wx, wz)
	return Vector3(wx, wy, wz)


func _update_grass_player_position(pos: Vector3) -> void:
	if _meadow_multimesh_root == null or _meadow_multimesh_root.get_child_count() == 0:
		return
	var bundle := _meadow_multimesh_root.get_child(0)
	if bundle == null:
		return
	var carpet := bundle.get_node_or_null("GrassBladeCarpetMM") as MultiMeshInstance3D
	if carpet != null and carpet.multimesh != null and carpet.multimesh.mesh != null:
		var mat := carpet.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("player_pos", pos)


func _apply_camera_transform(immediate: bool = false) -> void:
	if _camera_3d == null:
		return
	var cam_pos := Vector3.ZERO
	var look_target := Vector3.ZERO
	var fov := 38.0

	match _camera_lookpoint:
		"valley_panorama":
			cam_pos = Vector3(-2.5, 22.0, 32.5)
			look_target = Vector3(-1.5, 1.2, -5.5)
			fov = 44.0
		"heravo_meadow":
			cam_pos = Vector3(24.5, 5.2, 14.5)
			look_target = Vector3(9.5, 1.1, -2.5)
			fov = 37.0
		"nivarel_rapids":
			cam_pos = Vector3(10.5, 7.4, 7.5)
			look_target = Vector3(-3.5, 1.0, -9.5)
			fov = 38.0
		"settlement_hearth":
			cam_pos = Vector3(-5.8, 7.2, 2.8)
			look_target = Vector3(-14.5, 1.2, -7.8)
			fov = 36.0
		_:
			var offset := Vector3(0.0, 12.2, 13.8)
			fov = 38.0
			if _camera_zoom_index == 0:
				offset = Vector3(0.0, 20.5, 22.0)
				fov = 42.0
			elif _camera_zoom_index == 2:
				offset = Vector3(0.0, 6.2, 8.2)
				fov = 34.0
			cam_pos = _focus_world_pos + offset
			look_target = _focus_world_pos + Vector3(0.0, 0.85, -0.8)

	_camera_3d.fov = fov
	if immediate:
		_camera_target_pos = cam_pos
		_camera_target_look = look_target
	else:
		_camera_target_pos = _camera_target_pos.lerp(cam_pos, 0.25)
		_camera_target_look = _camera_target_look.lerp(look_target, 0.25)

	if is_inside_tree():
		_camera_3d.look_at_from_position(_camera_target_pos, _camera_target_look, Vector3.UP)
	else:
		_camera_3d.position = _camera_target_pos
		var forward := (_camera_target_look - _camera_target_pos).normalized()
		if forward.length_squared() > 0.001:
			_camera_3d.basis = Basis.looking_at(forward, Vector3.UP)


func _apply_material_mode(is_greybox: bool) -> void:
	if _terrain_mesh_inst != null:
		_terrain_mesh_inst.material_override = (
			_terrain_greybox_mat if is_greybox else _terrain_shader_mat
		)
	if _water_mesh_inst != null:
		_water_mesh_inst.material_override = (
			_water_greybox_mat if is_greybox else _water_shader_mat
		)


func _apply_day_phase_lighting(day_phase: String, is_greybox: bool) -> void:
	if _sun_light == null or _environment == null:
		return
	if is_greybox:
		_sun_light.light_color = Color(0.90, 0.92, 0.95)
		_sun_light.light_energy = 1.05
		return
	match day_phase:
		"noon":
			_sun_light.light_color = Color(1.0, 0.97, 0.90)
			_sun_light.light_energy = 1.18
			_sun_light.rotation_degrees = Vector3(-56.0, -26.0, 0.0)
		"dusk":
			_sun_light.light_color = Color(1.0, 0.76, 0.54)
			_sun_light.light_energy = 1.02
			_sun_light.rotation_degrees = Vector3(-30.0, -46.0, 0.0)
		"night":
			_sun_light.light_color = Color(0.45, 0.58, 0.82)
			_sun_light.light_energy = 0.52
			_sun_light.rotation_degrees = Vector3(-38.0, 25.0, 0.0)
		_:
			_sun_light.light_color = Color(1.0, 0.95, 0.86)
			_sun_light.light_energy = 1.12
			_sun_light.rotation_degrees = Vector3(-44.0, -34.0, 0.0)


func _npc_palette_for_id(npc_id: String, idx: int) -> Dictionary:
	match npc_id:
		"npc_sarela":
			return {
				"cloak": Color(0.24, 0.44, 0.30),
				"tunic": Color(0.48, 0.42, 0.32),
				"pack": false,
				"satchel": true,
				"staff": false,
			}
		"npc_tovan":
			return {
				"cloak": Color(0.46, 0.34, 0.22),
				"tunic": Color(0.36, 0.38, 0.40),
				"pack": true,
				"satchel": false,
				"staff": true,
			}
		"npc_selima":
			return {
				"cloak": Color(0.54, 0.28, 0.24),
				"tunic": Color(0.56, 0.50, 0.40),
				"pack": false,
				"satchel": true,
				"staff": false,
			}
		"npc_evaren":
			return {
				"cloak": Color(0.28, 0.38, 0.26),
				"tunic": Color(0.42, 0.34, 0.26),
				"pack": true,
				"satchel": true,
				"staff": true,
			}
		_:
			var c_base := Color(0.30, 0.36, 0.44).lerp(
				Color(0.48, 0.38, 0.28), float(idx % 4) / 3.0
			)
			return {
				"cloak": c_base,
				"tunic": Color(0.46, 0.42, 0.36),
				"pack": idx % 2 == 0,
				"satchel": idx % 2 == 1,
				"staff": idx % 3 == 0,
			}

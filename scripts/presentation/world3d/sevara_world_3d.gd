class_name SevaraWorld3D
extends Node3D
## Complete 3D valley world for Sevara (160 x 120 m valley floor + distant mountain rings).
## Built from the ground up with CC0 glTF/GLB models, MultiMesh dense meadows,
## custom spatial shaders, smooth character locomotion, and scenic valley camera lookpoints.

## Step-by-step Look-Dev progression:
## LOOKDEV_STEP = 1 -> Step 1: Terrain relief, calm velvety 3D grass, path & lighting.
## LOOKDEV_STEP = 2 -> Step 2: Crystal Nivarel creek, shoreline foam, stone ford & mossy boulders.
const LOOKDEV_STEP := 2

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
var _sky_shader_mat: ShaderMaterial
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

var _last_meadow_signature: String = ""
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
	var anim_shaders := bool(gfx.get("wind_and_water_shaders", true))
	_apply_shader_animation_toggle(anim_shaders)
	var meadow_sig := "%.2f" % fol_dens
	if meadow_sig != _last_meadow_signature:
		_last_meadow_signature = meadow_sig
		for child: Node in _meadow_multimesh_root.get_children():
			child.free()
		_meadow_multimesh_root.add_child(
			SevaraPropsFactory3D.build_dense_meadow_multimeshes(fol_dens)
		)
		_apply_shader_animation_toggle(anim_shaders)

	var eco_sig := (
		"%s|%d|%s|%d|%d|%d"
		% [
			str(p1_active),
			int(avg_silt * 20.0),
			str(kevalu_wild),
			canopy_q,
			herb_q,
			scav_q,
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
	var sky_shader := SevaraAssetLibrary3D.load_shader("sevara_sky_3d.gdshader")
	if sky_shader != null:
		_sky_shader_mat = ShaderMaterial.new()
		_sky_shader_mat.shader = sky_shader
		sky.sky_material = _sky_shader_mat
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.24, 0.46, 0.70)
		sky_mat.sky_horizon_color = Color(0.84, 0.86, 0.82)
		sky.sky_material = sky_mat
	_environment.sky = sky

	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_color = Color(0.58, 0.67, 0.76)
	_environment.ambient_light_sky_contribution = 0.48
	_environment.ambient_light_energy = 0.64
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 0.95
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.72, 0.80, 0.86)
	_environment.fog_light_energy = 0.42
	_environment.fog_density = 0.00075
	_environment.fog_sky_affect = 0.14
	_environment.glow_enabled = false
	_env_node.environment = _environment
	add_child(_env_node)

	_sun_light = DirectionalLight3D.new()
	_sun_light.name = "SunDirectionalLight3D"
	_sun_light.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	_sun_light.light_color = Color(1.0, 0.94, 0.82)
	_sun_light.light_energy = 1.04
	_sun_light.shadow_enabled = true
	_sun_light.shadow_opacity = 0.76
	_sun_light.shadow_blur = 1.35
	_sun_light.directional_shadow_max_distance = 145.0
	add_child(_sun_light)

	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "SkyFillLight3D"
	_fill_light.rotation_degrees = Vector3(-52.0, 145.0, 0.0)
	_fill_light.light_color = Color(0.62, 0.75, 0.90)
	_fill_light.light_energy = 0.32
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
	_terrain_mesh_inst.mesh = SevaraTerrainGen3D.build_terrain_mesh(32, 24, 256, 192)

	var t_shader := SevaraAssetLibrary3D.load_shader("sevara_terrain_3d.gdshader")
	_terrain_shader_mat = ShaderMaterial.new()
	_terrain_shader_mat.shader = t_shader

	_terrain_greybox_mat = StandardMaterial3D.new()
	_terrain_greybox_mat.albedo_color = Color(0.32, 0.36, 0.34)
	_terrain_greybox_mat.roughness = 0.92
	_terrain_mesh_inst.material_override = _terrain_shader_mat
	add_child(_terrain_mesh_inst)

	if LOOKDEV_STEP >= 2:
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
	var fol_dens := float(SettingsManager.graphics_profile().get("foliage_density", 1.0))
	_last_meadow_signature = "%.2f" % fol_dens
	_meadow_multimesh_root.add_child(SevaraPropsFactory3D.build_dense_meadow_multimeshes(fol_dens))
	if LOOKDEV_STEP >= 2:
		_populate_step2_boulders()
	if LOOKDEV_STEP >= 4:
		SevaraPropsFactory3D.populate_static_settlement(_settlement_root)


static func get_step2_boulder_specs() -> Array[Dictionary]:
	return [
		# Stone ford & central rapids boulders (clear of cart ruts: road_core < 0.05)
		{"pos": Vector2(5.9, -4.5), "sc": Vector3(1.15, 0.72, 1.05), "moss": true},
		{"pos": Vector2(6.3, -1.2), "sc": Vector3(0.95, 0.62, 0.90), "moss": true},
		{"pos": Vector2(12.2, -4.3), "sc": Vector3(1.25, 0.78, 1.15), "moss": true},
		{"pos": Vector2(12.5, -1.1), "sc": Vector3(1.05, 0.68, 0.95), "moss": true},
		{"pos": Vector2(8.3, -4.6), "sc": Vector3(0.78, 0.45, 0.72), "moss": false},
		{"pos": Vector2(10.2, -4.5), "sc": Vector3(0.72, 0.42, 0.68), "moss": false},
		{"pos": Vector2(8.6, -1.0), "sc": Vector3(0.68, 0.38, 0.64), "moss": false},
		# Upstream stepping stones bordering the Stone Ford causeway
		{"pos": Vector2(10.2, 1.15), "sc": Vector3(0.74, 0.32, 0.68), "moss": false},
		{"pos": Vector2(11.5, 1.18), "sc": Vector3(0.80, 0.34, 0.72), "moss": false},
		{"pos": Vector2(12.8, 1.12), "sc": Vector3(0.76, 0.32, 0.70), "moss": false},
		{"pos": Vector2(14.0, 1.08), "sc": Vector3(0.70, 0.30, 0.64), "moss": false},
		# Shore abutment boulders flanking the Stone Ford approach ramps
		{"pos": Vector2(8.6, 0.8), "sc": Vector3(1.12, 0.74, 1.04), "moss": true},
		{"pos": Vector2(15.4, 0.9), "sc": Vector3(1.18, 0.78, 1.08), "moss": true},
		{"pos": Vector2(9.0, 4.4), "sc": Vector3(1.08, 0.72, 1.02), "moss": true},
		{"pos": Vector2(15.0, 4.3), "sc": Vector3(1.14, 0.76, 1.06), "moss": true},
		# Upper creek rapids & mossy bank boulders (z = -28..-8)
		{"pos": Vector2(2.6, -9.8), "sc": Vector3(1.38, 0.98, 1.28), "moss": true},
		{"pos": Vector2(9.2, -9.2), "sc": Vector3(1.26, 0.88, 1.18), "moss": true},
		{"pos": Vector2(0.4, -15.6), "sc": Vector3(1.52, 1.12, 1.40), "moss": true},
		{"pos": Vector2(3.4, -15.0), "sc": Vector3(0.85, 0.52, 0.80), "moss": false},
		{"pos": Vector2(6.8, -16.2), "sc": Vector3(1.42, 1.04, 1.32), "moss": true},
		{"pos": Vector2(-1.4, -24.5), "sc": Vector3(1.68, 1.20, 1.52), "moss": true},
		{"pos": Vector2(4.8, -23.2), "sc": Vector3(1.45, 1.08, 1.36), "moss": true},
		# Lower creek pool & meadow bank boulders (z = +5..+14)
		{"pos": Vector2(7.8, 5.2), "sc": Vector3(1.30, 0.90, 1.20), "moss": true},
		{"pos": Vector2(14.6, 5.4), "sc": Vector3(1.48, 1.05, 1.36), "moss": true},
		{"pos": Vector2(11.4, 6.2), "sc": Vector3(0.82, 0.48, 0.76), "moss": false},
		{"pos": Vector2(9.2, 10.4), "sc": Vector3(1.52, 1.10, 1.40), "moss": true},
		{"pos": Vector2(16.8, 11.0), "sc": Vector3(1.62, 1.18, 1.50), "moss": true},
		# Hillside terrace & crossroads accent boulders
		{"pos": Vector2(-9.6, -12.8), "sc": Vector3(1.55, 1.10, 1.42), "moss": true},
		{"pos": Vector2(-8.2, -12.1), "sc": Vector3(0.90, 0.62, 0.84), "moss": true},
		{"pos": Vector2(-6.8, -5.8), "sc": Vector3(1.06, 0.72, 0.98), "moss": true},
		{"pos": Vector2(-15.5, -19.5), "sc": Vector3(1.75, 1.26, 1.60), "moss": true},
	]


func _populate_step2_boulders() -> void:
	var step2_rocks := get_step2_boulder_specs()
	for r_idx in range(step2_rocks.size()):
		var rs: Dictionary = step2_rocks[r_idx]
		var rp: Vector2 = rs["pos"]
		var sc_v: Vector3 = rs["sc"]
		var boulder := SevaraPropsFactory3D.create_boulder_3d(sc_v, bool(rs["moss"]))
		boulder.position = Vector3(
			rp.x, SevaraTerrainGen3D.get_height_at(rp.x, rp.y) - 0.11 * sc_v.y, rp.y
		)
		boulder.rotation.y = float(r_idx) * 1.18
		_ecology_root.add_child(boulder)


func _rebuild_ecology_and_npcs(
	world: WorldState,
	p1_active: bool,
	basin: Dictionary,
	any_kevalu_wild: bool,
	_foliage_density: float
) -> void:
	for child: Node in _ecology_root.get_children():
		child.free()
	for child: Node in _npcs_root.get_children():
		child.free()
	if LOOKDEV_STEP >= 2:
		_populate_step2_boulders()
	if LOOKDEV_STEP < 3:
		return

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
		Vector2(-11.8, 12.2),
		Vector2(14.2, 9.6),
		Vector2(-9.6, 17.8),
		Vector2(9.8, 15.8),
		Vector2(-5.4, 24.5),
		Vector2(12.8, 22.0),
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
	if LOOKDEV_STEP < 5:
		if local_body_entity_id > 0 and world.has_entity(local_body_entity_id):
			var lpos := world.get_entity_component(
				local_body_entity_id, GreyboxWorld.POSITION_COMPONENT
			)
			var ltile := GreyboxWorld.position_from_component(
				lpos, session.greybox_width_tiles, session.greybox_height_tiles
			)
			_focus_world_pos = _map_tile_to_valley_3d(ltile)
		return
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
	var wy := SevaraTerrainGen3D.get_walkable_height_at(wx, wz)
	return Vector3(wx, wy, wz)


func _apply_shader_animation_toggle(enabled: bool) -> void:
	if _water_shader_mat != null:
		_water_shader_mat.set_shader_parameter("flow_speed", 0.54 if enabled else 0.0)
		_water_shader_mat.set_shader_parameter("wave_height", 0.016 if enabled else 0.0)
	if _sky_shader_mat != null:
		_sky_shader_mat.set_shader_parameter("cloud_speed", 0.012 if enabled else 0.0)
	if _meadow_multimesh_root != null and _meadow_multimesh_root.get_child_count() > 0:
		var bundle := _meadow_multimesh_root.get_child(0)
		if bundle != null:
			var carpet := bundle.get_node_or_null("GrassBladeCarpetMM") as MultiMeshInstance3D
			if carpet != null and carpet.multimesh != null and carpet.multimesh.mesh != null:
				var mat := carpet.multimesh.mesh.surface_get_material(0) as ShaderMaterial
				if mat != null:
					mat.set_shader_parameter("wind_strength", 1.0 if enabled else 0.0)


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
			cam_pos = Vector3(-16.5, 6.6, 9.2)
			look_target = Vector3(5.5, 1.1, -5.5)
			fov = 38.0
		"heravo_meadow":
			cam_pos = Vector3(-10.5, 5.6, 6.8)
			look_target = Vector3(5.8, 0.85, -3.8)
			fov = 36.0
		"nivarel_rapids":
			cam_pos = Vector3(17.5, 5.6, 8.8)
			look_target = Vector3(3.2, 0.9, -7.5)
			fov = 36.0
		"settlement_hearth":
			cam_pos = Vector3(4.2, 5.2, 8.6)
			look_target = Vector3(11.8, 0.45, 2.2)
			fov = 35.0
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
	var presets: Dictionary = {
		"noon":
		[
			Color(1.0, 0.97, 0.90),
			1.16,
			Vector3(-56.0, -26.0, 0.0),
			Color(0.60, 0.69, 0.78),
			Color(0.74, 0.82, 0.88),
			Color(0.18, 0.46, 0.78),
			Color(0.82, 0.88, 0.92),
			Color(1.0, 0.99, 0.96),
		],
		"dusk":
		[
			Color(1.0, 0.72, 0.46),
			1.04,
			Vector3(-26.0, -48.0, 0.0),
			Color(0.68, 0.58, 0.50),
			Color(0.88, 0.72, 0.56),
			Color(0.24, 0.36, 0.62),
			Color(0.92, 0.72, 0.54),
			Color(1.0, 0.85, 0.66),
		],
		"night":
		[
			Color(0.45, 0.58, 0.82),
			0.52,
			Vector3(-38.0, 25.0, 0.0),
			Color(0.28, 0.36, 0.48),
			Color(0.22, 0.28, 0.38),
			Color(0.06, 0.11, 0.22),
			Color(0.18, 0.25, 0.38),
			Color(0.42, 0.50, 0.65),
		],
	}
	var p: Array = (
		presets
		. get(
			day_phase,
			[
				Color(1.0, 0.95, 0.86),
				1.08,
				Vector3(-42.0, -34.0, 0.0),
				Color(0.58, 0.67, 0.76),
				Color(0.72, 0.80, 0.86),
				Color(0.20, 0.48, 0.80),
				Color(0.84, 0.88, 0.90),
				Color(1.0, 0.98, 0.94),
			]
		)
	)
	_sun_light.light_color = p[0] as Color
	_sun_light.light_energy = float(p[1])
	_sun_light.rotation_degrees = p[2] as Vector3
	_environment.ambient_light_color = p[3] as Color
	_environment.fog_light_color = p[4] as Color
	if _sky_shader_mat != null:
		_sky_shader_mat.set_shader_parameter("sky_top_color", p[5] as Color)
		_sky_shader_mat.set_shader_parameter("sky_horizon_color", p[6] as Color)
		_sky_shader_mat.set_shader_parameter("cloud_bright_color", p[7] as Color)


func _npc_palette_for_id(npc_id: String, idx: int) -> Dictionary:
	var table: Dictionary = {
		"npc_sarela": [Color(0.24, 0.44, 0.30), Color(0.48, 0.42, 0.32), false, true, false],
		"npc_tovan": [Color(0.46, 0.34, 0.22), Color(0.36, 0.38, 0.40), true, false, true],
		"npc_selima": [Color(0.54, 0.28, 0.24), Color(0.56, 0.50, 0.40), false, true, false],
		"npc_evaren": [Color(0.28, 0.38, 0.26), Color(0.42, 0.34, 0.26), true, true, true],
	}
	var c_base := Color(0.30, 0.36, 0.44).lerp(Color(0.48, 0.38, 0.28), float(idx % 4) / 3.0)
	var row: Array = table.get(
		npc_id, [c_base, Color(0.46, 0.42, 0.36), idx % 2 == 0, idx % 2 == 1, idx % 3 == 0]
	)
	return {
		"cloak": row[0],
		"tunic": row[1],
		"pack": row[2],
		"satchel": row[3],
		"staff": row[4],
	}

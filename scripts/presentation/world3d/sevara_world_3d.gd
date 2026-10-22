class_name SevaraWorld3D
extends Node3D
## Full 3D living world presentation for the Sevara Valley slice in Godot 4.7.
##
## Replaces flat 2D backdrop images with real 3D terrain geometry, 3D water,
## modular 3D buildings, sluice gate, wooden bridge, 3D pine/blossom flora,
## 3D wildlife and articulated 3D characters lit by `DirectionalLight3D` and
## `WorldEnvironment`. State is read strictly from `GameSession`.

const TERRAIN_SHADER_PATH := "res://assets/shaders/sevara_terrain_3d.gdshader"
const WATER_SHADER_PATH := "res://assets/shaders/sevara_water_3d.gdshader"

var _world_env: WorldEnvironment
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _sun_light: DirectionalLight3D
var _camera_3d: Camera3D
var _terrain_mesh_instance: MeshInstance3D
var _terrain_material: ShaderMaterial
var _water_mesh_instance: MeshInstance3D
var _water_material: ShaderMaterial

var _static_root: Node3D
var _eco_root: Node3D
var _actors_root: Node3D

var _camera_preset_index: int = 1
var _last_eco_signature: String = ""


func _init() -> void:
	name = "SevaraWorld3D"
	_build_environment_and_lights()
	_build_terrain_and_water()
	_static_root = Node3D.new()
	_static_root.name = "StaticScenery3D"
	add_child(_static_root)
	_eco_root = Node3D.new()
	_eco_root.name = "DynamicEcology3D"
	add_child(_eco_root)
	_actors_root = Node3D.new()
	_actors_root.name = "ActorsAndCrates3D"
	add_child(_actors_root)
	_populate_static_scenery()


func camera_3d() -> Camera3D:
	return _camera_3d


func set_camera_preset(preset_index: int, focus_tile: Vector2i = Vector2i(14, 11)) -> void:
	_camera_preset_index = posmod(preset_index, 3)
	var focus_pos := SevaraTerrainGen3D.tile_to_world_pos3d(focus_tile, 0.8)
	if _camera_preset_index == 0:
		# Strategic valley overview
		var cam_pos := Vector3(0.0, 27.5, 29.5)
		_camera_3d.fov = 40.0
		_camera_3d.look_at_from_position(cam_pos, Vector3(0.0, 0.5, -1.5), Vector3.UP)
	elif _camera_preset_index == 1:
		# Balanced 3/4 gameplay camera over Nivara courtyard, sluice and bridge
		var target := Vector3(
			clampf(focus_pos.x * 0.35, -6.0, 6.0), 0.8, clampf(focus_pos.z * 0.35, -4.0, 5.0)
		)
		var cam_pos := target + Vector3(0.0, 19.5, 22.0)
		_camera_3d.fov = 37.0
		_camera_3d.look_at_from_position(cam_pos, target, Vector3.UP)
	else:
		# Immersive low-angle close-up showing 3D buildings, trees, horizon & sky
		var target := focus_pos + Vector3(1.5, 0.6, -2.5)
		var cam_pos := focus_pos + Vector3(-5.2, 5.6, 10.8)
		_camera_3d.fov = 45.0
		_camera_3d.look_at_from_position(cam_pos, target, Vector3.UP)


func cycle_camera_preset(focus_tile: Vector2i = Vector2i(14, 11)) -> int:
	set_camera_preset(_camera_preset_index + 1, focus_tile)
	return _camera_preset_index


func sync_from_session(session: GameSession) -> void:
	var is_greybox := SettingsManager.texture_quality == SettingsManager.TEXTURE_QUALITY_GREYBOX
	visible = not is_greybox
	if _camera_3d != null:
		_camera_3d.current = not is_greybox
	if is_greybox or session == null:
		return
	var world := session.world_state()
	if world == null or not world.is_initialized():
		return

	var hour := world.clock().hour_of_day()
	_apply_time_of_day_lighting(hour)

	var basin := SevaraEcoChain.basin_summary(world)
	_update_shader_ecology_params(basin)
	_rebuild_dynamic_ecology_if_needed(basin)
	_rebuild_actors_and_crates(session, world, hour)


func _build_environment_and_lights() -> void:
	_world_env = WorldEnvironment.new()
	_world_env.name = "SevaraWorldEnvironment"
	_environment = Environment.new()
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_top_color = Color(0.28, 0.48, 0.72)
	_sky_material.sky_horizon_color = Color(0.68, 0.78, 0.86)
	_sky_material.ground_horizon_color = Color(0.52, 0.58, 0.54)
	_sky_material.ground_bottom_color = Color(0.20, 0.24, 0.20)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_sky_contribution = 0.65
	_environment.ambient_light_energy = 0.85
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.72, 0.80, 0.86)
	_environment.fog_density = 0.0045
	_world_env.environment = _environment
	add_child(_world_env)

	_sun_light = DirectionalLight3D.new()
	_sun_light.name = "SunDirectionalLight3D"
	_sun_light.shadow_enabled = true
	_sun_light.directional_shadow_max_distance = 90.0
	_sun_light.light_energy = 1.35
	_sun_light.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	add_child(_sun_light)

	_camera_3d = Camera3D.new()
	_camera_3d.name = "WorldCamera3D"
	_camera_3d.current = true
	_camera_3d.near = 0.2
	_camera_3d.far = 260.0
	add_child(_camera_3d)
	set_camera_preset(1, Vector2i(12, 11))


func _build_terrain_and_water() -> void:
	_terrain_mesh_instance = MeshInstance3D.new()
	_terrain_mesh_instance.name = "SevaraTerrainMesh3D"
	_terrain_mesh_instance.mesh = SevaraTerrainGen3D.build_terrain_mesh()
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = load(TERRAIN_SHADER_PATH) as Shader
	_bind_terrain_textures(_terrain_material)
	_terrain_mesh_instance.material_override = _terrain_material
	add_child(_terrain_mesh_instance)

	_water_mesh_instance = MeshInstance3D.new()
	_water_mesh_instance.name = "SevaraWaterMesh3D"
	_water_mesh_instance.mesh = SevaraTerrainGen3D.build_water_mesh()
	_water_material = ShaderMaterial.new()
	_water_material.shader = load(WATER_SHADER_PATH) as Shader
	var water_norm := (
		load("res://assets/textures/sevara_p1/tex_riverbed_pebbles_normal.png") as Texture2D
	)
	if water_norm != null:
		_water_material.set_shader_parameter("normal_tex", water_norm)
	_water_mesh_instance.material_override = _water_material
	add_child(_water_mesh_instance)


func _bind_terrain_textures(mat: ShaderMaterial) -> void:
	var pairs := {
		"tex_pebbles": "res://assets/textures/sevara_p1/tex_riverbed_pebbles.png",
		"tex_pebbles_normal": "res://assets/textures/sevara_p1/tex_riverbed_pebbles_normal.png",
		"tex_mud_silt": "res://assets/textures/sevara_p1/tex_spring_mud_and_silt.png",
		"tex_mud_silt_normal": "res://assets/textures/sevara_p1/tex_spring_mud_and_silt_normal.png",
		"tex_meadow": "res://assets/textures/sevara_p1/tex_meadow_moss_and_snow.png",
		"tex_meadow_normal": "res://assets/textures/sevara_p1/tex_meadow_moss_and_snow_normal.png",
		"tex_rock": "res://assets/textures/sevara_p1/tex_stone_and_timber.png",
		"tex_rock_normal": "res://assets/textures/sevara_p1/tex_stone_and_timber_normal.png",
	}
	for param_name in pairs.keys():
		var tex := load(String(pairs[param_name])) as Texture2D
		if tex != null:
			mat.set_shader_parameter(String(param_name), tex)


func _populate_static_scenery() -> void:
	# 1) Nivara communal longhouse (Sarela's hearth + Selima's chronicle rack)
	var longhouse := SevaraPropsFactory3D.build_longhouse_3d()
	longhouse.position = Vector3(-14.5, SevaraTerrainGen3D.raw_terrain_height(-14.5, -5.2), -5.2)
	longhouse.rotation_degrees = Vector3(0.0, 14.0, 0.0)
	_static_root.add_child(longhouse)

	# 2) Mavena's herbalist courtyard & stone quarantine pond
	var herb_yard := SevaraPropsFactory3D.build_herbalist_yard_3d()
	herb_yard.position = Vector3(-11.2, SevaraTerrainGen3D.raw_terrain_height(-11.2, 6.6), 6.6)
	herb_yard.rotation_degrees = Vector3(0.0, 8.0, 0.0)
	_static_root.add_child(herb_yard)

	# 3) Wooden bridge across the Nivarel channel
	var bridge := SevaraPropsFactory3D.build_wooden_bridge_3d()
	var bx := SevaraTerrainGen3D.river_center_x(11.2)
	bridge.position = Vector3(bx, SevaraTerrainGen3D.WATER_LEVEL_Y + 0.1, 11.2)
	_static_root.add_child(bridge)

	# 4) Torava pine forest along Toramek slope & western ridge
	var pine_coords := [
		Vector3(-22.0, 1.15, -14.0),
		Vector3(-18.5, 1.25, -15.5),
		Vector3(-13.0, 1.10, -15.8),
		Vector3(-9.5, 0.95, -16.2),
		Vector3(-6.2, 1.05, -14.5),
		Vector3(-23.5, 1.30, -7.5),
		Vector3(-22.2, 1.10, 0.5),
		Vector3(-20.8, 1.20, 8.2),
		Vector3(-17.5, 0.95, 13.5),
		Vector3(-13.8, 0.88, 15.2),
		Vector3(8.5, 1.10, -16.8),
		Vector3(12.5, 1.25, -17.5),
		Vector3(24.5, 1.15, -15.0),
		Vector3(26.0, 1.20, -6.5),
		Vector3(25.2, 1.05, 4.5),
		Vector3(23.5, 0.95, 13.5),
		Vector3(-28.0, 1.45, -22.0),
		Vector3(-16.0, 1.50, -24.0),
		Vector3(-4.0, 1.35, -25.0),
		Vector3(10.0, 1.40, -24.5),
		Vector3(24.0, 1.45, -23.0),
	]
	for p in pine_coords:
		var snow_top := p.z < -13.0
		var pine := SevaraPropsFactory3D.create_torava_pine_3d(p.y, snow_top)
		pine.position = Vector3(p.x, SevaraTerrainGen3D.raw_terrain_height(p.x, p.z) - 0.1, p.z)
		pine.rotation_degrees = Vector3(0.0, fmod(absf(p.x * 37.0 + p.z * 19.0), 360.0), 0.0)
		_static_root.add_child(pine)

	# 5) Flowering Mirval & Talina shrubs on the eastern Heravo meadow
	var bush_coords := [
		Vector3(9.2, 1.1, 2.5),
		Vector3(13.5, 1.25, 5.2),
		Vector3(17.8, 1.0, 1.8),
		Vector3(11.0, 0.95, 9.8),
		Vector3(16.2, 1.15, 11.5),
		Vector3(19.5, 1.05, 7.4),
		Vector3(-7.5, 0.9, 9.2),
		Vector3(-16.2, 1.0, 3.8),
	]
	for b in bush_coords:
		var bush := SevaraPropsFactory3D.create_mirval_blossom_bush_3d(b.y)
		bush.position = Vector3(b.x, SevaraTerrainGen3D.raw_terrain_height(b.x, b.z), b.z)
		_static_root.add_child(bush)

	# 6) Granite boulders around the Kevar crater rim and riverbanks
	for i in range(14):
		var angle := (float(i) / 14.0) * TAU
		var rad := SevaraTerrainGen3D.KEVAR_POOL_RADIUS + 1.1 + float(i % 3) * 0.65
		var rx := SevaraTerrainGen3D.KEVAR_POOL_CENTER.x + cos(angle) * rad
		var rz := SevaraTerrainGen3D.KEVAR_POOL_CENTER.y + sin(angle) * rad
		var rock := SevaraPropsFactory3D.create_rock_boulder_3d(
			0.75 + float(i % 3) * 0.28, Vector3(1.25, 0.85, 1.05)
		)
		rock.position = Vector3(rx, SevaraTerrainGen3D.raw_terrain_height(rx, rz) - 0.15, rz)
		rock.rotation_degrees = Vector3(0.0, rad_to_deg(angle), 0.0)
		_static_root.add_child(rock)


func _apply_time_of_day_lighting(hour: int) -> void:
	if _sun_light == null or _environment == null or _sky_material == null:
		return
	if hour >= 6 and hour < 11:
		# Crisp spring morning golden light
		_sun_light.rotation_degrees = Vector3(-34.0, -48.0, 0.0)
		_sun_light.light_color = Color(1.0, 0.91, 0.76)
		_sun_light.light_energy = 1.35
		_sky_material.sky_top_color = Color(0.28, 0.50, 0.76)
		_sky_material.sky_horizon_color = Color(0.84, 0.82, 0.74)
		_environment.fog_light_color = Color(0.82, 0.84, 0.80)
		_environment.ambient_light_energy = 0.88
	elif hour >= 11 and hour < 17:
		# High clear spring midday
		_sun_light.rotation_degrees = Vector3(-58.0, -22.0, 0.0)
		_sun_light.light_color = Color(1.0, 0.97, 0.92)
		_sun_light.light_energy = 1.45
		_sky_material.sky_top_color = Color(0.22, 0.46, 0.78)
		_sky_material.sky_horizon_color = Color(0.70, 0.82, 0.90)
		_environment.fog_light_color = Color(0.74, 0.84, 0.90)
		_environment.ambient_light_energy = 0.95
	elif hour >= 17 and hour < 21:
		# Warm amber Sevaran dusk with long shadows
		_sun_light.rotation_degrees = Vector3(-22.0, 46.0, 0.0)
		_sun_light.light_color = Color(1.0, 0.62, 0.36)
		_sun_light.light_energy = 1.15
		_sky_material.sky_top_color = Color(0.18, 0.24, 0.42)
		_sky_material.sky_horizon_color = Color(0.86, 0.52, 0.34)
		_environment.fog_light_color = Color(0.66, 0.48, 0.38)
		_environment.ambient_light_energy = 0.62
	else:
		# Cool moonlit night
		_sun_light.rotation_degrees = Vector3(-40.0, 120.0, 0.0)
		_sun_light.light_color = Color(0.52, 0.66, 0.88)
		_sun_light.light_energy = 0.48
		_sky_material.sky_top_color = Color(0.05, 0.08, 0.15)
		_sky_material.sky_horizon_color = Color(0.14, 0.20, 0.28)
		_environment.fog_light_color = Color(0.14, 0.20, 0.28)
		_environment.ambient_light_energy = 0.38


func _update_shader_ecology_params(basin: Dictionary) -> void:
	var wetland: Variant = basin.get(SevaraEcoChain.NODE_MULANE_WETLAND, {})
	var channel: Variant = basin.get(SevaraEcoChain.NODE_NIVAREL_CHANNEL, {})
	var silt := (
		float((wetland as Dictionary).get("silt_load", 0.25))
		if typeof(wetland) == TYPE_DICTIONARY
		else 0.25
	)
	var clarity := (
		float((wetland as Dictionary).get("water_clarity", 0.78))
		if typeof(wetland) == TYPE_DICTIONARY
		else 0.78
	)
	var kevalu_wild := (
		float((channel as Dictionary).get("kevalu_wild_biomass", 0.0))
		if typeof(channel) == TYPE_DICTIONARY
		else 0.0
	)
	if _terrain_material != null:
		_terrain_material.set_shader_parameter("silt_load", silt)
		_terrain_material.set_shader_parameter("kevalu_contamination", kevalu_wild)
	if _water_material != null:
		_water_material.set_shader_parameter("silt_load", silt)
		_water_material.set_shader_parameter("water_clarity", clarity)
		_water_material.set_shader_parameter("kevalu_tint", kevalu_wild)


func _rebuild_dynamic_ecology_if_needed(basin: Dictionary) -> void:
	var channel: Variant = basin.get(SevaraEcoChain.NODE_NIVAREL_CHANNEL, {})
	var meadow: Variant = basin.get(SevaraEcoChain.NODE_HERAVO_MEADOW, {})
	var dams := (
		float((channel as Dictionary).get("navelu_dams_integrity", 0.72))
		if typeof(channel) == TYPE_DICTIONARY
		else 0.72
	)
	var selave := (
		float((channel as Dictionary).get("selave_beds", 0.74))
		if typeof(channel) == TYPE_DICTIONARY
		else 0.74
	)
	var kevalu_wild := (
		float((channel as Dictionary).get("kevalu_wild_biomass", 0.0))
		if typeof(channel) == TYPE_DICTIONARY
		else 0.0
	)
	var heruna_pop := (
		float((meadow as Dictionary).get("heruna_grazers", 0.68))
		if typeof(meadow) == TYPE_DICTIONARY
		else 0.68
	)
	var sig := "%.2f_%.2f_%.2f_%.2f" % [dams, selave, kevalu_wild, heruna_pop]
	if sig == _last_eco_signature:
		return
	_last_eco_signature = sig

	for child in _eco_root.get_children():
		child.free()

	# 1) Sluice gate + upstream Navelu beaver log dam
	var sluice := SevaraPropsFactory3D.build_sluice_and_dam_3d(dams)
	var sx := SevaraTerrainGen3D.river_center_x(-1.2)
	sluice.position = Vector3(sx, SevaraTerrainGen3D.WATER_LEVEL_Y, -1.2)
	_eco_root.add_child(sluice)

	# 2) Navelu river builders near the upstream dam when intact
	if dams > 0.25:
		for offset in [Vector3(-1.4, 0.1, -8.8), Vector3(1.2, 0.1, -9.4)]:
			var navelu := SevaraCreatures3D.create_navelu_builder_3d()
			navelu.position = sluice.position + offset
			navelu.rotation_degrees = Vector3(0.0, 35.0, 0.0)
			_eco_root.add_child(navelu)

	# 3) Selave filtration reed beds along both banks of the Nivarel channel
	for z_reed in [-6.5, -4.2, 2.0, 4.5, 7.2, 14.0]:
		var rcx := SevaraTerrainGen3D.river_center_x(z_reed)
		var rhw := SevaraTerrainGen3D.river_half_width(z_reed)
		for side in [-1.0, 1.0]:
			var reed := SevaraPropsFactory3D.create_selave_reed_clump_3d(selave)
			reed.position = Vector3(
				rcx + side * (rhw - 0.35), SevaraTerrainGen3D.WATER_LEVEL_Y - 0.05, z_reed
			)
			_eco_root.add_child(reed)

	# 4) Harune horned grazers on the eastern Heravo meadow
	var grazer_spots := [
		Vector3(12.2, 0.0, 6.2),
		Vector3(15.6, 0.0, 8.4),
		Vector3(14.0, 0.0, 3.2),
	]
	var grazer_count := maxi(1, int(round(heruna_pop * 3.0)))
	for i in range(mini(grazer_count, grazer_spots.size())):
		var gp: Vector3 = grazer_spots[i]
		var harune := SevaraCreatures3D.create_harune_grazer_3d(0.95 + float(i) * 0.06)
		harune.position = Vector3(gp.x, SevaraTerrainGen3D.raw_terrain_height(gp.x, gp.z), gp.z)
		harune.rotation_degrees = Vector3(0.0, -45.0 + float(i) * 52.0, 0.0)
		_eco_root.add_child(harune)

	# 5) Wild Kevalu ash-white mineral root tendrils creeping from Kevar toward Nivarel
	if kevalu_wild > 0.04:
		var tendril_spots := [
			Vector3(13.0, 0.0, -8.5),
			Vector3(9.8, 0.0, -6.2),
			Vector3(6.8, 0.0, -4.5),
			Vector3(4.2, 0.0, -3.0),
		]
		for tp in tendril_spots:
			var cluster := SevaraPropsFactory3D.create_kevalu_tendril_cluster_3d(kevalu_wild)
			cluster.position = Vector3(
				tp.x, SevaraTerrainGen3D.raw_terrain_height(tp.x, tp.z), tp.z
			)
			_eco_root.add_child(cluster)


func _rebuild_actors_and_crates(session: GameSession, world: WorldState, _hour: int) -> void:
	for child in _actors_root.get_children():
		child.free()

	var status := session.session_status()
	var local_body_id := int(status.get("local_body_entity_id", -1))

	# 1) Supply crate
	var crate_id := GreyboxWorld.find_supply_object(world)
	if crate_id > 0 and world.has_entity(crate_id):
		var crate_tile := GreyboxWorld.position_from_component(
			world.get_entity_component(crate_id, GreyboxWorld.POSITION_COMPONENT),
			session.greybox_width_tiles,
			session.greybox_height_tiles
		)
		var container := world.get_entity_component(crate_id, GreyboxWorld.CONTAINER_COMPONENT)
		var count := int(GreyboxWorld.integral_value(container.get("count", 0)).get("value", 0))
		var crate_node := SevaraCreatures3D.create_supply_crate_3d(
			"Припасы Торавы: %d" % count, count > 0
		)
		crate_node.position = SevaraTerrainGen3D.tile_to_world_pos3d(crate_tile)
		_actors_root.add_child(crate_node)

	# 2) Player / participant bodies
	for body_rec in GreyboxWorld.body_records(world):
		var eid := int(body_rec.get("body_entity_id", -1))
		var tile := Vector2i(int(body_rec.get("tile_x", 2)), int(body_rec.get("tile_y", 2)))
		var is_local := eid == local_body_id
		var disp_name := String(body_rec.get("display_name", "Путник"))
		var vitals := world.get_entity_component(eid, BodyVitals.VITALS_COMPONENT)
		var pal := {
			"cloak": Color(0.28, 0.38, 0.25) if is_local else Color(0.24, 0.40, 0.48),
			"tunic": Color(0.74, 0.68, 0.56),
			"trim": Color(0.92, 0.74, 0.28),
			"prop": "staff",
		}
		var tag := ("★ %s" % disp_name) if is_local else disp_name
		var actor_3d := SevaraCreatures3D.create_humanoid_3d(pal, tag, is_local, vitals)
		actor_3d.position = SevaraTerrainGen3D.tile_to_world_pos3d(tile)
		actor_3d.rotation_degrees = Vector3(0.0, 25.0, 0.0)
		_actors_root.add_child(actor_3d)

	# 3) 8 Anchor NPCs of the P1 slice on their 3D valley workstations
	for npc in SevaraP1Npcs.npcs_summary(world):
		var npc_id := String(npc.get("npc_id", ""))
		var default_tile := SevaraVisualTheme.npc_anchor_tile(npc_id)
		var tx := int(npc.get("tile_x", default_tile.x))
		var ty := int(npc.get("tile_y", default_tile.y))
		var pal := SevaraVisualTheme.npc_visual_palette(npc_id)
		var tag := SevaraVisualTheme.npc_display_tag(npc_id)
		var npc_3d := SevaraCreatures3D.create_humanoid_3d(pal, tag, false)
		npc_3d.position = SevaraTerrainGen3D.tile_to_world_pos3d(Vector2i(tx, ty))
		npc_3d.rotation_degrees = Vector3(0.0, float((tx * 37 + ty * 53) % 120 - 60), 0.0)
		_actors_root.add_child(npc_3d)

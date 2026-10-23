extends Node
## P0-F greybox presentation, input controller, camera and debug overlay tests.
##
## Verifies that:
## - all `data/core` definitions have RU/EN translations and `SettingsManager`
##   controls the `Ambience` bus volume;
## - `ActorView` and `SupplyCrateView` configure named 2D `PhysicsLayers`;
## - `GreyboxChunkView` hydrates views from `GameSession` and can dehydrate
##   and re-hydrate without changing `WorldState` or `domain_state_hash()`;
## - semantic `InputMap` actions (`move_*`, `interact`, `debug_toggle`) flow
##   through `GameSession` intents, update `Camera2D` and populate
##   `GreyboxDebugOverlay`;
## - two networked `GreyboxStage` instances (host + client over localhost ENet)
##   hydrate the same world and converge on the same `state_hash`.

const GREYBOX_STAGE_SCENE := "res://scenes/levels/greybox_stage.tscn"
const TEST_SAVE_ROOT := "user://tests/presentation_p0f"

var _failures: Array[String] = []
var _checks: int = 0
var _host_session: GameSession
var _client_session: GameSession


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_localization_and_ambience_settings()
	_test_grid_metrics_and_physics_layers()
	_test_step2_creek_ford_and_boulders()
	_test_stage_hydration_and_disposable_views()
	_test_input_actions_and_debug_overlay()
	await _test_networked_two_stage_presentation()

	if _failures.is_empty():
		print("PRESENTATION_TESTS_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("PRESENTATION_TESTS_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_localization_and_ambience_settings() -> void:
	UiLocaleCatalog.ensure_registered()
	var registry := DefinitionRegistry.new()
	var load_report: Dictionary = registry.load_package("res://data/core/manifest.json")
	_check(bool(load_report.get("ok", false)), "core manifest loads for locale check")
	var missing_keys: Array[String] = UiLocaleCatalog.validate_registry_keys(registry)
	_check(
		missing_keys.is_empty(),
		"all core definition name_keys have RU/EN translations: %s" % str(missing_keys)
	)

	SettingsManager.set_language("en")
	_check_equal(
		tr("ui.main_menu.new_game"), "New Campaign (Sevara Valley)", "EN translation for main menu"
	)
	_check_equal(tr("material.torava_wood.name"), "Torava Wood", "EN translation for torava wood")

	SettingsManager.set_language("ru")
	_check_equal(
		tr("ui.main_menu.new_game"),
		"Новая кампания (Долина Севары)",
		"RU translation for main menu"
	)
	_check_equal(
		tr("material.torava_wood.name"), "Древесина торавы", "RU translation for torava wood"
	)

	var ambience_bus_idx := AudioServer.get_bus_index(AudioManager.BUS_AMBIENCE)
	_check(ambience_bus_idx >= 0, "Ambience audio bus exists")
	SettingsManager.set_ambience_volume(0.35)
	SettingsManager.ambience_volume = 0.9
	SettingsManager.load_settings()
	_check(
		is_equal_approx(SettingsManager.ambience_volume, 0.35),
		"SettingsManager persists and reloads ambience_volume 0.35"
	)
	_check(not AudioServer.is_bus_mute(ambience_bus_idx), "Ambience bus is unmuted at volume 0.35")
	SettingsManager.set_ambience_volume(0.0)
	_check(AudioServer.is_bus_mute(ambience_bus_idx), "Ambience bus is muted at volume 0.0")
	SettingsManager.set_ambience_volume(1.0)

	_check(
		not SettingsManager.set_texture_quality("invalid_preset"),
		"SettingsManager rejects unknown texture_quality preset"
	)
	_check(
		SettingsManager.set_texture_quality(SettingsManager.TEXTURE_QUALITY_GREYBOX),
		"SettingsManager accepts greybox texture_quality preset"
	)
	SettingsManager.set_foliage_density(0.45)
	SettingsManager.set_wind_and_water_shaders(false)
	SettingsManager.set_ui_scale(1.25)
	SettingsManager.texture_quality = SettingsManager.TEXTURE_QUALITY_HIGH
	SettingsManager.foliage_density = 1.0
	SettingsManager.load_settings()
	var gfx: Dictionary = SettingsManager.graphics_profile()
	_check_equal(
		String(gfx.get("texture_quality", "")),
		SettingsManager.TEXTURE_QUALITY_GREYBOX,
		"SettingsManager persists texture_quality preset"
	)
	_check(
		is_equal_approx(float(gfx.get("foliage_density", 0.0)), 0.45),
		"SettingsManager persists foliage_density"
	)
	_check(
		not bool(gfx.get("wind_and_water_shaders", true)),
		"SettingsManager persists wind_and_water_shaders toggle"
	)
	SettingsManager.set_texture_quality(SettingsManager.TEXTURE_QUALITY_HIGH)
	SettingsManager.set_foliage_density(1.0)
	SettingsManager.set_wind_and_water_shaders(true)
	SettingsManager.set_ui_scale(1.0)


func _test_step2_creek_ford_and_boulders() -> void:
	var r_cx0 := SevaraTerrainGen3D.river_center_x(0.0)
	_check(
		SevaraTerrainGen3D.is_water_at(r_cx0, 0.0),
		"Nivarel creek channel center at z=0 is submerged below WATER_SURFACE_Y"
	)
	var ford_x := SevaraTerrainGen3D.river_center_x(2.68)
	var ford_road := SevaraTerrainGen3D.get_road_core_at(ford_x, 2.68)
	_check(ford_road > 0.85, "Main two-track road crosses Nivarel creek at the Stone Ford (z=2.68)")
	var deep_bed_y := SevaraTerrainGen3D.get_height_at(
		SevaraTerrainGen3D.river_center_x(-10.0), -10.0
	)
	var ford_bed_y := SevaraTerrainGen3D.get_height_at(ford_x, 2.68)
	_check(
		ford_bed_y > deep_bed_y + 0.35,
		"Stone Ford riverbed is significantly shallower than deep creek thalweg"
	)
	var walk_y := SevaraTerrainGen3D.get_walkable_height_at(r_cx0, 0.0)
	_check(
		walk_y >= SevaraTerrainGen3D.WATER_SURFACE_Y - 0.17,
		"Walkable height clamps actor immersion in creek channel"
	)
	var blocked_roads := 0
	for spec: Dictionary in SevaraPropsFactory3D.get_step2_boulder_specs():
		var p: Vector2 = spec["pos"]
		if SevaraTerrainGen3D.get_road_core_at(p.x, p.y) >= 0.08:
			blocked_roads += 1
	_check_equal(blocked_roads, 0, "No Step 2 boulder obstructs the active two-track roadbed")
	_check(
		(
			(
				SevaraTerrainGen3D.get_height_at(-12.0, 10.0)
				> SevaraTerrainGen3D.WATER_SURFACE_Y + 0.14
			)
			and not SevaraTerrainGen3D.is_water_at(-12.0, 10.0)
		),
		"Dry meadow hollows outside the Nivarel stream corridor stay above the water table"
	)


func _test_grid_metrics_and_physics_layers() -> void:
	var center := GreyboxGridMetrics.tile_to_world_center(Vector2i(2, 3), 48.0)
	_check_equal(center, Vector2(120.0, 168.0), "tile (2,3) center in world pixels")
	_check_equal(
		GreyboxGridMetrics.world_to_tile(center, 48.0),
		Vector2i(2, 3),
		"world center converts back to tile (2,3)"
	)
	_check_equal(
		GreyboxGridMetrics.ecocell_for_tile(Vector2i(8, 15)),
		Vector2i(1, 1),
		"ecocell coordinates for tile (8,15)"
	)
	_check_equal(
		GreyboxGridMetrics.chunk_for_tile(Vector2i(31, 23)),
		Vector2i(0, 0),
		"chunk coordinates for tile (31,23)"
	)

	var actor_view := ActorView.new()
	var actor_summary: Dictionary = actor_view.view_summary()
	_check_equal(
		int(actor_summary.get("collision_layer", 0)),
		PhysicsLayers.BODIES_BIT,
		"ActorView collision_layer uses BODIES_BIT"
	)
	_check_equal(
		int(actor_summary.get("collision_mask", 0)),
		PhysicsLayers.TERRAIN_BIT | PhysicsLayers.BODIES_BIT | PhysicsLayers.STRUCTURES_BIT,
		"ActorView collision_mask uses TERRAIN | BODIES | STRUCTURES"
	)
	_check_equal(
		int(actor_summary.get("sensor_layer", 0)),
		PhysicsLayers.SENSORS_BIT,
		"ActorView sensor uses SENSORS_BIT"
	)
	_check_equal(
		int(actor_summary.get("sensor_mask", 0)),
		PhysicsLayers.INTERACTABLES_BIT | PhysicsLayers.ITEMS_BIT,
		"ActorView sensor mask uses INTERACTABLES | ITEMS"
	)
	actor_view.free()

	var crate_view := SupplyCrateView.new()
	var crate_summary: Dictionary = crate_view.view_summary()
	_check_equal(
		int(crate_summary.get("collision_layer", 0)),
		PhysicsLayers.STRUCTURES_BIT | PhysicsLayers.INTERACTABLES_BIT,
		"SupplyCrateView collision_layer uses STRUCTURES | INTERACTABLES"
	)
	_check_equal(
		int(crate_summary.get("collision_mask", -1)), 0, "SupplyCrateView collision_mask is zero"
	)
	crate_view.free()


func _test_stage_hydration_and_disposable_views() -> void:
	var stage := _instantiate_stage()
	if stage == null:
		return
	var start_report: Dictionary = stage.start_offline_campaign(
		"p0f_hydration", 90123, "host", "Host"
	)
	_check(bool(start_report.get("ok", false)), "stage starts offline campaign")

	var chunk_view := stage.chunk_view()
	var local_actor := chunk_view.local_actor_view()
	var crate_view := chunk_view.supply_crate_view()
	_check(local_actor != null, "local ActorView is hydrated")
	_check(crate_view != null, "SupplyCrateView is hydrated")
	if local_actor == null or crate_view == null:
		_destroy_node(stage)
		return

	_check_equal(local_actor.tile_position, Vector2i(2, 2), "hydrated host body tile")
	_check_equal(crate_view.tile_position, Vector2i(3, 2), "hydrated supply crate tile")
	_check(crate_view.adjacent_to_local_body, "supply crate detects adjacent local body")
	_check(
		crate_view.can_interact_now(), "supply crate is interactable when adjacent and non-empty"
	)
	_check_equal(
		stage.camera().position, local_actor.position, "Camera2D centers on the local ActorView"
	)

	var hash_before: String = stage.session().domain_state_hash()
	var original_actor_id := local_actor.entity_id
	local_actor.free()
	_check_equal(
		stage.session().domain_state_hash(),
		hash_before,
		"freeing ActorView does not alter domain_state_hash"
	)

	chunk_view.dehydrate_all()
	_check(
		chunk_view.hydrated_entity_ids().is_empty(), "dehydrate_all removes all presentation views"
	)
	_check_equal(
		stage.session().domain_state_hash(),
		hash_before,
		"dehydrating the chunk does not alter domain_state_hash"
	)

	stage.refresh_presentation()
	var rehydrated_actor := chunk_view.local_actor_view()
	var rehydrated_crate := chunk_view.supply_crate_view()
	_check(rehydrated_actor != null, "refresh_presentation re-hydrates ActorView from WorldState")
	_check(
		rehydrated_crate != null, "refresh_presentation re-hydrates SupplyCrateView from WorldState"
	)
	if rehydrated_actor != null:
		_check_equal(rehydrated_actor.entity_id, original_actor_id, "re-hydrated actor entity_id")
		_check_equal(rehydrated_actor.tile_position, Vector2i(2, 2), "re-hydrated actor tile")
	_check_equal(
		stage.session().domain_state_hash(), hash_before, "re-hydration preserves domain_state_hash"
	)
	_destroy_node(stage)


func _test_input_actions_and_debug_overlay() -> void:
	var stage := _instantiate_stage()
	if stage == null:
		return
	var start_report: Dictionary = stage.start_offline_campaign("p0f_input", 445566, "host", "Host")
	_check(bool(start_report.get("ok", false)), "input test stage starts campaign")

	var interact_event := InputEventAction.new()
	interact_event.action = GreyboxGridMetrics.ACTION_INTERACT
	interact_event.pressed = true
	var interact_report: Dictionary = stage.handle_input_event(interact_event)
	_check(bool(interact_report.get("ok", false)), "interact InputEventAction submits intent")
	_check(bool(interact_report.get("applied", false)), "adjacent interact intent is applied")

	var actor := stage.chunk_view().local_actor_view()
	var crate := stage.chunk_view().supply_crate_view()
	_check(actor != null and crate != null, "actor and crate views remain hydrated after interact")
	if actor != null and crate != null:
		_check_equal(crate.remaining_count, 2, "crate remaining_count decreases to 2 in view")
		_check_equal(actor.total_inventory_items, 1, "actor inventory count increases to 1 in view")

	var move_event := InputEventAction.new()
	move_event.action = GreyboxGridMetrics.ACTION_MOVE_DOWN
	move_event.pressed = true
	var move_report: Dictionary = stage.handle_input_event(move_event)
	_check(bool(move_report.get("ok", false)), "move_down InputEventAction submits intent")
	_check(bool(move_report.get("applied", false)), "move_down intent is applied")

	actor = stage.chunk_view().local_actor_view()
	crate = stage.chunk_view().supply_crate_view()
	if actor != null and crate != null:
		_check_equal(actor.tile_position, Vector2i(2, 3), "actor view moves to tile (2,3)")
		_check_equal(
			stage.camera().position, actor.position, "Camera2D follows local actor to tile (2,3)"
		)
		_check(
			not crate.adjacent_to_local_body, "crate view updates adjacency to false at distance 2"
		)

	var failed_interact: Dictionary = stage.trigger_action(GreyboxGridMetrics.ACTION_INTERACT)
	_check(
		not bool(failed_interact.get("applied", true)),
		"interact from a non-adjacent tile is rejected by the host"
	)
	var overlay_snapshot: Dictionary = stage.debug_overlay().last_snapshot()
	var last_rejection: Dictionary = overlay_snapshot.get("last_rejection", {})
	_check_equal(
		String(last_rejection.get("reason", "")),
		"not_adjacent",
		"debug overlay records not_adjacent rejection"
	)
	var overlay_text := stage.debug_overlay().report_text()
	_check(
		overlay_text.contains("Last Rejection: reason=not_adjacent"),
		"debug overlay text renders last rejection"
	)
	_check(
		overlay_text.contains(stage.session().domain_state_hash().substr(0, 16)),
		"debug overlay text renders state hash prefix"
	)

	var hash_before_toggle: String = stage.session().domain_state_hash()
	var toggle_off: Dictionary = stage.trigger_action(GreyboxGridMetrics.ACTION_DEBUG_TOGGLE)
	_check(bool(toggle_off.get("ok", false)), "debug_toggle action is handled")
	_check(not stage.debug_overlay().visible, "debug_toggle hides GreyboxDebugOverlay")
	var toggle_on: Dictionary = stage.trigger_action(GreyboxGridMetrics.ACTION_DEBUG_TOGGLE)
	_check(bool(toggle_on.get("ok", false)), "second debug_toggle action is handled")
	_check(stage.debug_overlay().visible, "second debug_toggle shows GreyboxDebugOverlay")
	_check_equal(
		stage.session().domain_state_hash(),
		hash_before_toggle,
		"debug_toggle does not mutate WorldState"
	)

	var echo_key := InputEventKey.new()
	echo_key.pressed = true
	echo_key.echo = true
	echo_key.physical_keycode = KEY_W
	_check_equal(
		GreyboxInputController.resolve_action_from_event(echo_key),
		&"",
		"echo key event is ignored by GreyboxInputController"
	)

	var save_report: Dictionary = stage.save_offline_campaign("p0f_saved_slot")
	_check(bool(save_report.get("ok", false)), "stage saves offline campaign slot")
	var saved_hash: String = stage.session().domain_state_hash()

	var unbind_status: Dictionary = stage.bind_session(null)
	var unbind_overlay: Dictionary = unbind_status.get("debug_snapshot", {})
	_check_equal(
		String(unbind_overlay.get("role", "")),
		"inactive",
		"bind_session(null) resets overlay role to inactive"
	)
	_check(
		stage.chunk_view().hydrated_entity_ids().is_empty(),
		"bind_session(null) dehydrates chunk views"
	)
	_destroy_node(stage)

	var loaded_stage := _instantiate_stage()
	if loaded_stage != null:
		var load_report: Dictionary = loaded_stage.load_offline_campaign(
			"p0f_saved_slot", "host", "Host"
		)
		_check(bool(load_report.get("ok", false)), "new stage loads saved campaign slot")
		_check_equal(
			loaded_stage.session().domain_state_hash(),
			saved_hash,
			"loaded stage restores exact domain_state_hash"
		)
		if loaded_stage.chunk_view().local_actor_view() != null:
			_check_equal(
				loaded_stage.chunk_view().local_actor_view().tile_position,
				Vector2i(2, 3),
				"loaded stage hydrates actor at saved tile (2,3)"
			)
		var next_preset: String = loaded_stage.cycle_texture_quality_preset()
		_check_equal(
			next_preset,
			SettingsManager.TEXTURE_QUALITY_GREYBOX,
			"stage cycles texture quality preset from high to greybox"
		)
		_check_equal(
			loaded_stage.session().domain_state_hash(),
			saved_hash,
			"cycling client texture quality preset never mutates domain_state_hash"
		)
		SettingsManager.set_texture_quality(SettingsManager.TEXTURE_QUALITY_HIGH)
		var p1_enable: Dictionary = loaded_stage.enable_p1_slice()
		_check(bool(p1_enable.get("ok", false)), "stage enables P1 ecological and NPC slice")
		var p1_snap: Dictionary = loaded_stage.debug_overlay().last_snapshot()
		_check_equal(
			int(p1_snap.get("p1_npcs_count", 0)),
			8,
			"debug overlay snapshot reports 8 active P1 anchor NPCs"
		)
		var chunk_summary: Dictionary = loaded_stage.chunk_view().presentation_summary()
		_check_equal(
			int(chunk_summary.get("p1_basin_nodes_count", 0)),
			4,
			"chunk presentation summary reports 4 P1 basin nodes"
		)
		_check_equal(
			int(chunk_summary.get("p1_npcs_count", 0)),
			8,
			"chunk presentation summary reports 8 P1 anchor NPCs"
		)
		var pebble_tex := SevaraVisualTheme.load_canvas_texture("tex_riverbed_pebbles", true)
		_check(
			pebble_tex is CanvasTexture,
			"SevaraVisualTheme loads CanvasTexture with diffuse + normal map"
		)
		var zoom_step_1 := loaded_stage.cycle_camera_zoom()
		_check(
			is_equal_approx(zoom_step_1, 1.45), "stage camera cycles to close inspection zoom 1.45x"
		)
		var zoom_step_2 := loaded_stage.cycle_camera_zoom()
		_check(
			is_equal_approx(zoom_step_2, 0.65),
			"stage camera cycles to overview tactical zoom 0.65x"
		)
		_destroy_node(loaded_stage)


func _test_networked_two_stage_presentation() -> void:
	_host_session = _make_session("NetHostSession")
	_client_session = _make_session("NetClientSession")
	var host_stage := _instantiate_stage()
	var client_stage := _instantiate_stage()
	if host_stage == null or client_stage == null:
		_cleanup_network_nodes(host_stage, client_stage)
		return

	host_stage.bind_session(_host_session)
	client_stage.bind_session(_client_session)

	var port := _start_host_on_available_port(_host_session)
	_check(port > 0, "network host starts for presentation test on port %d" % port)
	if port <= 0:
		_cleanup_network_nodes(host_stage, client_stage)
		return

	var client_start: Dictionary = _client_session.start_client("127.0.0.1", port, "guest", "Guest")
	_check(bool(client_start.get("ok", false)), "network client starts for presentation test")
	var joined: bool = await _wait_until(Callable(self, "_is_network_pair_ready"), 5000)
	_check(
		joined,
		(
			"client stage receives welcome snapshot (host=%s client=%s h_ev=%s c_ev=%s)"
			% [
				str(_host_session.session_status()),
				str(_client_session.session_status()),
				str(_host_session.take_local_events()),
				str(_client_session.take_local_events()),
			]
		)
	)
	if not joined:
		_cleanup_network_nodes(host_stage, client_stage)
		return

	host_stage.refresh_presentation()
	client_stage.refresh_presentation()

	_check_equal(
		host_stage.chunk_view().hydrated_entity_ids().size(),
		3,
		"host stage hydrates two bodies and one crate"
	)
	_check_equal(
		client_stage.chunk_view().hydrated_entity_ids().size(),
		3,
		"client stage hydrates two bodies and one crate"
	)
	var host_local_actor := host_stage.chunk_view().local_actor_view()
	var client_local_actor := client_stage.chunk_view().local_actor_view()
	_check(
		host_local_actor != null and client_local_actor != null, "both stages resolve local body"
	)
	if host_local_actor != null and client_local_actor != null:
		_check_equal(host_local_actor.tile_position, Vector2i(2, 2), "host local actor tile")
		_check_equal(client_local_actor.tile_position, Vector2i(4, 2), "client local actor tile")
		_check_equal(
			host_stage.camera().position,
			host_local_actor.position,
			"host Camera2D focuses host body"
		)
		_check_equal(
			client_stage.camera().position,
			client_local_actor.position,
			"client Camera2D focuses guest body"
		)

	var client_move: Dictionary = client_stage.trigger_action(GreyboxGridMetrics.ACTION_MOVE_DOWN)
	_check(bool(client_move.get("ok", false)), "client stage submits move_down intent over ENet")
	var synced: bool = await _wait_until(Callable(self, "_did_guest_reach_tile_4_3"), 5000)
	_check(synced, "guest move_down replicates to both host and client stages")

	host_stage.refresh_presentation()
	client_stage.refresh_presentation()
	var host_overlay: Dictionary = host_stage.debug_overlay().last_snapshot()
	var client_overlay: Dictionary = client_stage.debug_overlay().last_snapshot()
	_check_equal(
		String(host_overlay.get("state_hash", "host")),
		String(client_overlay.get("state_hash", "client")),
		"host and client debug overlays report identical state_hash"
	)
	if client_stage.chunk_view().local_actor_view() != null:
		_check_equal(
			client_stage.chunk_view().local_actor_view().tile_position,
			Vector2i(4, 3),
			"client local ActorView updated to (4,3) after snapshot"
		)

	_cleanup_network_nodes(host_stage, client_stage)


func _instantiate_stage() -> GreyboxStage:
	var packed := load(GREYBOX_STAGE_SCENE) as PackedScene
	_check(packed != null, "GreyboxStage scene loads")
	if packed == null:
		return null
	var stage := packed.instantiate() as GreyboxStage
	_check(stage != null, "GreyboxStage instantiates")
	if stage == null:
		return null
	stage.auto_start_offline = false
	stage.save_root_dir = TEST_SAVE_ROOT
	add_child(stage)
	return stage


func _make_session(node_name: String) -> GameSession:
	var session := GameSession.new()
	session.name = node_name
	session.save_root_dir = TEST_SAVE_ROOT
	add_child(session)
	return session


func _start_host_on_available_port(session: GameSession) -> int:
	for offset in range(25):
		var candidate_port := 25140 + offset
		var report: Dictionary = session.start_new_host(
			"p0f_net", 654321, candidate_port, "host", "Host"
		)
		if bool(report.get("ok", false)):
			return candidate_port
	return -1


func _is_network_pair_ready() -> bool:
	if _host_session == null or _client_session == null:
		return false
	var client_status: Dictionary = _client_session.session_status()
	return (
		bool(client_status.get("client_ready", false))
		and _host_session.domain_state_hash() == _client_session.domain_state_hash()
	)


func _did_guest_reach_tile_4_3() -> bool:
	if not _is_network_pair_ready():
		return false
	var guest_id := GreyboxWorld.find_body(_client_session.world_state(), "guest")
	if guest_id < 1:
		return false
	var tile := GreyboxWorld.position_from_component(
		_client_session.world_state().get_entity_component(
			guest_id, GreyboxWorld.POSITION_COMPONENT
		),
		_client_session.greybox_width_tiles,
		_client_session.greybox_height_tiles
	)
	return tile == Vector2i(4, 3)


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_msec:
		if _host_session != null:
			_host_session.poll_transport()
			_host_session.process_pending_intents()
		if _client_session != null:
			_client_session.poll_transport()
		if bool(predicate.call()):
			return true
		OS.delay_msec(2)
		await get_tree().process_frame
	return bool(predicate.call())


func _cleanup_network_nodes(host_stage: GreyboxStage, client_stage: GreyboxStage) -> void:
	_destroy_node(client_stage)
	_destroy_node(host_stage)
	if _client_session != null and is_instance_valid(_client_session):
		_client_session.stop_session()
		_client_session.free()
		_client_session = null
	if _host_session != null and is_instance_valid(_host_session):
		_host_session.stop_session()
		_host_session.free()
		_host_session = null


func _destroy_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])

extends Node
## Captures real engine screenshots from Godot 4.7.2 under Xvfb/OpenGL3.
##
## Saves 4 screenshots into `res://docs/art/godot_captures/`:
## 1) `01_godot_main_menu.png` — Main Menu scene
## 2) `02_godot_stage_p1_morning_clean.png` — GreyboxStage with P1 enabled (morning, HIGH textures)
## 3) `03_godot_stage_p1_dusk_silted_debug.png` — GreyboxStage in dusk + wild Kevalu + DebugOverlay
## 4) `04_godot_stage_greybox_comparison.png` — GreyboxStage in diagnostic `greybox` preset

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu/main_menu.tscn"
const STAGE_SCENE := "res://scenes/levels/greybox_stage.tscn"
const CAPTURE_DIR := "res://docs/art/godot_captures"
const CAPTURE_SAVE_ROOT := "user://tests/godot_captures"


func _ready() -> void:
	call_deferred("_run_captures")


func _run_captures() -> void:
	var abs_dir := ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	SettingsManager.set_language("ru")
	SettingsManager.set_texture_quality(SettingsManager.TEXTURE_QUALITY_HIGH)

	await _capture_main_menu(abs_dir)
	await _capture_stage_states(abs_dir)

	print("GODOT_SCREENSHOTS_CAPTURED_OK")
	get_tree().quit(0)


func _capture_main_menu(abs_dir: String) -> void:
	var packed := load(MAIN_MENU_SCENE) as PackedScene
	if packed == null:
		return
	var menu := packed.instantiate()
	add_child(menu)
	await _wait_frames(4)
	_save_viewport_png(abs_dir.path_join("01_godot_main_menu.png"))
	menu.free()


func _capture_stage_states(abs_dir: String) -> void:
	var packed := load(STAGE_SCENE) as PackedScene
	if packed == null:
		return
	var stage := packed.instantiate() as GreyboxStage
	if stage == null:
		return
	stage.auto_start_offline = false
	stage.save_root_dir = CAPTURE_SAVE_ROOT
	add_child(stage)

	stage.start_offline_campaign("sevara_p1_showcase", 4072026, "host", "Путник")
	stage.enable_p1_slice()
	stage.session().advance_simulation_minutes(480)
	for _step in range(3):
		stage.trigger_action(&"move_down", true)
		stage.trigger_action(&"move_right", true)
	SettingsManager.set_texture_quality(SettingsManager.TEXTURE_QUALITY_HIGH)
	stage.refresh_presentation()
	stage.debug_overlay().visible = false
	stage.world_3d().set_camera_preset(1, Vector2i(12, 11))

	await _wait_frames(4)
	_save_viewport_png(abs_dir.path_join("02_godot_stage_p1_morning_clean.png"))

	# Capture close-up low-angle 3D view showing 3D buildings, trees, horizon & sky
	stage.world_3d().set_camera_preset(2, Vector2i(11, 11))
	await _wait_frames(4)
	_save_viewport_png(abs_dir.path_join("04_godot_stage_greybox_comparison.png"))

	stage.session().submit_intent(
		SessionProtocol.INTENT_ECO_INTERVENTION,
		{"intervention": SevaraEcoChain.INTERVENTION_CLEAR_NAVELU_DAM}
	)
	stage.session().submit_intent(
		SessionProtocol.INTENT_ECO_INTERVENTION,
		{"intervention": SevaraEcoChain.INTERVENTION_RELEASE_KEVALU_WILD}
	)
	stage.session().process_pending_intents()
	stage.session().advance_simulation_minutes(600)
	stage.refresh_presentation()
	stage.debug_overlay().visible = true
	stage.world_3d().set_camera_preset(1, Vector2i(12, 11))

	await _wait_frames(4)
	_save_viewport_png(abs_dir.path_join("03_godot_stage_p1_dusk_silted_debug.png"))

	stage.free()


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
	RenderingServer.force_draw(false)


func _save_viewport_png(output_path: String) -> void:
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		return
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(output_path)

extends Control
## Игровой экран: палуба, HUD, карточки памяти, стройка, журнал, итоги ночи.

signal exit_requested
signal restart_requested

const Palette = preload("res://src/core/palette.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const WakeViewScript = preload("res://src/game/wake_view.gd")

var wake_view: Control
var watch_timer: Timer
var day_label: Label
var watch_label: Label
var light_label: Label
var faith_label: Label
var resources_label: Label
var light_bar: ProgressBar
var faith_bar: ProgressBar
var follower_box: VBoxContainer
var cult_stats_label: Label
var log_label: RichTextLabel
var pause_overlay: Control
var pause_button: Button
var feed_button: Button
var miracle_button: Button
var journal_button: Button
var build_button: Button
var save_button: Button

var _modal: Control
var _pending_building_id := ""
var _log_lines: Array = []


func _ready() -> void:
	theme = UiKit.make_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	_log_lines = GameState.log_history.duplicate()

	_build_world()
	_build_top_bar()
	_build_cult_panel()
	_build_log_panel()
	_build_bottom_bar()
	_build_pause_overlay()
	_build_timer()
	_connect_events()
	_refresh_all()
	_sync_timer()


func _build_world() -> void:
	wake_view = WakeViewScript.new()
	wake_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wake_view.follower_clicked.connect(_open_follower_modal)
	wake_view.slot_clicked.connect(_on_slot_clicked)
	wake_view.cancel_requested.connect(_on_build_cancelled)
	add_child(wake_view)


func _build_top_bar() -> void:
	var panel := UiKit.panel()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 24.0
	panel.offset_top = 16.0
	panel.offset_right = -24.0
	panel.offset_bottom = 92.0
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	day_label = UiKit.label("Ночь 1 из 3", 18, Palette.AMBER)
	row.add_child(day_label)

	watch_label = UiKit.label("Вахта 1/6 · Сумерки", 14, Palette.MUTED)
	row.add_child(watch_label)

	row.add_child(UiKit.hspacer(0))

	row.add_child(UiKit.label("Свет", 14, Palette.MUTED))
	light_bar = UiKit.stat_bar(45.0, 100.0, Palette.AMBER)
	light_bar.custom_minimum_size = Vector2(190, 16)
	row.add_child(light_bar)
	light_label = UiKit.label("45", 14, Palette.TEXT)
	light_label.custom_minimum_size = Vector2(42, 0)
	row.add_child(light_label)

	row.add_child(UiKit.label("Вера", 14, Palette.MUTED))
	faith_bar = UiKit.stat_bar(50.0, 100.0, Palette.HOPE)
	faith_bar.custom_minimum_size = Vector2(110, 12)
	row.add_child(faith_bar)
	faith_label = UiKit.label("50", 14, Palette.TEXT)
	row.add_child(faith_label)

	row.add_child(UiKit.hspacer(0))

	resources_label = UiKit.label("", 13, Palette.SALT)
	row.add_child(resources_label)


func _build_cult_panel() -> void:
	var panel := UiKit.panel()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24.0
	panel.offset_top = 108.0
	panel.offset_right = 324.0
	panel.offset_bottom = 610.0
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var heading := UiKit.label("Культ Уэйка", 21, Palette.AMBER)
	column.add_child(heading)

	column.add_child(UiKit.wrapped_label("Нажми на имя, чтобы открыть воспоминания.", 12, Palette.MUTED))
	column.add_child(UiKit.separator())

	follower_box = VBoxContainer.new()
	follower_box.add_theme_constant_override("separation", 6)
	follower_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(follower_box)

	column.add_child(UiKit.separator())
	cult_stats_label = UiKit.label("", 12, Palette.MUTED)
	column.add_child(cult_stats_label)


func _build_log_panel() -> void:
	var panel := UiKit.panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -344.0
	panel.offset_top = 108.0
	panel.offset_right = -24.0
	panel.offset_bottom = 610.0
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	column.add_child(UiKit.label("Хроника", 21, Palette.AMBER))
	column.add_child(UiKit.separator())

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = false
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, 100)
	log_label.add_theme_font_size_override("normal_font_size", 14)
	log_label.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(log_label)


func _build_bottom_bar() -> void:
	var panel := UiKit.panel()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 24.0
	panel.offset_top = -92.0
	panel.offset_right = -24.0
	panel.offset_bottom = -20.0
	add_child(panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	feed_button = UiKit.button("Дерево · +3 света", 14)
	feed_button.custom_minimum_size = Vector2(150, 44)
	feed_button.tooltip_text = "Сжечь доску, чтобы поддержать Уголёк"
	feed_button.pressed.connect(_on_feed_pressed)
	row.add_child(feed_button)

	miracle_button = UiKit.gold_button("Чудо · −1 страница", 14)
	miracle_button.custom_minimum_size = Vector2(170, 44)
	miracle_button.tooltip_text = "Мгновенный свет ценой страницы Журнала"
	miracle_button.pressed.connect(_on_miracle_pressed)
	row.add_child(miracle_button)

	build_button = UiKit.button("Строить", 14)
	build_button.custom_minimum_size = Vector2(110, 44)
	build_button.pressed.connect(_open_build_modal)
	row.add_child(build_button)

	journal_button = UiKit.button("Журнал (8)", 14)
	journal_button.custom_minimum_size = Vector2(140, 44)
	journal_button.pressed.connect(_open_journal_modal)
	row.add_child(journal_button)

	pause_button = UiKit.button("Пауза", 14)
	pause_button.custom_minimum_size = Vector2(100, 44)
	pause_button.pressed.connect(_toggle_pause)
	row.add_child(pause_button)

	save_button = UiKit.button("Сохранить", 14)
	save_button.custom_minimum_size = Vector2(120, 44)
	save_button.pressed.connect(_on_save_pressed)
	row.add_child(save_button)

	var menu_button := UiKit.button("В меню", 14)
	menu_button.custom_minimum_size = Vector2(100, 44)
	menu_button.pressed.connect(_exit_to_menu)
	row.add_child(menu_button)


func _build_pause_overlay() -> void:
	pause_overlay = Control.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.visible = false
	add_child(pause_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(shade)

	var label := UiKit.label("ПАУЗА", 52, Palette.AMBER)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(label)


func _build_timer() -> void:
	watch_timer = Timer.new()
	watch_timer.wait_time = float(Database.config.get("seconds_per_watch", 8.0))
	watch_timer.one_shot = false
	watch_timer.autostart = false
	watch_timer.timeout.connect(_on_watch_timeout)
	add_child(watch_timer)


func _connect_events() -> void:
	EventBus.light_changed.connect(_on_light_changed)
	EventBus.faith_changed.connect(_on_faith_changed)
	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.followers_changed.connect(_on_followers_changed)
	EventBus.journal_changed.connect(_on_journal_changed)
	EventBus.buildings_changed.connect(_on_buildings_changed)
	EventBus.log_added.connect(_on_log_added)
	EventBus.toast_requested.connect(_on_toast)
	EventBus.running_changed.connect(_on_running_changed)
	EventBus.pause_changed.connect(_on_pause_changed)
	EventBus.night_ended.connect(_on_night_ended)
	EventBus.demo_completed.connect(_on_demo_completed)
	EventBus.game_over.connect(_on_game_over)


func _refresh_all() -> void:
	_on_light_changed(GameState.light, GameState.ember_max())
	_on_faith_changed(GameState.faith)
	_on_resources_changed(GameState.resources)
	_on_day_changed(GameState.day, GameState.watch, int(Database.config.get("watches_per_night", 6)), GameState.phase_title())
	_on_journal_changed(GameState.journal_pages, GameState.lost_entries.size())
	_rebuild_followers()
	_rebuild_log()
	_refresh_buttons()


func _on_light_changed(value: float, maximum: float) -> void:
	if light_bar == null:
		return
	light_bar.max_value = maximum
	light_bar.value = value
	light_label.text = str(int(value))
	var fill := Palette.DANGER if value < 25.0 else Palette.AMBER
	light_bar.add_theme_stylebox_override("fill", UiKit.box(fill, fill, 0, 6))


func _on_faith_changed(value: float) -> void:
	if faith_bar == null:
		return
	faith_bar.value = value
	faith_label.text = str(int(value))


func _on_resources_changed(values: Dictionary) -> void:
	if resources_label == null:
		return
	var parts: Array = []
	for item_id in Database.item_order:
		var item := Database.get_item(str(item_id))
		parts.append("%s %d" % [item.get("name", item_id), int(values.get(item_id, 0.0))])
	resources_label.text = " · ".join(PackedStringArray(parts))
	_refresh_buttons()


func _on_day_changed(day: int, watch: int, total_watches: int, phase: String) -> void:
	if day_label == null:
		return
	var total_nights := int(Database.config.get("nights_to_survive", 3))
	day_label.text = "Ночь %d из %d" % [day, total_nights]
	var current_watch := mini(watch + 1, total_watches)
	watch_label.text = "Вахта %d/%d · %s" % [current_watch, total_watches, phase]


func _on_followers_changed() -> void:
	if follower_box == null:
		return
	_rebuild_followers()
	_refresh_buttons()


func _rebuild_followers() -> void:
	UiKit.clear_children(follower_box)
	for follower in GameState.followers:
		var status := ""
		if follower.left:
			status = "ушёл(ла)"
		elif follower.hollow:
			status = "Пол"
		else:
			status = "%d памяти · %d надежды" % [follower.memory_count(), int(follower.hope)]
		var entry := UiKit.button("%s · %s" % [follower.display_name, status], 13)
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.custom_minimum_size = Vector2(0, 56)
		entry.disabled = follower.left
		entry.tooltip_text = str(follower.role)
		if follower.hollow:
			entry.add_theme_color_override("font_color", Palette.MUTED)
		entry.pressed.connect(_open_follower_modal.bind(str(follower.id)))
		follower_box.add_child(entry)

	cult_stats_label.text = "Полов: %d · ушли: %d · построек: %d/8" % [
		int(GameState.flags.get("hollows", 0)),
		int(GameState.flags.get("left", 0)),
		GameState.used_slots()
	]


func _rebuild_log() -> void:
	if log_label == null:
		return
	log_label.text = "\n".join(PackedStringArray(_log_lines))


func _on_log_added(text_value: String) -> void:
	_log_lines.append(text_value)
	if _log_lines.size() > 150:
		_log_lines.pop_front()
	_rebuild_log()


func _on_buildings_changed() -> void:
	if cult_stats_label == null:
		return
	_rebuild_followers()
	_refresh_buttons()


func _on_journal_changed(pages: int, lost: int) -> void:
	if journal_button == null:
		return
	journal_button.text = "Журнал (%d)" % pages
	journal_button.tooltip_text = "Потеряно страниц: %d" % lost
	var color := Palette.DANGER if pages <= 3 else Palette.TEXT
	journal_button.add_theme_color_override("font_color", color)
	_refresh_buttons()


func _on_running_changed(_is_running: bool) -> void:
	_refresh_buttons()
	_sync_timer()


func _on_pause_changed(_is_paused: bool) -> void:
	_refresh_buttons()
	_sync_timer()


func _refresh_buttons() -> void:
	if feed_button == null:
		return
	var wood_cost := float(Database.config.get("wood_feed_cost", 1.0))
	var can_act := GameState.running and GameState.can_act()
	feed_button.text = "Дерево · +%d света" % int(Database.config.get("wood_feed_light", 3.0))
	feed_button.disabled = not can_act or float(GameState.resources.get("wood", 0.0)) < wood_cost
	miracle_button.disabled = not can_act or GameState.journal_pages <= 0
	build_button.disabled = not can_act or not GameState.has_free_slot()
	journal_button.disabled = not GameState.can_act()
	pause_button.disabled = not GameState.running
	pause_button.text = "Продолжить" if GameState.paused else "Пауза"
	save_button.disabled = not can_act


func _sync_timer() -> void:
	if watch_timer == null:
		return
	if not GameState.running:
		watch_timer.stop()
	else:
		var build_pending: bool = wake_view != null and wake_view.build_mode
		var should_run := not GameState.paused and _modal == null and not build_pending
		if watch_timer.is_stopped():
			watch_timer.start()
		watch_timer.paused = not should_run
	if pause_overlay != null:
		pause_overlay.visible = GameState.paused and _modal == null


func _on_watch_timeout() -> void:
	GameState.advance_watch()
	_sync_timer()


func _toggle_pause() -> void:
	if not GameState.running:
		return
	GameState.toggle_pause()


func _on_feed_pressed() -> void:
	GameState.feed_wood()


func _on_miracle_pressed() -> void:
	GameState.miracle()


func _on_save_pressed() -> void:
	if SaveSystem.save_game():
		EventBus.toast_requested.emit("Вахта сохранена")


func _exit_to_menu() -> void:
	if GameState.demo_over:
		SaveSystem.delete_save()
	elif GameState.running:
		SaveSystem.save_game()
	exit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _modal != null:
		# Финальные окна (рассвет, поражение, финал демо) нельзя закрыть Esc:
		# иначе игрок остаётся на мёртвом экране без кнопки продолжения.
		if GameState.running and GameState.can_act():
			_close_modal()
	elif wake_view.build_mode:
		wake_view.cancel_build_mode()
	elif GameState.running:
		GameState.toggle_pause()
	get_viewport().set_input_as_handled()


func _open_modal(content: Control) -> void:
	_close_modal()
	get_viewport().gui_release_focus()
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.68)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.add_child(content)
	overlay.add_child(center)
	add_child(overlay)
	_modal = overlay
	_sync_timer()


func _close_modal() -> void:
	if _modal == null:
		return
	_modal.queue_free()
	_modal = null
	_sync_timer()


func _open_follower_modal(follower_id: String) -> void:
	var follower = GameState.find_follower(follower_id)
	if follower == null:
		return

	var panel := UiKit.panel(Palette.PANEL, 14)
	panel.custom_minimum_size = Vector2(780, 560)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	var name_label := UiKit.label(follower.display_name, 28, follower.color)
	header.add_child(name_label)
	var role_label := UiKit.label(str(follower.role), 14, Palette.MUTED)
	role_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(role_label)
	header.add_child(UiKit.hspacer(0))
	var close_button := UiKit.button("×", 20)
	close_button.custom_minimum_size = Vector2(42, 36)
	close_button.pressed.connect(_close_modal)
	header.add_child(close_button)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	column.add_child(stats)
	stats.add_child(UiKit.label("Надежда", 13, Palette.MUTED))
	var hope_bar := UiKit.stat_bar(follower.hope, 100.0, Palette.HOPE)
	hope_bar.custom_minimum_size = Vector2(140, 12)
	stats.add_child(hope_bar)
	stats.add_child(UiKit.label("Тепло", 13, Palette.MUTED))
	var warmth_bar := UiKit.stat_bar(follower.warmth, 100.0, Palette.AMBER)
	warmth_bar.custom_minimum_size = Vector2(140, 12)
	stats.add_child(warmth_bar)
	stats.add_child(UiKit.label("Близость: %d" % follower.closeness, 13, Palette.MUTED))

	column.add_child(UiKit.wrapped_label(str(follower.bio), 14, Palette.TEXT))
	column.add_child(UiKit.separator())

	if follower.left:
		column.add_child(UiKit.wrapped_label("Этот человек ушёл в туман. Его история закончилась без тебя.", 16, Palette.DANGER))
	elif follower.hollow:
		column.add_child(UiKit.wrapped_label(
			"Перед тобой Пол. Тело помнит, как держать ложку, но не помнит, зачем. Памяти не осталось.",
			16,
			Palette.MUTED
		))
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size = Vector2(0, 320)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 10)
		scroll.add_child(list)
		for memory_id in follower.memories:
			list.add_child(_build_memory_card(follower, str(memory_id), false))
		for memory_id in follower.preserved:
			list.add_child(_build_memory_card(follower, str(memory_id), true))
		column.add_child(scroll)

	_open_modal(panel)


func _build_memory_card(follower, memory_id: String, preserved: bool) -> Control:
	var memory := Database.get_memory(memory_id)
	var card := UiKit.card()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	header.add_child(UiKit.label(str(memory.get("title", "?")), 17, Palette.TEXT))
	var memory_type := str(memory.get("type", "bond"))
	header.add_child(UiKit.chip(_type_name(memory_type), Palette.type_color(memory_type)))
	header.add_child(UiKit.hspacer(0))
	if not preserved and follower.was_read(memory_id):
		header.add_child(UiKit.chip("прочитано", Palette.MUTED))

	column.add_child(UiKit.wrapped_label(str(memory.get("summary", "")), 14, Palette.MUTED))

	if not preserved and follower.was_read(memory_id):
		column.add_child(UiKit.wrapped_label(str(memory.get("text", "")), 13, Palette.TEXT))

	if preserved:
		var note := UiKit.label("Сохранено в Хранилище Памяти", 13, Palette.HOPE)
		column.add_child(note)
		return card

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)

	var burn_button := UiKit.danger_button("Сжечь", 13)
	burn_button.custom_minimum_size = Vector2(110, 34)
	burn_button.tooltip_text = "Свет +%d. %s" % [int(memory.get("burn_light", 18.0)), str(memory.get("burn", ""))]
	burn_button.pressed.connect(_open_confirm_burn.bind(str(follower.id), memory_id))
	actions.add_child(burn_button)

	var keep_cost := int(Database.config.get("keep_memory_wax_cost", 2.0))
	var keep_button := UiKit.button("Сохранить · %d воска" % keep_cost, 13)
	keep_button.custom_minimum_size = Vector2(180, 34)
	keep_button.tooltip_text = "Надежда +%d. Память останется в Хранилище." % int(memory.get("keep_hope", 6.0))
	keep_button.pressed.connect(_keep_memory.bind(str(follower.id), memory_id))
	actions.add_child(keep_button)

	var read_button := UiKit.button("Прочесть", 13)
	read_button.custom_minimum_size = Vector2(110, 34)
	read_button.disabled = follower.was_read(memory_id)
	read_button.pressed.connect(_read_memory.bind(str(follower.id), memory_id))
	actions.add_child(read_button)

	return card


func _type_name(memory_type: String) -> String:
	match memory_type:
		"joy":
			return "Радость"
		"grief":
			return "Горе"
		"skill":
			return "Навык"
		"bond":
			return "Связь"
		"secret":
			return "Тайна"
		"debt":
			return "Долг"
		_:
			return memory_type


func _open_confirm_burn(follower_id: String, memory_id: String) -> void:
	var memory := Database.get_memory(memory_id)
	var panel := UiKit.panel(Palette.PANEL, 14)
	panel.custom_minimum_size = Vector2(580, 360)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	column.add_child(UiKit.label("Сжечь память?", 26, Palette.DANGER))
	column.add_child(UiKit.wrapped_label("«%s»" % str(memory.get("title", "?")), 18, Palette.AMBER))
	column.add_child(UiKit.wrapped_label(str(memory.get("burn", "")), 15, Palette.TEXT))
	column.add_child(UiKit.wrapped_label(
		"Уголёк получит +%d света. Это нельзя отменить." % int(memory.get("burn_light", 18.0)),
		15,
		Palette.MUTED
	))
	column.add_child(UiKit.spacer(8))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)

	var confirm := UiKit.danger_button("Сжечь навсегда", 15)
	confirm.custom_minimum_size = Vector2(240, 44)
	confirm.pressed.connect(_burn_memory.bind(follower_id, memory_id))
	actions.add_child(confirm)

	var cancel := UiKit.button("Оставить", 15)
	cancel.custom_minimum_size = Vector2(200, 44)
	cancel.pressed.connect(_cancel_burn.bind(follower_id))
	actions.add_child(cancel)

	_open_modal(panel)


func _cancel_burn(follower_id: String) -> void:
	_close_modal()
	_open_follower_modal(follower_id)


func _burn_memory(follower_id: String, memory_id: String) -> void:
	if GameState.burn_memory(follower_id, memory_id):
		_close_modal()
		_open_follower_modal(follower_id)


func _keep_memory(follower_id: String, memory_id: String) -> void:
	if GameState.keep_memory(follower_id, memory_id):
		_close_modal()
		_open_follower_modal(follower_id)


func _read_memory(follower_id: String, memory_id: String) -> void:
	if GameState.read_memory(follower_id, memory_id):
		_close_modal()
		_open_follower_modal(follower_id)


func _open_build_modal() -> void:
	var panel := UiKit.panel(Palette.PANEL, 14)
	panel.custom_minimum_size = Vector2(700, 560)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(UiKit.label("Строить на палубе", 24, Palette.AMBER))
	header.add_child(UiKit.hspacer(0))
	var close_button := UiKit.button("×", 20)
	close_button.custom_minimum_size = Vector2(42, 36)
	close_button.pressed.connect(_close_modal)
	header.add_child(close_button)

	column.add_child(UiKit.wrapped_label("Каждая постройка работает каждую вахту. Мест на палубе: %d, свободно: %d." % [
		int(Database.config.get("build_slots", 8)),
		int(Database.config.get("build_slots", 8)) - GameState.used_slots()
	], 13, Palette.MUTED))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	column.add_child(scroll)

	var order: Array = Database.building_order
	if order.is_empty():
		order = Database.buildings.keys()
	for building_id in order:
		list.add_child(_build_building_card(str(building_id)))

	_open_modal(panel)


func _build_building_card(building_id: String) -> Control:
	var data := Database.get_building(building_id)
	var card := UiKit.card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var color := Color.from_string(str(data.get("color", "#2E6B6B")), Palette.TEAL)
	info.add_child(UiKit.label(str(data.get("name", building_id)), 18, color))
	info.add_child(UiKit.wrapped_label(str(data.get("description", "")), 13, Palette.MUTED))
	info.add_child(UiKit.label("Цена: %s" % _format_cost(data.get("cost", {})), 13, Palette.SALT))
	var production := _format_production(data)
	if not production.is_empty():
		info.add_child(UiKit.label(production, 13, Palette.HOPE))

	var select_button := UiKit.gold_button("Выбрать", 14)
	select_button.custom_minimum_size = Vector2(110, 44)
	select_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	select_button.disabled = not GameState.can_afford(data.get("cost", {})) or not GameState.has_free_slot()
	select_button.pressed.connect(_select_building.bind(building_id))
	row.add_child(select_button)
	return card


func _format_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for item_id in cost.keys():
		parts.append("%s %d" % [Database.get_item(str(item_id)).get("name", item_id), int(cost[item_id])])
	return " · ".join(PackedStringArray(parts))


func _format_production(data: Dictionary) -> String:
	var parts: Array = []
	var production: Dictionary = data.get("production", {})
	for item_id in production.keys():
		parts.append("%s +%d за вахту" % [Database.get_item(str(item_id)).get("name", item_id), int(production[item_id])])
	var hope := float(data.get("hope_per_watch", 0.0))
	if hope > 0.0:
		parts.append("надежда +%d за вахту" % int(hope))
	return " · ".join(PackedStringArray(parts))


func _select_building(building_id: String) -> void:
	_pending_building_id = building_id
	_close_modal()
	wake_view.set_build_mode(true, building_id)
	_sync_timer()
	EventBus.toast_requested.emit("Выберите свободное место на палубе. ПКМ — отмена.")


func _on_slot_clicked(slot: int) -> void:
	if _pending_building_id.is_empty():
		return
	var result: Dictionary = GameState.build(_pending_building_id, slot)
	EventBus.toast_requested.emit(str(result.get("message", "")))
	if bool(result.get("ok", false)):
		_pending_building_id = ""
		wake_view.set_build_mode(false)
		_sync_timer()


func _on_build_cancelled() -> void:
	_pending_building_id = ""
	_sync_timer()
	EventBus.toast_requested.emit("Строительство отменено")


func _open_journal_modal() -> void:
	var panel := UiKit.panel(Palette.PANEL, 14)
	panel.custom_minimum_size = Vector2(700, 560)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(UiKit.label("Журнал Хранителя", 24, Palette.AMBER))
	header.add_child(UiKit.hspacer(0))
	var close_button := UiKit.button("×", 20)
	close_button.custom_minimum_size = Vector2(42, 36)
	close_button.pressed.connect(_close_modal)
	header.add_child(close_button)

	column.add_child(UiKit.wrapped_label(
		"Страниц осталось: %d. Потеряно: %d. Каждое чудо Уголька сжигает одну страницу — и один кусок того, кем ты был." % [
			GameState.journal_pages,
			GameState.lost_entries.size()
		],
		14,
		Palette.TEXT
	))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 330)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	column.add_child(scroll)

	for entry in GameState.journal_entries:
		list.add_child(UiKit.wrapped_label("— %s" % str(entry.get("text", "")), 15, Palette.TEXT))
	if GameState.lost_entries.is_empty():
		list.add_child(UiKit.wrapped_label("Пока ничего не потеряно.", 14, Palette.MUTED))
	else:
		list.add_child(UiKit.spacer(8))
		list.add_child(UiKit.label("Сожжённые страницы", 14, Palette.DANGER))
		for entry in GameState.lost_entries:
			list.add_child(UiKit.wrapped_label("× %s" % str(entry.get("text", "")), 13, Palette.MUTED))

	var miracle := UiKit.gold_button("Сжечь страницу ради чуда (+%d света)" % int(Database.config.get("miracle_light", 30.0)), 14)
	miracle.disabled = GameState.journal_pages <= 0
	miracle.pressed.connect(_journal_miracle)
	column.add_child(miracle)

	_open_modal(panel)


func _journal_miracle() -> void:
	if GameState.miracle():
		_close_modal()
		if GameState.is_game_over:
			_open_game_over_modal(GameState.ending_reason)
		else:
			_open_journal_modal()


func _on_night_ended(summary: Dictionary) -> void:
	call_deferred("_open_summary_modal", summary)


func _open_summary_modal(summary: Dictionary) -> void:
	var panel := UiKit.panel(Palette.PANEL, 14)
	panel.custom_minimum_size = Vector2(620, 480)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	column.add_child(UiKit.label("Рассвет", 30, Palette.AMBER))
	column.add_child(UiKit.wrapped_label("Уэйк дожил до утра. Свет ещё горит, но следующая ночь будет темнее.", 15, Palette.TEXT))
	column.add_child(UiKit.separator())
	column.add_child(UiKit.wrapped_label(_summary_text(summary), 15, Palette.TEXT))
	column.add_child(UiKit.spacer(12))

	var next_button := UiKit.gold_button("Следующая ночь", 17)
	next_button.custom_minimum_size = Vector2(320, 48)
	next_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_button.pressed.connect(_start_next_night)
	column.add_child(next_button)

	_open_modal(panel)


func _start_next_night() -> void:
	_close_modal()
	GameState.start_next_night()
	_sync_timer()


func _on_demo_completed(summary: Dictionary) -> void:
	call_deferred("_open_demo_modal", summary)


func _open_demo_modal(summary: Dictionary) -> void:
	var panel := UiKit.panel(Palette.PANEL, 14)
	panel.custom_minimum_size = Vector2(640, 520)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	column.add_child(UiKit.label("Третье утро", 30, Palette.AMBER))
	column.add_child(UiKit.wrapped_label(
		"Уэйк пережил три ночи. Где-то в тумане Хор поёт твою песню, Соляной Двор считает твой долг, а под водой кит видит сон о тебе.\n\n"
		+ "Это конец демо — и начало пути. Дальше: Отмели, маяк и первая встреча с Кантором.",
		16,
		Palette.TEXT
	))
	column.add_child(UiKit.separator())
	column.add_child(UiKit.wrapped_label(_summary_text(summary), 14, Palette.MUTED))
	column.add_child(UiKit.spacer(8))

	var again := UiKit.gold_button("Новая вахта", 16)
	again.custom_minimum_size = Vector2(280, 46)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(_restart)
	column.add_child(again)

	var menu := UiKit.button("В меню", 16)
	menu.custom_minimum_size = Vector2(280, 46)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.pressed.connect(_exit_to_menu)
	column.add_child(menu)

	_open_modal(panel)


func _on_game_over(reason: String) -> void:
	call_deferred("_open_game_over_modal", reason)


func _open_game_over_modal(reason: String) -> void:
	var panel := UiKit.panel(Palette.PANEL, 14)
	panel.custom_minimum_size = Vector2(640, 480)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	column.add_child(UiKit.label("Тишина", 32, Palette.DANGER))
	column.add_child(UiKit.wrapped_label(reason, 16, Palette.TEXT))
	column.add_child(UiKit.separator())
	column.add_child(UiKit.wrapped_label(_summary_text(GameState.get_summary()), 14, Palette.MUTED))
	column.add_child(UiKit.spacer(8))

	var again := UiKit.gold_button("Начать заново", 16)
	again.custom_minimum_size = Vector2(280, 46)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(_restart)
	column.add_child(again)

	var menu := UiKit.button("В меню", 16)
	menu.custom_minimum_size = Vector2(280, 46)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.pressed.connect(_exit_to_menu)
	column.add_child(menu)

	_open_modal(panel)


func _restart() -> void:
	_close_modal()
	restart_requested.emit()


func _summary_text(summary: Dictionary) -> String:
	return (
		"Свет: %d · вера: %d\n"
		+ "Сожжено воспоминаний: %d\n"
		+ "Сохранено в Хранилище: %d\n"
		+ "Прочитано: %d\n"
		+ "Полов: %d · ушло людей: %d\n"
		+ "Чудес: %d · страниц осталось: %d"
	) % [
		int(summary.get("light", 0.0)),
		int(summary.get("faith", 0.0)),
		int(summary.get("burned", 0)),
		int(summary.get("kept", 0)),
		int(summary.get("read", 0)),
		int(summary.get("hollows", 0)),
		int(summary.get("left", 0)),
		int(summary.get("miracles", 0)),
		int(summary.get("pages", 0))
	]


func _on_toast(text_value: String) -> void:
	var label := UiKit.label(text_value, 18, Palette.AMBER)
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = 104.0
	label.offset_bottom = 136.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)

	var tween := create_tween()
	tween.tween_interval(1.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: label.queue_free())

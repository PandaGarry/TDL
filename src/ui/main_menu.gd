extends Control
## Главное меню. Пока без арта: рисуем море, кости кита и Уголёк кодом.

signal new_game_requested
signal continue_requested
signal quit_requested

const Palette = preload("res://src/core/palette.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")

const AMBIENT_REDRAW_INTERVAL := 1.0 / 30.0

var _time := 0.0
var _redraw_accum := 0.0
var _continue_button: Button


func _ready() -> void:
	theme = UiKit.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)
	_build()
	set_process(true)


func _on_viewport_resized() -> void:
	size = get_viewport_rect().size
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_redraw_accum += delta
	if _redraw_accum < AMBIENT_REDRAW_INTERVAL:
		return
	_redraw_accum = 0.0
	queue_redraw()


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	column.custom_minimum_size = Vector2(620, 0)
	center.add_child(column)

	var title := UiKit.label("SALTVIGIL", 66, Palette.AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := UiKit.label("СОЛЯНАЯ ВАХТА", 18, Palette.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	column.add_child(UiKit.spacer(14))

	var tagline := UiKit.wrapped_label(
		"Солнце мертво. Веди плавучий культ по костям мёртвого бога.\n"
		+ "Сжигай воспоминания, чтобы горел свет, и реши, кем ты станешь, когда память закончится.",
		16,
		Palette.TEXT
	)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.custom_minimum_size = Vector2(620, 0)
	column.add_child(tagline)

	column.add_child(UiKit.spacer(30))

	var new_button := UiKit.gold_button("Новая вахта", 18)
	new_button.custom_minimum_size = Vector2(380, 50)
	new_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	new_button.pressed.connect(func() -> void: new_game_requested.emit())
	column.add_child(new_button)

	_continue_button = UiKit.button("Продолжить", 18)
	_continue_button.custom_minimum_size = Vector2(380, 50)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.disabled = not SaveSystem.has_save()
	_continue_button.tooltip_text = "Сохранение появится после первого рассвета"
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	column.add_child(_continue_button)

	var quit_button := UiKit.button("Выход", 18)
	quit_button.custom_minimum_size = Vector2(380, 50)
	quit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit_button)

	var footer := UiKit.label("M1 preview · v0.2.0 · Godot 4.7", 13, Palette.MUTED)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 24.0
	footer.offset_top = -40.0
	footer.offset_right = 460.0
	footer.offset_bottom = -16.0
	add_child(footer)


func _draw() -> void:
	var canvas := size
	if canvas.x < 1.0 or canvas.y < 1.0:
		canvas = get_viewport_rect().size

	draw_rect(Rect2(Vector2.ZERO, canvas), Palette.WATER_DEEP)

	var horizon := canvas.y * 0.62
	var bands := 18
	for index in bands:
		var t := float(index) / float(bands)
		var color := Palette.WATER_DEEP.lerp(Palette.WATER, t * 0.8)
		draw_rect(Rect2(0, canvas.y * t, canvas.x, canvas.y / bands + 2), color)

	var glow_center := Vector2(canvas.x * 0.5, horizon)
	for radius in [300.0, 220.0, 150.0, 90.0, 48.0]:
		var alpha: float = 0.012 + (300.0 - float(radius)) / 300.0 * 0.03
		draw_circle(glow_center, float(radius), Palette.alpha(Palette.EMBER, alpha))

	for index in 12:
		var y := horizon + 30.0 + index * 26.0
		var points := PackedVector2Array()
		for step in 48:
			var x := canvas.x * float(step) / 47.0
			var wave := sin(float(step) * 0.35 + _time * 0.25 + index) * (2.0 + index * 0.4)
			points.append(Vector2(x, y + wave))
		draw_polyline(points, Palette.alpha(Palette.TEAL, 0.05), 1.0, true)

	for rib in 5:
		var radius := 360.0 + rib * 90.0
		draw_arc(glow_center + Vector2(0, 170), radius, PI * 1.08, PI * 1.92, 64, Palette.alpha(Palette.MUTED, 0.10), 2.0, true)

	var deck := PackedVector2Array([
		Vector2(canvas.x * 0.5 - 260.0, canvas.y - 80.0),
		Vector2(canvas.x * 0.5 - 180.0, canvas.y - 120.0),
		Vector2(canvas.x * 0.5 + 180.0, canvas.y - 120.0),
		Vector2(canvas.x * 0.5 + 260.0, canvas.y - 80.0),
		Vector2(canvas.x * 0.5 + 220.0, canvas.y),
		Vector2(canvas.x * 0.5 - 220.0, canvas.y)
	])
	draw_colored_polygon(deck, Palette.alpha(Palette.DECK_DARK, 0.85))
	var deck_outline := deck.duplicate()
	deck_outline.append(deck[0])
	draw_polyline(deck_outline, Palette.alpha(Palette.DECK_EDGE, 0.5), 2.0, true)

	var ember := glow_center + Vector2(0, 18)
	draw_circle(ember, 16.0, Palette.EMBER)
	draw_circle(ember, 9.0, Palette.AMBER)
	draw_circle(ember, 4.0, Palette.SALT)

	for index in 30:
		var x := fmod(float(index) * 137.0, canvas.x)
		var y := fmod(float(index) * 61.0, horizon * 0.7)
		var twinkle := 0.06 + 0.04 * sin(_time * 0.8 + index)
		draw_circle(Vector2(x, y), 1.2, Palette.alpha(Palette.SALT, twinkle))

extends Control
## Палуба Уэйка: заглушки арта, слоты строительства и токены последователей.
## Всё рисуется кодом, чтобы каркас работал без ассетов.

signal follower_clicked(follower_id: String)
signal slot_clicked(slot_index: int)
signal cancel_requested

const Palette = preload("res://src/core/palette.gd")

const SLOT_SIZE := Vector2(86.0, 50.0)
const TOKEN_RADIUS := 25.0
const DECK_RADIUS := Vector2(440.0, 270.0)
const SLOT_RADIUS := Vector2(320.0, 160.0)
const FOLLOWER_X := [-150.0, 0.0, 150.0]
const FOLLOWER_Y := 225.0

var build_mode := false
var pending_building_id := ""
var time := 0.0
var hover_slot := -1
var hover_follower := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	EventBus.followers_changed.connect(queue_redraw)
	EventBus.buildings_changed.connect(queue_redraw)
	EventBus.light_changed.connect(_on_light_changed)


func _on_light_changed(_value: float, _maximum: float) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func set_build_mode(enabled: bool, building_id: String = "") -> void:
	build_mode = enabled
	pending_building_id = building_id
	hover_slot = -1
	queue_redraw()


func cancel_build_mode() -> void:
	if not build_mode:
		return
	build_mode = false
	pending_building_id = ""
	hover_slot = -1
	cancel_requested.emit()
	queue_redraw()


func _deck_center() -> Vector2:
	return size * 0.5 + Vector2(0.0, 10.0)


func _slot_center(index: int) -> Vector2:
	var angle := TAU * float(index) / 8.0 - PI * 0.5
	return _deck_center() + Vector2(cos(angle) * SLOT_RADIUS.x, sin(angle) * SLOT_RADIUS.y)


func _follower_position(index: int) -> Vector2:
	var x: float = FOLLOWER_X[clampi(index, 0, FOLLOWER_X.size() - 1)]
	return _deck_center() + Vector2(x, FOLLOWER_Y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_hover(motion.position)
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed and build_mode:
			cancel_build_mode()
			accept_event()
			return
		if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
			return
		if build_mode:
			var slot := _slot_at(mouse.position)
			if slot >= 0:
				slot_clicked.emit(slot)
				accept_event()
			return
		var follower_id := _follower_at(mouse.position)
		if not follower_id.is_empty():
			follower_clicked.emit(follower_id)
			accept_event()


func _update_hover(position: Vector2) -> void:
	var new_slot := -1
	var new_follower := ""
	if build_mode:
		new_slot = _slot_at(position)
	else:
		new_follower = _follower_at(position)
	if new_slot != hover_slot or new_follower != hover_follower:
		hover_slot = new_slot
		hover_follower = new_follower
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (hover_slot >= 0 or not hover_follower.is_empty()) else Control.CURSOR_ARROW
		queue_redraw()


func _slot_at(position: Vector2) -> int:
	for index in int(Database.config.get("build_slots", 8)):
		if _slot_occupied(index):
			continue
		var rect := Rect2(_slot_center(index) - SLOT_SIZE * 0.5, SLOT_SIZE)
		if rect.has_point(position):
			return index
	return -1


func _follower_at(position: Vector2) -> String:
	var index := 0
	for follower in GameState.followers:
		if follower.left:
			continue
		if position.distance_to(_follower_position(index)) <= TOKEN_RADIUS + 8.0:
			return str(follower.id)
		index += 1
	return ""


func _slot_occupied(index: int) -> bool:
	for entry in GameState.buildings:
		if int(entry.get("slot", -1)) == index:
			return true
	return false


func _draw() -> void:
	var canvas := size
	if canvas.x < 1.0 or canvas.y < 1.0:
		return

	draw_rect(Rect2(Vector2.ZERO, canvas), Palette.WATER)
	_draw_water(canvas)
	_draw_deck()
	_draw_slots()
	_draw_followers()


func _draw_water(canvas: Vector2) -> void:
	for index in 10:
		var y := canvas.y * (0.08 + float(index) * 0.095)
		var points := PackedVector2Array()
		for step in 40:
			var x := canvas.x * float(step) / 39.0
			points.append(Vector2(x, y + sin(float(step) * 0.4 + time * 0.3 + index) * 4.0))
		draw_polyline(points, Palette.alpha(Palette.TEAL, 0.06), 1.0, true)

	for index in 16:
		var x := fmod(float(index) * 173.0, canvas.x)
		var y := fmod(float(index) * 97.0, canvas.y * 0.45)
		draw_circle(Vector2(x, y), 1.3, Palette.alpha(Palette.SALT, 0.10))


func _draw_deck() -> void:
	var center := _deck_center()
	var shadow := _ellipse_points(center + Vector2(0, 14), DECK_RADIUS + Vector2(6, 6), 28)
	draw_colored_polygon(shadow, Palette.alpha(Palette.WATER_DEEP, 0.75))

	var deck := _ellipse_points(center, DECK_RADIUS, 28)
	draw_colored_polygon(deck, Palette.DECK)
	draw_polyline(deck, Palette.DECK_EDGE, 5.0, true)
	var inner := _ellipse_points(center, DECK_RADIUS - Vector2(26, 24), 28)
	draw_polyline(inner, Palette.alpha(Palette.DECK_EDGE, 0.45), 1.5, true)

	var plank := 56.0
	var x := -DECK_RADIUS.x + plank
	while x < DECK_RADIUS.x - 20.0:
		var ratio := x / DECK_RADIUS.x
		var half := DECK_RADIUS.y * sqrt(maxf(0.0, 1.0 - ratio * ratio)) - 8.0
		if half > 0.0:
			draw_line(center + Vector2(x, -half), center + Vector2(x, half), Palette.alpha(Palette.DECK_DARK, 0.5), 1.0)
		x += plank

	_draw_ember(center)


func _draw_ember(center: Vector2) -> void:
	var ratio := clampf(GameState.light / maxf(GameState.ember_max(), 1.0), 0.0, 1.0)
	var glow := 70.0 + ratio * 90.0
	draw_circle(center, glow, Palette.alpha(Palette.EMBER, 0.035 + ratio * 0.03))
	draw_circle(center, glow * 0.62, Palette.alpha(Palette.EMBER, 0.05 + ratio * 0.04))
	draw_circle(center + Vector2(0, 18), 30.0, Palette.DECK_DARK)
	draw_arc(center + Vector2(0, 18), 30.0, 0.0, TAU, 32, Palette.DECK_EDGE, 4.0, true)
	draw_circle(center + Vector2(0, 18), 16.0, Palette.alpha(Palette.EMBER, 0.55))

	var flame_height := 42.0 + sin(time * 3.1) * 5.0 + ratio * 16.0
	var lean := sin(time * 2.2) * 4.0
	var flame := PackedVector2Array([
		center + Vector2(lean, -flame_height),
		center + Vector2(-16.0, -10.0),
		center + Vector2(0.0, 4.0),
		center + Vector2(16.0, -10.0)
	])
	draw_colored_polygon(flame, Palette.alpha(Palette.EMBER, 0.92))
	var core := PackedVector2Array([
		center + Vector2(lean * 0.6, -flame_height * 0.62),
		center + Vector2(-8.0, -8.0),
		center + Vector2(0.0, 0.0),
		center + Vector2(8.0, -8.0)
	])
	draw_colored_polygon(core, Palette.SALT)

	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-150, 62), "УГОЛЁК", HORIZONTAL_ALIGNMENT_CENTER, 300.0, 13, Palette.alpha(Palette.MUTED, 0.9))


func _draw_slots() -> void:
	var slots := int(Database.config.get("build_slots", 8))
	for index in slots:
		var center := _slot_center(index)
		var occupied := _slot_occupied(index)
		var points := _rounded_points(center, SLOT_SIZE, 10.0)
		if occupied:
			var data := _building_at(index)
			var color := Color.from_string(str(data.get("color", "#2E6B6B")), Palette.TEAL)
			draw_colored_polygon(points, Palette.alpha(color, 0.35))
			draw_polyline(points, color, 2.0, true)
			_draw_text_centered(str(data.get("short", "?")), center + Vector2(0, 4), 13, Palette.TEXT, SLOT_SIZE.x + 30.0)
		elif build_mode:
			var pulse := 0.45 + sin(time * 4.0) * 0.2
			var hovered := index == hover_slot
			draw_colored_polygon(points, Palette.alpha(Palette.AMBER, 0.22 if hovered else 0.06))
			draw_polyline(points, Palette.alpha(Palette.AMBER, 0.95 if hovered else pulse), 2.0, true)
			_draw_text_centered("+", center + Vector2(0, 5), 20, Palette.alpha(Palette.AMBER, 0.9), 60.0)
		else:
			draw_polyline(points, Palette.alpha(Palette.DECK_EDGE, 0.55), 1.5, true)


func _building_at(slot: int) -> Dictionary:
	for entry in GameState.buildings:
		if int(entry.get("slot", -1)) == slot:
			return Database.get_building(str(entry.get("id", "")))
	return {}


func _draw_followers() -> void:
	var index := 0
	for follower in GameState.followers:
		if follower.left:
			continue
		var center := _follower_position(index)
		var color: Color = follower.color
		if follower.hollow:
			color = Palette.MUTED
		draw_circle(center + Vector2(0, 4), TOKEN_RADIUS + 4.0, Palette.alpha(Color.BLACK, 0.25))
		draw_circle(center, TOKEN_RADIUS, color)
		draw_circle(center + Vector2(0, -4), TOKEN_RADIUS * 0.55, Palette.alpha(Palette.SALT, 0.18))
		draw_arc(center, TOKEN_RADIUS + 5.0, -PI * 0.5, -PI * 0.5 + TAU * follower.hope_ratio(), 32, Palette.HOPE, 3.0, true)
		if str(follower.id) == hover_follower:
			draw_arc(center, TOKEN_RADIUS + 10.0, 0.0, TAU, 40, Palette.AMBER, 2.0, true)

		var caption: String = follower.display_name
		if follower.hollow:
			caption = "Пол"
		_draw_text_centered(caption, center + Vector2(0, TOKEN_RADIUS + 20.0), 13, Palette.TEXT, 150.0)

		if not follower.hollow:
			var dots := follower.memory_count()
			var start := center + Vector2(-float(dots - 1) * 5.0, TOKEN_RADIUS + 6.0)
			for dot in dots:
				draw_circle(start + Vector2(dot * 10.0, 0), 2.5, Palette.AMBER)

		index += 1


func _ellipse_points(center: Vector2, radius: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in steps:
		var angle := TAU * float(step) / float(steps)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


func _rounded_points(center: Vector2, box_size: Vector2, cut: float) -> PackedVector2Array:
	var half := box_size * 0.5
	return PackedVector2Array([
		center + Vector2(-half.x + cut, -half.y),
		center + Vector2(half.x - cut, -half.y),
		center + Vector2(half.x, -half.y + cut),
		center + Vector2(half.x, half.y - cut),
		center + Vector2(half.x - cut, half.y),
		center + Vector2(-half.x + cut, half.y),
		center + Vector2(-half.x, half.y - cut),
		center + Vector2(-half.x, -half.y + cut)
	])


func _draw_text_centered(text_value: String, position: Vector2, font_size: int, color: Color, width: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, position - Vector2(width * 0.5, 0), text_value, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

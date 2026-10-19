extends RefCounted
## Фабрика UI: тема, панели, кнопки, карточки.
## UI собирается кодом, пока нет финального арта и макетов.

const Palette = preload("res://src/core/palette.gd")

static var _theme: Theme


static func make_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	theme.set_stylebox("panel", "PanelContainer", box(Palette.PANEL, Palette.BORDER, 1, 14))
	theme.set_stylebox("panel", "Panel", box(Palette.PANEL, Palette.BORDER, 1, 14))

	theme.set_stylebox("normal", "Button", box(Palette.PANEL_LIGHT, Palette.BORDER, 1, 8))
	theme.set_stylebox("hover", "Button", box(Palette.TEAL, Palette.AMBER, 1, 8))
	theme.set_stylebox("pressed", "Button", box(Palette.AMBER, Palette.AMBER, 1, 8))
	theme.set_stylebox("disabled", "Button", box(Palette.PANEL, Palette.BORDER, 1, 8))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Palette.AMBER, 1, 8))

	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Palette.BG)
	theme.set_color("font_disabled_color", "Button", Palette.MUTED)
	theme.set_color("font_focus_color", "Button", Palette.TEXT)
	theme.set_constant("outline_size", "Button", 0)

	theme.set_stylebox("background", "ProgressBar", box(Palette.WATER_DEEP, Palette.BORDER, 1, 6))
	theme.set_stylebox("fill", "ProgressBar", box(Palette.AMBER, Palette.AMBER, 0, 6))
	theme.set_color("font_color", "ProgressBar", Palette.BG)
	theme.set_font_size("font_size", "ProgressBar", 12)

	theme.set_stylebox("scroll", "VScrollBar", box(Palette.PANEL, Palette.PANEL, 0, 6))
	theme.set_stylebox("grabber", "VScrollBar", box(Palette.BORDER, Palette.BORDER, 0, 6))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(Palette.AMBER, Palette.AMBER, 0, 6))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(Palette.AMBER, Palette.AMBER, 0, 6))
	theme.set_constant("minimum_grab_thickness", "VScrollBar", 24)

	theme.set_color("default_color", "RichTextLabel", Palette.TEXT)
	theme.set_color("font_color", "RichTextLabel", Palette.TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", 15)

	_theme = theme
	return theme


static func box(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func label(text_value: String, size: int = 16, color: Color = Palette.TEXT) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func wrapped_label(text_value: String, size: int = 15, color: Color = Palette.TEXT) -> Label:
	var node := label(text_value, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func title(text_value: String, size: int = 24) -> Label:
	return label(text_value, size, Palette.AMBER)


static func button(text_value: String, size: int = 15) -> Button:
	var node := Button.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.focus_mode = Control.FOCUS_ALL
	return node


static func danger_button(text_value: String, size: int = 15) -> Button:
	var node := button(text_value, size)
	node.add_theme_stylebox_override("normal", box(Palette.DANGER.darkened(0.35), Palette.DANGER, 1, 8))
	node.add_theme_stylebox_override("hover", box(Palette.DANGER, Palette.AMBER, 1, 8))
	return node


static func gold_button(text_value: String, size: int = 15) -> Button:
	var node := button(text_value, size)
	node.add_theme_stylebox_override("normal", box(Palette.GOLD_BORDER.darkened(0.35), Palette.AMBER, 1, 8))
	node.add_theme_stylebox_override("hover", box(Palette.AMBER, Palette.AMBER, 1, 8))
	node.add_theme_color_override("font_hover_color", Palette.BG)
	return node


static func panel(bg: Color = Palette.PANEL, radius: int = 14) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", box(bg, Palette.BORDER, 1, radius))
	return node


static func card(bg: Color = Palette.PANEL_LIGHT) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", box(bg, Palette.BORDER, 1, 10))
	return node


static func chip(text_value: String, color: Color) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", box(Palette.alpha(color, 0.16), color, 1, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	margin.add_child(label(text_value, 12, color))
	node.add_child(margin)
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node


static func spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func hspacer(width: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(width, 0)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func separator() -> ColorRect:
	var node := ColorRect.new()
	node.color = Palette.alpha(Palette.BORDER, 0.7)
	node.custom_minimum_size = Vector2(0, 1)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func stat_bar(value: float, maximum: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 12)
	bar.add_theme_stylebox_override("fill", box(color, color, 0, 5))
	bar.add_theme_stylebox_override("background", box(Palette.WATER_DEEP, Palette.BORDER, 1, 5))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

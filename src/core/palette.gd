extends RefCounted
## Палитра Saltvigil. Один источник цвета для всего UI и заглушек арта.

const BG := Color(0.027, 0.078, 0.090)
const WATER := Color(0.047, 0.133, 0.149)
const WATER_DEEP := Color(0.020, 0.063, 0.075)
const DECK := Color(0.200, 0.149, 0.114)
const DECK_DARK := Color(0.137, 0.102, 0.078)
const DECK_EDGE := Color(0.353, 0.259, 0.188)
const AMBER := Color(0.949, 0.690, 0.294)
const EMBER := Color(1.000, 0.478, 0.184)
const SALT := Color(0.929, 0.902, 0.839)
const TEAL := Color(0.180, 0.420, 0.420)
const TEXT := Color(0.953, 0.918, 0.847)
const MUTED := Color(0.576, 0.663, 0.643)
const DANGER := Color(0.776, 0.333, 0.294)
const HOPE := Color(0.498, 0.784, 0.663)
const PANEL := Color(0.055, 0.141, 0.161)
const PANEL_LIGHT := Color(0.075, 0.180, 0.196)
const BORDER := Color(0.122, 0.267, 0.290)
const GOLD_BORDER := Color(0.580, 0.430, 0.220)


static func alpha(color: Color, value: float) -> Color:
	return Color(color.r, color.g, color.b, value)


static func type_color(memory_type: String) -> Color:
	match memory_type:
		"joy":
			return AMBER
		"grief":
			return Color(0.45, 0.62, 0.80)
		"skill":
			return TEAL
		"bond":
			return Color(0.88, 0.55, 0.60)
		"secret":
			return Color(0.70, 0.58, 0.85)
		"debt":
			return SALT
		_:
			return MUTED

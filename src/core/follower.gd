extends RefCounted
## Данные последователя. Обычный RefCounted, чтобы легко сохранять и тестировать.

var id := ""
var display_name := ""
var role := ""
var bio := ""
var color := Color.WHITE
var traits: Array = []
var warmth := 70.0
var hope := 65.0
var closeness := 0
var memories: Array = []
var preserved: Array = []
var read_memories: Array = []
var hollow := false
var left := false
var quarters_slot := -1


func setup(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	display_name = str(data.get("name", id))
	role = str(data.get("role", ""))
	bio = str(data.get("bio", ""))
	color = Color.from_string(str(data.get("color", "#FFFFFF")), Color.WHITE)
	traits = data.get("traits", []).duplicate()
	warmth = float(data.get("warmth", 70.0))
	hope = float(data.get("hope", 65.0))
	memories = data.get("memories", []).duplicate()


func is_active() -> bool:
	return not hollow and not left


func memory_count() -> int:
	return memories.size()


func has_memory(memory_id: String) -> bool:
	return memories.has(memory_id)


func remove_memory(memory_id: String) -> bool:
	var index := memories.find(memory_id)
	if index < 0:
		return false
	memories.remove_at(index)
	return true


func preserve_memory(memory_id: String) -> bool:
	if not remove_memory(memory_id):
		return false
	preserved.append(memory_id)
	return true


func mark_read(memory_id: String) -> bool:
	if read_memories.has(memory_id):
		return false
	read_memories.append(memory_id)
	return true


func was_read(memory_id: String) -> bool:
	return read_memories.has(memory_id)


func hope_ratio() -> float:
	return clampf(hope / 100.0, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"role": role,
		"bio": bio,
		"color": "#" + color.to_html(false),
		"traits": traits.duplicate(),
		"warmth": warmth,
		"hope": hope,
		"closeness": closeness,
		"memories": memories.duplicate(),
		"preserved": preserved.duplicate(),
		"read_memories": read_memories.duplicate(),
		"hollow": hollow,
		"left": left,
		"quarters_slot": quarters_slot
	}


func from_dict(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	display_name = str(data.get("name", id))
	role = str(data.get("role", ""))
	bio = str(data.get("bio", ""))
	color = Color.from_string(str(data.get("color", "#FFFFFF")), Color.WHITE)
	traits = data.get("traits", []).duplicate()
	warmth = float(data.get("warmth", 70.0))
	hope = float(data.get("hope", 65.0))
	closeness = int(data.get("closeness", 0))
	memories = data.get("memories", []).duplicate()
	preserved = data.get("preserved", []).duplicate()
	read_memories = data.get("read_memories", []).duplicate()
	hollow = bool(data.get("hollow", false))
	left = bool(data.get("left", false))
	quarters_slot = int(data.get("quarters_slot", -1))

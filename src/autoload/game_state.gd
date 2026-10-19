extends Node
## Состояние одной партии. Никакого UI: только правила, ресурсы и сигналы.

const FollowerScript = preload("res://src/core/follower.gd")
const PHASES := ["Сумерки", "Первая вахта", "Полночь", "Глубокая ночь", "Серый час", "Рассвет"]

var config: Dictionary = {}
var day := 1
var watch := 0
var light := 45.0
var faith := 50.0
var resources: Dictionary = {}
var followers: Array = []
var buildings: Array = []
var journal_pages := 8
var journal_entries: Array = []
var lost_entries: Array = []
var flags: Dictionary = {}
var running := false
var paused := false
var demo_over := false
var is_game_over := false
var ending_reason := ""
var log_history: Array = []

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	config = Database.config
	_rng.randomize()


func _cfg(key: String, fallback: Variant = 0) -> Variant:
	return config.get(key, fallback)


func new_game() -> void:
	config = Database.config
	day = 1
	watch = 0
	light = float(_cfg("starting_light", 45.0))
	faith = 50.0
	running = false
	paused = false
	demo_over = false
	is_game_over = false
	ending_reason = ""
	buildings.clear()
	lost_entries.clear()
	log_history.clear()
	flags = {
		"burned": 0,
		"kept": 0,
		"read": 0,
		"hollows": 0,
		"left": 0,
		"miracles": 0
	}

	resources = {}
	var starting: Dictionary = _cfg("starting_resources", {})
	for item_id in Database.items.keys():
		resources[item_id] = float(starting.get(item_id, 0.0))

	followers.clear()
	for index in Database.followers.size():
		var data: Dictionary = Database.followers[index]
		var follower = FollowerScript.new()
		follower.setup(data)
		follower.quarters_slot = index
		followers.append(follower)

	journal_entries = Database.journal.duplicate(true)
	journal_pages = mini(int(_cfg("starting_journal_pages", 8)), journal_entries.size())
	if journal_pages < journal_entries.size():
		journal_entries = journal_entries.slice(0, journal_pages)

	_rng.randomize()
	_add_log("Уголёк почти погас. Уэйк идёт по Позвоночнику, и туман уже близко.")
	_add_log("Три человека смотрят на тебя. У каждого есть память, которую можно сжечь.")
	_add_log("Продержись три ночи. Память — единственное топливо, которое у тебя есть. Esc — пауза.")
	_emit_all()


func start() -> void:
	if is_game_over or demo_over:
		return
	if watch >= _watches():
		start_next_night()
		return
	running = true
	paused = false
	EventBus.running_changed.emit(true)
	EventBus.pause_changed.emit(false)
	EventBus.day_changed.emit(day, watch, _watches(), phase_title())
	_add_log("Начинается вахта. Свет: %d." % int(light))


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	EventBus.pause_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


func advance_watch() -> void:
	if not running or paused or is_game_over or demo_over:
		return

	_apply_production()
	var has_food := _consume_food()
	var decay := current_light_decay()
	if faith < float(_cfg("low_faith_threshold", 20.0)):
		decay += float(_cfg("low_faith_decay_bonus", 1.0))
	light = maxf(0.0, light - decay)

	var light_low := light < float(_cfg("low_light_threshold", 25.0))
	var any_follower_changed := false
	for follower in followers:
		if follower.is_active():
			_tick_follower(follower, has_food, light_low)
			any_follower_changed = true

	watch += 1
	EventBus.light_changed.emit(light, ember_max())
	EventBus.resources_changed.emit(resources.duplicate())
	if any_follower_changed:
		EventBus.followers_changed.emit()
	EventBus.day_changed.emit(day, watch, _watches(), phase_title())

	if light <= 0.0:
		_game_over("Уголёк погас. Тишина вошла в Уэйк и забрала всё, что вы помнили.")
		return
	if get_active_followers().is_empty():
		_game_over("На палубе не осталось никого, кто помнит своё имя. Уэйк опустел.")
		return

	if watch >= _watches():
		_end_night()
	elif watch % 2 == 0:
		_add_log("Наступает %s. Свет: %d." % [phase_title().to_lower(), int(light)])


func current_light_decay() -> float:
	var decays: Array = _cfg("light_decay", [6.0])
	var index := clampi(day - 1, 0, decays.size() - 1)
	return float(decays[index])


func ember_max() -> float:
	return float(_cfg("ember_max_light", 100.0))


func phase_title() -> String:
	return PHASES[clampi(watch, 0, PHASES.size() - 1)]


func _watches() -> int:
	return int(_cfg("watches_per_night", 6))


func find_follower(follower_id: String) -> Variant:
	for follower in followers:
		if follower.id == follower_id:
			return follower
	return null


func get_active_followers() -> Array:
	var result: Array = []
	for follower in followers:
		if follower.is_active():
			result.append(follower)
	return result


func has_free_slot() -> bool:
	return buildings.size() < int(_cfg("build_slots", 8))


func used_slots() -> int:
	return buildings.size()


func can_afford(cost: Dictionary) -> bool:
	for item_id in cost.keys():
		if float(resources.get(item_id, 0.0)) < float(cost[item_id]):
			return false
	return true


func has_building(building_id: String) -> bool:
	for entry in buildings:
		if entry.get("id", "") == building_id:
			return true
	return false


func get_memory_for(follower_id: String, memory_id: String) -> Dictionary:
	var memory := Database.get_memory(memory_id)
	if memory.is_empty():
		return {}
	if str(memory.get("owner", "")) != follower_id:
		return {}
	return memory


func burn_memory(follower_id: String, memory_id: String) -> bool:
	var follower = find_follower(follower_id)
	if follower == null or not follower.is_active():
		return false
	if not follower.has_memory(memory_id):
		return false
	var memory := get_memory_for(follower_id, memory_id)
	if memory.is_empty():
		return false

	follower.remove_memory(memory_id)
	light = minf(ember_max(), light + float(memory.get("burn_light", 18.0)))
	faith = minf(100.0, faith + float(_cfg("burn_memory_faith", 3.0)))
	resources["ash"] = float(resources.get("ash", 0.0)) + float(_cfg("burn_memory_ash", 1.0))
	flags["burned"] = int(flags.get("burned", 0)) + 1

	_add_log("Память «%s» сожжена. %s" % [memory.get("title", "?"), memory.get("burn", "")])
	EventBus.memory_action.emit(follower_id, memory_id, "burn")
	EventBus.toast_requested.emit("−1 воспоминание · +%d света" % int(memory.get("burn_light", 18.0)))

	if follower.memories.is_empty() and follower.preserved.is_empty():
		_make_hollow(follower)

	_emit_all()
	_check_collapse()
	return true


func keep_memory(follower_id: String, memory_id: String) -> bool:
	var follower = find_follower(follower_id)
	if follower == null or not follower.is_active():
		return false
	if not follower.has_memory(memory_id):
		return false
	var cost := float(_cfg("keep_memory_wax_cost", 2.0))
	if float(resources.get("wax", 0.0)) < cost:
		EventBus.toast_requested.emit("Нужно %d воска, чтобы сохранить память." % int(cost))
		return false
	var memory := get_memory_for(follower_id, memory_id)
	if memory.is_empty():
		return false

	resources["wax"] = float(resources.get("wax", 0.0)) - cost
	follower.preserve_memory(memory_id)
	follower.hope = minf(100.0, follower.hope + float(memory.get("keep_hope", 6.0)))
	faith = minf(100.0, faith + float(_cfg("keep_memory_faith", 2.0)))
	flags["kept"] = int(flags.get("kept", 0)) + 1

	_add_log("Память «%s» сохранена в Хранилище. %s" % [memory.get("title", "?"), memory.get("keep", "")])
	EventBus.memory_action.emit(follower_id, memory_id, "keep")
	EventBus.toast_requested.emit("Память сохранена · −%d воска" % int(cost))
	_emit_all()
	return true


func read_memory(follower_id: String, memory_id: String) -> bool:
	var follower = find_follower(follower_id)
	if follower == null or not follower.is_active():
		return false
	if not follower.has_memory(memory_id):
		return false
	if not follower.mark_read(memory_id):
		return false

	follower.closeness += int(_cfg("read_memory_closeness", 1))
	faith = minf(100.0, faith + float(_cfg("read_memory_faith", 1.0)))
	flags["read"] = int(flags.get("read", 0)) + 1
	var title := str(get_memory_for(follower_id, memory_id).get("title", "?"))
	_add_log("%s прочёл(а) память «%s». Это осталось между вами." % [follower.display_name, title])
	EventBus.memory_action.emit(follower_id, memory_id, "read")
	EventBus.follower_changed.emit(follower_id)
	EventBus.faith_changed.emit(faith)
	return true


func feed_wood() -> bool:
	var cost := float(_cfg("wood_feed_cost", 1.0))
	if float(resources.get("wood", 0.0)) < cost:
		EventBus.toast_requested.emit("Дерево закончилось. Осталась память.")
		return false
	resources["wood"] = float(resources.get("wood", 0.0)) - cost
	light = minf(ember_max(), light + float(_cfg("wood_feed_light", 3.0)))
	EventBus.light_changed.emit(light, ember_max())
	EventBus.resources_changed.emit(resources.duplicate())
	EventBus.toast_requested.emit("+%d света" % int(_cfg("wood_feed_light", 3.0)))
	return true


func miracle() -> bool:
	if not running:
		return false
	var cost := int(_cfg("miracle_journal_cost", 1))
	if journal_pages < cost:
		EventBus.toast_requested.emit("Журнал пуст. Ты не помнишь, зачем горишь.")
		return false

	journal_pages -= cost
	light = minf(ember_max(), light + float(_cfg("miracle_light", 30.0)))
	faith = minf(100.0, faith + float(_cfg("miracle_faith", 2.0)))
	flags["miracles"] = int(flags.get("miracles", 0)) + 1

	var lost := _lose_journal_entry()
	if not lost.is_empty():
		_add_log("Ты сжёг страницу Журнала ради чуда. Ты больше не помнишь: «%s»" % lost.get("text", ""))
	else:
		_add_log("Ты сжёг страницу Журнала ради чуда. В журнале было пусто.")

	EventBus.journal_changed.emit(journal_pages, lost_entries.size())
	EventBus.light_changed.emit(light, ember_max())
	EventBus.faith_changed.emit(faith)
	EventBus.toast_requested.emit("Чудо Уголька · +%d света · −1 страница" % int(_cfg("miracle_light", 30.0)))

	if journal_pages <= 0:
		_game_over("Ты забыл всё, что делало тебя Хранителем. Уголёк горит, но это уже не ты.")
		return true
	return true


func build(building_id: String, slot: int) -> Dictionary:
	var data := Database.get_building(building_id)
	if data.is_empty():
		return {"ok": false, "message": "Неизвестное здание."}
	if slot < 0 or slot >= int(_cfg("build_slots", 8)):
		return {"ok": false, "message": "Здесь нельзя строить."}
	for entry in buildings:
		if int(entry.get("slot", -1)) == slot:
			return {"ok": false, "message": "Это место уже занято."}

	var cost: Dictionary = data.get("cost", {})
	for item_id in cost.keys():
		if float(resources.get(item_id, 0.0)) < float(cost[item_id]):
			return {"ok": false, "message": "Не хватает: " + Database.get_item(item_id).get("name", item_id)}
	for item_id in cost.keys():
		resources[item_id] = float(resources.get(item_id, 0.0)) - float(cost[item_id])

	buildings.append({"id": building_id, "slot": slot})
	_add_log("На палубе появилась «%s»." % data.get("name", building_id))
	EventBus.resources_changed.emit(resources.duplicate())
	EventBus.buildings_changed.emit()
	return {"ok": true, "message": "Построено: %s." % data.get("name", building_id)}


func _apply_production() -> void:
	var changed := false
	for entry in buildings:
		var data := Database.get_building(str(entry.get("id", "")))
		if data.is_empty():
			continue
		var production: Dictionary = data.get("production", {})
		for item_id in production.keys():
			resources[item_id] = float(resources.get(item_id, 0.0)) + float(production[item_id])
			changed = true
		var hope_bonus := float(data.get("hope_per_watch", 0.0))
		if hope_bonus > 0.0:
			for follower in followers:
				if follower.is_active():
					follower.hope = minf(100.0, follower.hope + hope_bonus)
	if changed:
		EventBus.resources_changed.emit(resources.duplicate())


func _consume_food() -> bool:
	var need := float(get_active_followers().size()) * float(_cfg("food_per_follower", 0.5))
	if need <= 0.0:
		return true
	if float(resources.get("food", 0.0)) >= need:
		resources["food"] = float(resources.get("food", 0.0)) - need
		EventBus.resources_changed.emit(resources.duplicate())
		return true
	resources["food"] = 0.0
	EventBus.resources_changed.emit(resources.duplicate())
	_add_log("Кухня пуста. Культ ложится спать голодным.")
	return false


func _tick_follower(follower, has_food: bool, light_low: bool) -> void:
	var warmth_delta := 2.0 if not light_low else -5.0
	follower.warmth = clampf(follower.warmth + warmth_delta, 0.0, 100.0)

	var hope_delta := -1.0
	if follower.warmth > 60.0:
		hope_delta += 1.0
	if has_food:
		hope_delta += 0.5
	else:
		hope_delta -= 2.0
	if light_low:
		hope_delta -= float(_cfg("low_light_hope_penalty", 2.0))
	follower.hope = clampf(follower.hope + hope_delta, 0.0, 100.0)

	if follower.hope <= 0.0:
		_follower_leaves(follower)
	elif follower.memories.is_empty() and follower.preserved.is_empty() and not follower.hollow:
		_make_hollow(follower)


func _follower_leaves(follower) -> void:
	if follower.left:
		return
	follower.left = true
	follower.hope = 0.0
	flags["left"] = int(flags.get("left", 0)) + 1
	faith = maxf(0.0, faith - float(_cfg("leave_faith_penalty", 15.0)))
	_add_log("%s ушёл(ла) в туман. Надежда кончилась раньше памяти." % follower.display_name)
	EventBus.faith_changed.emit(faith)
	EventBus.toast_requested.emit("%s покинул(а) Уэйк" % follower.display_name)
	EventBus.followers_changed.emit()


func _make_hollow(follower) -> void:
	if follower.hollow:
		return
	follower.hollow = true
	flags["hollows"] = int(flags.get("hollows", 0)) + 1
	faith = maxf(0.0, faith - float(_cfg("hollow_faith_penalty", 10.0)))
	_add_log("%s стал(а) Полом. Тело всё ещё ходит, но это уже не тот человек." % follower.display_name)
	EventBus.faith_changed.emit(faith)
	EventBus.toast_requested.emit("%s стал(а) Полом" % follower.display_name)
	EventBus.followers_changed.emit()
	EventBus.follower_changed.emit(follower.id)


func _lose_journal_entry() -> Dictionary:
	if journal_entries.is_empty():
		return {}
	var index := _rng.randi_range(0, journal_entries.size() - 1)
	var entry: Dictionary = journal_entries[index]
	journal_entries.remove_at(index)
	lost_entries.append(entry)
	return entry


func _end_night() -> void:
	running = false
	EventBus.running_changed.emit(false)
	var summary := get_summary()
	if day >= int(_cfg("nights_to_survive", 3)):
		demo_over = true
		_add_log("Рассвет. Демо пройдено — Уэйк дожил до третьего утра.")
		EventBus.demo_completed.emit(summary)
	else:
		_add_log("Рассвет. Уэйк дожил до утра. Но впереди ещё одна ночь.")
		EventBus.night_ended.emit(summary)


func start_next_night() -> void:
	if is_game_over or demo_over:
		return
	day += 1
	watch = 0
	light = minf(ember_max(), light + float(_cfg("dawn_light_bonus", 5.0)))
	faith = minf(100.0, faith + float(_cfg("dawn_faith_bonus", 2.0)))
	for follower in followers:
		if follower.is_active():
			follower.hope = minf(100.0, follower.hope + float(_cfg("dawn_hope_bonus", 6.0)))
			follower.warmth = minf(100.0, follower.warmth + float(_cfg("dawn_warmth_bonus", 6.0)))

	running = true
	paused = false
	EventBus.running_changed.emit(true)
	EventBus.pause_changed.emit(false)
	EventBus.day_changed.emit(day, watch, _watches(), phase_title())
	EventBus.light_changed.emit(light, ember_max())
	EventBus.faith_changed.emit(faith)
	EventBus.followers_changed.emit()
	_add_log("Наступает ночь %d. Свет: %d." % [day, int(light)])


func get_summary() -> Dictionary:
	return {
		"day": day,
		"light": light,
		"faith": faith,
		"burned": int(flags.get("burned", 0)),
		"kept": int(flags.get("kept", 0)),
		"read": int(flags.get("read", 0)),
		"hollows": int(flags.get("hollows", 0)),
		"left": int(flags.get("left", 0)),
		"miracles": int(flags.get("miracles", 0)),
		"pages": journal_pages,
		"followers_alive": get_active_followers().size()
	}


func _check_collapse() -> void:
	if is_game_over:
		return
	if get_active_followers().is_empty():
		_game_over("На палубе не осталось никого, кто помнит своё имя. Уэйк опустел.")


func _game_over(reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	running = false
	ending_reason = reason
	EventBus.running_changed.emit(false)
	_add_log(reason)
	EventBus.game_over.emit(reason)


func _add_log(text_value: String) -> void:
	log_history.append(text_value)
	if log_history.size() > 200:
		log_history.pop_front()
	EventBus.log_added.emit(text_value)


func _emit_all() -> void:
	EventBus.light_changed.emit(light, ember_max())
	EventBus.faith_changed.emit(faith)
	EventBus.resources_changed.emit(resources.duplicate())
	EventBus.day_changed.emit(day, watch, _watches(), phase_title())
	EventBus.followers_changed.emit()
	EventBus.journal_changed.emit(journal_pages, lost_entries.size())
	EventBus.buildings_changed.emit()


func to_dict() -> Dictionary:
	var follower_data: Array = []
	for follower in followers:
		follower_data.append(follower.to_dict())
	return {
		"day": day,
		"watch": watch,
		"light": light,
		"faith": faith,
		"resources": resources.duplicate(),
		"followers": follower_data,
		"buildings": buildings.duplicate(true),
		"journal_pages": journal_pages,
		"journal_entries": journal_entries.duplicate(true),
		"lost_entries": lost_entries.duplicate(true),
		"flags": flags.duplicate(),
		"demo_over": demo_over,
		"is_game_over": is_game_over,
		"ending_reason": ending_reason,
		"log_history": log_history.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	config = Database.config
	day = int(data.get("day", 1))
	watch = int(data.get("watch", 0))
	light = float(data.get("light", 45.0))
	faith = float(data.get("faith", 50.0))
	resources = data.get("resources", {}).duplicate(true)
	buildings = data.get("buildings", []).duplicate(true)
	journal_pages = int(data.get("journal_pages", 8))
	journal_entries = data.get("journal_entries", []).duplicate(true)
	lost_entries = data.get("lost_entries", []).duplicate(true)
	flags = data.get("flags", {}).duplicate(true)
	demo_over = bool(data.get("demo_over", false))
	is_game_over = bool(data.get("is_game_over", false))
	ending_reason = str(data.get("ending_reason", ""))
	log_history = data.get("log_history", []).duplicate()
	running = false
	paused = false

	followers.clear()
	for entry in data.get("followers", []):
		var follower = FollowerScript.new()
		follower.from_dict(entry)
		followers.append(follower)

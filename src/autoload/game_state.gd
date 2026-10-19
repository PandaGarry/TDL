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
var laws: Array = []
var pending_event: Dictionary = {}
var fed_this_watch := 0

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
	laws.clear()
	pending_event = {}
	fed_this_watch = 0
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
		# На рассвете сначала закон, потом следующая ночь. Иначе загрузка
		# с чекпоинта молча пропускала бы выбор.
		if should_choose_law():
			running = false
			return
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


func can_act() -> bool:
	## Действия с памятью и ресурсами доступны только в живой партии.
	return not is_game_over and not demo_over


func _doctrine_choices() -> int:
	return int(_cfg("doctrine_choices", 2))


func should_choose_law() -> bool:
	## Закон принимается только на рассвете: после ночи, но до следующей.
	if is_game_over or demo_over or watch < _watches():
		return false
	return laws.size() < mini(day, _doctrine_choices())


func choose_law(law_id: String) -> bool:
	if not can_act() or not should_choose_law() or laws.has(law_id):
		return false
	var doctrine := Database.get_doctrine(law_id)
	if doctrine.is_empty() or str(doctrine.get("status", "")) != "active":
		return false
	laws.append(law_id)
	_add_log("Уэйк принял «%s». %s" % [
		str(doctrine.get("name", law_id)),
		str(doctrine.get("effect", ""))
	])
	EventBus.laws_changed.emit()
	EventBus.toast_requested.emit("Закон принят: %s" % str(doctrine.get("name", law_id)))
	return true


func law_names() -> String:
	if laws.is_empty():
		return "нет"
	var names: Array = []
	for law_id in laws:
		names.append(str(Database.get_doctrine(str(law_id)).get("name", law_id)))
	return " · ".join(PackedStringArray(names))


func law_names_short() -> String:
	if laws.is_empty():
		return "нет"
	var names: Array = []
	for law_id in laws:
		var full := str(Database.get_doctrine(str(law_id)).get("name", law_id))
		names.append(full.trim_prefix("Закон "))
	return " · ".join(PackedStringArray(names))


func _law_sum(key: String) -> float:
	var total := 0.0
	for law_id in laws:
		var doctrine := Database.get_doctrine(str(law_id))
		var modifiers: Dictionary = doctrine.get("modifiers", {})
		total += float(modifiers.get(key, 0.0))
	return total


func _law_mult(key: String) -> float:
	var total := 1.0
	for law_id in laws:
		var doctrine := Database.get_doctrine(str(law_id))
		var modifiers: Dictionary = doctrine.get("modifiers", {})
		if modifiers.has(key):
			total *= float(modifiers[key])
	return total


func burn_light_for(memory: Dictionary) -> float:
	return float(memory.get("burn_light", 18.0)) * _law_mult("burn_light_mult")


func keep_memory_cost() -> float:
	return maxf(1.0, float(_cfg("keep_memory_wax_cost", 2.0)) + _law_sum("keep_wax_delta"))


func miracle_cost() -> int:
	return maxi(1, int(_cfg("miracle_journal_cost", 1)) + int(_law_sum("miracle_cost_delta")))


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
	fed_this_watch = 0
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
	else:
		if watch % 2 == 0:
			_add_log("Наступает %s. Свет: %d." % [phase_title().to_lower(), int(light)])
		_trigger_event()


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
	if not can_act():
		return false
	var follower = find_follower(follower_id)
	if follower == null or not follower.is_active():
		return false
	if not follower.has_memory(memory_id):
		return false
	var memory := get_memory_for(follower_id, memory_id)
	if memory.is_empty():
		return false

	follower.remove_memory(memory_id)
	var burn_light := burn_light_for(memory)
	light = minf(ember_max(), light + burn_light)
	faith = minf(100.0, faith + float(_cfg("burn_memory_faith", 3.0)))
	resources["ash"] = float(resources.get("ash", 0.0)) + float(_cfg("burn_memory_ash", 1.0))
	flags["burned"] = int(flags.get("burned", 0)) + 1

	var hope_penalty := float(_cfg("burn_memory_hope_penalty", 3.0))
	for other in followers:
		if other.is_active():
			other.hope = clampf(other.hope - hope_penalty, 0.0, 100.0)

	_add_log("Память «%s» сожжена. %s" % [memory.get("title", "?"), memory.get("burn", "")])
	EventBus.memory_action.emit(follower_id, memory_id, "burn")
	EventBus.toast_requested.emit("−1 воспоминание · +%d света · −%d надежды" % [
		int(burn_light),
		int(hope_penalty)
	])

	if follower.memories.is_empty() and follower.preserved.is_empty():
		_make_hollow(follower)
	for other in get_active_followers():
		if other.hope <= 0.0:
			_follower_leaves(other)

	_emit_all()
	_check_collapse()
	return true


func keep_memory(follower_id: String, memory_id: String) -> bool:
	if not can_act():
		return false
	var follower = find_follower(follower_id)
	if follower == null or not follower.is_active():
		return false
	if not follower.has_memory(memory_id):
		return false
	var cost := keep_memory_cost()
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
	if not can_act():
		return false
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


func feed_limit() -> int:
	return int(_cfg("wood_feed_per_watch", 1))


func can_feed() -> bool:
	if not can_act() or fed_this_watch >= feed_limit():
		return false
	return float(resources.get("wood", 0.0)) >= float(_cfg("wood_feed_cost", 1.0))


func feed_wood() -> bool:
	if not can_act():
		return false
	if fed_this_watch >= feed_limit():
		EventBus.toast_requested.emit("Уголёк уже принял подношение в эту вахту.")
		return false
	var cost := float(_cfg("wood_feed_cost", 1.0))
	if float(resources.get("wood", 0.0)) < cost:
		EventBus.toast_requested.emit("Дерево закончилось. Осталась память.")
		return false
	resources["wood"] = float(resources.get("wood", 0.0)) - cost
	fed_this_watch += 1
	light = minf(ember_max(), light + float(_cfg("wood_feed_light", 3.0)))
	EventBus.light_changed.emit(light, ember_max())
	EventBus.resources_changed.emit(resources.duplicate())
	EventBus.toast_requested.emit("+%d света" % int(_cfg("wood_feed_light", 3.0)))
	return true


func miracle() -> bool:
	if not running or not can_act():
		return false
	var cost := miracle_cost()
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
	EventBus.toast_requested.emit("Чудо Уголька · +%d света · −%d стр." % [int(_cfg("miracle_light", 30.0)), cost])

	if journal_pages <= 0:
		_game_over("Ты забыл всё, что делало тебя Хранителем. Уголёк горит, но это уже не ты.")
		return true
	return true


func build(building_id: String, slot: int) -> Dictionary:
	if not can_act():
		return {"ok": false, "message": "Вахта окончена."}
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
		hope_delta -= float(_cfg("low_light_hope_penalty", 2.0)) * _law_mult("low_light_hope_mult")
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
	if follower.id == "iskra":
		_add_log("Искра вернулась в тишину. Мел остался лежать на палубе.")
		EventBus.toast_requested.emit("Искра замолчала")
	else:
		_add_log("%s стал(а) Полом. Тело всё ещё ходит, но это уже не тот человек." % follower.display_name)
		EventBus.toast_requested.emit("%s стал(а) Полом" % follower.display_name)
	EventBus.faith_changed.emit(faith)
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


func _trigger_event() -> void:
	if not pending_event.is_empty() or watch <= 0 or watch >= _watches():
		return
	for entry in Database.events:
		if not (entry is Dictionary):
			continue
		var event: Dictionary = entry
		if int(event.get("night", 0)) != day or int(event.get("watch", 0)) != watch:
			continue
		var event_id := str(event.get("id", ""))
		if event_id.is_empty():
			continue
		if bool(event.get("once", true)) and bool(flags.get("event_" + event_id, false)):
			continue
		if not _event_conditions_met(event):
			continue
		pending_event = event.duplicate(true)
		EventBus.event_triggered.emit(pending_event)
		return


func _event_conditions_met(event: Dictionary) -> bool:
	var conditions: Dictionary = event.get("conditions", {})
	if conditions.has("food_below") and float(resources.get("food", 0.0)) >= float(conditions["food_below"]):
		return false
	if conditions.has("faith_below") and faith >= float(conditions["faith_below"]):
		return false
	if conditions.has("light_below") and light >= float(conditions["light_below"]):
		return false
	if conditions.has("follower_active"):
		var follower = find_follower(str(conditions["follower_active"]))
		if follower == null or not follower.is_active():
			return false
	return true


func resolve_event(choice_id: String) -> bool:
	if pending_event.is_empty() or not can_act():
		return false
	var choices: Variant = pending_event.get("choices", [])
	var choice: Dictionary = {}
	if choices is Array:
		for entry in choices:
			if not (entry is Dictionary):
				continue
			var candidate: Dictionary = entry
			if str(candidate.get("id", "")) == choice_id:
				choice = candidate
				break
	if choice.is_empty():
		return false

	var event_id := str(pending_event.get("id", ""))
	_apply_event_effects(choice.get("effects", {}))
	var choice_log := str(choice.get("log", ""))
	if not choice_log.is_empty():
		_add_log(choice_log)
	flags["event_" + event_id] = true
	pending_event = {}
	EventBus.event_resolved.emit(event_id, choice_id)
	_emit_all()

	if light <= 0.0:
		_game_over("Уголёк погас. Тишина вошла в Уэйк и забрала всё, что вы помнили.")
	elif get_active_followers().is_empty():
		_game_over("На палубе не осталось никого, кто помнит своё имя. Уэйк опустел.")
	return true


func _apply_event_effects(effects: Variant) -> void:
	if not (effects is Dictionary):
		return
	for item_id in Database.items.keys():
		if effects.has(item_id):
			var amount := float(resources.get(item_id, 0.0)) + float(effects[item_id])
			resources[item_id] = clampf(amount, 0.0, 9999.0)
	if effects.has("light"):
		light = clampf(light + float(effects["light"]), 0.0, ember_max())
	if effects.has("faith"):
		faith = clampf(faith + float(effects["faith"]), 0.0, 100.0)
	if effects.has("hope_all"):
		for follower in followers:
			if follower.is_active():
				follower.hope = clampf(follower.hope + float(effects["hope_all"]), 0.0, 100.0)
	if effects.has("hope") and effects["hope"] is Dictionary:
		var hopes: Dictionary = effects["hope"] as Dictionary
		for follower_id in hopes.keys():
			var follower = find_follower(str(follower_id))
			if follower != null and follower.is_active():
				follower.hope = clampf(follower.hope + float(hopes[follower_id]), 0.0, 100.0)
	if effects.has("flags") and effects["flags"] is Array:
		var flag_list: Array = effects["flags"] as Array
		for flag in flag_list:
			flags[str(flag)] = true
	for follower in get_active_followers():
		if follower.hope <= 0.0:
			_follower_leaves(follower)


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
	# Событие прошлой ночи не переносится: ночь закончилась, окно закрыто.
	pending_event = {}
	fed_this_watch = 0
	day += 1
	watch = 0
	# Уголёк разгорается к утру: даже после худшей ночи есть с чего начать.
	light = clampf(
		light + float(_cfg("dawn_light_bonus", 5.0)),
		float(_cfg("dawn_light_floor", 20.0)),
		ember_max()
	)
	faith = minf(100.0, faith + float(_cfg("dawn_faith_bonus", 2.0)))
	for follower in followers:
		if follower.is_active():
			var dawn_hope := float(_cfg("dawn_hope_bonus", 6.0)) + _law_sum("dawn_hope_delta")
			follower.hope = clampf(follower.hope + dawn_hope, 0.0, 100.0)
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
		"laws": laws.size(),
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
	EventBus.laws_changed.emit()


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
		"laws": laws.duplicate(),
		"fed_this_watch": fed_this_watch,
		"demo_over": demo_over,
		"is_game_over": is_game_over,
		"ending_reason": ending_reason,
		"log_history": log_history.duplicate()
	}


## Загружает состояние терпимо к повреждённым и старым данным:
## неизвестные поля игнорируются, числа зажимаются в допустимые диапазоны.
func from_dict(data: Dictionary) -> void:
	config = Database.config
	day = clampi(int(data.get("day", 1)), 1, int(_cfg("nights_to_survive", 3)))
	watch = clampi(int(data.get("watch", 0)), 0, _watches())
	light = clampf(float(data.get("light", 45.0)), 0.0, ember_max())
	faith = clampf(float(data.get("faith", 50.0)), 0.0, 100.0)
	demo_over = bool(data.get("demo_over", false))
	is_game_over = bool(data.get("is_game_over", false))
	ending_reason = str(data.get("ending_reason", ""))

	resources = _sanitize_resources(data.get("resources", {}))
	buildings = _sanitize_buildings(data.get("buildings", []))
	journal_entries = _sanitize_entries(data.get("journal_entries", []))
	lost_entries = _sanitize_entries(data.get("lost_entries", []))
	journal_pages = clampi(int(data.get("journal_pages", 8)), 0, journal_entries.size())
	var saved_flags: Variant = data.get("flags", {})
	flags = saved_flags.duplicate(true) if saved_flags is Dictionary else {}
	log_history = _sanitize_log(data.get("log_history", []))
	laws = _sanitize_laws(data.get("laws", []))
	fed_this_watch = clampi(int(data.get("fed_this_watch", 0)), 0, feed_limit())
	pending_event = {}
	running = false
	paused = false

	followers.clear()
	var saved_followers: Variant = data.get("followers", [])
	if saved_followers is Array:
		for entry in saved_followers:
			if not (entry is Dictionary):
				continue
			var follower = FollowerScript.new()
			follower.from_dict(entry)
			followers.append(follower)


func _sanitize_resources(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	for item_id in Database.items.keys():
		var value := 0.0
		if raw is Dictionary:
			value = float(raw.get(item_id, 0.0))
		result[item_id] = clampf(value, 0.0, 9999.0)
	return result


func _sanitize_buildings(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		return result
	var used_slots := {}
	var slot_limit := int(_cfg("build_slots", 8))
	for entry in raw:
		if not (entry is Dictionary):
			continue
		var building_id := str(entry.get("id", ""))
		var slot := int(entry.get("slot", -1))
		if Database.get_building(building_id).is_empty():
			continue
		if slot < 0 or slot >= slot_limit or used_slots.has(slot):
			continue
		used_slots[slot] = true
		result.append({"id": building_id, "slot": slot})
	return result


func _sanitize_entries(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		return result
	for entry in raw:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result


func _sanitize_laws(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		return result
	for law_id in raw:
		var doctrine := Database.get_doctrine(str(law_id))
		if doctrine.is_empty() or str(doctrine.get("status", "")) != "active":
			continue
		if result.has(str(law_id)):
			continue
		result.append(str(law_id))
		if result.size() >= _doctrine_choices():
			break
	return result


func _sanitize_log(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		return result
	for line in raw:
		result.append(str(line))
	if result.size() > 200:
		result = result.slice(result.size() - 200, result.size())
	return result

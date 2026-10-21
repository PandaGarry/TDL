class_name SimulationScheduler
extends RefCounted
## Deterministic minute-based scheduler for trusted domain systems.
##
## The scheduler owns no world state and writes no facts. It advances a
## WorldState clock in deterministic event order and invokes registered
## callables exactly on their scheduled domain minute. Periodic systems
## are aligned to absolute campaign minutes, so loading a world does not
## require a separate persisted scheduler clock for ordinary intervals.
##
## A system callable has the shape:
## `func(world: WorldState, context: Dictionary) -> Variant`.
## Returning `false` reports failure and stops the current advance at the
## failed event minute. Systems must not advance the world clock
## themselves; time ownership stays with the scheduler/GameSession pair.

const DEFAULT_MAX_SYSTEM_CALLS := 10000

var _systems: Dictionary = {}
var _next_due_by_id: Dictionary = {}


func register_system(
	system_id: String,
	interval_minutes: int,
	callable: Callable,
	order: int = 0,
	phase_minute: int = 0
) -> bool:
	if (
		not StableId.is_valid_segment(system_id)
		or interval_minutes < 1
		or not callable.is_valid()
		or phase_minute < 0
		or phase_minute >= interval_minutes
		or _systems.has(system_id)
	):
		return false
	_systems[system_id] = {
		"interval_minutes": interval_minutes,
		"callable": callable,
		"order": order,
		"phase_minute": phase_minute,
	}
	_next_due_by_id.erase(system_id)
	return true


func unregister_system(system_id: String) -> bool:
	if not _systems.has(system_id):
		return false
	_systems.erase(system_id)
	_next_due_by_id.erase(system_id)
	return true


func clear() -> void:
	_systems.clear()
	_next_due_by_id.clear()


func has_system(system_id: String) -> bool:
	return _systems.has(system_id)


func system_ids() -> PackedStringArray:
	var result := PackedStringArray(_systems.keys())
	result.sort()
	return result


func reset_for_minute(current_minute: int) -> void:
	_next_due_by_id.clear()
	if current_minute < 0:
		return
	for system_id in _systems.keys():
		_next_due_by_id[String(system_id)] = _next_due_after(
			current_minute, _system_entry(String(system_id))
		)


func advance(
	world: WorldState, minutes: int, max_system_calls: int = DEFAULT_MAX_SYSTEM_CALLS
) -> Dictionary:
	if world == null or not world.is_initialized() or minutes < 0 or max_system_calls < 1:
		return _report(false, 0, 0, 0, 0, false, ["invalid scheduler advance request"])

	var start_minute := world.clock().total_minutes()
	var target_minute := start_minute + minutes
	if target_minute < start_minute or target_minute > JsonValue.MAX_SAFE_INTEGER:
		return _report(
			false,
			start_minute,
			start_minute,
			start_minute,
			0,
			false,
			["scheduler target minute is outside the JSON-safe range"]
		)

	_ensure_next_due_initialized(start_minute)
	var errors: Array[String] = []
	var system_calls := 0
	var truncated := false
	var failed := false

	while not failed:
		var event_minute := _next_event_minute(target_minute)
		if event_minute < 0:
			break
		var due_entries := _due_entries(event_minute)
		if system_calls + due_entries.size() > max_system_calls:
			truncated = true
			break
		_advance_clock_to(world, event_minute)
		_prepare_next_due(due_entries)
		for entry in due_entries:
			var system_id := String(entry.get("system_id", ""))
			if not _systems.has(system_id):
				continue
			var context := {
				"system_id": system_id,
				"scheduled_minute": event_minute,
				"current_minute": world.clock().total_minutes(),
				"interval_minutes": int(entry.get("interval_minutes", 1)),
				"order": int(entry.get("order", 0)),
			}
			var callable: Callable = entry.get("callable", Callable())
			var result: Variant = callable.call(world, context)
			system_calls += 1
			if typeof(result) == TYPE_BOOL and not bool(result):
				errors.append("scheduled system '%s' reported failure" % system_id)
				failed = true
				break

	if not failed and not truncated:
		_advance_clock_to(world, target_minute)

	return _report(
		not failed,
		start_minute,
		world.clock().total_minutes(),
		target_minute,
		system_calls,
		truncated,
		errors
	)


func _system_entry(system_id: String) -> Dictionary:
	var entry: Variant = _systems.get(system_id, {})
	return entry if entry is Dictionary else {}


func _ensure_next_due_initialized(current_minute: int) -> void:
	for system_id_variant in _systems.keys():
		var system_id := String(system_id_variant)
		var next_due := int(_next_due_by_id.get(system_id, -1))
		if next_due <= current_minute:
			_next_due_by_id[system_id] = _next_due_after(current_minute, _system_entry(system_id))


func _next_due_after(current_minute: int, entry: Dictionary) -> int:
	var interval := maxi(int(entry.get("interval_minutes", 1)), 1)
	var phase := clampi(int(entry.get("phase_minute", 0)), 0, interval - 1)
	var delta := posmod(phase - posmod(current_minute, interval), interval)
	if delta == 0:
		delta = interval
	return current_minute + delta


func _next_event_minute(target_minute: int) -> int:
	var result := -1
	for system_id_variant in _systems.keys():
		var due := int(_next_due_by_id.get(String(system_id_variant), -1))
		if due >= 0 and due <= target_minute and (result < 0 or due < result):
			result = due
	return result


func _due_entries(event_minute: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for system_id_variant in _systems.keys():
		var system_id := String(system_id_variant)
		if int(_next_due_by_id.get(system_id, -1)) != event_minute:
			continue
		var entry := _system_entry(system_id).duplicate()
		entry["system_id"] = system_id
		result.append(entry)
	result.sort_custom(_compare_entries)
	return result


func _prepare_next_due(due_entries: Array[Dictionary]) -> void:
	for entry in due_entries:
		var system_id := String(entry.get("system_id", ""))
		if not _systems.has(system_id):
			continue
		var due := int(_next_due_by_id.get(system_id, 0))
		_next_due_by_id[system_id] = due + maxi(int(entry.get("interval_minutes", 1)), 1)


func _advance_clock_to(world: WorldState, target_minute: int) -> void:
	var delta := target_minute - world.clock().total_minutes()
	if delta > 0:
		world.clock().advance_minutes(delta)


func _report(
	ok: bool,
	from_minute: int,
	to_minute: int,
	target_minute: int,
	system_calls: int,
	truncated: bool,
	errors: Array[String]
) -> Dictionary:
	return {
		"ok": ok,
		"from_minute": from_minute,
		"to_minute": to_minute,
		"target_minute": target_minute,
		"system_calls": system_calls,
		"truncated": truncated,
		"errors": errors.duplicate(),
	}


static func _compare_entries(left: Dictionary, right: Dictionary) -> bool:
	var left_order := int(left.get("order", 0))
	var right_order := int(right.get("order", 0))
	if left_order != right_order:
		return left_order < right_order
	return String(left.get("system_id", "")) < String(right.get("system_id", ""))

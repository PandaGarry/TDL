class_name SevaraP1Npcs
extends RefCounted
## P1-C active anchor NPCs of the Sevara slice with daily schedules, domain
## clues, social memory of player interventions and enforceable promises.
##
## Spawns and steps 8 canonical anchor residents from `docs/lore/characters.md`:
## - Sarela (Nivara chief)
## - Tovan (Nivara sluice & channel keeper)
## - Ilune (Nivara seed & Talune garden keeper)
## - Mavena (Nivara healer & quarantine pond steward)
## - Evaren (Nivara / Kevar anchor warden)
## - Selima (Nivara chronicler & keeper of promises)
## - Tobren (Mulane master fisher)
## - Ruvet (Toramek logging foreman)

const ANCHOR_NPC_DEFINITION_ID := "core:actor/anchor_npc"
const NPC_COMPONENT := "npc_state"

const NPC_SARELA := "npc_sarela"
const NPC_TOVAN := "npc_tovan"
const NPC_ILUNE := "npc_ilune"
const NPC_MAVENA := "npc_mavena"
const NPC_EVAREN := "npc_evaren"
const NPC_SELIMA := "npc_selima"
const NPC_TOBREN := "npc_tobren"
const NPC_RUVET := "npc_ruvet"

const PROMISE_NONE := "none"
const PROMISE_RESTORE_NAVELU_DAM := "promise_restore_navelu_dam"
const PROMISE_QUARANTINE_KEVALU := "promise_quarantine_kevalu"
const PROMISE_RESPECT_TORAVA_QUOTA := "promise_respect_torava_quota"
const PROMISE_STABILIZE_MULANE_FISH := "promise_stabilize_mulane_fish"


static func ensure_slice_npcs(world: WorldState) -> Dictionary:
	if world == null or not world.is_initialized():
		return {"ok": false, "error": "world is not initialized"}
	var existing := find_npcs(world)
	var specs := _default_npc_specs()
	for npc_id in specs.keys():
		if existing.has(npc_id):
			continue
		var state: Dictionary = specs[npc_id]
		var entity_id := world.create_entity(ANCHOR_NPC_DEFINITION_ID, {NPC_COMPONENT: state})
		if entity_id <= 0:
			return {"ok": false, "error": "failed to spawn anchor NPC '%s'" % String(npc_id)}
		existing[npc_id] = entity_id
	return {"ok": true, "npcs": existing}


static func find_npcs(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	if world == null or not world.is_initialized():
		return result
	for entity_id in world.entity_ids():
		var entity := world.get_entity(entity_id)
		if String(entity.get("definition_id", "")) != ANCHOR_NPC_DEFINITION_ID:
			continue
		var comp := world.get_entity_component(entity_id, NPC_COMPONENT)
		var npc_id := String(comp.get("npc_id", ""))
		if not npc_id.is_empty():
			result[npc_id] = entity_id
	return result


static func step_hour(world: WorldState) -> Dictionary:
	var ensured := ensure_slice_npcs(world)
	if not bool(ensured.get("ok", false)):
		return ensured
	var npcs: Dictionary = ensured.get("npcs", {})
	var hour := world.clock().hour_of_day()
	var activity := _activity_for_hour(hour)
	var basin := SevaraEcoChain.basin_summary(world)

	for raw_npc_id in npcs.keys():
		var npc_id := String(raw_npc_id)
		var entity_id := int(npcs[raw_npc_id])
		var state := world.get_entity_component(entity_id, NPC_COMPONENT)
		state["current_activity"] = activity
		if npc_id == NPC_RUVET and hour == 12:
			_apply_ruvet_midday_logging(world, state)
		if not basin.is_empty():
			_evaluate_active_promise(world, entity_id, state, basin)
		world.set_entity_component(entity_id, NPC_COMPONENT, state)

	return {"ok": true, "npc_count": npcs.size()}


static func record_intervention_reaction(world: WorldState, intervention_kind: String) -> void:
	var npcs := find_npcs(world)
	if npcs.is_empty():
		return
	match intervention_kind:
		SevaraEcoChain.INTERVENTION_RESTORE_NAVELU_DAM:
			_adjust_npc_memory(world, npcs, NPC_TOVAN, "restored_navelu_dam", 12.0)
			_adjust_npc_memory(world, npcs, NPC_TOBREN, "restored_upstream_navelu", 10.0)
		SevaraEcoChain.INTERVENTION_CLEAR_NAVELU_DAM:
			_adjust_npc_memory(world, npcs, NPC_TOBREN, "cleared_navelu_dam_silt_surge", -14.0)
			_adjust_npc_memory(world, npcs, NPC_ILUNE, "damaged_selave_signal_habitat", -10.0)
		SevaraEcoChain.INTERVENTION_PLANT_KEVALU_QUARANTINE:
			_adjust_npc_memory(world, npcs, NPC_MAVENA, "placed_kevalu_in_quarantine", 14.0)
			_adjust_npc_memory(world, npcs, NPC_EVAREN, "respected_kevar_quarantine", 10.0)
		SevaraEcoChain.INTERVENTION_RELEASE_KEVALU_WILD:
			_adjust_npc_memory(world, npcs, NPC_MAVENA, "released_kevalu_uncontained", -20.0)
			_adjust_npc_memory(world, npcs, NPC_ILUNE, "threatened_tivane_with_wild_kevalu", -16.0)
			_adjust_npc_memory(world, npcs, NPC_EVAREN, "violated_kevar_containment", -18.0)


static func npcs_summary(world: WorldState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var npcs := find_npcs(world)
	var ids: Array = npcs.keys()
	ids.sort()
	for raw_id in ids:
		var entity_id := int(npcs[raw_id])
		result.append(world.get_entity_component(entity_id, NPC_COMPONENT))
	return result


static func _apply_ruvet_midday_logging(world: WorldState, ruvet_state: Dictionary) -> void:
	var promise_state := String(ruvet_state.get("promise_state", "none"))
	var active_promise := String(ruvet_state.get("active_promise", PROMISE_NONE))
	if active_promise == PROMISE_RESPECT_TORAVA_QUOTA and promise_state in ["active", "fulfilled"]:
		return
	var nodes := SevaraEcoChain.find_basin_nodes(world)
	if not nodes.has(SevaraEcoChain.NODE_TORAMEK_SLOPE):
		return
	var slope_id := int(nodes[SevaraEcoChain.NODE_TORAMEK_SLOPE])
	var slope := world.get_entity_component(slope_id, SevaraEcoChain.ECO_NODE_COMPONENT)
	var canopy := float(slope.get("torava_canopy", 0.70))
	slope["torava_canopy"] = roundf(maxf(canopy - 0.012, 0.15) * 10000.0) / 10000.0
	world.set_entity_component(slope_id, SevaraEcoChain.ECO_NODE_COMPONENT, slope)


static func _evaluate_active_promise(
	world: WorldState, entity_id: int, state: Dictionary, basin: Dictionary
) -> void:
	if String(state.get("promise_state", "none")) != "active":
		return
	var promise := String(state.get("active_promise", PROMISE_NONE))
	var channel: Dictionary = basin.get(SevaraEcoChain.NODE_NIVAREL_CHANNEL, {})
	var wetland: Dictionary = basin.get(SevaraEcoChain.NODE_MULANE_WETLAND, {})
	var npc_id := String(state.get("npc_id", ""))

	if promise == PROMISE_RESTORE_NAVELU_DAM:
		if not bool(channel.get("navelu_refugium_alive", true)):
			_settle_promise(world, entity_id, state, npc_id, promise, "broken", -25.0)
		elif float(channel.get("navelu_dams_integrity", 0.0)) >= 0.55:
			_settle_promise(world, entity_id, state, npc_id, promise, "fulfilled", 15.0)
	elif promise == PROMISE_QUARANTINE_KEVALU:
		if float(channel.get("kevalu_wild_biomass", 0.0)) > 0.05:
			_settle_promise(world, entity_id, state, npc_id, promise, "broken", -25.0)
		elif (
			bool(channel.get("kevalu_quarantine_active", false))
			and float(channel.get("kevalu_quarantine_knowledge", 0.0)) >= 0.10
		):
			_settle_promise(world, entity_id, state, npc_id, promise, "fulfilled", 18.0)
	elif promise == PROMISE_STABILIZE_MULANE_FISH:
		if float(wetland.get("murela_juveniles", 0.0)) >= 0.45:
			_settle_promise(world, entity_id, state, npc_id, promise, "fulfilled", 16.0)


static func _settle_promise(
	world: WorldState,
	entity_id: int,
	state: Dictionary,
	npc_id: String,
	promise: String,
	outcome: String,
	trust_delta: float
) -> void:
	state["promise_state"] = outcome
	state["trust"] = clampf(float(state.get("trust", 50.0)) + trust_delta, 0.0, 100.0)
	var kind := "npc_promise_fulfilled" if outcome == "fulfilled" else "npc_promise_broken"
	world.fact_log().append_fact(
		kind,
		world.clock().total_minutes(),
		{"npc_id": npc_id, "promise": promise, "trust": state["trust"]},
		entity_id,
		ANCHOR_NPC_DEFINITION_ID
	)


static func _adjust_npc_memory(
	world: WorldState, npcs: Dictionary, npc_id: String, memory_tag: String, trust_delta: float
) -> void:
	if not npcs.has(npc_id):
		return
	var entity_id := int(npcs[npc_id])
	var state := world.get_entity_component(entity_id, NPC_COMPONENT)
	state["trust"] = clampf(float(state.get("trust", 50.0)) + trust_delta, 0.0, 100.0)
	var memories: Array = state.get("memory_entries", [])
	if not memories.has(memory_tag):
		memories.append(memory_tag)
	state["memory_entries"] = memories
	world.set_entity_component(entity_id, NPC_COMPONENT, state)


static func _activity_for_hour(hour: int) -> String:
	if hour >= 6 and hour < 12:
		return "morning_work"
	if hour >= 12 and hour < 18:
		return "afternoon_work"
	if hour >= 18 and hour < 22:
		return "evening_hearth"
	return "night_rest"


static func _default_npc_specs() -> Dictionary:
	return {
		NPC_SARELA:
		_make_spec(
			NPC_SARELA,
			"Sarela",
			"Сарела",
			"nivara",
			"chief",
			SevaraEcoChain.NODE_NIVAREL_CHANNEL,
			"clue_sarela_water_rationing",
			PROMISE_STABILIZE_MULANE_FISH
		),
		NPC_TOVAN:
		_make_spec(
			NPC_TOVAN,
			"Tovan",
			"Тован",
			"nivara",
			"sluice_keeper",
			SevaraEcoChain.NODE_NIVAREL_CHANNEL,
			"clue_tovan_orunel_sluice_silt",
			PROMISE_RESTORE_NAVELU_DAM
		),
		NPC_ILUNE:
		_make_spec(
			NPC_ILUNE,
			"Ilune",
			"Илуне",
			"nivara",
			"seed_keeper",
			SevaraEcoChain.NODE_NIVAREL_CHANNEL,
			"clue_ilune_tivane_selave_signal",
			PROMISE_NONE
		),
		NPC_MAVENA:
		_make_spec(
			NPC_MAVENA,
			"Mavena",
			"Мавена",
			"nivara",
			"healer_quarantine",
			SevaraEcoChain.NODE_NIVAREL_CHANNEL,
			"clue_mavena_quarantine_pond",
			PROMISE_QUARANTINE_KEVALU
		),
		NPC_EVAREN:
		_make_spec(
			NPC_EVAREN,
			"Evaren",
			"Эварен",
			"nivara",
			"kevar_warden",
			SevaraEcoChain.NODE_NIVAREL_CHANNEL,
			"clue_evaren_kevar_kin_wetland",
			PROMISE_QUARANTINE_KEVALU
		),
		NPC_SELIMA:
		_make_spec(
			NPC_SELIMA,
			"Selima",
			"Селима",
			"nivara",
			"chronicler",
			SevaraEcoChain.NODE_NIVAREL_CHANNEL,
			"clue_selima_missing_orunel_accord",
			PROMISE_NONE
		),
		NPC_TOBREN:
		_make_spec(
			NPC_TOBREN,
			"Tobren",
			"Тобрен",
			"mulane",
			"master_fisher",
			SevaraEcoChain.NODE_MULANE_WETLAND,
			"clue_tobren_murela_nursery_silt",
			PROMISE_RESTORE_NAVELU_DAM
		),
		NPC_RUVET:
		_make_spec(
			NPC_RUVET,
			"Ruvet",
			"Рувет",
			"toramek",
			"logger_foreman",
			SevaraEcoChain.NODE_TORAMEK_SLOPE,
			"clue_ruvet_torava_quota_pressure",
			PROMISE_RESPECT_TORAVA_QUOTA
		),
	}


static func _make_spec(
	npc_id: String,
	name_en: String,
	name_ru: String,
	settlement_id: String,
	role: String,
	work_node_id: String,
	clue_id: String,
	offered_promise: String
) -> Dictionary:
	return {
		"npc_id": npc_id,
		"name_en": name_en,
		"name_ru": name_ru,
		"settlement_id": settlement_id,
		"role": role,
		"work_node_id": work_node_id,
		"current_activity": "morning_work",
		"trust": 50.0,
		"clue_id": clue_id,
		"offered_promise": offered_promise,
		"active_promise": PROMISE_NONE,
		"promise_state": "none",
		"memory_entries": [],
	}

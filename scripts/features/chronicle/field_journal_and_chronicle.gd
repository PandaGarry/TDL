class_name FieldJournalAndChronicle
extends RefCounted
## P1-C/P1-D bodily field journal (observations -> hypotheses without omniscient
## spoilers), Kevar anchor sample collection and Selima's settlement chronicle.
##
## Implements the canonical 5-rung revelation ladder from Baseline Lock §2.3:
## 1) `hyp_1_symptoms_silt_and_late_tivane` (observing Mulane silt & fry decline)
## 2) `hyp_2_physical_traces_orunel_channel_cuts` (inspecting Nivarel sluice/dams)
## 3) `hyp_3_social_lie_orunel_chronicle_gap` (consulting Selima & Tovan)
## 4) `hyp_4_kevar_kin_ecosystem_parallel` (collecting Kevalu at Kevar + Evaren)
## 5) `hyp_5_basin_restoration_choice` (quarantine test or Navelu dam restoration)

const JOURNAL_COMPONENT := "field_journal"

const ACTION_INSPECT_BASIN_NODE := "inspect_basin_node"
const ACTION_CONSULT_NPC := "consult_npc"
const ACTION_COLLECT_KEVAR_SAMPLE := "collect_kevar_sample"

const HYP_1_SYMPTOMS := "hyp_1_symptoms_silt_and_late_tivane"
const HYP_2_PHYSICAL_TRACES := "hyp_2_physical_traces_orunel_channel_cuts"
const HYP_3_SOCIAL_LIE := "hyp_3_social_lie_orunel_chronicle_gap"
const HYP_4_KEVAR_KIN := "hyp_4_kevar_kin_ecosystem_parallel"
const HYP_5_RESTORATION_CHOICE := "hyp_5_basin_restoration_choice"


static func ensure_journal(world: WorldState, body_entity_id: int) -> Dictionary:
	if world == null or not world.is_initialized() or not world.has_entity(body_entity_id):
		return {}
	var journal := world.get_entity_component(body_entity_id, JOURNAL_COMPONENT)
	if journal.is_empty():
		journal = {
			"observations": [],
			"clues": [],
			"hypotheses": [],
		}
		world.set_entity_component(body_entity_id, JOURNAL_COMPONENT, journal)
	return journal


static func apply_field_action(
	world: WorldState,
	body_entity_id: int,
	action: String,
	target_id: String = "",
	accept_promise: bool = false
) -> Dictionary:
	if world == null or not world.is_initialized() or not world.has_entity(body_entity_id):
		return {"ok": false, "reason": "body_not_found", "error": "body entity is missing"}
	BodyVitals.ensure_body_components(world, body_entity_id)
	var journal := ensure_journal(world, body_entity_id)

	match action:
		ACTION_INSPECT_BASIN_NODE:
			return _inspect_basin_node(world, body_entity_id, journal, target_id)
		ACTION_CONSULT_NPC:
			return _consult_npc(world, body_entity_id, journal, target_id, accept_promise)
		ACTION_COLLECT_KEVAR_SAMPLE:
			return _collect_kevar_sample(world, body_entity_id, journal)
	return {
		"ok": false,
		"reason": "unknown_field_action",
		"error": "unknown field action '%s'" % action,
	}


static func build_settlement_chronicle(world: WorldState) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if world == null or not world.is_initialized():
		return entries
	var chronicle_kinds := [
		"campaign_created",
		"eco_intervention",
		"eco_kevalu_spread",
		"eco_navelu_refugium_lost",
		"kevar_sample_collected",
		"npc_promise_accepted",
		"npc_promise_fulfilled",
		"npc_promise_broken",
		"body_contracted_silt_malaise",
	]
	for fact in world.fact_log().facts():
		var kind := String(fact.get("kind", ""))
		if chronicle_kinds.has(kind):
			entries.append(fact)
	return entries


static func _inspect_basin_node(
	world: WorldState, body_entity_id: int, journal: Dictionary, node_id: String
) -> Dictionary:
	var nodes := SevaraEcoChain.find_basin_nodes(world)
	if not nodes.has(node_id):
		return {
			"ok": false,
			"reason": "node_not_found",
			"error": "ecological basin node '%s' does not exist" % node_id,
		}
	var obs_id := "obs_%s" % node_id
	_append_unique_string(journal, "observations", obs_id)
	_recompute_hypotheses(world, journal)
	world.set_entity_component(body_entity_id, JOURNAL_COMPONENT, journal)
	BodyVitals.award_practice(world, body_entity_id, BodyVitals.PRACTICE_BOTANY, 1.5)

	var fact := world.fact_log().append_fact(
		"field_observation_recorded",
		world.clock().total_minutes(),
		{"node_id": node_id, "observation": obs_id, "hypotheses": journal["hypotheses"]},
		body_entity_id,
		SevaraEcoChain.BASIN_NODE_DEFINITION_ID
	)
	return {"ok": true, "journal": journal, "fact": fact, "reason": "", "error": ""}


static func _consult_npc(
	world: WorldState,
	body_entity_id: int,
	journal: Dictionary,
	npc_id: String,
	accept_promise: bool
) -> Dictionary:
	var npcs := SevaraP1Npcs.find_npcs(world)
	if not npcs.has(npc_id):
		return {
			"ok": false,
			"reason": "npc_not_found",
			"error": "anchor NPC '%s' does not exist" % npc_id,
		}
	var npc_entity_id := int(npcs[npc_id])
	var npc_state := world.get_entity_component(npc_entity_id, SevaraP1Npcs.NPC_COMPONENT)
	var clue_id := String(npc_state.get("clue_id", ""))
	if not clue_id.is_empty():
		_append_unique_string(journal, "clues", clue_id)

	var offered_promise := String(npc_state.get("offered_promise", SevaraP1Npcs.PROMISE_NONE))
	if accept_promise and offered_promise != SevaraP1Npcs.PROMISE_NONE:
		npc_state["active_promise"] = offered_promise
		npc_state["promise_state"] = "active"
		world.set_entity_component(npc_entity_id, SevaraP1Npcs.NPC_COMPONENT, npc_state)
		world.fact_log().append_fact(
			"npc_promise_accepted",
			world.clock().total_minutes(),
			{"npc_id": npc_id, "promise": offered_promise},
			body_entity_id,
			SevaraP1Npcs.ANCHOR_NPC_DEFINITION_ID
		)

	_recompute_hypotheses(world, journal)
	world.set_entity_component(body_entity_id, JOURNAL_COMPONENT, journal)
	var fact := world.fact_log().append_fact(
		"npc_consulted",
		world.clock().total_minutes(),
		{"npc_id": npc_id, "clue_id": clue_id, "accepted_promise": accept_promise},
		body_entity_id,
		SevaraP1Npcs.ANCHOR_NPC_DEFINITION_ID
	)
	return {"ok": true, "journal": journal, "fact": fact, "reason": "", "error": ""}


static func _collect_kevar_sample(
	world: WorldState, body_entity_id: int, journal: Dictionary
) -> Dictionary:
	var day := world.clock().day_of_season()
	var window_open := world.world_rules().kevar_window_always_open() or (day >= 18 and day <= 24)
	if not window_open:
		return {
			"ok": false,
			"reason": "kevar_window_closed",
			"error": "Kevar anchor window is only open on days 18..24 of the season",
		}
	var inv := world.get_entity_component(body_entity_id, GreyboxWorld.INVENTORY_COMPONENT)
	var next_inv := inv.duplicate(true)
	var cur := int(
		GreyboxWorld.integral_value(next_inv.get("core:material/kevalu_propagule", 0)).get(
			"value", 0
		)
	)
	next_inv["core:material/kevalu_propagule"] = cur + 1
	world.set_entity_component(body_entity_id, GreyboxWorld.INVENTORY_COMPONENT, next_inv)

	_append_unique_string(journal, "observations", "obs_kevar_kin_wetland_sample")
	_recompute_hypotheses(world, journal)
	world.set_entity_component(body_entity_id, JOURNAL_COMPONENT, journal)
	BodyVitals.award_practice(world, body_entity_id, BodyVitals.PRACTICE_BOTANY, 3.0)

	var fact := world.fact_log().append_fact(
		"kevar_sample_collected",
		world.clock().total_minutes(),
		{"item_id": "core:material/kevalu_propagule", "count": cur + 1},
		body_entity_id,
		"core:species/kevalu"
	)
	return {"ok": true, "journal": journal, "fact": fact, "reason": "", "error": ""}


static func _recompute_hypotheses(world: WorldState, journal: Dictionary) -> void:
	var obs: Array = journal.get("observations", [])
	var clues: Array = journal.get("clues", [])
	if obs.has("obs_mulane_wetland") or clues.has("clue_tobren_murela_nursery_silt"):
		_append_unique_string(journal, "hypotheses", HYP_1_SYMPTOMS)
	if obs.has("obs_nivarel_channel") and clues.has("clue_tovan_orunel_sluice_silt"):
		_append_unique_string(journal, "hypotheses", HYP_2_PHYSICAL_TRACES)
	if clues.has("clue_selima_missing_orunel_accord") and clues.has("clue_sarela_water_rationing"):
		_append_unique_string(journal, "hypotheses", HYP_3_SOCIAL_LIE)
	if obs.has("obs_kevar_kin_wetland_sample") and clues.has("clue_evaren_kevar_kin_wetland"):
		_append_unique_string(journal, "hypotheses", HYP_4_KEVAR_KIN)

	var basin := SevaraEcoChain.basin_summary(world)
	var channel: Dictionary = basin.get(SevaraEcoChain.NODE_NIVAREL_CHANNEL, {})
	if (
		bool(channel.get("kevalu_quarantine_active", false))
		or float(channel.get("navelu_dams_integrity", 0.0)) >= 0.55
	):
		_append_unique_string(journal, "hypotheses", HYP_5_RESTORATION_CHOICE)


static func _append_unique_string(dict: Dictionary, key: String, item: String) -> void:
	var list: Array = dict.get(key, [])
	if not list.has(item):
		list.append(item)
	dict[key] = list

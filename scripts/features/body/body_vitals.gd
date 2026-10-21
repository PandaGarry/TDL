class_name BodyVitals
extends RefCounted
## P1-B bodily survival, symptom causality and practice progression (0..100).
##
## Connects the player's mortal body (`core:actor/greybox_body`) directly to the
## Sevara ecological cascade and `WorldRules`:
## - `vitals` component tracks nutrition, hydration, stamina, warmth, wetness
##   and waterborne_malaise;
## - `practice` component tracks classless domain practice (`0.0..100.0`) scaled
##   by `world.world_rules().skill_xp_multiplier()`;
## - drinking water from a silted basin (`silt_load >= 0.50` when Navelu/Selave
##   filtration fails) causes `waterborne_malaise` (`silt_fever_nausea`),
##   directly linking watershed health to bodily health.

const VITALS_COMPONENT := "vitals"
const PRACTICE_COMPONENT := "practice"

const ACTION_EAT_FOOD := "eat_food"
const ACTION_DRINK_BASIN_WATER := "drink_basin_water"
const ACTION_REST_AND_WARM := "rest_and_warm"

const PRACTICE_WATERSHED := "watershed_engineering"
const PRACTICE_FISHERY := "fishery_and_foraging"
const PRACTICE_WOODCRAFT := "forest_woodcraft"
const PRACTICE_BOTANY := "quarantine_botany"


static func ensure_body_components(world: WorldState, body_entity_id: int) -> bool:
	if world == null or not world.is_initialized() or not world.has_entity(body_entity_id):
		return false
	var entity := world.get_entity(body_entity_id)
	if String(entity.get("definition_id", "")) != GreyboxWorld.BODY_DEFINITION_ID:
		return false
	if world.get_entity_component(body_entity_id, VITALS_COMPONENT).is_empty():
		world.set_entity_component(body_entity_id, VITALS_COMPONENT, default_vitals())
	if world.get_entity_component(body_entity_id, PRACTICE_COMPONENT).is_empty():
		world.set_entity_component(body_entity_id, PRACTICE_COMPONENT, default_practice())
	return true


static func ensure_all_bodies(world: WorldState) -> int:
	if world == null or not world.is_initialized():
		return 0
	var count := 0
	for record in GreyboxWorld.body_records(world):
		var body_id := int(record.get("body_entity_id", -1))
		if ensure_body_components(world, body_id):
			count += 1
	return count


static func default_vitals() -> Dictionary:
	return {
		"nutrition": 0.85,
		"hydration": 0.88,
		"stamina": 0.90,
		"body_warmth": 0.82,
		"wetness": 0.10,
		"waterborne_malaise": 0.0,
	}


static func default_practice() -> Dictionary:
	return {
		PRACTICE_WATERSHED: 0.0,
		PRACTICE_FISHERY: 0.0,
		PRACTICE_WOODCRAFT: 0.0,
		PRACTICE_BOTANY: 0.0,
	}


static func step_hour(world: WorldState) -> Dictionary:
	if world == null or not world.is_initialized():
		return {"ok": false, "error": "world is not initialized"}
	var pressure := world.world_rules().survival_pressure_multiplier()
	var hour := world.clock().hour_of_day()
	var is_night := hour < 6 or hour >= 20
	var updated_bodies := 0

	for record in GreyboxWorld.body_records(world):
		var body_id := int(record.get("body_entity_id", -1))
		if not ensure_body_components(world, body_id):
			continue
		var body_comp := world.get_entity_component(body_id, GreyboxWorld.BODY_COMPONENT)
		if bool(body_comp.get("sheltered", false)):
			continue
		var vitals := world.get_entity_component(body_id, VITALS_COMPONENT)
		var malaise := float(vitals.get("waterborne_malaise", 0.0))
		var wetness := float(vitals.get("wetness", 0.10))

		var nutrition := clampf(float(vitals.get("nutrition", 0.85)) - 0.018 * pressure, 0.0, 1.0)
		var hydration := clampf(
			float(vitals.get("hydration", 0.88)) - (0.024 + malaise * 0.015) * pressure, 0.0, 1.0
		)
		var stamina := clampf(
			float(vitals.get("stamina", 0.90)) - (0.015 + malaise * 0.020) * pressure, 0.0, 1.0
		)
		var chill_rate := (0.020 if is_night else 0.006) + wetness * 0.025
		var warmth := clampf(
			float(vitals.get("body_warmth", 0.82)) - chill_rate * pressure, 0.0, 1.0
		)
		wetness = clampf(wetness - 0.03, 0.0, 1.0)

		vitals["nutrition"] = _round4(nutrition)
		vitals["hydration"] = _round4(hydration)
		vitals["stamina"] = _round4(stamina)
		vitals["body_warmth"] = _round4(warmth)
		vitals["wetness"] = _round4(wetness)
		vitals["waterborne_malaise"] = _round4(malaise)
		world.set_entity_component(body_id, VITALS_COMPONENT, vitals)
		updated_bodies += 1

	return {"ok": true, "updated_bodies": updated_bodies}


static func award_practice(
	world: WorldState, body_entity_id: int, domain: String, base_gain: float
) -> Dictionary:
	if not ensure_body_components(world, body_entity_id):
		return {"ok": false, "error": "body entity is missing"}
	var practice := world.get_entity_component(body_entity_id, PRACTICE_COMPONENT)
	if not practice.has(domain):
		return {"ok": false, "error": "unknown practice domain '%s'" % domain}
	var xp_mult := world.world_rules().skill_xp_multiplier()
	var current := float(practice.get(domain, 0.0))
	var next_val := _round4(clampf(current + maxf(base_gain, 0.0) * xp_mult, 0.0, 100.0))
	practice[domain] = next_val
	world.set_entity_component(body_entity_id, PRACTICE_COMPONENT, practice)
	return {"ok": true, "domain": domain, "value": next_val}


static func apply_body_care(
	world: WorldState, body_entity_id: int, action: String, item_id: String = ""
) -> Dictionary:
	if not ensure_body_components(world, body_entity_id):
		return {"ok": false, "reason": "body_not_found", "error": "body entity is missing"}
	var vitals := world.get_entity_component(body_entity_id, VITALS_COMPONENT)
	var inventory := world.get_entity_component(body_entity_id, GreyboxWorld.INVENTORY_COMPONENT)

	match action:
		ACTION_EAT_FOOD:
			var chosen_item := item_id
			if chosen_item.is_empty():
				chosen_item = (
					"core:material/talune_grain"
					if int(inventory.get("core:material/talune_grain", 0)) > 0
					else "core:material/murela_catch"
				)
			if (
				chosen_item != "core:material/murela_catch"
				and chosen_item != "core:material/talune_grain"
			):
				return {
					"ok": false,
					"reason": "inedible_item",
					"error": "item '%s' is not edible food" % chosen_item,
				}
			var have_count := int(
				GreyboxWorld.integral_value(inventory.get(chosen_item, 0)).get("value", 0)
			)
			if have_count < 1:
				return {
					"ok": false,
					"reason": "missing_food_item",
					"error": "inventory has no '%s'" % chosen_item,
				}
			var new_inv := inventory.duplicate(true)
			if have_count == 1:
				new_inv.erase(chosen_item)
			else:
				new_inv[chosen_item] = have_count - 1
			var nut_gain := 0.45 if chosen_item == "core:material/talune_grain" else 0.38
			vitals["nutrition"] = _round4(
				clampf(float(vitals.get("nutrition", 0.85)) + nut_gain, 0.0, 1.0)
			)
			vitals["stamina"] = _round4(clampf(float(vitals.get("stamina", 0.90)) + 0.15, 0.0, 1.0))
			world.set_entity_component(body_entity_id, GreyboxWorld.INVENTORY_COMPONENT, new_inv)
			world.set_entity_component(body_entity_id, VITALS_COMPONENT, vitals)

		ACTION_DRINK_BASIN_WATER:
			var silt_load := _current_basin_silt(world)
			vitals["hydration"] = _round4(
				clampf(float(vitals.get("hydration", 0.88)) + 0.45, 0.0, 1.0)
			)
			if silt_load >= 0.50:
				var next_malaise := _round4(
					clampf(float(vitals.get("waterborne_malaise", 0.0)) + 0.35, 0.0, 1.0)
				)
				vitals["waterborne_malaise"] = next_malaise
				world.fact_log().append_fact(
					"body_contracted_silt_malaise",
					world.clock().total_minutes(),
					{"entity_id": body_entity_id, "silt_load": silt_load},
					body_entity_id,
					GreyboxWorld.BODY_DEFINITION_ID
				)
			world.set_entity_component(body_entity_id, VITALS_COMPONENT, vitals)

		ACTION_REST_AND_WARM:
			vitals["stamina"] = _round4(clampf(float(vitals.get("stamina", 0.90)) + 0.40, 0.0, 1.0))
			vitals["body_warmth"] = _round4(
				clampf(float(vitals.get("body_warmth", 0.82)) + 0.35, 0.0, 1.0)
			)
			vitals["wetness"] = _round4(maxf(float(vitals.get("wetness", 0.10)) - 0.50, 0.0))
			var selave_count := int(
				GreyboxWorld.integral_value(inventory.get("core:material/selave_bundle", 0)).get(
					"value", 0
				)
			)
			if float(vitals.get("waterborne_malaise", 0.0)) > 0.0:
				var heal := 0.45 if selave_count > 0 else 0.15
				vitals["waterborne_malaise"] = _round4(
					maxf(float(vitals.get("waterborne_malaise", 0.0)) - heal, 0.0)
				)
			world.set_entity_component(body_entity_id, VITALS_COMPONENT, vitals)

		_:
			return {
				"ok": false,
				"reason": "unknown_body_care_action",
				"error": "unknown body care action '%s'" % action,
			}

	var fact := world.fact_log().append_fact(
		"body_care_applied",
		world.clock().total_minutes(),
		{"entity_id": body_entity_id, "action": action, "vitals": vitals},
		body_entity_id,
		GreyboxWorld.BODY_DEFINITION_ID
	)
	return {
		"ok": true,
		"action": action,
		"vitals": vitals,
		"diagnostics": diagnose_body(vitals),
		"fact": fact,
	}


static func diagnose_body(vitals: Dictionary) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	if float(vitals.get("nutrition", 1.0)) < 0.45:
		(
			findings
			. append(
				{
					"symptom": "hunger_weakness",
					"cause": "low_nutrition_need_murela_or_talune",
				}
			)
		)
	if float(vitals.get("hydration", 1.0)) < 0.45:
		(
			findings
			. append(
				{
					"symptom": "dehydration_dizziness",
					"cause": "low_hydration_need_clean_water",
				}
			)
		)
	if float(vitals.get("body_warmth", 1.0)) < 0.50 or float(vitals.get("wetness", 0.0)) > 0.55:
		(
			findings
			. append(
				{
					"symptom": "chill_and_dampness",
					"cause": "wet_exposure_need_shelter_and_warmth",
				}
			)
		)
	if float(vitals.get("waterborne_malaise", 0.0)) >= 0.25:
		(
			findings
			. append(
				{
					"symptom": "silt_fever_nausea",
					"cause": "drank_turbid_water_from_degraded_selave_channel",
				}
			)
		)
	if float(vitals.get("stamina", 1.0)) < 0.35:
		(
			findings
			. append(
				{
					"symptom": "exhaustion_tremor",
					"cause": "depleted_stamina_from_labor_or_malaise",
				}
			)
		)
	return findings


static func _current_basin_silt(world: WorldState) -> float:
	var nodes := SevaraEcoChain.find_basin_nodes(world)
	if not nodes.has(SevaraEcoChain.NODE_MULANE_WETLAND):
		return 0.0
	var wetland := world.get_entity_component(
		int(nodes[SevaraEcoChain.NODE_MULANE_WETLAND]), SevaraEcoChain.ECO_NODE_COMPONENT
	)
	return float(wetland.get("silt_load", 0.0))


static func _round4(value: float) -> float:
	return roundf(value * 10000.0) / 10000.0

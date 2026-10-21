class_name SevaraEcoChain
extends RefCounted
## Deterministic P1-A ecological cascade for the Sevara Valley slice.
##
## Models the four coupled watershed/biome nodes of the Act I slice:
## 1) `toramek_slope` (Torava forest canopy, Orive pioneer shrub, snowmelt runoff)
## 2) `nivarel_channel` (Navelu dam/refugium, Selave filtration beds, Tivane
##    pollinator sync, Talune garden yield, Orunel sluice gate, Kevalu quarantine
##    vs uncontained wild spread)
## 3) `mulane_wetland` (silt load, water clarity, juvenile & adult Murela fish)
## 4) `heravo_meadow` (meadow forage, Heruna grazers, Karune predators)
##
## All state lives inside `WorldState` entities (`core:object/eco_basin_node`)
## so it is automatically saved, hashed by `domain_state_hash()` and replicated.
## Multipliers are read from `world.world_rules()` (`ecology_recovery_multiplier`,
## `resource_yield_multiplier`).

const BASIN_NODE_DEFINITION_ID := "core:object/eco_basin_node"
const ECO_NODE_COMPONENT := "eco_node"

const NODE_TORAMEK_SLOPE := "toramek_slope"
const NODE_NIVAREL_CHANNEL := "nivarel_channel"
const NODE_MULANE_WETLAND := "mulane_wetland"
const NODE_HERAVO_MEADOW := "heravo_meadow"

const INTERVENTION_RESTORE_NAVELU_DAM := "restore_navelu_dam"
const INTERVENTION_CLEAR_NAVELU_DAM := "clear_navelu_dam"
const INTERVENTION_HARVEST_TORAVA := "harvest_torava"
const INTERVENTION_HARVEST_MURELA := "harvest_murela"
const INTERVENTION_PLANT_KEVALU_QUARANTINE := "plant_kevalu_quarantine"
const INTERVENTION_RELEASE_KEVALU_WILD := "release_kevalu_wild"
const INTERVENTION_PURGE_KEVALU_CHANNEL := "purge_kevalu_channel"


static func ensure_basin_nodes(world: WorldState) -> Dictionary:
	if world == null or not world.is_initialized():
		return {"ok": false, "error": "world is not initialized"}
	var existing := find_basin_nodes(world)
	if existing.size() == 4:
		return {"ok": true, "nodes": existing}

	var defaults := _default_node_components(world.genesis_seed())
	for node_key in [
		NODE_TORAMEK_SLOPE,
		NODE_NIVAREL_CHANNEL,
		NODE_MULANE_WETLAND,
		NODE_HERAVO_MEADOW,
	]:
		if existing.has(node_key):
			continue
		var comp: Dictionary = defaults[node_key]
		var entity_id := world.create_entity(BASIN_NODE_DEFINITION_ID, {ECO_NODE_COMPONENT: comp})
		if entity_id <= 0:
			return {"ok": false, "error": "failed to create eco_basin_node '%s'" % node_key}
		existing[node_key] = entity_id
	return {"ok": true, "nodes": existing}


static func find_basin_nodes(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	if world == null or not world.is_initialized():
		return result
	for entity_id in world.entity_ids():
		var entity := world.get_entity(entity_id)
		if String(entity.get("definition_id", "")) != BASIN_NODE_DEFINITION_ID:
			continue
		var comp := world.get_entity_component(entity_id, ECO_NODE_COMPONENT)
		var node_id := String(comp.get("node_id", ""))
		if not node_id.is_empty():
			result[node_id] = entity_id
	return result


static func step_hour(world: WorldState) -> Dictionary:
	var ensured := ensure_basin_nodes(world)
	if not bool(ensured.get("ok", false)):
		return ensured
	var nodes: Dictionary = ensured.get("nodes", {})
	var recovery_mult := world.world_rules().ecology_recovery_multiplier()
	var yield_mult := world.world_rules().resource_yield_multiplier()

	var slope_id := int(nodes[NODE_TORAMEK_SLOPE])
	var channel_id := int(nodes[NODE_NIVAREL_CHANNEL])
	var wetland_id := int(nodes[NODE_MULANE_WETLAND])
	var meadow_id := int(nodes[NODE_HERAVO_MEADOW])

	var slope := world.get_entity_component(slope_id, ECO_NODE_COMPONENT)
	var channel := world.get_entity_component(channel_id, ECO_NODE_COMPONENT)
	var wetland := world.get_entity_component(wetland_id, ECO_NODE_COMPONENT)
	var meadow := world.get_entity_component(meadow_id, ECO_NODE_COMPONENT)

	_step_slope(slope, recovery_mult)
	_step_channel_and_wetland(world, slope, channel, wetland, recovery_mult, yield_mult)
	_step_meadow(meadow, recovery_mult)

	world.set_entity_component(slope_id, ECO_NODE_COMPONENT, slope)
	world.set_entity_component(channel_id, ECO_NODE_COMPONENT, channel)
	world.set_entity_component(wetland_id, ECO_NODE_COMPONENT, wetland)
	world.set_entity_component(meadow_id, ECO_NODE_COMPONENT, meadow)
	return {"ok": true, "summary": basin_summary(world)}


static func apply_intervention(
	world: WorldState, kind: String, actor_entity_id: int = -1
) -> Dictionary:
	var ensured := ensure_basin_nodes(world)
	if not bool(ensured.get("ok", false)):
		return ensured
	var nodes: Dictionary = ensured.get("nodes", {})
	var yield_mult := world.world_rules().resource_yield_multiplier()
	var slope_id := int(nodes[NODE_TORAMEK_SLOPE])
	var channel_id := int(nodes[NODE_NIVAREL_CHANNEL])
	var wetland_id := int(nodes[NODE_MULANE_WETLAND])

	var slope := world.get_entity_component(slope_id, ECO_NODE_COMPONENT)
	var channel := world.get_entity_component(channel_id, ECO_NODE_COMPONENT)
	var wetland := world.get_entity_component(wetland_id, ECO_NODE_COMPONENT)
	var yielded_items: Dictionary = {}
	var target_subject := BASIN_NODE_DEFINITION_ID

	match kind:
		INTERVENTION_RESTORE_NAVELU_DAM:
			if not bool(channel.get("navelu_refugium_alive", true)):
				return {"ok": false, "error": "Navelu refugium is extinct in this channel"}
			channel["navelu_dams_integrity"] = _round4(
				clampf(float(channel.get("navelu_dams_integrity", 0.25)) + 0.35, 0.0, 1.0)
			)
			channel["navelu_population"] = _round4(
				clampf(float(channel.get("navelu_population", 0.22)) + 0.18, 0.0, 1.0)
			)
			target_subject = "core:species/navelu"
		INTERVENTION_CLEAR_NAVELU_DAM:
			channel["navelu_dams_integrity"] = _round4(
				maxf(float(channel.get("navelu_dams_integrity", 0.25)) - 0.40, 0.0)
			)
			channel["navelu_population"] = _round4(
				maxf(float(channel.get("navelu_population", 0.22)) - 0.15, 0.0)
			)
			target_subject = "core:species/navelu"
		INTERVENTION_HARVEST_TORAVA:
			slope["torava_canopy"] = _round4(
				maxf(float(slope.get("torava_canopy", 0.72)) - 0.18, 0.05)
			)
			slope["orive_shrub"] = _round4(
				clampf(float(slope.get("orive_shrub", 0.24)) + 0.10, 0.0, 1.0)
			)
			yielded_items["core:material/torava_wood"] = maxi(int(roundf(2.0 * yield_mult)), 1)
			target_subject = "core:species/torava"
		INTERVENTION_HARVEST_MURELA:
			var adult_fish := float(wetland.get("murela_adults", 0.48))
			if adult_fish < 0.12:
				return {"ok": false, "error": "Murela population is too depleted to harvest"}
			wetland["murela_adults"] = _round4(maxf(adult_fish - 0.14, 0.0))
			yielded_items["core:material/murela_catch"] = maxi(int(roundf(2.0 * yield_mult)), 1)
			target_subject = "core:species/murela"
		INTERVENTION_PLANT_KEVALU_QUARANTINE:
			channel["kevalu_quarantine_active"] = true
			channel["kevalu_quarantine_samples"] = (
				int(channel.get("kevalu_quarantine_samples", 0)) + 1
			)
			target_subject = "core:species/kevalu"
		INTERVENTION_RELEASE_KEVALU_WILD:
			channel["kevalu_wild_biomass"] = _round4(
				clampf(float(channel.get("kevalu_wild_biomass", 0.0)) + 0.28, 0.0, 1.0)
			)
			target_subject = "core:species/kevalu"
		INTERVENTION_PURGE_KEVALU_CHANNEL:
			channel["kevalu_wild_biomass"] = _round4(
				maxf(float(channel.get("kevalu_wild_biomass", 0.0)) - 0.35, 0.0)
			)
			target_subject = "core:species/kevalu"
		_:
			return {"ok": false, "error": "unknown ecological intervention '%s'" % kind}

	world.set_entity_component(slope_id, ECO_NODE_COMPONENT, slope)
	world.set_entity_component(channel_id, ECO_NODE_COMPONENT, channel)
	world.set_entity_component(wetland_id, ECO_NODE_COMPONENT, wetland)

	var fact := world.fact_log().append_fact(
		"eco_intervention",
		world.clock().total_minutes(),
		{"intervention": kind, "yielded_items": yielded_items},
		actor_entity_id,
		target_subject
	)
	return {
		"ok": true,
		"intervention": kind,
		"yielded_items": yielded_items,
		"fact": fact,
		"summary": basin_summary(world),
	}


static func basin_summary(world: WorldState) -> Dictionary:
	var nodes := find_basin_nodes(world)
	if nodes.size() < 4:
		return {}
	var slope := world.get_entity_component(int(nodes[NODE_TORAMEK_SLOPE]), ECO_NODE_COMPONENT)
	var channel := world.get_entity_component(int(nodes[NODE_NIVAREL_CHANNEL]), ECO_NODE_COMPONENT)
	var wetland := world.get_entity_component(int(nodes[NODE_MULANE_WETLAND]), ECO_NODE_COMPONENT)
	var meadow := world.get_entity_component(int(nodes[NODE_HERAVO_MEADOW]), ECO_NODE_COMPONENT)
	return {
		NODE_TORAMEK_SLOPE: slope,
		NODE_NIVAREL_CHANNEL: channel,
		NODE_MULANE_WETLAND: wetland,
		NODE_HERAVO_MEADOW: meadow,
		"diagnostics": diagnose_basin(slope, channel, wetland, meadow),
	}


static func diagnose_basin(
	slope: Dictionary, channel: Dictionary, wetland: Dictionary, meadow: Dictionary
) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	if float(wetland.get("silt_load", 0.0)) >= 0.55:
		(
			findings
			. append(
				{
					"symptom": "mulane_high_silt",
					"cause":
					(
						"low_torava_or_missing_navelu_dams"
						if float(channel.get("navelu_dams_integrity", 0.0)) < 0.45
						else "rapid_snowmelt_runoff"
					),
				}
			)
		)
	if float(wetland.get("murela_juveniles", 0.0)) < 0.35:
		(
			findings
			. append(
				{
					"symptom": "murela_juvenile_decline",
					"cause": "degraded_selave_nursery_and_high_silt",
				}
			)
		)
	if float(channel.get("kevalu_wild_biomass", 0.0)) >= 0.20:
		(
			findings
			. append(
				{
					"symptom": "tivane_early_desync_and_channel_choke",
					"cause": "uncontained_kevalu_displacing_selave",
				}
			)
		)
	elif bool(channel.get("kevalu_quarantine_active", false)):
		(
			findings
			. append(
				{
					"symptom": "kevalu_contained_in_quarantine",
					"cause": "quarantine_pond_filters_without_channel_spread",
				}
			)
		)
	if float(meadow.get("heruna_population", 0.0)) > 0.72:
		(
			findings
			. append(
				{
					"symptom": "meadow_overgrazing",
					"cause": "low_karune_predation_pressure",
				}
			)
		)
	if float(slope.get("torava_canopy", 1.0)) < 0.45:
		(
			findings
			. append(
				{
					"symptom": "slope_erosion_and_orive_spread",
					"cause": "excessive_torava_logging",
				}
			)
		)
	return findings


static func _step_slope(slope: Dictionary, recovery_mult: float) -> void:
	var canopy := float(slope.get("torava_canopy", 0.72))
	var orive := float(slope.get("orive_shrub", 0.24))
	canopy = clampf(canopy + 0.002 * recovery_mult * (1.0 - orive * 0.4), 0.05, 1.0)
	if canopy > 0.65:
		orive = clampf(orive - 0.003 * recovery_mult, 0.05, 1.0)
	else:
		orive = clampf(orive + 0.004 * (0.65 - canopy), 0.05, 1.0)
	var runoff_silt := clampf((1.0 - canopy) * 0.75 + orive * 0.15, 0.05, 1.0)
	slope["torava_canopy"] = _round4(canopy)
	slope["orive_shrub"] = _round4(orive)
	slope["runoff_silt"] = _round4(runoff_silt)


static func _step_channel_and_wetland(
	world: WorldState,
	slope: Dictionary,
	channel: Dictionary,
	wetland: Dictionary,
	recovery_mult: float,
	yield_mult: float
) -> void:
	var dams := float(channel.get("navelu_dams_integrity", 0.28))
	var navelu := float(channel.get("navelu_population", 0.24))
	var selave := float(channel.get("selave_coverage", 0.42))
	var kevalu_wild := float(channel.get("kevalu_wild_biomass", 0.0))
	var quarantine := bool(channel.get("kevalu_quarantine_active", false))

	if bool(channel.get("navelu_refugium_alive", true)):
		var target_navelu := clampf(0.15 + dams * 0.75, 0.05, 1.0)
		navelu = move_toward(navelu, target_navelu, 0.015 * recovery_mult)
		dams = clampf(dams + (navelu - 0.22) * 0.02 * recovery_mult, 0.05, 1.0)
	if kevalu_wild > 0.0:
		kevalu_wild = clampf(kevalu_wild + 0.025 * (1.0 - dams * 0.3), 0.0, 1.0)
		selave = clampf(selave - kevalu_wild * 0.03, 0.05, 1.0)
	else:
		var selave_target := clampf(0.25 + dams * 0.65, 0.10, 1.0)
		selave = move_toward(selave, selave_target, 0.02 * recovery_mult)

	if quarantine:
		channel["kevalu_quarantine_knowledge"] = _round4(
			clampf(float(channel.get("kevalu_quarantine_knowledge", 0.0)) + 0.05, 0.0, 1.0)
		)

	var tivane_sync := clampf(selave * (1.0 - kevalu_wild * 0.65), 0.05, 1.0)
	var talune_yield := clampf((0.20 + tivane_sync * 0.75) * minf(yield_mult, 2.0), 0.05, 2.0)
	var runoff_silt := float(slope.get("runoff_silt", 0.32))
	var filtration := clampf(dams * 0.45 + selave * 0.45 + kevalu_wild * 0.25, 0.05, 0.95)
	var silt_load := clampf(runoff_silt * (1.15 - filtration), 0.05, 1.0)
	var clarity := clampf(1.0 - silt_load * 0.85, 0.05, 1.0)

	var juveniles := float(wetland.get("murela_juveniles", 0.38))
	var adults := float(wetland.get("murela_adults", 0.46))
	var juv_target := clampf(clarity * 0.55 + selave * 0.45 - kevalu_wild * 0.20, 0.05, 1.0)
	juveniles = move_toward(juveniles, juv_target, 0.025 * recovery_mult)
	adults = move_toward(adults, clampf(juveniles * 0.92, 0.05, 1.0), 0.018 * recovery_mult)

	var prev_kevalu := float(channel.get("kevalu_wild_biomass", 0.0))
	if prev_kevalu < 0.25 and kevalu_wild >= 0.25:
		world.fact_log().append_fact(
			"eco_kevalu_spread",
			world.clock().total_minutes(),
			{"kevalu_wild_biomass": _round4(kevalu_wild), "selave_coverage": _round4(selave)},
			-1,
			"core:species/kevalu"
		)

	channel["navelu_population"] = _round4(navelu)
	channel["navelu_dams_integrity"] = _round4(dams)
	channel["selave_coverage"] = _round4(selave)
	channel["kevalu_wild_biomass"] = _round4(kevalu_wild)
	channel["tivane_sync"] = _round4(tivane_sync)
	channel["talune_yield_index"] = _round4(talune_yield)

	wetland["silt_load"] = _round4(silt_load)
	wetland["water_clarity"] = _round4(clarity)
	wetland["murela_juveniles"] = _round4(juveniles)
	wetland["murela_adults"] = _round4(adults)


static func _step_meadow(meadow: Dictionary, recovery_mult: float) -> void:
	var forage := float(meadow.get("meadow_forage", 0.64))
	var heruna := float(meadow.get("heruna_population", 0.52))
	var karune := float(meadow.get("karune_pressure", 0.34))
	var forage_delta := (0.018 * recovery_mult) - (heruna * 0.022)
	forage = clampf(forage + forage_delta, 0.10, 1.0)
	var heruna_target := clampf(forage * 0.85 - karune * 0.35, 0.10, 0.95)
	heruna = move_toward(heruna, heruna_target, 0.015 * recovery_mult)
	karune = move_toward(karune, clampf(heruna * 0.62, 0.10, 0.85), 0.01 * recovery_mult)
	meadow["meadow_forage"] = _round4(forage)
	meadow["heruna_population"] = _round4(heruna)
	meadow["karune_pressure"] = _round4(karune)


static func _default_node_components(seed_value: int) -> Dictionary:
	var seed_offset := float(absi(seed_value % 7)) * 0.01
	return {
		NODE_TORAMEK_SLOPE:
		{
			"node_id": NODE_TORAMEK_SLOPE,
			"torava_canopy": _round4(0.70 + seed_offset),
			"orive_shrub": _round4(0.24),
			"runoff_silt": _round4(0.30),
		},
		NODE_NIVAREL_CHANNEL:
		{
			"node_id": NODE_NIVAREL_CHANNEL,
			"navelu_refugium_alive": true,
			"navelu_population": _round4(0.24 + seed_offset),
			"navelu_dams_integrity": _round4(0.28),
			"selave_coverage": _round4(0.42),
			"tivane_sync": _round4(0.42),
			"talune_yield_index": _round4(0.52),
			"kevalu_quarantine_active": false,
			"kevalu_quarantine_samples": 0,
			"kevalu_quarantine_knowledge": 0.0,
			"kevalu_wild_biomass": 0.0,
		},
		NODE_MULANE_WETLAND:
		{
			"node_id": NODE_MULANE_WETLAND,
			"silt_load": _round4(0.48),
			"water_clarity": _round4(0.58),
			"murela_juveniles": _round4(0.38),
			"murela_adults": _round4(0.46),
		},
		NODE_HERAVO_MEADOW:
		{
			"node_id": NODE_HERAVO_MEADOW,
			"meadow_forage": _round4(0.64),
			"heruna_population": _round4(0.52),
			"karune_pressure": _round4(0.34),
		},
	}


static func _round4(value: float) -> float:
	return roundf(value * 10000.0) / 10000.0

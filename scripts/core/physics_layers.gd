class_name PhysicsLayers
extends RefCounted
## Named 2D physics layers for TDL.
##
## Project code should use these constants instead of magic layer numbers.
## Human-readable names live in `project.godot` under `[layer_names]` and
## are verified by the core foundation tests.

const TERRAIN := 1
const BODIES := 2
const STRUCTURES := 3
const ITEMS := 4
const INTERACTABLES := 5
const HAZARDS := 6
const SENSORS := 7
const PROJECTILES := 8

const TERRAIN_BIT := 1
const BODIES_BIT := 2
const STRUCTURES_BIT := 4
const ITEMS_BIT := 8
const INTERACTABLES_BIT := 16
const HAZARDS_BIT := 32
const SENSORS_BIT := 64
const PROJECTILES_BIT := 128


static func bit(layer: int) -> int:
	if layer < 1 or layer > 32:
		push_warning("PhysicsLayers.bit: layer must be within 1..32, got %d" % layer)
		return 0
	return 1 << (layer - 1)


static func layer_name(layer: int) -> String:
	return String(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % layer, ""))

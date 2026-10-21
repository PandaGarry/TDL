class_name UiLocaleCatalog
extends RefCounted
## Built-in RU/EN translation catalog for P0 UI and core definition keys.
##
## Architecture rule: user-facing UI and content `name_key` values use
## stable dot-separated localization keys from day one instead of
## hardcoded language strings scattered across scenes.

const SUPPORTED_LOCALES := ["ru", "en"]

const MESSAGES_RU := {
	"actor.anchor_npc.name": "Якорный житель долины Севары",
	"actor.greybox_body.name": "Тело участника (greybox)",
	"object.greybox_supply_crate.name": "Ящик припасов (greybox)",
	"object.eco_basin_node.name": "Экологический узел бассейна Севары",
	"material.kevalu_propagule.name": "Росток кевалу (карантинный образец)",
	"material.murela_catch.name": "Улов мурелы",
	"material.reed_fiber.name": "Тростниковое волокно",
	"material.selave_bundle.name": "Пучок селаве",
	"material.talune_grain.name": "Зерно талуне",
	"material.torava_wood.name": "Древесина торавы",
	"species.heruna.name": "Херуна",
	"species.karune.name": "Каруне",
	"species.kevalu.name": "Кевалу",
	"species.murela.name": "Мурела",
	"species.navelu.name": "Навелу",
	"species.orive.name": "Ориве",
	"species.selave.name": "Селаве",
	"species.talune.name": "Талуне",
	"species.tivane.name": "Тиване",
	"species.torava.name": "Торава",
	"ui.main_menu.title": "TDL",
	"ui.main_menu.subtitle": "Долина Севары — P0 Core & Greybox Prototype (Godot 4.7)",
	"ui.main_menu.new_game": "Новая кампания (Greybox)",
	"ui.main_menu.continue": "Продолжить кампанию",
	"ui.main_menu.settings": "Настройки",
	"ui.main_menu.quit": "Выход",
	"ui.main_menu.status_no_save": "Сохранение кампании не найдено или повреждено.",
	"ui.main_menu.status_settings_info":
	"Настройки звука (Master/Music/SFX/Ambience) и экрана хранит SettingsManager.",
	"ui.greybox.header_title": "P0-F Greybox — Активный чанк",
	"ui.greybox.controls_hint":
	"WASD / Стрелки: шаг (1 клетка) | E: взять припас | F3: Debug Overlay | Сохранить / В меню",
	"ui.greybox.save_button": "Сохранить слот",
	"ui.greybox.step_time_button": "+1 мин",
	"ui.greybox.menu_button": "В главное меню",
	"ui.greybox.interact_prompt": "[E] Взять 1",
	"ui.greybox.crate_empty": "Пусто",
}

const MESSAGES_EN := {
	"actor.anchor_npc.name": "Sevara Valley Anchor Resident",
	"actor.greybox_body.name": "Participant Body (Greybox)",
	"object.greybox_supply_crate.name": "Supply Crate (Greybox)",
	"object.eco_basin_node.name": "Sevara Basin Ecological Node",
	"material.kevalu_propagule.name": "Kevalu Propagule (Quarantine Sample)",
	"material.murela_catch.name": "Murela Catch",
	"material.reed_fiber.name": "Reed Fiber",
	"material.selave_bundle.name": "Selave Bundle",
	"material.talune_grain.name": "Talune Grain",
	"material.torava_wood.name": "Torava Wood",
	"species.heruna.name": "Heruna",
	"species.karune.name": "Karune",
	"species.kevalu.name": "Kevalu",
	"species.murela.name": "Murela",
	"species.navelu.name": "Navelu",
	"species.orive.name": "Orive",
	"species.selave.name": "Selave",
	"species.talune.name": "Talune",
	"species.tivane.name": "Tivane",
	"species.torava.name": "Torava",
	"ui.main_menu.title": "TDL",
	"ui.main_menu.subtitle": "Sevara Valley — P0 Core & Greybox Prototype (Godot 4.7)",
	"ui.main_menu.new_game": "New Campaign (Greybox)",
	"ui.main_menu.continue": "Continue Campaign",
	"ui.main_menu.settings": "Settings",
	"ui.main_menu.quit": "Quit",
	"ui.main_menu.status_no_save": "Campaign save was not found or could not be loaded.",
	"ui.main_menu.status_settings_info":
	"Audio (Master/Music/SFX/Ambience) and display settings are managed by SettingsManager.",
	"ui.greybox.header_title": "P0-F Greybox — Active Chunk",
	"ui.greybox.controls_hint":
	"WASD / Arrows: step (1 tile) | E: take supply | F3: Debug Overlay | Save / Main Menu",
	"ui.greybox.save_button": "Save Slot",
	"ui.greybox.step_time_button": "+1 min",
	"ui.greybox.menu_button": "Main Menu",
	"ui.greybox.interact_prompt": "[E] Take 1",
	"ui.greybox.crate_empty": "Empty",
}

static var _registered := false


static func ensure_registered() -> void:
	if _registered:
		return
	_register_locale_messages("ru", MESSAGES_RU)
	_register_locale_messages("en", MESSAGES_EN)
	_registered = true


static func has_key(key: String, locale: String = "ru") -> bool:
	var table := _table_for_locale(locale)
	return table.has(key)


static func translate_key(key: String, locale: String = "") -> String:
	ensure_registered()
	var resolved_locale := locale.strip_edges().to_lower()
	if resolved_locale.is_empty():
		resolved_locale = TranslationServer.get_locale().substr(0, 2).to_lower()
	var table := _table_for_locale(resolved_locale)
	if table.has(key):
		return String(table[key])
	if MESSAGES_RU.has(key):
		return String(MESSAGES_RU[key])
	if MESSAGES_EN.has(key):
		return String(MESSAGES_EN[key])
	return key


static func validate_registry_keys(active_registry: DefinitionRegistry) -> Array[String]:
	var errors: Array[String] = []
	if active_registry == null:
		errors.append("registry is null")
		return errors
	for definition_id in active_registry.definition_ids():
		var definition := active_registry.get_definition(definition_id)
		var name_key := String(definition.get("name_key", ""))
		for locale in SUPPORTED_LOCALES:
			if not has_key(name_key, locale):
				errors.append(
					(
						"definition '%s' is missing '%s' translation for key '%s'"
						% [definition_id, locale, name_key]
					)
				)
	return errors


static func _register_locale_messages(locale: String, messages: Dictionary) -> void:
	var translation := Translation.new()
	translation.locale = locale
	for raw_key in messages.keys():
		var key := String(raw_key)
		var value := String(messages[raw_key])
		translation.add_message(StringName(key), StringName(value))
	TranslationServer.add_translation(translation)


static func _table_for_locale(locale: String) -> Dictionary:
	if locale.begins_with("en"):
		return MESSAGES_EN
	if locale.begins_with("ru"):
		return MESSAGES_RU
	return {}

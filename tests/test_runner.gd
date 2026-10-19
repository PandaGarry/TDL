extends Node
## Headless-тесты каркаса. Запуск:
## godot --headless --path . res://tests/test_runner.tscn

const TEST_SAVE_PATH := "user://saltvigil_test_save.json"
const GameScreenScript = preload("res://src/game/game_screen.gd")
const MainMenuScript = preload("res://src/ui/main_menu.gd")

var failures := 0
var checks := 0


func _ready() -> void:
	print("Saltvigil · каркас · тесты")
	# Тесты не должны трогать сохранение игрока.
	SaveSystem.save_path = TEST_SAVE_PATH
	SaveSystem.delete_save()

	_test_database()
	_test_data_integrity()
	_test_new_game()
	_test_memory_burn()
	_test_memory_keep_and_read()
	_test_feed_and_build()
	_test_miracle()
	_test_laws()
	_test_dawn_floor()
	_test_events()
	_test_event_conditions()
	_test_night_cycle()
	_test_save_and_resume()
	_test_game_over()
	_test_demo_completion()
	_test_save_laws()
	_test_hollow()
	_test_action_guards()
	_test_corrupt_save_fallback()
	await _test_ui_smoke()

	SaveSystem.delete_save()
	SaveSystem.save_path = "user://saltvigil_save.json"
	print("Проверок: %d · провалов: %d" % [checks, failures])
	if failures == 0:
		print("ALL TESTS PASSED")
	get_tree().quit(0 if failures == 0 else 1)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  ok   " + message)
	else:
		failures += 1
		printerr("  FAIL " + message)


func _test_database() -> void:
	print("\n[Database]")
	expect(Database.loaded, "все JSON загружены")
	expect(Database.buildings.size() >= 4, "есть минимум 4 здания")
	expect(Database.followers.size() == 3, "три стартовых последователя")
	expect(Database.memories.size() >= 9, "минимум 9 воспоминаний")
	expect(Database.journal.size() >= 8, "минимум 8 страниц журнала")


func _test_data_integrity() -> void:
	print("\n[Data integrity]")
	var ok := true
	for follower in Database.followers:
		for memory_id in follower.get("memories", []):
			var memory := Database.get_memory(str(memory_id))
			if memory.is_empty():
				ok = false
				printerr("  нет памяти " + str(memory_id))
			elif str(memory.get("owner", "")) != str(follower.get("id", "")):
				ok = false
				printerr("  владелец памяти не совпадает: " + str(memory_id))
	expect(ok, "все памяти существуют и принадлежат своим последователям")


func _test_new_game() -> void:
	print("\n[New game]")
	GameState.new_game()
	expect(GameState.followers.size() == 3, "созданы три последователя")
	expect(is_equal_approx(GameState.light, 45.0), "стартовый свет 45")
	expect(GameState.journal_pages == 8, "восемь страниц журнала")
	expect(float(GameState.resources.get("wood", 0.0)) == 8.0, "восемь дерева")
	expect(GameState.watch == 0 and GameState.day == 1, "первая ночь, нулевая вахта")


func _test_memory_burn() -> void:
	print("\n[Memory burn]")
	GameState.new_game()
	var mira = GameState.find_follower("mira")
	var before := GameState.light
	var hope_before: float = mira.hope
	var burned := GameState.burn_memory("mira", "mira_mother")
	expect(burned, "память сожжена")
	expect(GameState.light > before, "свет вырос")
	expect(is_equal_approx(mira.hope, hope_before - 3.0), "культ теряет 3 надежды")
	expect(not mira.has_memory("mira_mother"), "память исчезла у Миры")
	expect(int(GameState.flags.get("burned", 0)) == 1, "счётчик сожжённых равен 1")
	expect(float(GameState.resources.get("ash", 0.0)) >= 1.0, "появился пепел")


func _test_memory_keep_and_read() -> void:
	print("\n[Memory keep and read]")
	GameState.new_game()
	GameState.resources["wax"] = 10.0
	var mira = GameState.find_follower("mira")
	var hope_before: float = mira.hope
	var kept := GameState.keep_memory("mira", "mira_name")
	expect(kept, "память сохранена")
	expect(mira.preserved.has("mira_name"), "память лежит в Хранилище")
	expect(is_equal_approx(float(GameState.resources.get("wax", 0.0)), 8.0), "списано два воска")
	expect(mira.hope > hope_before, "надежда выросла")

	var read := GameState.read_memory("mira", "mira_salt")
	expect(read, "память прочитана")
	expect(mira.was_read("mira_salt"), "отметка о прочтении стоит")
	expect(not GameState.read_memory("mira", "mira_salt"), "повторно прочитать нельзя")


func _test_feed_and_build() -> void:
	print("\n[Feed and build]")
	GameState.new_game()
	GameState.resources["wood"] = 5.0
	GameState.light = 40.0
	expect(GameState.feed_wood(), "дрова сожжены")
	expect(is_equal_approx(float(GameState.resources.get("wood", 0.0)), 4.0), "дерево уменьшилось")
	expect(is_equal_approx(GameState.light, 43.0), "свет вырос на 3")
	expect(not GameState.feed_wood(), "второе подношение в ту же вахту запрещено")
	expect(not GameState.can_feed(), "кнопка дерева гаснет до следующей вахты")
	GameState.start()
	GameState.advance_watch()
	expect(GameState.can_feed(), "в новой вахте подношение снова доступно")

	GameState.resources["wood"] = 30.0
	GameState.resources["salt"] = 30.0
	GameState.resources["wax"] = 30.0
	var result := GameState.build("greenhouse", 0)
	expect(bool(result.get("ok", false)), "теплица построена")
	expect(GameState.used_slots() == 1, "занят один слот")
	var duplicate := GameState.build("workshop", 0)
	expect(not bool(duplicate.get("ok", true)), "нельзя построить в занятый слот")
	expect(GameState.has_free_slot(), "свободные слоты ещё есть")


func _test_miracle() -> void:
	print("\n[Miracle]")
	GameState.new_game()
	GameState.start()
	GameState.light = 10.0
	var pages_before := GameState.journal_pages
	expect(GameState.miracle(), "чудо совершено")
	expect(GameState.journal_pages == pages_before - 1, "страница сожжена")
	expect(is_equal_approx(GameState.light, 40.0), "свет вырос на 30")
	expect(GameState.lost_entries.size() == 1, "одна страница потеряна навсегда")


func _test_laws() -> void:
	print("\n[Laws]")
	GameState.new_game()
	GameState.start()
	expect(not GameState.should_choose_law(), "в начале ночи закон не выбирается")
	expect(not GameState.choose_law("ash_law"), "до рассвета закон принять нельзя")

	GameState.light = 100.0
	for _step in 6:
		GameState.advance_watch()
	expect(GameState.should_choose_law(), "на рассвете первого дня доступен закон")
	expect(GameState.choose_law("ash_law"), "Закон Пепла принят")
	expect(GameState.laws == ["ash_law"], "закон записан в состояние")
	expect(is_equal_approx(GameState.burn_light_for({"burn_light": 20.0}), 25.0), "Пепел даёт +25% света")
	expect(is_equal_approx(GameState.keep_memory_cost(), 3.0), "Пепел делает сохранение дороже")
	expect(not GameState.should_choose_law(), "второй закон в первый рассвет недоступен")
	expect(not GameState.choose_law("silence_law"), "второй закон не принимается")

	GameState.start_next_night()
	GameState.light = 100.0
	for _step in 6:
		GameState.advance_watch()
	expect(GameState.should_choose_law(), "на втором рассвете доступен второй закон")
	expect(GameState.choose_law("silence_law"), "Закон Тишины принят")
	expect(GameState.laws.size() == 2, "два закона в силе")
	expect(GameState.miracle_cost() == 2, "Тишина удорожает чудо")
	expect(not GameState.choose_law("keeper_law"), "третий закон не принимается")


func _test_dawn_floor() -> void:
	print("\n[Dawn floor]")
	GameState.new_game()
	GameState.start()
	GameState.light = 100.0
	for _step in 6:
		GameState.advance_watch()
	GameState.light = 3.0
	GameState.start_next_night()
	expect(GameState.light >= 20.0, "рассвет поднимает свет до минимума")
	expect(GameState.day == 2, "наступает вторая ночь")


func _test_events() -> void:
	print("\n[Events]")
	GameState.new_game()
	GameState.day = 2
	GameState.start()
	GameState.light = 90.0
	GameState.resources["food"] = 4.0
	GameState.advance_watch()
	expect(str(GameState.pending_event.get("id", "")) == "empty_kitchen", "голодная ночь вызывает событие")
	expect(not GameState.resolve_event("unknown"), "неизвестный вариант отклонён")
	var krylo_before: float = GameState.find_follower("krylo").hope
	var food_before := float(GameState.resources.get("food", 0.0))
	expect(GameState.resolve_event("workers"), "вариант события применён")
	expect(is_equal_approx(float(GameState.resources.get("food", 0.0)), maxf(0.0, food_before - 3.0)), "еда списана по эффекту")
	expect(is_equal_approx(float(GameState.find_follower("krylo").hope), krylo_before - 6.0), "надежда Крыла упала")
	expect(bool(GameState.flags.get("event_empty_kitchen", false)), "событие отмечено в флагах")
	expect(GameState.pending_event.is_empty(), "событие закрыто")


func _test_event_conditions() -> void:
	print("\n[Event conditions]")
	GameState.new_game()
	GameState.day = 2
	GameState.start()
	GameState.light = 90.0
	GameState.resources["food"] = 40.0
	GameState.advance_watch()
	expect(GameState.pending_event.is_empty(), "условие события не выполнено — тишина")
	GameState.advance_watch()
	GameState.advance_watch()
	expect(str(GameState.pending_event.get("id", "")) == "iskra_rail", "событие с Искрой сработало")
	var iskra_before: float = GameState.find_follower("iskra").hope
	expect(GameState.resolve_event("chalk"), "вариант с мелом принят")
	expect(bool(GameState.flags.get("chalk_taken", false)), "флаг выбора записан")
	expect(is_equal_approx(float(GameState.find_follower("iskra").hope), iskra_before - 5.0), "надежда Искры упала")


func _test_save_laws() -> void:
	print("\n[Save laws]")
	# Законы переживают сохранение и не дублируются при загрузке.
	GameState.new_game()
	GameState.laws = ["ash_law", "silence_law"]
	GameState.flags["event_empty_kitchen"] = true
	expect(SaveSystem.save_game(), "состояние с законами сохранено")
	GameState.new_game()
	expect(SaveSystem.load_game(), "состояние с законами загружено")
	expect(GameState.laws.size() == 2, "оба закона восстановлены")
	expect(bool(GameState.flags.get("event_empty_kitchen", false)), "флаг события восстановлен")


func _test_night_cycle() -> void:
	print("\n[Night cycle]")
	GameState.new_game()
	GameState.start()
	GameState.light = 100.0
	for _step in 6:
		GameState.advance_watch()
	expect(GameState.watch == 6, "прошло шесть вахт")
	expect(not GameState.running, "ночь закончилась")
	expect(not GameState.demo_over, "демо ещё не закончено")
	expect(not GameState.is_game_over, "игра не проиграна")


func _test_save_and_resume() -> void:
	print("\n[Save and resume]")
	SaveSystem.save_game()
	var saved_day := GameState.day
	var saved_light := GameState.light
	expect(SaveSystem.has_save(), "файл сохранения создан")
	GameState.new_game()
	expect(is_equal_approx(GameState.light, 45.0), "новая игра сбрасывает свет")
	expect(SaveSystem.load_game(), "сохранение загружено")
	expect(GameState.day == saved_day, "день восстановлен")
	expect(is_equal_approx(GameState.light, saved_light), "свет восстановлен")
	GameState.start()
	expect(GameState.day == saved_day, "рассвет не проглатывается при загрузке")
	expect(GameState.should_choose_law(), "на рассвете ждёт выбор закона")
	expect(GameState.choose_law("keeper_law"), "закон принят после загрузки")
	GameState.start_next_night()
	expect(GameState.day == saved_day + 1, "после рассвета загружается следующая ночь")
	expect(GameState.running, "игра продолжается")


func _test_game_over() -> void:
	print("\n[Game over]")
	GameState.new_game()
	GameState.start()
	GameState.light = 1.0
	GameState.advance_watch()
	expect(GameState.is_game_over, "свет на нуле завершает игру")
	expect(not GameState.ending_reason.is_empty(), "причина поражения записана")
	expect(not GameState.running, "таймер остановлен")


func _test_demo_completion() -> void:
	print("\n[Demo completion]")
	GameState.new_game()
	GameState.day = 3
	GameState.start()
	GameState.light = 100.0
	for _step in 6:
		GameState.advance_watch()
	expect(GameState.demo_over, "третья ночь завершает демо")
	expect(not GameState.running, "после демо игра не идёт")
	expect(not GameState.can_act(), "после демо действия заблокированы")


func _test_hollow() -> void:
	print("\n[Hollow]")
	GameState.new_game()
	var mira = GameState.find_follower("mira")
	GameState.burn_memory("mira", "mira_mother")
	GameState.burn_memory("mira", "mira_name")
	GameState.burn_memory("mira", "mira_salt")
	expect(mira.hollow, "Мира стала Полом после третьей памяти")
	expect(int(GameState.flags.get("hollows", 0)) == 1, "счётчик Полов равен 1")
	expect(GameState.get_active_followers().size() == 2, "в культе осталось два человека")
	expect(not GameState.is_game_over, "игра продолжается, пока есть кому помнить")


func _test_action_guards() -> void:
	print("\n[Action guards]")
	GameState.new_game()
	GameState.start()
	expect(GameState.can_act(), "в живой партии действия доступны")
	GameState.light = 1.0
	GameState.advance_watch()
	expect(GameState.is_game_over, "партия завершена")
	expect(not GameState.can_act(), "после поражения действия заблокированы")
	expect(not GameState.feed_wood(), "нельзя кормить Уголёк после поражения")
	expect(not GameState.burn_memory("mira", "mira_mother"), "нельзя сжигать память после поражения")
	expect(not GameState.read_memory("mira", "mira_salt"), "нельзя читать память после поражения")
	expect(not bool(GameState.build("greenhouse", 0).get("ok", true)), "нельзя строить после поражения")
	expect(not SaveSystem.save_game(), "мёртвое состояние не сохраняется")


func _test_ui_smoke() -> void:
	print("\n[UI smoke]")
	# Скрипты экранов компилируются и собираются в headless-режиме.
	# Это ловит ошибки типов, которые не видны gdlint.
	GameState.new_game()
	GameState.start()
	var screen := GameScreenScript.new()
	add_child(screen)
	var menu := MainMenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	expect(screen.get_child_count() > 0, "игровой экран собирается")
	expect(menu.get_child_count() > 0, "главное меню собирается")
	screen.queue_free()
	menu.queue_free()


func _test_corrupt_save_fallback() -> void:
	print("\n[Corrupt save fallback]")
	GameState.new_game()
	GameState.start()
	GameState.day = 2
	GameState.light = 77.0
	expect(SaveSystem.save_game(), "первое сохранение записано")
	expect(SaveSystem.save_game(), "второе сохранение создало резервную копию")

	var file := FileAccess.open(SaveSystem.save_path, FileAccess.WRITE)
	expect(file != null, "файл сохранения открыт для порчи")
	if file != null:
		file.store_string("{ broken json")
		file.close()

	GameState.new_game()
	expect(SaveSystem.load_game(), "повреждённый файл заменён резервной копией")
	expect(GameState.day == 2, "день восстановлен из копии")
	expect(is_equal_approx(GameState.light, 77.0), "свет восстановлен из копии")

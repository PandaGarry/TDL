extends Node
## Глобальная шина событий. UI, сохранения и звук не зависят друг от друга напрямую.

signal light_changed(value: float, maximum: float)
signal faith_changed(value: float)
signal resources_changed(resources: Dictionary)
signal day_changed(day: int, watch: int, total_watches: int, phase_title: String)
signal followers_changed
signal follower_changed(follower_id: String)
signal log_added(text_value: String)
signal toast_requested(text_value: String)
signal journal_changed(pages: int, lost: int)
signal buildings_changed
signal running_changed(is_running: bool)
signal pause_changed(is_paused: bool)
signal night_ended(summary: Dictionary)
signal demo_completed(summary: Dictionary)
signal game_over(reason: String)
signal memory_action(follower_id: String, memory_id: String, action: String)
signal laws_changed
signal event_triggered(event: Dictionary)
signal event_resolved(event_id: String, choice_id: String)

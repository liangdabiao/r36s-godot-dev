extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/Game.tscn").instance()
	root.add_child(scene)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	scene.hud.show_title(scene.best_score)
	print("TITLE_STATE ", scene.get_state_name(), " overlay=", scene.hud.overlay.visible, " title_panel=", scene.hud.title_panel.visible)
	yield(scene.get_tree().create_timer(0.3), "timeout")
	yield(_capture("title"), "completed")
	scene.start_game()
	yield(scene.get_tree().create_timer(1.6), "timeout")
	if scene.enemies.size() > 0:
		scene.enemies[0].spawn_timer = 0.0
		scene.enemies[0].global_position = scene.player.global_position + Vector2(70, 10)
	if scene.enemies.size() > 1:
		scene.enemies[1].spawn_timer = 0.0
		scene.enemies[1].global_position = scene.player.global_position + Vector2(-85, -25)
	yield(_capture("combat"), "completed")
	scene.spawn_queue = 0
	for index in range(6):
		scene.debug_kill_all_enemies()
		yield(scene.get_tree().create_timer(0.2), "timeout")
	yield(scene.get_tree().create_timer(1.0), "timeout")
	print("UPGRADE_STATE ", scene.get_state_name(), " overlay=", scene.hud.overlay.visible, " upgrade_panel=", scene.hud.upgrade_panel.visible)
	yield(_capture("upgrade"), "completed")
	scene.state = scene.State.PLAYING
	scene.wave = 4
	scene._begin_wave()
	scene.hud.hide_overlay()
	scene.spawn_queue = 0
	scene._spawn_enemy()
	yield(scene.get_tree().create_timer(0.5), "timeout")
	yield(_capture("boss"), "completed")
	scene.debug_kill_all_enemies()
	yield(scene.get_tree().create_timer(0.3), "timeout")
	scene._win_game()
	yield(scene.get_tree().create_timer(0.3), "timeout")
	print("WIN_STATE ", scene.get_state_name(), " end_panel=", scene.hud.end_panel.visible)
	yield(_capture("victory"), "completed")
	print("CAPTURE_DONE")
	quit(0)

func _capture(name: String) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var image: Image = root.get_texture().get_data()
	image.flip_y()
	var err := image.save_png("res://docs/images/game_" + name + ".png")
	print("CAPTURED ", name, " err=", err, " size=", image.get_size())
extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/Game.tscn").instance()
	root.add_child(scene)
	yield(self, "idle_frame")
	check(scene.get_state_name() == "TITLE", "game starts on title screen")
	check(scene.is_walkable_cell(scene.MAZE_ORIGIN), "player starts on a road cell")
	_check_maze_connectivity(scene)
	scene.start_game()
	check(scene.get_state_name() == "PLAYING", "start enters playing state")
	check(scene.wave == 1, "first wave is wave one")
	check(scene.player.alive and scene.player.hp == scene.player.max_hp, "player starts alive at full health")
	var move_start: Vector2 = scene.player.global_position
	var move_key := InputEventKey.new()
	move_key.physical_scancode = KEY_D
	move_key.pressed = true
	Input.parse_input_event(move_key)
	yield(scene.get_tree().create_timer(0.25), "timeout")
	check(scene.player.global_position.distance_to(move_start) > 10.0, "physical keyboard input moves the player")
	yield(scene.get_tree().create_timer(0.8), "timeout")
	check(scene.player.global_position.x <= 32.1, "player stops at a maze wall")
	check(scene.is_walkable_cell(scene.world_to_cell(scene.player.global_position)), "player remains on a road cell")
	move_key.pressed = false
	Input.parse_input_event(move_key)
	yield(scene.get_tree().create_timer(0.1), "timeout")
	yield(scene.get_tree().create_timer(1.3), "timeout")
	check(scene.living_enemy_count() > 0, "wave spawns enemies")
	var valid_spawns := true
	for spawned in scene.enemies:
		if not scene.is_walkable_cell(scene.world_to_cell(spawned.global_position)):
			valid_spawns = false
	check(valid_spawns, "enemies spawn on road cells")
	scene.spawn_queue = 0
	var enemy = scene.enemies[0]
	var enemy_start: Vector2 = enemy.global_position
	var enemy_start_steps: int = _path_distance(scene, scene.world_to_cell(enemy_start), scene.world_to_cell(scene.player.global_position))
	yield(scene.get_tree().create_timer(1.2), "timeout")
	check(enemy.global_position.distance_to(enemy_start) > 1.0, "enemies navigate toward the player")
	var enemy_steps: int = _path_distance(scene, scene.world_to_cell(enemy.global_position), scene.world_to_cell(scene.player.global_position))
	check(enemy_steps < enemy_start_steps - 2, "enemies make progress around maze walls")
	check(scene.is_walkable_cell(scene.world_to_cell(enemy.global_position)), "enemies stay on maze roads")
	var attack_direction := Vector2.UP
	var attack_cell: Vector2 = scene.world_to_cell(scene.player.global_position)
	for offset in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		if scene.is_walkable_cell(attack_cell + offset):
			attack_direction = offset
			attack_cell += offset
			break
	enemy.global_position = scene.cell_to_world(attack_cell)
	enemy.spawn_timer = 0.0
	var old_hp: float = enemy.hp
	scene._on_player_attack(scene.player.global_position + attack_direction * 8.0, attack_direction, 12.0)
	check(enemy.hp < old_hp, "frontal sword attack damages an enemy")
	scene.debug_damage_player(9.0)
	check(scene.player.hp < scene.player.max_hp, "player takes damage")
	scene.player._start_dash(Vector2.RIGHT)
	check(scene.player.dash_cooldown_timer > 0.0, "dash starts cooldown")
	scene.player._start_special()
	check(scene.player.special_cooldown_timer > 0.0, "spring burst starts cooldown")
	scene.debug_kill_all_enemies()
	yield(scene.get_tree().create_timer(1.1), "timeout")
	check(scene.get_state_name() == "UPGRADE", "clearing a wave opens upgrades")
	check(scene.upgrade_choices.size() == 3, "three upgrades are offered")
	var old_damage: float = scene.player.damage
	scene._select_upgrade("damage")
	check(scene.player.damage > old_damage, "selected upgrade changes player stats")
	check(scene.wave == 2 and scene.get_state_name() == "PLAYING", "upgrade starts the next wave")
	scene._toggle_pause()
	check(scene.get_state_name() == "PAUSED" and scene.get_tree().paused, "pause stops the scene tree")
	scene._resume_game()
	check(scene.get_state_name() == "PLAYING" and not scene.get_tree().paused, "resume restores play")
	for clear_index in range(3):
		scene.spawn_queue = 0
		scene.debug_kill_all_enemies()
		yield(scene.get_tree().create_timer(1.1), "timeout")
		check(scene.get_state_name() == "UPGRADE", "wave clear %d opens upgrades" % (clear_index + 1))
		scene._select_upgrade(scene.upgrade_choices[0]["id"])
	check(scene.wave == 5 and scene.get_state_name() == "PLAYING", "final wave is reached")
	scene.spawn_queue = 0
	scene.pending_boss = true
	scene._spawn_enemy()
	check(is_instance_valid(scene.boss) and scene.boss.kind == "boss", "final wave spawns the boss")
	yield(scene.get_tree().create_timer(0.4), "timeout")
	scene.boss.take_damage(scene.boss.max_hp * 0.5 + 1.0, Vector2.DOWN)
	check(scene.boss.enraged, "boss enrages below half health")
	yield(scene.get_tree().create_timer(0.4), "timeout")
	scene.debug_kill_all_enemies()
	yield(scene.get_tree().create_timer(1.1), "timeout")
	check(scene.get_state_name() == "WIN", "defeating the boss wins the run")
	check(scene.score > 0 and scene.kills > 0, "score and kills are recorded")
	check(scene.best_score > 0, "best score is saved")
	print("GAME_REGRESSION_FAILURES=", failures)
	quit(failures)

func _check_maze_connectivity(scene) -> void:
	var start: Vector2 = scene.walkable_cells[0]
	var seen := {start: true}
	var queue := [start]
	var front := 0
	while front < queue.size():
		var current: Vector2 = queue[front]
		front += 1
		for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var next: Vector2 = current + offset
			if scene.is_walkable_cell(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	check(seen.size() == scene.walkable_cells.size(), "all maze roads are connected")
	var coordinates_match := true
	for cell in scene.walkable_cells:
		if scene.world_to_cell(scene.cell_to_world(cell)) != cell:
			coordinates_match = false
	check(coordinates_match, "maze cells align with world coordinates")

func _path_distance(scene, start: Vector2, goal: Vector2) -> int:
	if start == goal:
		return 0
	var distances := {start: 0}
	var queue := [start]
	var front := 0
	while front < queue.size():
		var current: Vector2 = queue[front]
		front += 1
		for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var next: Vector2 = current + offset
			if scene.is_walkable_cell(next) and not distances.has(next):
				var next_distance: int = distances[current] + 1
				distances[next] = next_distance
				if next == goal:
					return next_distance
				queue.append(next)
	return 999

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error("FAIL " + message)

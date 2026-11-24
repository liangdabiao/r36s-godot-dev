extends Node2D

const EnemyScript = preload("res://game/Enemy.gd")
const PickupScript = preload("res://game/Pickup.gd")
const EffectsScript = preload("res://game/EffectsLayer.gd")
const HudScript = preload("res://game/HUD.gd")

enum State { TITLE, PLAYING, UPGRADE, PAUSED, WIN, LOSE }

const WAVE_COUNTS := [5, 8, 11, 14, 5]
const WAVE_NAMES := ["SLIMES IN THE GRASS", "QUICK WINGS", "HEAVY FOOTSTEPS", "THE LAST DEFENSE", "MOSS KING"]
const MAX_ENEMIES := 16
const COMBO_DURATION := 3.2
const SAVE_PATH := "user://spring_guard.cfg"

var state: int = State.TITLE
var wave := 0
var score := 0
var kills := 0
var combo := 0
var combo_timer := 0.0
var run_time := 0.0
var best_score := 0
var spawn_queue := 0
var spawn_timer := 0.0
var wave_clear_timer := 0.0
var pending_boss := false
var shake_strength := 0.0
var enemies := []
var upgrade_choices := []
var boss

onready var player = $Player
onready var camera: Camera2D = $Player/Camera2D

var entities: Node2D
var effects
var hud
var audio_players := []
var sounds := {}
var audio_index := 0
var arena_bounds := Rect2(-232, -168, 464, 336)
var pond_cells := {}

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_build_arena()
	entities = Node2D.new()
	entities.name = "Entities"
	add_child(entities)
	effects = EffectsScript.new()
	add_child(effects)
	hud = HudScript.new()
	hud.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(hud)
	_build_audio()
	_connect_signals()
	_load_best_score()
	player.set_control_enabled(false)
	player.reset_stats()
	player.set_control_enabled(false)
	hud.show_title(best_score)
	hud.set_stats(player.hp, player.max_hp, 1, 0, 0, 0, 0.0, 0.0, 0.0, 0.0)
	hud.set_boss("", -1.0)

func _build_arena() -> void:
	var water_texture: Texture = load("res://map/tileset/Water.png")
	var grass_texture: Texture = load("res://map/tileset/Grass.png")
	water_texture.flags = 0
	grass_texture.flags = 0
	var water_set := _make_tileset(water_texture, {17: Rect2(0, 0, 16, 16)}, true)
	var grass_set := _make_tileset(grass_texture, {
		1: Rect2(0, 0, 16, 16),
		2: Rect2(32, 0, 16, 16),
		3: Rect2(0, 16, 16, 16),
		4: Rect2(0, 16, 16, 16),
		5: Rect2(16, 16, 16, 16),
		6: Rect2(32, 16, 16, 16),
		7: Rect2(0, 32, 16, 16),
		8: Rect2(16, 32, 16, 16),
		9: Rect2(32, 32, 16, 16),
		10: Rect2(16, 0, 16, 16),
		11: Rect2(0, 80, 16, 16),
		12: Rect2(48, 80, 16, 16),
		13: Rect2(64, 80, 16, 16),
		14: Rect2(80, 80, 16, 16),
		15: Rect2(64, 96, 16, 16),
		16: Rect2(80, 96, 16, 16)
	}, false)
	var water := TileMap.new()
	water.name = "Water"
	water.tile_set = water_set
	water.cell_size = Vector2(16, 16)
	water.z_index = -2
	add_child(water)
	for x in range(-18, 18):
		for y in range(-14, 14):
			water.set_cell(x, y, 17)
	_mark_pond_cells()
	var grass := TileMap.new()
	grass.name = "Grass"
	grass.tile_set = grass_set
	grass.cell_size = Vector2(16, 16)
	grass.z_index = -1
	add_child(grass)
	var random := RandomNumberGenerator.new()
	random.seed = 3605
	for x in range(-15, 15):
		for y in range(-11, 11):
			if pond_cells.has(Vector2(x, y)):
				continue
			var tile := 10
			var roll := random.randi_range(1, 10)
			if roll <= 2:
				tile = [1, 2, 3, 5, 6, 7, 8, 9][random.randi_range(0, 7)]
			grass.set_cell(x, y, tile)
			if pond_cells.has(Vector2(x, y)):
				water.set_cell(x, y, 17)
	var decor := TileMap.new()
	decor.name = "Decor"
	decor.tile_set = grass_set
	decor.cell_size = Vector2(16, 16)
	decor.z_index = 0
	add_child(decor)
	for x in range(-14, 15):
		for y in range(-10, 11):
			if pond_cells.has(Vector2(x, y)) or abs(x) < 2 and abs(y) < 2:
				continue
			if random.randi_range(1, 100) <= 5:
				decor.set_cell(x, y, random.randi_range(11, 16))
	if is_instance_valid(camera):
		camera.limit_left = -256
		camera.limit_top = -192
		camera.limit_right = 256
		camera.limit_bottom = 192

func _make_tileset(texture: Texture, regions: Dictionary, collision: bool) -> TileSet:
	var tiles := TileSet.new()
	for id in regions.keys():
		tiles.create_tile(id)
		tiles.tile_set_name(id, str(id))
		tiles.tile_set_texture(id, texture)
		tiles.tile_set_region(id, regions[id])
		if collision:
			var shape := RectangleShape2D.new()
			shape.extents = Vector2(8, 8)
			tiles.tile_set_shapes(id, [shape])
	return tiles

func _mark_pond_cells() -> void:
	for x in range(5, 8):
		for y in range(-6, -3):
			pond_cells[Vector2(x, y)] = true
	for x in range(-7, -4):
		for y in range(4, 7):
			pond_cells[Vector2(x, y)] = true

func _build_audio() -> void:
	for sound_name in ["swing", "hit", "hurt", "dash", "pickup", "special", "wave", "win", "lose"]:
		sounds[sound_name] = load("res://assets/audio/" + sound_name + ".wav")
	for index in range(8):
		var audio := AudioStreamPlayer.new()
		add_child(audio)
		audio_players.append(audio)

func _play_sound(name: String) -> void:
	if not sounds.has(name) or audio_players.empty():
		return
	var audio: AudioStreamPlayer = audio_players[audio_index]
	audio_index = (audio_index + 1) % audio_players.size()
	audio.stream = sounds[name]
	audio.play()

func _connect_signals() -> void:
	player.connect("hp_changed", self, "_on_player_hp_changed")
	player.connect("died", self, "_on_player_died")
	player.connect("attack_started", self, "_on_player_attack_started")
	player.connect("attack_hit", self, "_on_player_attack")
	player.connect("dash_started", self, "_on_player_dash")
	player.connect("special_started", self, "_on_player_special")
	hud.connect("start_requested", self, "start_game")
	hud.connect("upgrade_selected", self, "_select_upgrade")
	hud.connect("resume_requested", self, "_resume_game")
	hud.connect("restart_requested", self, "start_game")

func _process(delta: float) -> void:
	_update_shake(delta)
	if state != State.PLAYING:
		return
	run_time += delta
	combo_timer = max(0.0, combo_timer - delta)
	if combo_timer <= 0.0:
		combo = 0
	if spawn_queue > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and living_enemy_count() < MAX_ENEMIES:
			_spawn_enemy()
			spawn_queue -= 1
			spawn_timer = 0.62 if wave < 5 else 0.85
	if spawn_queue == 0 and living_enemy_count() == 0:
		wave_clear_timer += delta
		if wave_clear_timer >= 0.75:
			wave_clear_timer = 0.0
			_complete_wave()
	else:
		wave_clear_timer = 0.0
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		return
	match state:
		State.TITLE:
			if event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
				start_game()
		State.UPGRADE:
			if event.is_action_pressed("ui_left"):
				hud.move_upgrade_selection(-1)
			elif event.is_action_pressed("ui_right"):
				hud.move_upgrade_selection(1)
			elif event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
				hud.confirm_upgrade()
			elif event is InputEventKey and event.pressed and not event.echo:
				if event.scancode >= KEY_1 and event.scancode <= KEY_3:
					hud.set_upgrade_selection(event.scancode - KEY_1)
					hud.confirm_upgrade()
		State.PAUSED:
			if event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
				_resume_game()
			elif event.is_action_pressed("dash"):
				start_game()
		State.WIN, State.LOSE:
			if event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
				start_game()

func start_game() -> void:
	get_tree().paused = false
	_clear_entities()
	effects.clear()
	score = 0
	kills = 0
	combo = 0
	combo_timer = 0.0
	run_time = 0.0
	wave = 0
	spawn_queue = 0
	spawn_timer = 0.0
	wave_clear_timer = 0.0
	pending_boss = false
	boss = null
	player.reset_stats()
	player.position = Vector2.ZERO
	player.invuln_timer = 1.2
	player.set_control_enabled(true)
	camera.offset = Vector2.ZERO
	hud.hide_overlay()
	hud.set_boss("", -1.0)
	state = State.PLAYING
	_begin_wave()

func _begin_wave() -> void:
	wave += 1
	spawn_queue = WAVE_COUNTS[wave - 1]
	spawn_timer = 0.9
	wave_clear_timer = 0.0
	pending_boss = wave == 5
	hud.show_message("WAVE %d / 5\n%s" % [wave, WAVE_NAMES[wave - 1]], 2.2)
	_play_sound("wave")
	if wave == 5:
		hud.set_boss("MOSS KING", 1.0)

func _spawn_enemy() -> void:
	var enemy_kind := "slime"
	if pending_boss:
		enemy_kind = "boss"
		pending_boss = false
	elif wave >= 3 and randf() < 0.22:
		enemy_kind = "brute"
	elif wave >= 2 and randf() < 0.42:
		enemy_kind = "bat"
	var enemy = EnemyScript.new()
	enemy.position = _spawn_position()
	enemy.setup(enemy_kind, wave, player)
	enemy.connect("died", self, "_on_enemy_died")
	enemy.connect("damaged", self, "_on_enemy_damaged")
	enemy.connect("boss_enraged", self, "_on_boss_enraged")
	entities.add_child(enemy)
	enemies.append(enemy)
	if enemy_kind == "boss":
		boss = enemy
		hud.set_boss("MOSS KING", 1.0)
		hud.show_message("MOSS KING AWAKENS", 1.6)

func _spawn_position() -> Vector2:
	var position := Vector2.ZERO
	for attempt in range(12):
		var side := randi() % 4
		match side:
			0:
				position = Vector2(rand_range(-218, 218), -154)
			1:
				position = Vector2(rand_range(-218, 218), 154)
			2:
				position = Vector2(-218, rand_range(-150, 150))
			_:
				position = Vector2(218, rand_range(-150, 150))
		if position.distance_to(player.global_position) > 135:
			break
	return position

func _on_player_attack_started(_direction: Vector2) -> void:
	_play_sound("swing")

func _on_player_attack(hit_position: Vector2, direction: Vector2, damage: float) -> void:
	effects.spawn_slash(player.global_position, direction)
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var offset: Vector2 = enemy.global_position - hit_position
		if offset.length() <= player.attack_range + enemy.radius and offset.normalized().dot(direction) > 0.18:
			enemy.take_damage(damage, direction)

func _on_player_dash(direction: Vector2) -> void:
	effects.spawn_ring(player.global_position, Color(0.36, 0.86, 1.0, 0.75), 34)
	_play_sound("dash")

func _on_player_special(direction: Vector2, damage: float) -> void:
	effects.spawn_ring(player.global_position, Color(1.0, 0.78, 0.28, 0.9), 112)
	effects.spawn_ring(player.global_position, Color(0.28, 0.88, 0.92, 0.75), 82)
	_play_sound("special")
	shake_strength = max(shake_strength, 6.0)
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var offset: Vector2 = enemy.global_position - player.global_position
		if offset.length() <= 112.0 + enemy.radius:
			enemy.take_damage(damage, offset.normalized())

func _on_enemy_damaged(enemy, amount: float, position: Vector2) -> void:
	effects.spawn_hit(position)
	effects.spawn_text(position, str(int(amount)), Color(1.0, 0.93, 0.62))
	_play_sound("hit")
	shake_strength = max(shake_strength, 1.8 if enemy.kind != "boss" else 2.8)

func _on_enemy_died(enemy) -> void:
	enemies.erase(enemy)
	kills += 1
	combo = min(5, combo + 1) if combo_timer > 0.0 else 1
	combo_timer = COMBO_DURATION
	score += enemy.score_value * combo
	effects.spawn_hit(enemy.global_position, Color(0.95, 0.72, 0.30))
	effects.spawn_text(enemy.global_position + Vector2(0, -14), "+" + str(enemy.score_value * combo), GOLD)
	_spawn_pickup(enemy.global_position, "gem", 12 * combo)
	if randf() < 0.18 or enemy.kind == "brute":
		_spawn_pickup(enemy.global_position + Vector2(12, 0), "heart", 18)
	if enemy.kind == "boss":
		score += 500
		_spawn_pickup(enemy.global_position + Vector2(-14, 0), "heart", 30)
		_spawn_pickup(enemy.global_position + Vector2(0, 14), "heart", 30)
		boss = null
		hud.set_boss("", -1.0)
		shake_strength = 9.0
	if player.life_steal > 0.0:
		player.heal(player.life_steal)

func _on_boss_enraged(enemy) -> void:
	hud.show_message("MOSS KING IS ENRAGED", 1.5)
	effects.spawn_ring(enemy.global_position, Color(1.0, 0.22, 0.16, 0.9), 70)
	shake_strength = 7.0
	for index in range(2):
		var minion = EnemyScript.new()
		minion.position = enemy.global_position + Vector2(35 + index * 18, 0)
		minion.setup("bat", wave, player)
		minion.connect("died", self, "_on_enemy_died")
		minion.connect("damaged", self, "_on_enemy_damaged")
		entities.add_child(minion)
		enemies.append(minion)

func _spawn_pickup(position: Vector2, kind: String, value: int) -> void:
	var pickup = PickupScript.new()
	pickup.position = position
	pickup.setup(kind, value, player)
	pickup.connect("collected", self, "_on_pickup_collected")
	entities.add_child(pickup)

func _on_pickup_collected(pickup) -> void:
	if pickup.kind == "heart":
		player.heal(pickup.value)
		effects.spawn_text(pickup.global_position, "+" + str(pickup.value) + " HP", Color(0.45, 1.0, 0.62))
	else:
		score += pickup.value
		combo_timer = COMBO_DURATION
		effects.spawn_text(pickup.global_position, "+" + str(pickup.value), CYAN)
	_play_sound("pickup")

func _complete_wave() -> void:
	if wave >= 5:
		_win_game()
		return
	state = State.UPGRADE
	player.set_control_enabled(false)
	player.heal(10.0)
	upgrade_choices = _generate_upgrades()
	hud.show_upgrades(upgrade_choices)
	_play_sound("wave")

func _generate_upgrades() -> Array:
	var pool := [
		{"id": "damage", "title": "KEEN EDGE", "description": "+7 sword damage"},
		{"id": "attack_speed", "title": "QUICK HANDS", "description": "14% faster attacks"},
		{"id": "move_speed", "title": "LIGHT STEP", "description": "+13 movement speed"},
		{"id": "max_hp", "title": "STRONG HEART", "description": "+22 max HP and heal 30"},
		{"id": "dash", "title": "WIND STEP", "description": "18% shorter dash cooldown"},
		{"id": "special", "title": "SPRING POWER", "description": "20% shorter burst cooldown, +10 damage"},
		{"id": "armor", "title": "BARK ARMOR", "description": "Take 2 less damage per hit"},
		{"id": "leech", "title": "LIFE DEW", "description": "Heal 1.5 HP for every kill"}
	]
	pool.shuffle()
	return [pool[0], pool[1], pool[2]]

func _select_upgrade(id: String) -> void:
	if state != State.UPGRADE:
		return
	player.apply_upgrade(id)
	hud.hide_overlay()
	hud.show_message("UPGRADE ACQUIRED", 1.2)
	state = State.PLAYING
	player.set_control_enabled(true)
	_begin_wave()

func _on_player_hp_changed(_current: float, _maximum: float) -> void:
	pass

func _on_player_died() -> void:
	if state != State.PLAYING:
		return
	state = State.LOSE
	player.set_control_enabled(false)
	_play_sound("lose")
	_save_best_score()
	yield(get_tree().create_timer(0.85), "timeout")
	hud.show_end(false, score, kills, wave, run_time, best_score)

func _win_game() -> void:
	state = State.WIN
	player.set_control_enabled(false)
	score += 1000
	_play_sound("win")
	_save_best_score()
	hud.show_end(true, score, kills, wave, run_time, best_score)

func _toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		get_tree().paused = true
		hud.show_pause()
	elif state == State.PAUSED:
		_resume_game()

func _resume_game() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	state = State.PLAYING
	hud.hide_overlay()

func _update_hud() -> void:
	hud.set_stats(
		player.hp,
		player.max_hp,
		wave,
		score,
		kills,
		combo,
		combo_timer / COMBO_DURATION,
		player.get_dash_remaining(),
		player.get_special_remaining(),
		run_time
	)
	if is_instance_valid(boss) and boss.alive:
		hud.set_boss("MOSS KING" + (" - ENRAGED" if boss.enraged else ""), boss.get_hp_ratio())
	elif not is_instance_valid(boss):
		hud.set_boss("", -1.0)

func _update_shake(delta: float) -> void:
	if shake_strength > 0.0:
		camera.offset = Vector2(rand_range(-shake_strength, shake_strength), rand_range(-shake_strength, shake_strength))
		shake_strength = max(0.0, shake_strength - delta * 18.0)
	else:
		camera.offset = Vector2.ZERO

func living_enemy_count() -> int:
	var count := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive:
			count += 1
	return count

func _clear_entities() -> void:
	for child in entities.get_children():
		entities.remove_child(child)
		child.free()
	enemies.clear()
	boss = null

func _load_best_score() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		best_score = int(config.get_value("records", "best_score", 0))

func _save_best_score() -> void:
	if score <= best_score:
		return
	best_score = score
	var config := ConfigFile.new()
	config.set_value("records", "best_score", best_score)
	config.save(SAVE_PATH)

func debug_kill_all_enemies() -> void:
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive:
			enemy.take_damage(100000.0, Vector2.DOWN)

func debug_damage_player(amount: float) -> void:
	player.invuln_timer = 0.0
	player.take_damage(amount, player.global_position + Vector2(0, 20))

func get_state_name() -> String:
	return ["TITLE", "PLAYING", "UPGRADE", "PAUSED", "WIN", "LOSE"][state]

const GOLD := Color(1.0, 0.78, 0.32)
const CYAN := Color(0.28, 0.88, 0.92)

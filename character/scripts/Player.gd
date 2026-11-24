extends KinematicBody2D

signal hp_changed(current, maximum)
signal died
signal attack_started(direction)
signal attack_hit(position, direction, damage)
signal dash_started(direction)
signal special_started(direction, damage)

const FRAME_SIZE := 48.0
const BASE_MOVE_SPEED := 108.0
const BASE_MAX_HP := 100.0
const BASE_DAMAGE := 24.0
const BASE_ATTACK_INTERVAL := 0.38
const BASE_DASH_COOLDOWN := 1.15
const BASE_SPECIAL_COOLDOWN := 6.0

var move_speed := BASE_MOVE_SPEED
var max_hp := BASE_MAX_HP
var hp := BASE_MAX_HP
var damage := BASE_DAMAGE
var attack_interval := BASE_ATTACK_INTERVAL
var attack_range := 50.0
var dash_cooldown := BASE_DASH_COOLDOWN
var dash_speed := 340.0
var dash_duration := 0.16
var special_cooldown := BASE_SPECIAL_COOLDOWN
var special_damage := 46.0
var armor := 0.0
var life_steal := 0.0

var velocity := Vector2.ZERO
var facing := Vector2.DOWN
var last_direction := "down"
var alive := true
var control_enabled := true
var attacking := false
var attack_pending := false
var attack_delay := 0.0
var attack_cooldown_timer := 0.0
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var special_cooldown_timer := 0.0
var invuln_timer := 0.0
var dash_direction := Vector2.DOWN
var knockback_velocity := Vector2.ZERO
var upgrades := {}

onready var anim_sprite: AnimatedSprite = $AnimatedSprite

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	z_index = 5
	_build_animations()
	anim_sprite.connect("animation_finished", self, "_on_animation_finished")
	reset_stats()
	update()

func _build_animations() -> void:
	var definitions := [
		["res://assets/sprites/player_idle.png", "idle", 8, 9.0, true],
		["res://assets/sprites/player_run.png", "run", 4, 12.0, true],
		["res://assets/sprites/player_attack.png", "attack", 6, 16.0, false],
		["res://assets/sprites/player_hurt.png", "hurt", 2, 10.0, false],
		["res://assets/sprites/player_die.png", "die", 6, 8.0, false]
	]
	var frames := SpriteFrames.new()
	for definition in definitions:
		var texture: Texture = load(definition[0])
		texture.flags = 0
		var prefix: String = definition[1]
		var count: int = definition[2]
		var animation_speed: float = definition[3]
		var looping: bool = definition[4]
		for direction_index in range(3):
			var direction: String = ["down", "left", "up"][direction_index]
			var name := prefix + "_" + direction
			var textures := []
			for frame_index in range(count):
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2((direction_index * count + frame_index) * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
				textures.append(atlas)
			frames.add_animation(name)
			frames.set_animation_speed(name, animation_speed)
			frames.set_animation_loop(name, looping)
			for frame_index in range(textures.size()):
				frames.add_frame(name, textures[frame_index], frame_index)
	anim_sprite.frames = frames
	anim_sprite.animation = "idle_down"

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not alive:
		velocity = Vector2.ZERO
		move_and_slide(velocity)
		return
	if not control_enabled:
		velocity = Vector2.ZERO
		move_and_slide(velocity)
		_idle_animation()
		return

	var input_direction := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_direction.length() > 0.1:
		input_direction = input_direction.normalized()
		facing = input_direction
		last_direction = _direction_name(input_direction)

	if attack_pending:
		attack_delay -= delta
		if attack_delay <= 0.0:
			attack_pending = false
			emit_signal("attack_hit", global_position + facing * 18.0, facing, damage)

	if Input.is_action_just_pressed("attack") and attack_cooldown_timer <= 0.0 and not attacking:
		_start_attack(input_direction)
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0:
		_start_dash(input_direction)
	if Input.is_action_just_pressed("special") and special_cooldown_timer <= 0.0:
		_start_special()

	if dash_timer > 0.0:
		velocity = dash_direction * dash_speed * max(0.35, dash_timer / dash_duration)
	else:
		velocity = input_direction * move_speed
	velocity += knockback_velocity
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, delta * 420.0)
	move_and_slide(velocity)
	_update_animation(input_direction)
	_update_hit_flash()

func _tick_timers(delta: float) -> void:
	attack_cooldown_timer = max(0.0, attack_cooldown_timer - delta)
	dash_timer = max(0.0, dash_timer - delta)
	dash_cooldown_timer = max(0.0, dash_cooldown_timer - delta)
	special_cooldown_timer = max(0.0, special_cooldown_timer - delta)
	invuln_timer = max(0.0, invuln_timer - delta)

func _start_attack(input_direction: Vector2) -> void:
	if input_direction.length() > 0.1:
		facing = input_direction
	attacking = true
	attack_pending = true
	attack_delay = 0.07
	attack_cooldown_timer = attack_interval
	_play_directional("attack")
	emit_signal("attack_started", facing)

func _start_dash(input_direction: Vector2) -> void:
	dash_direction = input_direction if input_direction.length() > 0.1 else facing
	facing = dash_direction
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	invuln_timer = max(invuln_timer, dash_duration + 0.10)
	attacking = false
	attack_pending = false
	emit_signal("dash_started", dash_direction)
	update()

func _start_special() -> void:
	var input_direction := _current_input_direction()
	if input_direction.length() > 0.1:
		facing = input_direction
	special_cooldown_timer = special_cooldown
	attacking = true
	attack_pending = false
	_play_directional("attack")
	emit_signal("special_started", facing, special_damage)

func _current_input_direction() -> Vector2:
	var direction := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	return direction.normalized() if direction.length() > 0.1 else facing

func take_damage(amount: float, source_position: Vector2 = Vector2.ZERO) -> bool:
	if not alive or invuln_timer > 0.0 or dash_timer > 0.0:
		return false
	var actual := max(1.0, amount - armor)
	hp = max(0.0, hp - actual)
	invuln_timer = 0.72
	if source_position != Vector2.ZERO:
		knockback_velocity = (global_position - source_position).normalized() * 150.0
	emit_signal("hp_changed", hp, max_hp)
	if hp <= 0.0:
		_die()
	else:
		attacking = false
		attack_pending = false
		_play_directional("hurt")
	return true

func heal(amount: float) -> void:
	if not alive:
		return
	hp = min(max_hp, hp + amount)
	emit_signal("hp_changed", hp, max_hp)

func _die() -> void:
	alive = false
	control_enabled = false
	attacking = false
	attack_pending = false
	velocity = Vector2.ZERO
	_play_directional("die")
	emit_signal("died")

func reset_stats() -> void:
	move_speed = BASE_MOVE_SPEED
	max_hp = BASE_MAX_HP
	hp = BASE_MAX_HP
	damage = BASE_DAMAGE
	attack_interval = BASE_ATTACK_INTERVAL
	attack_range = 50.0
	dash_cooldown = BASE_DASH_COOLDOWN
	dash_speed = 340.0
	dash_duration = 0.16
	special_cooldown = BASE_SPECIAL_COOLDOWN
	special_damage = 46.0
	armor = 0.0
	life_steal = 0.0
	upgrades.clear()
	alive = true
	control_enabled = true
	attacking = false
	attack_pending = false
	attack_cooldown_timer = 0.0
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	special_cooldown_timer = 0.0
	invuln_timer = 0.0
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	facing = Vector2.DOWN
	last_direction = "down"
	position = Vector2.ZERO
	anim_sprite.modulate = Color.white
	anim_sprite.flip_h = false
	_idle_animation()
	emit_signal("hp_changed", hp, max_hp)

func apply_upgrade(id: String) -> void:
	upgrades[id] = int(upgrades.get(id, 0)) + 1
	match id:
		"damage":
			damage += 7.0
		"attack_speed":
			attack_interval = max(0.18, attack_interval * 0.86)
		"move_speed":
			move_speed += 13.0
		"max_hp":
			max_hp += 22.0
			hp = min(max_hp, hp + 30.0)
		"dash":
			dash_cooldown = max(0.45, dash_cooldown * 0.82)
			dash_duration += 0.015
		"special":
			special_cooldown = max(2.4, special_cooldown * 0.80)
			special_damage += 10.0
		"armor":
			armor += 2.0
		"leech":
			life_steal += 1.5
	emit_signal("hp_changed", hp, max_hp)

func get_dash_remaining() -> float:
	return dash_cooldown_timer

func get_special_remaining() -> float:
	return special_cooldown_timer

func get_dash_ratio() -> float:
	return 1.0 if dash_cooldown_timer <= 0.0 else dash_cooldown_timer / dash_cooldown

func get_special_ratio() -> float:
	return 1.0 if special_cooldown_timer <= 0.0 else special_cooldown_timer / special_cooldown

func get_upgrade_count() -> int:
	var total := 0
	for value in upgrades.values():
		total += int(value)
	return total

func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO

func _update_animation(input_direction: Vector2) -> void:
	if not alive:
		return
	if attacking:
		return
	if input_direction.length() > 0.1:
		_play_directional("run")
	else:
		_idle_animation()

func _idle_animation() -> void:
	if alive and not attacking:
		_play_directional("idle")

func _play_directional(prefix: String) -> void:
	if not alive and prefix != "die":
		return
	var animation := prefix + "_" + last_direction
	anim_sprite.flip_h = last_direction == "left" and facing.x > 0.0
	anim_sprite.play(animation)

func _on_animation_finished() -> void:
	if not alive:
		return
	if attacking:
		attacking = false
		_idle_animation()

func _update_hit_flash() -> void:
	if invuln_timer > 0.0 and dash_timer <= 0.0:
		anim_sprite.modulate.a = 0.45 if int(invuln_timer * 18.0) % 2 == 0 else 1.0
	else:
		anim_sprite.modulate.a = 1.0
	update()

func _direction_name(direction: Vector2) -> String:
	if abs(direction.x) > abs(direction.y):
		return "left"
	return "down" if direction.y > 0.0 else "up"

func _draw() -> void:
	draw_ellipse(Vector2(0, 9), Vector2(10, 4), Color(0.05, 0.08, 0.06, 0.28))
	if dash_timer > 0.0:
		draw_arc(Vector2.ZERO, 15, 0, TAU, 20, Color(0.45, 0.9, 1.0, 0.65), 2.0)

func draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PoolVector2Array()
	for index in range(17):
		var angle := TAU * index / 16.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)

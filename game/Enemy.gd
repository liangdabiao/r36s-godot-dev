extends KinematicBody2D

signal died(enemy)
signal damaged(enemy, amount, position)
signal boss_enraged(enemy)

var kind := "slime"
var wave := 1
var max_hp := 30.0
var hp := 30.0
var speed := 50.0
var damage := 8.0
var score_value := 80
var radius := 11.0
var body_color := Color(0.25, 0.75, 0.38)
var alive := true
var enraged := false
var spawn_timer := 0.35
var flash_timer := 0.0
var death_timer := 0.0
var contact_cooldown := 0.0
var ability_timer := 1.5
var state := "chase"
var state_timer := 0.0
var charge_direction := Vector2.DOWN
var knockback_velocity := Vector2.ZERO
var velocity := Vector2.ZERO
var path_target := Vector2.ZERO
var path_timer := 0.0
var player
var arena

func _ready() -> void:
	if arena == null:
		arena = get_parent().get_parent()
	collision_layer = 2
	collision_mask = 1
	z_index = 4
	path_target = global_position
	add_to_group("enemies")
	var shape := CircleShape2D.new()
	shape.radius = min(radius, 7.0)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2.ZERO
	add_child(collision)
	update()

func setup(enemy_kind: String, wave_value: int, target: Node2D) -> void:
	kind = enemy_kind
	wave = wave_value
	player = target
	arena = target.get_parent()
	match kind:
		"slime":
			max_hp = 26.0 + wave * 4.0
			speed = 48.0 + wave * 2.0
			damage = 7.0 + wave
			score_value = 80 + wave * 10
			radius = 11.0
			body_color = Color(0.24, 0.76, 0.36)
		"bat":
			max_hp = 20.0 + wave * 3.0
			speed = 72.0 + wave * 3.0
			damage = 6.0 + wave
			score_value = 100 + wave * 12
			radius = 9.0
			body_color = Color(0.60, 0.38, 0.82)
		"brute":
			max_hp = 52.0 + wave * 6.0
			speed = 36.0 + wave * 1.5
			damage = 12.0 + wave
			score_value = 160 + wave * 18
			radius = 15.0
			body_color = Color(0.92, 0.48, 0.20)
		"boss":
			max_hp = 460.0
			speed = 42.0
			damage = 18.0
			score_value = 1800
			radius = 25.0
			body_color = Color(0.82, 0.16, 0.20)
	hp = max_hp
	ability_timer = 2.2 if kind == "boss" else 1.2

func _physics_process(delta: float) -> void:
	flash_timer = max(0.0, flash_timer - delta)
	contact_cooldown = max(0.0, contact_cooldown - delta)
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, delta * 360.0)
	if not alive:
		death_timer -= delta
		scale = Vector2.ONE * max(0.0, death_timer / 0.24)
		if death_timer <= 0.0:
			queue_free()
		return
	if spawn_timer > 0.0:
		spawn_timer -= delta
		scale = Vector2.ONE * (0.25 + 0.75 * (1.0 - spawn_timer / 0.35))
		velocity = Vector2.ZERO
		return
	scale = Vector2.ONE
	if not is_instance_valid(player) or not player.alive:
		velocity = Vector2.ZERO
		return

	var to_player: Vector2 = player.global_position - global_position
	var distance := to_player.length()
	path_timer -= delta
	if path_timer <= 0.0 or global_position.distance_to(path_target) < 1.5:
		path_target = arena.call("get_path_target", global_position, player.global_position)
		path_timer = 0.18
	var to_path_target: Vector2 = path_target - global_position
	var direction: Vector2 = to_path_target.normalized() if to_path_target.length() > 1.0 else to_player.normalized()
	velocity = knockback_velocity
	match kind:
		"bat":
			_chase(direction, delta)
		"brute":
			_charge_behavior(direction, delta, 145.0, 0.65, 0.40, 245.0, 2.4)
		"boss":
			_boss_behavior(direction, delta)
		_:
			_chase(direction, delta)
	if distance < radius + 13.0 and contact_cooldown <= 0.0 and state != "windup":
		if player.take_damage(damage, global_position):
			contact_cooldown = 0.85
	move_and_slide(velocity)
	update()

func _chase(direction: Vector2, _delta: float) -> void:
	velocity = direction * speed + knockback_velocity

func _charge_behavior(direction: Vector2, delta: float, trigger_distance: float, windup: float, charge_time: float, charge_speed: float, cooldown: float) -> void:
	ability_timer = max(0.0, ability_timer - delta)
	match state:
		"chase":
			velocity = direction * speed + knockback_velocity
			if distance_to_player() < trigger_distance and ability_timer <= 0.0:
				state = "windup"
				state_timer = windup
				charge_direction = direction
				velocity = Vector2.ZERO
		"windup":
			state_timer -= delta
			charge_direction = charge_direction.move_toward(direction, delta * 1.8).normalized()
			velocity = Vector2.ZERO
			if state_timer <= 0.0:
				state = "charge"
				state_timer = charge_time
		"charge":
			state_timer -= delta
			velocity = charge_direction * charge_speed
			if state_timer <= 0.0:
				state = "recover"
				state_timer = 0.55
		"recover":
			state_timer -= delta
			velocity = knockback_velocity
			if state_timer <= 0.0:
				state = "chase"
				ability_timer = cooldown

func _boss_behavior(direction: Vector2, delta: float) -> void:
	ability_timer = max(0.0, ability_timer - delta)
	var speed_scale := 1.22 if enraged else 1.0
	match state:
		"chase":
			velocity = direction * speed * speed_scale + knockback_velocity
			if ability_timer <= 0.0:
				state = "windup"
				state_timer = 0.82 if not enraged else 0.62
				charge_direction = direction
				velocity = Vector2.ZERO
		"windup":
			state_timer -= delta
			charge_direction = charge_direction.move_toward(direction, delta * 1.25).normalized()
			velocity = Vector2.ZERO
			if state_timer <= 0.0:
				state = "charge"
				state_timer = 0.58 if not enraged else 0.72
		"charge":
			state_timer -= delta
			velocity = charge_direction * (330.0 if not enraged else 390.0)
			if state_timer <= 0.0:
				state = "recover"
				state_timer = 0.72
		"recover":
			state_timer -= delta
			velocity = knockback_velocity
			if state_timer <= 0.0:
				state = "chase"
				ability_timer = 2.2 if not enraged else 1.45

func distance_to_player() -> float:
	return global_position.distance_to(player.global_position) if is_instance_valid(player) else INF

func take_damage(amount: float, hit_direction: Vector2 = Vector2.DOWN) -> bool:
	if not alive or spawn_timer > 0.0:
		return false
	hp = max(0.0, hp - amount)
	flash_timer = 0.12
	knockback_velocity = hit_direction * (95.0 if kind != "boss" else 35.0)
	emit_signal("damaged", self, amount, global_position)
	if kind == "boss" and not enraged and hp > 0.0 and hp <= max_hp * 0.5:
		enraged = true
		damage += 3.0
		speed *= 1.12
		emit_signal("boss_enraged", self)
	if hp <= 0.0:
		_die()
	return true

func _die() -> void:
	alive = false
	death_timer = 0.24
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	emit_signal("died", self)

func get_hp_ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0

func _draw() -> void:
	var tint := Color.white if flash_timer > 0.0 else body_color
	_draw_shadow()
	match kind:
		"slime":
			draw_circle(Vector2(0, 1), radius, Color(tint.r, tint.g, tint.b, 0.96))
			draw_circle(Vector2(-3, -3), 3.0, Color(1, 1, 1, 0.28))
			_draw_eyes(Vector2(0, 0), 4.0)
		"bat":
			var wing := PoolVector2Array([Vector2(-7, -2), Vector2(-18, -8), Vector2(-15, 4), Vector2(-7, 5)])
			draw_colored_polygon(wing, tint.darkened(0.12))
			wing = PoolVector2Array([Vector2(7, -2), Vector2(18, -8), Vector2(15, 4), Vector2(7, 5)])
			draw_colored_polygon(wing, tint.darkened(0.12))
			draw_circle(Vector2(0, 1), 9.0, tint)
			_draw_eyes(Vector2(0, 0), 3.5)
		"brute":
			draw_circle(Vector2(0, 2), radius, tint)
			draw_colored_polygon(PoolVector2Array([Vector2(-11, -8), Vector2(-16, -19), Vector2(-4, -11)]), tint.lightened(0.18))
			draw_colored_polygon(PoolVector2Array([Vector2(11, -8), Vector2(16, -19), Vector2(4, -11)]), tint.lightened(0.18))
			_draw_eyes(Vector2(0, -1), 4.0)
			draw_line(Vector2(-6, 8), Vector2(6, 8), tint.darkened(0.35), 2.0)
		"boss":
			draw_circle(Vector2(0, 2), radius + 3.0, tint.darkened(0.22))
			draw_circle(Vector2(0, 0), radius, tint)
			for spike_index in range(8):
				var angle := TAU * spike_index / 8.0
				var outer := Vector2(cos(angle), sin(angle)) * (radius + 10.0)
				var side := Vector2(cos(angle + 0.18), sin(angle + 0.18)) * (radius + 2.0)
				draw_colored_polygon(PoolVector2Array([Vector2(cos(angle), sin(angle)) * (radius - 2), outer, side]), tint.lightened(0.12))
			_draw_eyes(Vector2(0, -2), 6.0)
			draw_arc(Vector2(0, 0), 10.0, 0.2, PI - 0.2, 12, Color(1.0, 0.82, 0.25), 2.0)
	if state == "windup":
		var telegraph := Color(1.0, 0.25, 0.18, 0.35 + 0.45 * abs(sin(state_timer * 18.0)))
		draw_arc(Vector2.ZERO, radius + 9.0, 0, TAU, 32, telegraph, 3.0)
		draw_line(Vector2.ZERO, charge_direction * (radius + 24.0), telegraph, 2.0)
	if hp < max_hp and kind != "boss" and alive:
		var width := radius * 2.0
		draw_rect(Rect2(-width / 2.0, -radius - 10.0, width, 3.0), Color(0.08, 0.08, 0.10, 0.85))
		draw_rect(Rect2(-width / 2.0, -radius - 10.0, width * get_hp_ratio(), 3.0), Color(0.95, 0.32, 0.28))

func _draw_eyes(center: Vector2, spacing: float) -> void:
	draw_circle(center + Vector2(-spacing, 0), 2.2, Color(0.98, 0.97, 0.86))
	draw_circle(center + Vector2(spacing, 0), 2.2, Color(0.98, 0.97, 0.86))
	draw_circle(center + Vector2(-spacing + 0.4, 0), 1.1, Color(0.05, 0.06, 0.08))
	draw_circle(center + Vector2(spacing + 0.4, 0), 1.1, Color(0.05, 0.06, 0.08))

func _draw_shadow() -> void:
	var points := PoolVector2Array()
	for index in range(17):
		var angle := TAU * index / 16.0
		points.append(Vector2(0, radius * 0.65) + Vector2(cos(angle) * radius, sin(angle) * radius * 0.36))
	draw_colored_polygon(points, Color(0.04, 0.06, 0.05, 0.25))

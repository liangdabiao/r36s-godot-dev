extends KinematicBody2D

export var _move_speed := 48.0
var velocity := Vector2.ZERO
var last_direction := "down"

onready var anim_sprite := $AnimatedSprite

func _physics_process(delta):
	_move()

func _move() -> void:
	var axis_x := Input.get_axis("move_left", "move_right")
	var axis_y := Input.get_axis("move_up", "move_down")
	var direction := Vector2(axis_x, axis_y)

	if direction.length() > 0:
		direction = direction.normalized()
		velocity = direction * _move_speed
		move_and_slide(velocity)
		_play_walk_animation(direction)
	else:
		velocity = Vector2.ZERO
		move_and_slide(velocity)
		_play_idle_animation()

func _play_walk_animation(dir: Vector2) -> void:
	if abs(dir.x) > abs(dir.y):
		if dir.x > 0:
			anim_sprite.flip_h = true
			anim_sprite.play("walk_left")
			last_direction = "right"
		else:
			anim_sprite.flip_h = false
			anim_sprite.play("walk_left")
			last_direction = "left"
	else:
		anim_sprite.flip_h = false
		if dir.y > 0:
			anim_sprite.play("walk_down")
			last_direction = "down"
		else:
			anim_sprite.play("walk_up")
			last_direction = "up"

func _play_idle_animation() -> void:
	if last_direction == "left":
		anim_sprite.flip_h = false
		anim_sprite.play("idle_left")
	elif last_direction == "right":
		anim_sprite.flip_h = true
		anim_sprite.play("idle_left")
	else:
		anim_sprite.flip_h = false
		anim_sprite.play("idle_" + last_direction)

extends Area2D

signal collected(pickup)

var kind := "gem"
var value := 25
var life := 14.0
var bob_time := 0.0
var target

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	connect("body_entered", self, "_on_body_entered")
	add_to_group("pickups")
	bob_time = randf() * TAU

func setup(pickup_kind: String, pickup_value: int, pickup_target: Node2D) -> void:
	kind = pickup_kind
	value = pickup_value
	target = pickup_target
	update()

func _process(delta: float) -> void:
	life -= delta
	bob_time += delta * 4.0
	if life <= 0.0:
		queue_free()
		return
	scale = Vector2.ONE * (0.85 + sin(bob_time) * 0.08)
	if life < 3.0 and int(life * 10.0) % 2 == 0:
		modulate.a = 0.35
	else:
		modulate.a = 1.0
	if is_instance_valid(target):
		var distance := global_position.distance_to(target.global_position)
		if distance < 82.0:
			global_position = global_position.move_toward(target.global_position, delta * (110.0 + (82.0 - distance) * 4.0))
		if distance < 17.0:
			_collect()

func _on_body_entered(body: Node) -> void:
	if body == target:
		_collect()

func _collect() -> void:
	if not is_inside_tree():
		return
	emit_signal("collected", self)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2(0, 7), 6.0, Color(0.03, 0.05, 0.05, 0.22))
	match kind:
		"heart":
			draw_circle(Vector2(-4, -2), 5.0, Color(0.95, 0.25, 0.32))
			draw_circle(Vector2(4, -2), 5.0, Color(0.95, 0.25, 0.32))
			draw_colored_polygon(PoolVector2Array([Vector2(-8, 0), Vector2(8, 0), Vector2(0, 9)]), Color(0.95, 0.25, 0.32))
			draw_circle(Vector2(-4, -3), 1.5, Color(1, 0.65, 0.68, 0.7))
		_:
			draw_colored_polygon(PoolVector2Array([Vector2(0, -8), Vector2(6, 0), Vector2(0, 8), Vector2(-6, 0)]), Color(0.20, 0.88, 0.92))
			draw_colored_polygon(PoolVector2Array([Vector2(0, -8), Vector2(0, 8), Vector2(-6, 0)]), Color(0.10, 0.58, 0.72))
			draw_line(Vector2(-2, -4), Vector2(2, -4), Color(0.75, 1, 1, 0.8), 1.0)

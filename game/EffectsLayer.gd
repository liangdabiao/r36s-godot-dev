extends Node2D

const FONT = preload("res://game/GameFont.tres")

var effects := []

func _ready() -> void:
	z_index = 20

func _process(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		effect["life"] -= delta
		if effect["life"] <= 0.0:
			effects.remove(index)
			continue
		if effect["type"] == "text":
			effect["position"].y -= delta * 24.0
	update()

func spawn_hit(position: Vector2, color: Color = Color(1.0, 0.88, 0.45)) -> void:
	effects.append({
		"type": "burst",
		"position": position,
		"color": color,
		"life": 0.20,
		"max_life": 0.20,
		"seed": randf() * TAU
	})

func spawn_text(position: Vector2, text: String, color: Color = Color(1.0, 0.95, 0.72)) -> void:
	effects.append({
		"type": "text",
		"position": position + Vector2(rand_range(-5, 5), -12),
		"text": text,
		"color": color,
		"life": 0.65,
		"max_life": 0.65
	})

func spawn_slash(position: Vector2, direction: Vector2, color: Color = Color(0.72, 0.95, 1.0), radius: float = 44.0) -> void:
	effects.append({
		"type": "slash",
		"position": position,
		"direction": direction,
		"color": color,
		"radius": radius,
		"life": 0.16,
		"max_life": 0.16
	})

func spawn_ring(position: Vector2, color: Color, radius: float = 90.0) -> void:
	effects.append({
		"type": "ring",
		"position": position,
		"color": color,
		"radius": radius,
		"life": 0.38,
		"max_life": 0.38
	})

func clear() -> void:
	effects.clear()
	update()

func _draw() -> void:
	for effect in effects:
		var ratio := float(effect["life"]) / float(effect["max_life"])
		var tint: Color = effect["color"]
		tint.a *= ratio
		match effect["type"]:
			"text":
				draw_string(FONT, effect["position"], effect["text"], tint, 16)
			"burst":
				var origin: Vector2 = effect["position"]
				for particle_index in range(7):
					var angle := float(effect["seed"]) + TAU * particle_index / 7.0
					var inner := origin + Vector2(cos(angle), sin(angle)) * (4.0 + (1.0 - ratio) * 8.0)
					var outer := origin + Vector2(cos(angle), sin(angle)) * (10.0 + (1.0 - ratio) * 17.0)
					draw_line(inner, outer, tint, 2.0)
			"slash":
				var direction: Vector2 = effect["direction"]
				var radius: float = float(effect["radius"]) * (0.75 + (1.0 - ratio) * 0.35)
				draw_arc(effect["position"], radius, direction.angle() - 0.95, direction.angle() + 0.95, 18, tint, 4.0)
			"ring":
				var radius := float(effect["radius"]) * (1.0 - ratio)
				draw_arc(effect["position"], max(2.0, radius), 0, TAU, 36, tint, 3.0)

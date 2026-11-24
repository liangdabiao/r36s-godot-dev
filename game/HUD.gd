extends CanvasLayer

signal start_requested
signal upgrade_selected(id)
signal resume_requested
signal restart_requested

const FONT = preload("res://game/GameFont.tres")
const WHITE := Color(0.94, 0.97, 0.91)
const GOLD := Color(1.0, 0.78, 0.32)
const CYAN := Color(0.28, 0.88, 0.92)
const RED := Color(0.95, 0.30, 0.28)

var hp_bar: ProgressBar
var hp_label: Label
var wave_label: Label
var score_label: Label
var kills_label: Label
var combo_label: Label
var dash_label: Label
var special_label: Label
var time_label: Label
var boss_panel: Panel
var boss_bar: ProgressBar
var boss_label: Label
var message_label: Label
var message_timer := 0.0
var overlay: ColorRect
var title_panel: Panel
var upgrade_panel: Panel
var pause_panel: Panel
var end_panel: Panel
var title_best_label: Label
var end_title_label: Label
var end_stats_label: Label
var end_best_label: Label
var upgrade_buttons := []
var upgrade_choices := []
var selected_upgrade := 0

func _ready() -> void:
	layer = 20
	_build_hud()
	_build_overlays()

func _process(delta: float) -> void:
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message_label.visible = false

func _build_hud() -> void:
	var root := Control.new()
	root.rect_size = Vector2(640, 480)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var status_panel := _panel(root, Vector2(12, 12), Vector2(232, 64), Color(0.04, 0.08, 0.09, 0.88))
	_label(root, "VITALITY", Vector2(24, 18), 14, WHITE)
	hp_bar = _progress_bar(root, Vector2(24, 40), Vector2(154, 14), RED)
	hp_label = _label(root, "100 / 100", Vector2(184, 37), 14, WHITE)

	wave_label = _label(root, "WAVE 1 / 5", Vector2(258, 18), 20, GOLD)
	wave_label.align = Label.ALIGN_CENTER
	wave_label.rect_size = Vector2(124, 30)
	score_label = _label(root, "SCORE 0", Vector2(438, 18), 18, WHITE)
	score_label.rect_size = Vector2(188, 28)
	score_label.align = Label.ALIGN_RIGHT
	kills_label = _label(root, "KILLS 0", Vector2(454, 46), 13, Color(0.66, 0.76, 0.74))
	kills_label.rect_size = Vector2(172, 22)
	kills_label.align = Label.ALIGN_RIGHT
	time_label = _label(root, "00:00", Vector2(272, 48), 13, Color(0.66, 0.76, 0.74))
	time_label.rect_size = Vector2(96, 20)
	time_label.align = Label.ALIGN_CENTER
	combo_label = _label(root, "", Vector2(250, 78), 22, GOLD)
	combo_label.rect_size = Vector2(140, 30)
	combo_label.align = Label.ALIGN_CENTER

	var bottom_panel := _panel(root, Vector2(12, 408), Vector2(616, 60), Color(0.04, 0.08, 0.09, 0.88))
	dash_label = _label(root, "B / K  DASH READY", Vector2(26, 420), 15, CYAN)
	dash_label.rect_size = Vector2(240, 22)
	special_label = _label(root, "X / L  SPRING BURST READY", Vector2(282, 420), 15, GOLD)
	special_label.rect_size = Vector2(330, 22)
	_label(root, "A / J  ATTACK     SELECT / P  PAUSE     START  EXIT", Vector2(26, 446), 11, Color(0.62, 0.72, 0.70))

	boss_panel = _panel(root, Vector2(150, 86), Vector2(340, 42), Color(0.10, 0.03, 0.04, 0.92))
	boss_label = _label(boss_panel, "MOSS KING", Vector2(14, 5), 14, Color(1.0, 0.62, 0.58))
	boss_label.rect_size = Vector2(312, 20)
	boss_label.align = Label.ALIGN_CENTER
	boss_bar = _progress_bar(boss_panel, Vector2(14, 27), Vector2(312, 9), RED)
	boss_panel.visible = false

	message_label = _label_box(root, "", Vector2(100, 190), Vector2(440, 64), 32, GOLD)
	message_label.align = Label.ALIGN_CENTER
	message_label.autowrap = true
	message_label.visible = false

func _build_overlays() -> void:
	overlay = ColorRect.new()
	overlay.rect_size = Vector2(640, 480)
	overlay.color = Color(0.015, 0.025, 0.03, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.visible = false

	title_panel = _panel(overlay, Vector2(104, 66), Vector2(432, 348), Color(0.045, 0.10, 0.11, 0.98), GOLD)
	var title := _label(title_panel, "SPRING GUARD", Vector2(26, 24), 40, GOLD)
	title.rect_size = Vector2(380, 54)
	title.align = Label.ALIGN_CENTER
	var subtitle := _label(title_panel, "Defend the last spring. Survive five waves.", Vector2(26, 82), 16, WHITE)
	subtitle.rect_size = Vector2(380, 28)
	subtitle.align = Label.ALIGN_CENTER
	_label(title_panel, "MOVE   WASD / D-PAD\nATTACK   A / J\nDASH   B / K\nSPRING BURST   X / L\nPAUSE   SELECT / P", Vector2(38, 126), 17, Color(0.72, 0.84, 0.81)).rect_size = Vector2(250, 116)
	title_best_label = _label(title_panel, "BEST SCORE 0", Vector2(38, 260), 15, CYAN)
	title_best_label.rect_size = Vector2(220, 24)
	var start_button := _button(title_panel, "START RUN", Vector2(272, 252), Vector2(128, 48), GOLD)
	start_button.connect("pressed", self, "_on_start")

	upgrade_panel = _panel(overlay, Vector2(72, 92), Vector2(496, 300), Color(0.045, 0.10, 0.11, 0.98), CYAN)
	var upgrade_title := _label(upgrade_panel, "WAVE CLEARED", Vector2(24, 18), 30, GOLD)
	upgrade_title.rect_size = Vector2(448, 42)
	upgrade_title.align = Label.ALIGN_CENTER
	var upgrade_hint := _label(upgrade_panel, "Choose one upgrade. Left / Right + Attack.", Vector2(24, 60), 14, WHITE)
	upgrade_hint.rect_size = Vector2(448, 24)
	upgrade_hint.align = Label.ALIGN_CENTER
	for index in range(3):
		var button := _button(upgrade_panel, "", Vector2(28, 100 + index * 62), Vector2(440, 52), CYAN)
		button.align = Button.ALIGN_LEFT
		button.connect("pressed", self, "_on_upgrade_button", [index])
		upgrade_buttons.append(button)

	pause_panel = _panel(overlay, Vector2(150, 130), Vector2(340, 220), Color(0.045, 0.10, 0.11, 0.98), GOLD)
	var pause_title := _label(pause_panel, "PAUSED", Vector2(24, 22), 32, GOLD)
	pause_title.rect_size = Vector2(292, 44)
	pause_title.align = Label.ALIGN_CENTER
	var resume_button := _button(pause_panel, "RESUME", Vector2(58, 86), Vector2(224, 46), CYAN)
	resume_button.connect("pressed", self, "_on_resume")
	var restart_button := _button(pause_panel, "RESTART RUN", Vector2(58, 146), Vector2(224, 46), GOLD)
	restart_button.connect("pressed", self, "_on_restart")

	end_panel = _panel(overlay, Vector2(104, 92), Vector2(432, 296), Color(0.045, 0.10, 0.11, 0.98), GOLD)
	end_title_label = _label(end_panel, "VICTORY", Vector2(24, 20), 38, GOLD)
	end_title_label.rect_size = Vector2(384, 52)
	end_title_label.align = Label.ALIGN_CENTER
	end_stats_label = _label(end_panel, "", Vector2(36, 86), 18, WHITE)
	end_stats_label.rect_size = Vector2(360, 92)
	end_stats_label.align = Label.ALIGN_CENTER
	end_best_label = _label(end_panel, "", Vector2(36, 184), 15, CYAN)
	end_best_label.rect_size = Vector2(360, 26)
	end_best_label.align = Label.ALIGN_CENTER
	var again_button := _button(end_panel, "PLAY AGAIN", Vector2(132, 224), Vector2(168, 48), GOLD)
	again_button.connect("pressed", self, "_on_restart")
	_hide_overlays()

func _connect_signals() -> void:
	pass

func show_title(best_score: int) -> void:
	overlay.visible = true
	title_panel.visible = true
	upgrade_panel.visible = false
	pause_panel.visible = false
	end_panel.visible = false
	title_best_label.text = "BEST SCORE " + str(best_score)
	boss_panel.visible = false
	message_label.visible = false

func show_upgrades(choices: Array) -> void:
	upgrade_choices = choices
	selected_upgrade = 0
	overlay.visible = true
	title_panel.visible = false
	upgrade_panel.visible = true
	pause_panel.visible = false
	end_panel.visible = false
	for index in range(3):
		var choice: Dictionary = choices[index]
		upgrade_buttons[index].text = str(index + 1) + ". " + choice["title"] + "  -  " + choice["description"]
	set_upgrade_selection(0)

func show_pause() -> void:
	overlay.visible = true
	title_panel.visible = false
	upgrade_panel.visible = false
	pause_panel.visible = true
	end_panel.visible = false

func show_end(victory: bool, score: int, kills: int, wave: int, time: float, best: int) -> void:
	overlay.visible = true
	title_panel.visible = false
	upgrade_panel.visible = false
	pause_panel.visible = false
	end_panel.visible = true
	boss_panel.visible = false
	end_title_label.text = "VICTORY" if victory else "THE SPRING FELL"
	end_title_label.add_color_override("font_color", GOLD if victory else RED)
	end_stats_label.text = "SCORE  %d\nKILLS  %d     WAVE  %d / 5\nTIME  %02d:%02d" % [score, kills, wave, int(time) / 60, int(time) % 60]
	end_best_label.text = "BEST SCORE  " + str(best) + ("   NEW RECORD!" if score >= best and score > 0 else "")

func hide_overlay() -> void:
	overlay.visible = false
	title_panel.visible = false
	upgrade_panel.visible = false
	pause_panel.visible = false
	end_panel.visible = false

func set_stats(hp: float, maximum_hp: float, wave: int, score: int, kills: int, combo: int, combo_ratio: float, dash_remaining: float, special_remaining: float, time: float) -> void:
	hp_bar.max_value = maximum_hp
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [int(hp), int(maximum_hp)]
	wave_label.text = "WAVE %d / 5" % wave
	score_label.text = "SCORE " + str(score)
	kills_label.text = "KILLS " + str(kills)
	time_label.text = "%02d:%02d" % [int(time) / 60, int(time) % 60]
	combo_label.visible = combo > 1 and combo_ratio > 0.0
	combo_label.text = "COMBO x" + str(combo)
	combo_label.modulate.a = min(1.0, combo_ratio * 2.5)
	dash_label.text = "B / K  DASH " + ("READY" if dash_remaining <= 0.0 else "%.1fs" % dash_remaining)
	special_label.text = "X / L  SPRING BURST " + ("READY" if special_remaining <= 0.0 else "%.1fs" % special_remaining)
	dash_label.add_color_override("font_color", CYAN if dash_remaining <= 0.0 else Color(0.38, 0.52, 0.53))
	special_label.add_color_override("font_color", GOLD if special_remaining <= 0.0 else Color(0.55, 0.50, 0.34))

func set_boss(name: String, ratio: float) -> void:
	boss_panel.visible = ratio >= 0.0
	if ratio >= 0.0:
		boss_label.text = name
		boss_bar.max_value = 1.0
		boss_bar.value = ratio

func show_message(text: String, duration: float = 1.8) -> void:
	message_label.text = text
	message_label.visible = true
	message_timer = duration

func move_upgrade_selection(direction: int) -> void:
	selected_upgrade = posmod(selected_upgrade + direction, 3)
	set_upgrade_selection(selected_upgrade)

func confirm_upgrade() -> void:
	if upgrade_choices.size() > selected_upgrade:
		emit_signal("upgrade_selected", upgrade_choices[selected_upgrade]["id"])

func set_upgrade_selection(index: int) -> void:
	for button_index in range(upgrade_buttons.size()):
		var normal := _style(Color(0.07, 0.15, 0.16, 1.0), CYAN if button_index == index else Color(0.16, 0.28, 0.28), 2)
		upgrade_buttons[button_index].add_stylebox_override("normal", normal)
		upgrade_buttons[button_index].add_color_override("font_color", WHITE if button_index == index else Color(0.62, 0.74, 0.72))

func _hide_overlays() -> void:
	overlay.visible = false

func _on_start() -> void:
	emit_signal("start_requested")

func _on_upgrade_button(index: int) -> void:
	selected_upgrade = index
	set_upgrade_selection(index)
	if upgrade_choices.size() > index:
		emit_signal("upgrade_selected", upgrade_choices[index]["id"])

func _on_resume() -> void:
	emit_signal("resume_requested")

func _on_restart() -> void:
	emit_signal("restart_requested")

func _panel(parent: Node, position: Vector2, size: Vector2, color: Color, border: Color = Color(0.16, 0.32, 0.32)) -> Panel:
	var panel := Panel.new()
	panel.rect_position = position
	panel.rect_size = size
	panel.add_stylebox_override("panel", _style(color, border, 2))
	parent.add_child(panel)
	return panel

func _label(parent: Node, text: String, position: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.rect_position = position
	label.add_font_override("font", _sized_font(size))
	label.add_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _label_box(parent: Node, text: String, position: Vector2, label_size: Vector2, size: int, color: Color) -> Label:
	var label := _label(parent, text, position, size, color)
	label.rect_size = label_size
	return label

func _progress_bar(parent: Node, position: Vector2, size: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.rect_position = position
	bar.rect_size = size
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.percent_visible = false
	bar.add_stylebox_override("background", _style(Color(0.10, 0.13, 0.14, 1.0), Color(0.18, 0.24, 0.24), 1))
	bar.add_stylebox_override("fg", _style(color, color, 1))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar

func _button(parent: Node, text: String, position: Vector2, size: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.rect_position = position
	button.rect_size = size
	button.add_font_override("font", _sized_font(16))
	button.add_color_override("font_color", WHITE)
	button.add_color_override("font_color_hover", Color.white)
	button.add_color_override("font_color_pressed", accent)
	button.add_stylebox_override("normal", _style(Color(0.07, 0.15, 0.16, 1.0), accent, 2))
	button.add_stylebox_override("hover", _style(Color(0.10, 0.22, 0.22, 1.0), accent.lightened(0.15), 2))
	button.add_stylebox_override("pressed", _style(Color(0.16, 0.28, 0.26, 1.0), accent, 2))
	button.add_stylebox_override("focus", _style(Color(0.10, 0.22, 0.22, 1.0), accent, 2))
	parent.add_child(button)
	return button

func _sized_font(size: int) -> DynamicFont:
	var font := DynamicFont.new()
	font.font_data = FONT.font_data
	font.size = size
	return font

func _style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	return style

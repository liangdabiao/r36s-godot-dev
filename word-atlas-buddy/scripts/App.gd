extends Control

# 主控制器：640x480 固定布局，全部界面在 _draw() 里直接绘制。

enum Screen { HOME, REVIEW, ATLAS, BROWSE, DETAIL, CREDITS }

const W := 640.0
const H := 480.0
const FOOTER_Y := 452.0
const MARGIN := 40.0
const CONTENT_W := 560.0

var ui := UIKit.new()
var repo: ContentRepository
var store: ProgressStore
var audio: AudioDirector

var screen = Screen.HOME
var menu_index := 0

# 复习
var queue: Array = []
var queue_pos := 0
var revealed := false
var rate_index := 2
var session_total := 0

# 星图
var atlas_pos: Array = []
var atlas_cursor := 0
var atlas_built := false

# 词库
var browse_list: Array = []
var browse_index := 0
var browse_scroll := 0
var browse_filter := 0
var browse_filters: Array = []

# 详情
var detail_index := -1
var detail_scroll := 0.0
var detail_max_scroll := 0.0
var detail_from: int = Screen.BROWSE

# 提示
var toast_text := ""
var toast_until := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_size = Vector2(W, H)
	_register_actions()

	repo = get_node("ContentRepository")
	store = get_node("ProgressStore")
	audio = get_node("AudioDirector")

	if not repo.load_index():
		toast("词库索引缺失")
		return
	store.repo = repo
	store.srs = Srs.new()
	# 关键：音频模块也必须有 repo，否则 _play() 第一行就 return，永远没声音
	audio.repo = repo
	build_filters()
	AudioServer.set_bus_mute(0, not store.audio_enabled())
	_dbg("BOOT mute=%s vol_db=%s mix_rate=%s latency=%s devices=%s" % [
		str(AudioServer.is_bus_mute(0)), str(AudioServer.get_bus_volume_db(0)),
		str(AudioServer.get_mix_rate()), str(AudioServer.get_output_latency()),
		str(AudioServer.get_device_list())])
	print("[AUD] boot mute=", AudioServer.is_bus_mute(0),
		" vol_db=", AudioServer.get_bus_volume_db(0),
		" mix_rate=", AudioServer.get_mix_rate(),
		" latency=", AudioServer.get_output_latency(),
		" devices=", AudioServer.get_device_list())
	update()


# ---------------------------------------------------------------- 输入

func _register_actions() -> void:
	# 只绑键盘：gptokeyb 已把实体按键映射成 w/s/a/d/j/k/l/u 等键码。
	# 若再去绑 joypad 事件，一次按下会被引擎收到两份（键盘 + 手柄），
	# 表现为「按一下走两步」「发音刚起就停」。
	_action("nav_up", [KEY_W, KEY_UP], [], [])
	_action("nav_down", [KEY_S, KEY_DOWN], [], [])
	_action("nav_left", [KEY_A, KEY_LEFT], [], [])
	_action("nav_right", [KEY_D, KEY_RIGHT], [], [])
	_action("accept", [KEY_J, KEY_ENTER], [], [])
	_action("cancel", [KEY_K, KEY_BACKSPACE], [], [])
	_action("act_x", [KEY_L], [], [])
	_action("act_y", [KEY_U], [], [])
	_action("act_l", [KEY_Q], [], [])
	_action("act_r", [KEY_R], [], [])
	_action("act_start", [KEY_ESCAPE], [], [])
	_action("act_select", [KEY_P], [], [])


func _action(action_name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, 0.4)
	for k in keys:
		var ev := InputEventKey.new()
		ev.scancode = k
		InputMap.action_add_event(action_name, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action_name, jb)
	if axes.size() == 2:
		for sign_value in [-1.0, 1.0]:
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(axes[0])
			jm.axis_value = float(axes[1]) * sign_value
			InputMap.action_add_event(action_name, jm)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			_dbg("KEY scancode=%d screen=%d" % [ke.scancode, screen])
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_dbg("JOY btn=%d screen=%d" % [jb.button_index, screen])

	if event.is_action_pressed("act_start"):
		store.save_game()
		get_tree().quit()
		return

	match screen:
		Screen.HOME:
			_input_home(event)
		Screen.REVIEW:
			_input_review(event)
		Screen.ATLAS:
			_input_atlas(event)
		Screen.BROWSE:
			_input_browse(event)
		Screen.DETAIL:
			_input_detail(event)
		Screen.CREDITS:
			if event.is_action_pressed("cancel") or event.is_action_pressed("accept"):
				screen = Screen.HOME
				update()


# ---------------------------------------------------------------- 首页

func _input_home(event: InputEvent) -> void:
	if event.is_action_pressed("nav_up"):
		menu_index = int(max(0, menu_index - 1))
		update()
	elif event.is_action_pressed("nav_down"):
		menu_index = int(min(3, menu_index + 1))
		update()
	elif event.is_action_pressed("act_y"):
		_play_sample()
	elif event.is_action_pressed("act_l"):
		_play_tone()
	elif event.is_action_pressed("act_r"):
		_play_imported()
	elif event.is_action_pressed("accept"):
		match menu_index:
			0:
				start_review()
			1:
				screen = Screen.ATLAS
				ensure_atlas()
				atlas_cursor = int(min(atlas_cursor, repo.count - 1))
				update()
			2:
				screen = Screen.BROWSE
				rebuild_browse()
				update()
			3:
				screen = Screen.CREDITS
				update()


func _draw_home() -> void:
	ui.text(self, "词迹", Vector2(MARGIN, 34), 26, UIKit.TEXT)
	ui.text(self, "Word Atlas · 离线词库", Vector2(MARGIN + 62, 33), 13, UIKit.DIM)
	ui.text_right(self, "连续 %d 天" % store.streak(), W - MARGIN, 32, 14, UIKit.GOLD)
	ui.hline(self, MARGIN, W - MARGIN, 46)

	var stats := [
		["待复习", str(store.due_count()), UIKit.ACCENT],
		["已学", str(store.learned_count()), UIKit.BLUE],
		["累计复习", str(store.total_reviews()), UIKit.GOLD],
	]
	for i in range(3):
		var x := MARGIN + i * 190.0
		var rect := Rect2(x, 60, 172, 62)
		ui.panel(self, rect)
		ui.text(self, stats[i][0], Vector2(x + 14, 80), 13, UIKit.MUTED)
		ui.text(self, stats[i][1], Vector2(x + 14, 110), 26, stats[i][2])

	var items := ["今日复习", "词星图", "词库浏览", "关于与授权"]
	var subs := [
		"%d 张待复习 · 今日新词 %d" % [store.due_count(), store.new_remaining_today()],
		"按主题散布的 %d 个词" % repo.count,
		"分级 / 主题筛选，随时翻查",
		"CC BY 4.0 署名与来源",
	]
	for i in range(items.size()):
		var y := 140.0 + i * 56.0
		var rect := Rect2(MARGIN, y, CONTENT_W, 48)
		if i == menu_index:
			ui.panel(self, rect, UIKit.PANEL_HI, UIKit.ACCENT)
			ui.text(self, "›", Vector2(MARGIN + 12, y + 31), 20, UIKit.ACCENT)
		else:
			ui.panel(self, rect)
		ui.text(self, items[i], Vector2(MARGIN + 34, y + 22), 17,
			UIKit.TEXT if i == menu_index else UIKit.MUTED)
		ui.text(self, subs[i], Vector2(MARGIN + 34, y + 39), 12, UIKit.DIM)

	var srow := _sample_row()
	ui.panel(self, Rect2(MARGIN, 362, CONTENT_W, 52), UIKit.PANEL, UIKit.ACCENT)
	ui.speaker_button(self, Rect2(MARGIN + 14, 376, 26, 26), UIKit.ACCENT, audio.player.playing)
	ui.text(self, "按 Y 试听发音", Vector2(MARGIN + 52, 384), 17, UIKit.TEXT)
	ui.text(self, "先确认喇叭有声，再进复习", Vector2(MARGIN + 52, 404), 12, UIKit.MUTED)
	ui.text_right(self, repo.display_word(srow), W - MARGIN - 14, 394, 14, UIKit.MUTED)

	_keybar([["上下", "选择"], ["A", "进入"], ["Y", "试听发音"], ["L1", "自检音"], ["Start", "退出"]])


# ---------------------------------------------------------------- 复习

func start_review() -> void:
	queue = store.build_queue()
	queue_pos = 0
	session_total = queue.size()
	revealed = false
	rate_index = 2
	screen = Screen.REVIEW
	update()


func _current_wid() -> String:
	if queue_pos < 0 or queue_pos >= queue.size():
		return ""
	return String(queue[queue_pos])


func _current_row() -> int:
	return repo.find_id(_current_wid())


func _current_card() -> Dictionary:
	var wid := _current_wid()
	if wid == "":
		return {}
	var card: Dictionary = store.card_for(wid)
	if card.empty():
		return store.srs.new_card(int(OS.get_unix_time()))
	return card


func _input_review(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		screen = Screen.HOME
		update()
		return
	var row := _current_row()
	if row < 0:
		screen = Screen.HOME
		update()
		return

	if event.is_action_pressed("act_y"):
		_play_word(row)
		return

	if not revealed:
		if event.is_action_pressed("accept"):
			revealed = true
			rate_index = 2
			update()
		elif event.is_action_pressed("act_x") or event.is_action_pressed("act_l"):
			toast("翻面后才能听例句")
		return

	if event.is_action_pressed("act_x"):
		_play_sentence(row, false)
		return
	if event.is_action_pressed("act_l"):
		_play_sentence(row, true)
		return

	if event.is_action_pressed("nav_left"):
		rate_index = int(max(1, rate_index - 1))
		update()
	elif event.is_action_pressed("nav_right"):
		rate_index = int(min(4, rate_index + 1))
		update()
	elif event.is_action_pressed("accept"):
		_submit_rating(row, rate_index)


func _submit_rating(row: int, rating: int) -> void:
	var wid := _current_wid()
	var now := int(OS.get_unix_time())
	var next_card: Dictionary = store.review(wid, rating, now)
	# 学习步长内的卡回到队尾，同轮继续消化
	if int(next_card.get("state", 0)) in [Srs.STATE_LEARNING, Srs.STATE_RELEARNING]:
		queue.append(wid)
		session_total = queue.size()
	queue_pos += 1
	revealed = false
	rate_index = 2
	if queue_pos >= queue.size():
		toast("本轮完成，做了 %d 次复习" % session_total)
		screen = Screen.HOME
	update()


func _draw_review() -> void:
	if queue_pos >= queue.size():
		ui.text_center(self, "本轮已完成", W * 0.5, 200, 24, UIKit.TEXT)
		ui.text_center(self, "按 B 返回首页", W * 0.5, 236, 14, UIKit.MUTED)
		return

	var row := _current_row()
	if row < 0:
		return
	var wid := _current_wid()
	var total: int = max(queue.size(), 1)

	ui.text(self, "今日复习", Vector2(MARGIN, 32), 15, UIKit.MUTED)
	ui.text_right(self, "%d / %d" % [queue_pos + 1, queue.size()], W - MARGIN, 32, 13, UIKit.DIM)
	ui.bar(self, Rect2(MARGIN, 40, CONTENT_W, 3), float(queue_pos) / float(total))
	ui.hline(self, MARGIN, W - MARGIN, 50)

	if not revealed:
		_draw_card_front(row, wid)
	else:
		_draw_card_back(row, wid)


func _draw_card_front(row: int, wid: String) -> void:
	var tex: Texture = repo.texture_for(row)
	if tex != null:
		var size := 190.0
		var x := (W - size) * 0.5
		ui.panel(self, Rect2(x - 4, 62, size + 8, size + 8), UIKit.PANEL, UIKit.LINE)
		draw_texture_rect(tex, Rect2(x, 66, size, size), false)
		var word := repo.display_word(row)
		var wf := ui.font(38)
		var ww := wf.get_string_size(word).x
		ui.text_center(self, word, W * 0.5, 296, 38, UIKit.TEXT)
		_speaker_beside(row, ww, 296, 38, 32)
		var ipa_text := repo.phonetic(row)
		if ipa_text != "":
			var f := ui.ipa_font(16)
			var w := f.get_string_size(ipa_text).x
			ui.ipa(self, ipa_text, Vector2(W * 0.5 - w * 0.5, 322), 16, UIKit.MUTED)
	else:
		var word := repo.display_word(row)
		var wf := ui.font(44)
		var ww := wf.get_string_size(word).x
		ui.text_center(self, word, W * 0.5, 220, 44, UIKit.TEXT)
		_speaker_beside(row, ww, 220, 44, 36)
		var ipa_text := repo.phonetic(row)
		if ipa_text != "":
			var f := ui.ipa_font(17)
			var w := f.get_string_size(ipa_text).x
			ui.ipa(self, ipa_text, Vector2(W * 0.5 - w * 0.5, 250), 17, UIKit.MUTED)

	# 新词提示
	if store.is_new(wid):
		ui.text_center(self, "新词", W * 0.5, 348, 13, UIKit.GOLD)

	ui.text_center(self, "A 显示释义      Y 发音      B 返回", W * 0.5, 412, 15, UIKit.MUTED)
	_keybar([["A", "翻面"], ["Y", "发音"], ["B", "返回"], ["Start", "退出"]])


func _draw_card_back(row: int, wid: String) -> void:
	var entry: Dictionary = repo.entry(row)
	var tex: Texture = repo.texture_for(row)
	var text_w := CONTENT_W
	if tex != null:
		text_w = CONTENT_W - 146
		draw_texture_rect(tex, Rect2(W - MARGIN - 134, 58, 134, 134), false)

	var head_f := ui.font(26)
	var head_word := repo.display_word(row)
	draw_string(head_f, Vector2(MARGIN, 86), head_word, UIKit.TEXT)
	var hw := head_f.get_string_size(head_word).x
	var has_voice := repo.has_audio(row)
	var vcol: Color = UIKit.ACCENT
	if not has_voice:
		vcol = UIKit.DIM
	elif audio.is_playing():
		vcol = UIKit.GOLD
	ui.speaker_button(self, Rect2(MARGIN + hw + 8, 64, 24, 24), vcol, has_voice and audio.is_playing())
	var ipa_text := repo.phonetic(row)
	if ipa_text != "":
		var x := MARGIN + hw + 40
		draw_string(ui.ipa_font(15), Vector2(x, 84), ipa_text, UIKit.MUTED)
	var chip_x := MARGIN
	chip_x += ui.draw_chip(self, repo.cefr(row), Vector2(chip_x, 96), 11, ui.cefr_color(repo.cefr(row))) + 6
	ui.draw_chip(self, repo.topic_label(row), Vector2(chip_x, 96), 11, UIKit.BLUE)

	var blocks := _card_blocks(entry)
	var total := _measure_blocks(blocks, text_w)
	var band_top := 124.0
	var band_bottom := 384.0
	var top := band_top
	if total < band_bottom - band_top:
		top = band_top + (band_bottom - band_top - total) * 0.38
	_draw_blocks(blocks, text_w, top, top - 4.0, band_bottom)
	_draw_rating_row()


func _card_blocks(entry: Dictionary) -> Array:
	var blocks := []
	var senses: Array = entry.get("senses", [])
	for i in range(int(min(senses.size(), 3))):
		var sense: Dictionary = senses[i]
		var head := ("%s %s" % [sense.get("pos", ""), sense.get("zh", "")]).strip_edges()
		blocks.append(_blk(head, 16, UIKit.TEXT, 0, 1))
		var en := String(sense.get("en", ""))
		if en != "":
			blocks.append(_blk(en, 12, UIKit.DIM, 4, 2))
	blocks.append({"type": "gap", "h": 10.0})

	var examples: Array = entry.get("ex", [])
	if examples.size() > 0:
		blocks.append({"type": "line"})
		var ex: Dictionary = examples[0]
		blocks.append(_blk(String(ex.get("en", "")), 14, UIKit.TEXT, 5, 2))
		if String(ex.get("zh", "")) != "":
			blocks.append(_blk(String(ex.get("zh", "")), 12, UIKit.MUTED, 6, 1))

	var cols: Array = entry.get("col", [])
	if cols.size() > 0:
		var joined := []
		for c in cols:
			joined.append(String(c).split("｜")[0])
		blocks.append(_blk("搭配  " + " · ".join(PoolStringArray(joined.slice(0, 3))),
			12, UIKit.DIM, 4, 1))

	var tip := String(entry.get("tip", ""))
	if tip != "":
		blocks.append(_blk("提示  " + tip, 12, UIKit.GOLD, 2, 2))
	return blocks


func _blk(text: String, size: int, color: Color, gap_after: float, max_lines: int) -> Dictionary:
	return {"type": "text", "text": text, "size": size, "color": color,
		"gap": gap_after, "max": max_lines}


func _measure_blocks(blocks: Array, text_w: float) -> float:
	var total := 0.0
	for b in blocks:
		if b["type"] == "gap":
			total += b["h"]
		elif b["type"] == "line":
			total += 9.0
		else:
			var f := ui.font(b["size"])
			var lines: Array = ui.wrap_lines(f, b["text"], text_w)
			if b["max"] > 0:
				lines.resize(int(min(lines.size(), b["max"])))
			total += lines.size() * (f.get_height() + 2) + b["gap"]
	return total


func _draw_blocks(blocks: Array, text_w: float, y_start: float,
		clip_top: float, clip_bottom: float) -> void:
	var y := y_start
	for b in blocks:
		if b["type"] == "gap":
			y += b["h"]
			continue
		if b["type"] == "line":
			if y >= clip_top - 2 and y + 9 <= clip_bottom:
				ui.hline(self, MARGIN, MARGIN + text_w, y + 4)
			y += 9.0
			continue
		var f := ui.font(b["size"])
		var lines: Array = ui.wrap_lines(f, b["text"], text_w)
		if b["max"] > 0 and lines.size() > b["max"]:
			lines.resize(int(b["max"]))
			lines[b["max"] - 1] = ui.ellipsis(f, String(lines[b["max"] - 1]) + "…", text_w)
		var lh := f.get_height() + 2
		var ascent := f.get_ascent()
		for line in lines:
			if y >= clip_top - 2 and y + lh <= clip_bottom:
				draw_string(f, Vector2(MARGIN, y + ascent), line, b["color"])
			y += lh
		y += b["gap"]


func _draw_rating_row() -> void:
	var card := _current_card()
	var now := int(OS.get_unix_time())
	var previews: Dictionary = store.srs.preview_intervals(card, now)
	var labels := ["忘记", "模糊", "记得", "简单"]
	var colors := [UIKit.RED, UIKit.GOLD, UIKit.ACCENT, UIKit.BLUE]
	var width := (CONTENT_W - 24) / 4.0
	for i in range(4):
		var rating := i + 1
		var x := MARGIN + i * (width + 8)
		var rect := Rect2(x, 392, width, 44)
		var selected := rating == rate_index
		ui.panel(self, rect, UIKit.PANEL_HI if selected else UIKit.PANEL,
			colors[i] if selected else UIKit.LINE)
		ui.text_center(self, labels[i], x + width * 0.5, 412, 15,
			colors[i] if selected else UIKit.MUTED)
		ui.text_center(self, String(previews.get(rating, "")), x + width * 0.5, 428, 11, UIKit.DIM)
	_keybar([["Y", "发音"], ["X", "例句"], ["L1", "例句②"], ["左右", "评分"], ["A", "确认"], ["B", "返回"]])


# ---------------------------------------------------------------- 星图

func ensure_atlas() -> void:
	if atlas_built or repo == null:
		return
	atlas_pos.resize(repo.count)
	var clusters := {}
	for i in range(repo.count):
		var t := int(repo.rows[i][5])
		if not clusters.has(t):
			clusters[t] = []
		clusters[t].append(i)
	var keys := clusters.keys()
	keys.sort()
	var center := Vector2(W * 0.5, 250)
	var ring := 158.0
	for ki in range(keys.size()):
		var key = keys[ki]
		var members: Array = clusters[key]
		var angle := TAU * float(ki) / float(keys.size()) - PI * 0.5
		var origin := center + Vector2(cos(angle), sin(angle) * 0.82) * ring
		for m in range(members.size()):
			var member := int(members[m])
			var r: float = min(2.6 * sqrt(float(m)), 44.0)
			var theta := float(m) * 2.39996
			var pos := origin + Vector2(cos(theta), sin(theta)) * r
			atlas_pos[member] = Vector2(
				clamp(pos.x, MARGIN - 6, W - MARGIN + 6),
				clamp(pos.y, 64, 416))
	atlas_built = true


func _input_atlas(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		screen = Screen.HOME
		update()
		return
	if event.is_action_pressed("accept"):
		detail_index = atlas_cursor
		detail_scroll = 0.0
		detail_from = Screen.ATLAS
		screen = Screen.DETAIL
		update()
		return
	if event.is_action_pressed("act_y"):
		_play_word(atlas_cursor)
		return
	if event.is_action_pressed("act_x"):
		_play_sentence(atlas_cursor, false)
		return
	if event.is_action_pressed("act_l"):
		_play_sentence(atlas_cursor, true)
		return
	var dir := Vector2.ZERO
	if event.is_action_pressed("nav_up"):
		dir = Vector2(0, -1)
	elif event.is_action_pressed("nav_down"):
		dir = Vector2(0, 1)
	elif event.is_action_pressed("nav_left"):
		dir = Vector2(-1, 0)
	elif event.is_action_pressed("nav_right"):
		dir = Vector2(1, 0)
	if dir == Vector2.ZERO:
		return
	var moved := _nearest_in_direction(dir)
	if moved >= 0:
		atlas_cursor = moved
		update()


func _nearest_in_direction(dir: Vector2) -> int:
	var from: Vector2 = atlas_pos[atlas_cursor]
	var best := -1
	var best_score := INF
	for i in range(atlas_pos.size()):
		if i == atlas_cursor:
			continue
		var delta: Vector2 = atlas_pos[i] - from
		var along := delta.dot(dir)
		if along <= 6.0:
			continue
		var side := abs(delta.dot(Vector2(-dir.y, dir.x)))
		var score := along + side * 2.4
		if score < best_score:
			best_score = score
			best = i
	return best


func _draw_atlas() -> void:
	ui.text(self, "词星图", Vector2(MARGIN, 32), 16, UIKit.TEXT)
	ui.text(self, "按主题成团，颜色代表 CEFR 等级", Vector2(MARGIN + 62, 32), 12, UIKit.DIM)
	ui.text_right(self, "%d 词" % repo.count, W - MARGIN, 32, 12, UIKit.DIM)
	ui.hline(self, MARGIN, W - MARGIN, 46)

	for i in range(atlas_pos.size()):
		var pos: Vector2 = atlas_pos[i]
		var color := ui.cefr_color(repo.cefr(i))
		var radius := 1.6
		if store.has_card(repo.word_id(i)):
			radius = 2.2
		if i == atlas_cursor:
			draw_circle(pos, 6.0, Color(color.r, color.g, color.b, 0.30))
			draw_circle(pos, 3.4, UIKit.TEXT)
		else:
			draw_circle(pos, radius, Color(color.r, color.g, color.b, 0.75))

	var row := atlas_cursor
	var label: String = repo.display_word(row)
	var f := ui.font(13)
	var w := f.get_string_size(label).x
	var lp: Vector2 = atlas_pos[row]
	var lx := clamp(lp.x - w * 0.5, MARGIN, W - MARGIN - w)
	var ly := lp.y - 12
	if ly < 62:
		ly = lp.y + 22
	draw_rect(Rect2(lx - 6, ly - 13, w + 12, 19), UIKit.PANEL, true)
	ui.text(self, label, Vector2(lx, ly), 13, UIKit.TEXT)
	# 环心信息区（环带内圈是空的，正好放当前词）
	var cx := W * 0.5
	var cy := 246.0
	var word_f := ui.font(21)
	var word_w := word_f.get_string_size(label).x
	draw_string(word_f, Vector2(cx - word_w * 0.5, cy), label, UIKit.TEXT)
	var ipa_value := repo.phonetic(row)
	if ipa_value != "":
		var ipa_f := ui.ipa_font(13)
		var ipa_w := ipa_f.get_string_size(ipa_value).x
		draw_string(ipa_f, Vector2(cx - ipa_w * 0.5, cy + 20), ipa_value, UIKit.MUTED)
	ui.text_center(self, ui.ellipsis(ui.font(12), repo.brief_zh(row), 190.0), cx, cy + 42, 12, UIKit.MUTED)
	ui.text_center(self, "%s · %s" % [repo.cefr(row), repo.topic_label(row)], cx, cy + 62, 11, UIKit.DIM)

	_keybar([["方向", "移动"], ["Y", "发音"], ["X", "例句"], ["A", "查看"], ["B", "返回"]])


# ---------------------------------------------------------------- 词库浏览

func build_filters() -> void:
	browse_filters = [["全部", -1]]
	for t in repo.topics:
		browse_filters.append([t[1], repo.topics.find(t)])


func rebuild_browse() -> void:
	browse_list = []
	var want_topic: int = int(browse_filters[browse_filter][1])
	for i in range(repo.count):
		if want_topic >= 0 and int(repo.rows[i][5]) != want_topic:
			continue
		browse_list.append(i)
	browse_index = 0
	browse_scroll = 0


func _input_browse(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		screen = Screen.HOME
		update()
		return
	if event.is_action_pressed("nav_left"):
		browse_filter = int((browse_filter - 1 + browse_filters.size()) % browse_filters.size())
		rebuild_browse()
		update()
		return
	if event.is_action_pressed("nav_right"):
		browse_filter = int((browse_filter + 1) % browse_filters.size())
		rebuild_browse()
		update()
		return
	if browse_list.size() == 0:
		return
	if event.is_action_pressed("nav_up"):
		browse_index = int(max(0, browse_index - 1))
		_clamp_browse_scroll()
		update()
	elif event.is_action_pressed("nav_down"):
		browse_index = int(min(browse_list.size() - 1, browse_index + 1))
		_clamp_browse_scroll()
		update()
	elif event.is_action_pressed("accept"):
		detail_index = int(browse_list[browse_index])
		detail_scroll = 0.0
		detail_from = Screen.BROWSE
		screen = Screen.DETAIL
		update()


const BROWSE_ROWS := 8
const BROWSE_ROW_H := 40.0

func _clamp_browse_scroll() -> void:
	if browse_index < browse_scroll:
		browse_scroll = browse_index
	elif browse_index >= browse_scroll + BROWSE_ROWS:
		browse_scroll = browse_index - BROWSE_ROWS + 1


func _draw_browse() -> void:
	ui.text(self, "词库浏览", Vector2(MARGIN, 32), 16, UIKit.TEXT)
	ui.text_right(self, "%d 个词" % browse_list.size(), W - MARGIN, 32, 12, UIKit.DIM)
	ui.hline(self, MARGIN, W - MARGIN, 46)

	# 筛选条
	var chip_x := MARGIN
	var label: String = browse_filters[browse_filter][0]
	var w := ui.draw_chip(self, "主题：" + label, Vector2(chip_x, 54), 12, UIKit.ACCENT)
	ui.text(self, "左右 切换", Vector2(chip_x + w + 10, 68), 11, UIKit.DIM)

	if browse_list.size() == 0:
		ui.text_center(self, "该主题下没有词", W * 0.5, 240, 15, UIKit.MUTED)
		_keybar([["B", "返回"]])
		return

	var top := 82.0
	for slot in range(BROWSE_ROWS):
		var idx := browse_scroll + slot
		if idx >= browse_list.size():
			break
		var row := int(browse_list[idx])
		var y := top + slot * BROWSE_ROW_H
		var rect := Rect2(MARGIN, y, CONTENT_W, BROWSE_ROW_H - 4)
		var selected := idx == browse_index
		if selected:
			ui.panel(self, rect, UIKit.PANEL_HI, UIKit.ACCENT)
		elif slot % 2 == 0:
			ui.panel(self, Rect2(MARGIN, y, CONTENT_W, BROWSE_ROW_H - 4), UIKit.PANEL, Color(0, 0, 0, 0))

		var word: String = repo.display_word(row)
		ui.text(self, word, Vector2(MARGIN + 12, y + 22), 16, UIKit.TEXT if selected else UIKit.MUTED, 150)
		var ipa_text: String = repo.phonetic(row)
		if ipa_text != "":
			ui.ipa(self, ipa_text, Vector2(MARGIN + 170, y + 21), 12, UIKit.DIM)
		ui.text(self, repo.brief_zh(row), Vector2(MARGIN + 300, y + 21), 13,
			UIKit.MUTED if selected else UIKit.DIM, 190)
		ui.draw_chip(self, repo.cefr(row), Vector2(W - MARGIN - 34, y + 9), 10, ui.cefr_color(repo.cefr(row)))

	_keybar([["上下", "浏览"], ["左右", "换主题"], ["A", "查看"], ["B", "返回"]])


# ---------------------------------------------------------------- 详情

func _input_detail(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		screen = detail_from
		update()
		return
	if event.is_action_pressed("accept") or event.is_action_pressed("act_y"):
		_play_word(detail_index)
		return
	if event.is_action_pressed("act_x"):
		_play_sentence(detail_index, false)
		return
	if event.is_action_pressed("act_l"):
		_play_sentence(detail_index, true)
		return
	if event.is_action_pressed("nav_down"):
		detail_scroll = min(detail_max_scroll, detail_scroll + 40.0)
		update()
	elif event.is_action_pressed("nav_up"):
		detail_scroll = max(0.0, detail_scroll - 40.0)
		update()


func _draw_detail() -> void:
	var row := detail_index
	if row < 0 or row >= repo.count:
		screen = detail_from
		return
	var entry: Dictionary = repo.entry(row)

	var head_f := ui.font(26)
	var head_word := repo.display_word(row)
	draw_string(head_f, Vector2(MARGIN, 84), head_word, UIKit.TEXT)
	var hw := head_f.get_string_size(head_word).x
	var has_voice := repo.has_audio(row)
	var vcol: Color = UIKit.ACCENT
	if not has_voice:
		vcol = UIKit.DIM
	elif audio.is_playing():
		vcol = UIKit.GOLD
	ui.speaker_button(self, Rect2(MARGIN + hw + 8, 62, 24, 24), vcol, has_voice and audio.is_playing())
	var ipa_text: String = repo.phonetic(row)
	if ipa_text != "":
		var x := MARGIN + hw + 40
		draw_string(ui.ipa_font(15), Vector2(x, 82), ipa_text, UIKit.MUTED)
	var cx := MARGIN
	cx += ui.draw_chip(self, repo.cefr(row), Vector2(cx, 94), 11, ui.cefr_color(repo.cefr(row))) + 6
	ui.draw_chip(self, repo.topic_label(row), Vector2(cx, 94), 11, UIKit.BLUE)

	var tex: Texture = repo.texture_for(row)
	if tex != null:
		draw_texture_rect(tex, Rect2(W - MARGIN - 118, 54, 118, 118), false)
	ui.hline(self, MARGIN, W - MARGIN, 128)

	var clip_top := 136.0
	var clip_bottom := H - 48.0
	var blocks := _detail_blocks(entry)
	var total := _measure_blocks(blocks, CONTENT_W)
	detail_max_scroll = max(0.0, total - (clip_bottom - clip_top))
	detail_scroll = clamp(detail_scroll, 0.0, detail_max_scroll)
	_draw_blocks(blocks, CONTENT_W, clip_top - detail_scroll, clip_top, clip_bottom)

	if detail_max_scroll > 0.0:
		var track := Rect2(W - 14, clip_top, 3, clip_bottom - clip_top)
		draw_rect(track, UIKit.PANEL, true)
		var ratio := (clip_bottom - clip_top) / total
		var knob_h: float = max(18.0, (clip_bottom - clip_top) * ratio)
		var knob_y := clip_top + (clip_bottom - clip_top - knob_h) * (detail_scroll / detail_max_scroll)
		draw_rect(Rect2(W - 14, knob_y, 3, knob_h), UIKit.DIM, true)

	_keybar([["上下", "滚动"], ["Y", "发音"], ["X", "例句①"], ["L1", "例句②"], ["B", "返回"]])


func _detail_blocks(entry: Dictionary) -> Array:
	var blocks := []
	var senses: Array = entry.get("senses", [])
	for sense in senses:
		var head := ("%s %s" % [sense.get("pos", ""), sense.get("zh", "")]).strip_edges()
		blocks.append(_blk(head, 16, UIKit.TEXT, 0, 0))
		var en := String(sense.get("en", ""))
		if en != "":
			blocks.append(_blk(en, 12, UIKit.DIM, 4, 3))
	blocks.append({"type": "gap", "h": 8.0})

	var examples: Array = entry.get("ex", [])
	if examples.size() > 0:
		blocks.append(_blk("例句", 12, UIKit.GOLD, 2, 0))
		for ex in examples:
			blocks.append(_blk(String(ex.get("en", "")), 14, UIKit.TEXT, 2, 0))
			if String(ex.get("zh", "")) != "":
				blocks.append(_blk(String(ex.get("zh", "")), 12, UIKit.MUTED, 6, 0))

	var cols: Array = entry.get("col", [])
	if cols.size() > 0:
		blocks.append({"type": "gap", "h": 6.0})
		blocks.append(_blk("搭配", 12, UIKit.GOLD, 2, 0))
		for c in cols:
			blocks.append(_blk(String(c).replace("｜", "："), 12, UIKit.MUTED, 1, 0))

	var fam: Array = entry.get("fam", [])
	if fam.size() > 0:
		blocks.append({"type": "gap", "h": 6.0})
		blocks.append(_blk("词族", 12, UIKit.GOLD, 2, 0))
		blocks.append(_blk(" · ".join(PoolStringArray(fam)), 12, UIKit.MUTED, 0, 0))

	var syn: Array = entry.get("syn", [])
	var ant: Array = entry.get("ant", [])
	if syn.size() > 0:
		blocks.append(_blk("近义  " + " · ".join(PoolStringArray(syn)), 12, UIKit.MUTED, 1, 0))
	if ant.size() > 0:
		blocks.append(_blk("反义  " + " · ".join(PoolStringArray(ant)), 12, UIKit.MUTED, 1, 0))

	var tip := String(entry.get("tip", ""))
	if tip != "":
		blocks.append({"type": "gap", "h": 6.0})
		blocks.append(_blk("提示", 12, UIKit.GOLD, 2, 0))
		blocks.append(_blk(tip, 12, UIKit.MUTED, 0, 0))

	var wid: String = repo.word_id(detail_index)
	if store.has_card(wid):
		var card: Dictionary = store.card_for(wid)
		var state_name: String = Srs.STATE_NAMES[int(card.get("state", 0))]
		var due_in := int(card.get("due", 0)) - int(OS.get_unix_time())
		var when := "现在" if due_in <= 0 else Srs.humanize(due_in) + "后"
		blocks.append({"type": "gap", "h": 8.0})
		blocks.append(_blk("学习状态  %s · 下次 %s · 复习 %d 次" % [
			state_name, when, int(card.get("reps", 0))], 11, UIKit.DIM, 0, 0))
	else:
		blocks.append({"type": "gap", "h": 8.0})
		blocks.append(_blk("还没学过这个词", 11, UIKit.DIM, 0, 0))
	return blocks


# ---------------------------------------------------------------- 授权

func _draw_credits() -> void:
	ui.text(self, "关于与授权", Vector2(MARGIN, 34), 20, UIKit.TEXT)
	ui.hline(self, MARGIN, W - MARGIN, 46)

	var body := [
		"本应用的学习内容改编自 Word Atlas（github.com/designfuchen/word-atlas）。",
		"",
		"内容署名：Word Atlas contributors — CC BY 4.0",
		"授权全文：creativecommons.org/licenses/by/4.0/",
		"代码授权：MIT License",
		"",
		"本应用做过的修改：",
		"1. 从上游 7,298 词中选取 %d 词（A1、A2 全量，B1 按主题均衡补齐）。" % repo.count,
		"2. 插画由 512×512 WebP 重新编码为 256×256 JPEG。",
		"3. 英音由 66kbps 转码为 32kbps 单声道。",
		"4. 界面由 React 网页重制为 Godot 3.5 掌机应用。",
		"5. 三维词星图降级为二维布局。",
		"",
		"上游声明：内容由 AI 模型生成（文本大语言模型、插画图像模型、录音 ElevenLabs 合成语音），经自动校验，未逐条人工审校，按现状提供，不作准确性担保。录音授权仅覆盖成品音频文件，不含底层声音模型或声音身份。本词表不是官方雅思词表，与雅思考试主办方无关。",
	]
	var y := 74.0
	for line in body:
		if line == "":
			y += 8
			continue
		var h := ui.paragraph(self, line, Vector2(MARGIN, y), CONTENT_W, 12, UIKit.MUTED, 3)
		y += h
	_keybar([["A/B", "返回"]])


# ---------------------------------------------------------------- 杂项

var _sample_row := -1
var _tone_player: AudioStreamPlayer
var _tone_pb: AudioStreamGeneratorPlayback
var _tone_until := 0
var _tone_t := 0.0


func _sample_row() -> int:
	if _sample_row >= 0:
		return _sample_row
	for i in range(repo.count):
		if repo.display_word(i) == "ability" and repo.has_audio(i):
			_sample_row = i
			return i
	for i in range(repo.count):
		if repo.has_audio(i):
			_sample_row = i
			return i
	_sample_row = 0
	return 0


func _play_sample() -> void:
	var row := _sample_row()
	toast("试听 " + repo.display_word(row))
	_play_word(row)
	_dbg("SAMPLE row=%d playing=%s bytes_ok=%s" % [row, str(audio.player.playing), str(repo.has_audio(row))])


# 音频自检：绕过 MP3，直接向 Master 推 3 秒正弦波
var _imp_player: AudioStreamPlayer


# 完全照 english-buddy：加载导入管线处理过的 mp3 资源
func _play_imported() -> void:
	var stream = load("res://assets/audio/test.mp3")
	_dbg("IMPORTED stream_null=%s" % str(stream == null))
	if stream == null:
		toast("导入资源加载失败")
		return
	if _imp_player == null:
		_imp_player = AudioStreamPlayer.new()
		add_child(_imp_player)
	_imp_player.stream = stream
	_imp_player.play()
	toast("导入资源测试")
	_dbg("IMPORTED playing=%s len=%s" % [str(_imp_player.playing), str(stream.get_length())])


func _play_tone() -> void:
	if _tone_player == null:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 44100.0
		gen.buffer_length = 0.4
		_tone_player = AudioStreamPlayer.new()
		_tone_player.stream = gen
		_tone_player.bus = "Master"
		add_child(_tone_player)
	_tone_player.play()
	_tone_pb = _tone_player.get_stream_playback()
	_tone_t = 0.0
	_tone_until = OS.get_ticks_msec() + 3000
	toast("音频自检：3 秒嘟嘟声")
	_dbg("TONE start pb_null=%s inside=%s" % [str(_tone_pb == null), str(_tone_player.is_inside_tree())])
	print("[AUD] tone start pb_null=", _tone_pb == null,
		" mute=", AudioServer.is_bus_mute(0))


var _dbg_budget := 600


func _dbg(msg: String) -> void:
	if _dbg_budget <= 0:
		return
	_dbg_budget -= 1
	var f := File.new()
	if f.open("user://dbg.txt", File.READ_WRITE) != OK:
		if f.open("user://dbg.txt", File.WRITE) != OK:
			return
	else:
		f.seek_end()
	f.store_line(msg)
	f.flush()
	f.close()


func _cap_w(k: String, f: Font) -> float:
	return max(26.0, f.get_string_size(k).x + 16.0)


# 底栏按键条：每个键画成一个方块，方块右边直接写这个键干什么
func _keybar(items: Array) -> void:
	ui.hline(self, MARGIN, W - MARGIN, 436.0)
	var lf := ui.font(15)
	var kf := ui.font(12)
	var cap_h := 21.0
	var gap := 16.0
	var total := 0.0
	for it in items:
		total += _cap_w(String(it[0]), kf) + 6.0 + lf.get_string_size(String(it[1])).x + gap
	total -= gap
	var x := MARGIN + max(0.0, (CONTENT_W - total) * 0.5)
	var top := 444.0
	for it in items:
		var k := String(it[0])
		var label := String(it[1])
		var kw := _cap_w(k, kf)
		draw_rect(Rect2(x, top, kw, cap_h), UIKit.PANEL_HI, true)
		draw_rect(Rect2(x, top, kw, cap_h), UIKit.ACCENT, false, 1.0)
		draw_string(kf, Vector2(x + (kw - kf.get_string_size(k).x) * 0.5, top + 14), k, UIKit.ACCENT)
		x += kw + 6.0
		draw_string(lf, Vector2(x, top + 14), label, UIKit.TEXT)
		x += lf.get_string_size(label).x + gap


func _play_word(row: int) -> void:
	_dbg("PLAY_WORD row=%d has_audio=%s" % [row, str(repo.has_audio(row))])
	if row < 0:
		return
	if repo.has_audio(row):
		audio.play(row)
	else:
		toast("该词暂无发音")


# 在单词右边画一个可见的喇叭按钮；放不下就落到单词正下方。
# 播放中高亮，让「按了有没有反应」一眼可见。
func _speaker_beside(row: int, word_w: float, baseline: float, _fsize: int, isize: float) -> void:
	var has_voice := repo.has_audio(row)
	var col: Color = UIKit.ACCENT if has_voice else UIKit.DIM
	var playing: bool = has_voice and audio.is_playing()
	if playing:
		col = UIKit.GOLD
	var bx := W * 0.5 + word_w * 0.5 + 12.0
	var by := baseline - isize * 0.86
	if bx + isize > W - MARGIN:
		bx = W * 0.5 - isize * 0.5
		by = baseline + 8.0
	ui.speaker_button(self, Rect2(bx, by, isize, isize), col, playing)


func _play_sentence(row: int, second: bool) -> void:
	if row < 0:
		return
	var ok := repo.has_sentence2(row) if second else repo.has_sentence(row)
	if ok:
		audio.play_sentence(row, second)
	else:
		toast("该词暂无例句音频")


func toast(text: String) -> void:
	toast_text = text
	toast_until = OS.get_ticks_msec() + 2400
	update()


func _process(_delta: float) -> void:
	if toast_text != "" and OS.get_ticks_msec() > toast_until:
		toast_text = ""
		update()
	if _tone_pb == null:
		return
	if OS.get_ticks_msec() > _tone_until:
		_tone_player.stop()
		_tone_pb = null
		print("[AUD] tone done")
		return
	var n := _tone_pb.get_frames_available()
	for _i in range(n):
		_tone_t += 1.0 / 44100.0
		var v := sin(_tone_t * TAU * 660.0) * 0.3
		_tone_pb.push_frame(Vector2(v, v))


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), UIKit.BG, true)
	match screen:
		Screen.HOME:
			_draw_home()
		Screen.REVIEW:
			_draw_review()
		Screen.ATLAS:
			_draw_atlas()
		Screen.BROWSE:
			_draw_browse()
		Screen.DETAIL:
			_draw_detail()
		Screen.CREDITS:
			_draw_credits()

	if toast_text != "":
		var f := ui.font(13)
		var w := f.get_string_size(toast_text).x + 28
		var rect := Rect2((W - w) * 0.5, H - 78, w, 30)
		draw_rect(rect, UIKit.PANEL_HI, true)
		draw_rect(rect, UIKit.ACCENT, false, 1.0)
		draw_string(f, Vector2(rect.position.x + 14, rect.position.y + 20), toast_text, UIKit.TEXT)

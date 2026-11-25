extends Node
class_name ProgressStore

signal changed

# 学习进度存档。写入走 tmp -> 原子替换，避免掌机断电把档写坏。

const SAVE_PATH := "user://word_atlas_profile.json"
const TEMP_PATH := "user://word_atlas_profile.tmp"
const BACKUP_PATH := "user://word_atlas_profile.bak"

const NEW_PER_DAY := 15

var data: Dictionary = {}
var srs: Srs
var repo: ContentRepository


func _ready() -> void:
	srs = Srs.new()
	load_game()


func default_data() -> Dictionary:
	return {
		"v": 1,
		"cards": {},
		"streak": 0,
		"lastDay": "",
		"totalReviews": 0,
		"newToday": 0,
		"newDay": "",
		"settings": {"audio": true},
		"cursor": 0,
	}


func load_game() -> void:
	data = default_data()
	var file := File.new()
	for path in [SAVE_PATH, BACKUP_PATH]:
		if file.file_exists(path) and file.open(path, File.READ) == OK:
			var parsed = JSON.parse(file.get_as_text())
			file.close()
			if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY \
					and int(parsed.result.get("v", 0)) == 1:
				var loaded: Dictionary = parsed.result
				for key in loaded:
					data[key] = loaded[key]
				_roll_day()
				emit_signal("changed")
				return


func save_game() -> void:
	var file := File.new()
	if file.open(TEMP_PATH, File.WRITE) != OK:
		push_error("无法写入存档")
		return
	file.store_string(JSON.print(data))
	file.close()
	var dir := Directory.new()
	if file.file_exists(SAVE_PATH):
		dir.remove(BACKUP_PATH)
		dir.rename(SAVE_PATH, BACKUP_PATH)
	if dir.rename(TEMP_PATH, SAVE_PATH) != OK:
		if file.file_exists(BACKUP_PATH):
			dir.rename(BACKUP_PATH, SAVE_PATH)
		push_error("存档替换失败")
		return
	emit_signal("changed")


# ---------------------------------------------------------------- 卡片

func card_for(wid: String) -> Dictionary:
	if not data["cards"].has(wid):
		return {}
	return data["cards"][wid]


func ensure_card(wid: String) -> Dictionary:
	if not data["cards"].has(wid):
		data["cards"][wid] = srs.new_card(int(OS.get_unix_time()))
	return data["cards"][wid]


func has_card(wid: String) -> bool:
	return data["cards"].has(wid)


func review(wid: String, rating: int, now: int) -> Dictionary:
	var is_first_time: bool = not data["cards"].has(wid)
	var card := ensure_card(wid)
	if is_first_time:
		_roll_day()
		data["newToday"] = int(data["newToday"]) + 1
	var next_card: Dictionary = srs.schedule(card, rating, now)
	data["cards"][wid] = next_card
	data["totalReviews"] = int(data["totalReviews"]) + 1
	_touch_day()
	save_game()
	return next_card


func due_words(limit := 999) -> Array:
	var now := int(OS.get_unix_time())
	var out := []
	for wid in data["cards"]:
		var card: Dictionary = data["cards"][wid]
		if int(card.get("due", 0)) <= now:
			out.append(wid)
	out.sort()
	if out.size() > limit:
		out.resize(limit)
	return out


func due_count() -> int:
	var now := int(OS.get_unix_time())
	var n := 0
	for wid in data["cards"]:
		if int(data["cards"][wid].get("due", 0)) <= now:
			n += 1
	return n


func learned_count() -> int:
	return int(data["cards"].size())


func new_remaining_today() -> int:
	_roll_day()
	return int(max(0, NEW_PER_DAY - int(data["newToday"])))


# 今日复习队列：先到期的旧卡，再补新词。
func build_queue() -> Array:
	var queue := due_words()
	var budget := new_remaining_today()
	if budget > 0 and repo != null:
		var seen := {}
		for wid in data["cards"]:
			seen[wid] = true
		var now := int(OS.get_unix_time())
		for i in range(repo.count):
			if budget <= 0:
				break
			var wid: String = repo.word_id(i)
			if seen.has(wid):
				continue
			# 新卡也允许提前进队，标记为 new
			queue.append(wid)
			budget -= 1
	return queue


func mark_introduced(wid: String) -> void:
	data["cards"][wid] = srs.new_card(int(OS.get_unix_time()))
	_roll_day()
	data["newToday"] = int(data["newToday"]) + 1
	save_game()


func is_new(wid: String) -> bool:
	return not data["cards"].has(wid)


# ---------------------------------------------------------------- 统计

func streak() -> int:
	_roll_day()
	return int(data["streak"])


func total_reviews() -> int:
	return int(data["totalReviews"])


func _roll_day() -> void:
	var today := _today()
	if String(data.get("newDay", "")) != today:
		data["newDay"] = today
		data["newToday"] = 0


func _touch_day() -> void:
	var today := _today()
	if String(data.get("lastDay", "")) == today:
		return
	var yesterday := _day_string(int(OS.get_unix_time()) - 86400)
	data["streak"] = int(data["streak"]) + 1 if String(data.get("lastDay", "")) == yesterday else 1
	data["lastDay"] = today


func _today() -> String:
	return _day_string(int(OS.get_unix_time()))


func _day_string(stamp: int) -> String:
	var d := OS.get_datetime_from_unix_time(stamp)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


# ---------------------------------------------------------------- 设置

func audio_enabled() -> bool:
	return bool(data["settings"].get("audio", true))


func set_audio(enabled: bool) -> void:
	data["settings"]["audio"] = enabled
	AudioServer.set_bus_mute(0, not enabled)
	save_game()


func reset() -> void:
	data = default_data()
	save_game()

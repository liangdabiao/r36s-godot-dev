extends SceneTree

# 上机/桌面验收：数据完整性、FSRS 排程、存档往返。
# 结果写到 user://smoke_result.txt，全部通过时打印 PASS。

var failures := []
var checks := 0


func _init() -> void:
	var lf := File.new()
	lf.open("user://smoke_result.txt", File.WRITE)

	_check_index(lf)
	_check_entries(lf)
	_check_media(lf)
	_check_srs(lf)
	_check_save(lf)

	lf.store_line("")
	lf.store_line("CHECKS %d  FAILURES %d" % [checks, failures.size()])
	lf.store_line("PASS" if failures.size() == 0 else "FAIL")
	lf.close()
	quit()


func _ok(lf: File, name: String, detail: String) -> void:
	checks += 1
	lf.store_line("  OK   %s  %s" % [name, detail])


func _fail(lf: File, name: String, detail: String) -> void:
	checks += 1
	failures.append(name)
	lf.store_line("  FAIL %s  %s" % [name, detail])


func _load_json(path: String):
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return null
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK:
		return null
	return parsed.result


func _check_index(lf: File) -> void:
	lf.store_line("[index]")
	var idx = _load_json("res://data/index.json")
	if idx == null:
		_fail(lf, "index", "无法解析")
		return
	var rows: Array = idx["words"]
	if rows.size() == 3000:
		_ok(lf, "词数", "3000")
	else:
		_fail(lf, "词数", str(rows.size()))
	if idx["chunk"] == 100 and idx["cefr"].size() == 6:
		_ok(lf, "元数据", "chunk=100 cefr=6")
	else:
		_fail(lf, "元数据", "字段异常")
	var no_media := 0
	var empty_zh := 0
	var seen := {}
	var dup := 0
	for r in rows:
		if int(r[6]) != 3:
			no_media += 1
		if String(r[2]) == "":
			empty_zh += 1
		if seen.has(r[0]):
			dup += 1
		seen[r[0]] = true
	if no_media == 0:
		_ok(lf, "媒体标记", "全部带图+音")
	else:
		_fail(lf, "媒体标记", "%d 条缺媒体" % no_media)
	if empty_zh == 0:
		_ok(lf, "中文释义", "无空值")
	else:
		_fail(lf, "中文释义", "%d 条为空" % empty_zh)
	if dup == 0:
		_ok(lf, "词条唯一", "无重复 id")
	else:
		_fail(lf, "词条唯一", "%d 条重复" % dup)


func _check_entries(lf: File) -> void:
	lf.store_line("[entries]")
	var missing := 0
	var no_sense := 0
	var no_ex := 0
	for c in range(30):
		var chunk = _load_json("res://data/chunks/%02d.json" % c)
		if chunk == null:
			missing += 1
			continue
		for e in chunk:
			if e.get("senses", []).size() == 0:
				no_sense += 1
			if e.get("ex", []).size() == 0:
				no_ex += 1
	if missing == 0:
		_ok(lf, "词条块", "30 块全部可解析")
	else:
		_fail(lf, "词条块", "%d 块缺失" % missing)
	if no_sense == 0:
		_ok(lf, "释义", "每条都有义项")
	else:
		_fail(lf, "释义", "%d 条无义项" % no_sense)
	if no_ex == 0:
		_ok(lf, "例句", "每条都有例句")
	else:
		_fail(lf, "例句", "%d 条无例句" % no_ex)


func _check_media(lf: File) -> void:
	lf.store_line("[media]")
	var idx = _load_json("res://data/index.json")
	var rows: Array = idx["words"]
	var sample := [0, 777, 1500, 2222, 2999]
	for i in sample:
		var wid := String(rows[i][0])
		var f := File.new()
		var img_ok := f.open("res://raw/img/%s.jpgraw" % wid, File.READ) == OK
		var img_size := 0
		var decoded := false
		if img_ok:
			var bytes := f.get_buffer(f.get_len())
			img_size = bytes.size()
			f.close()
			var img := Image.new()
			decoded = img.load_jpg_from_buffer(bytes) == OK and img.get_width() == 256
		var f2 := File.new()
		var aud_ok := f2.open("res://raw/aud/%s.mp3raw" % wid, File.READ) == OK
		var aud_size := 0
		if aud_ok:
			aud_size = f2.get_len()
			f2.close()
		if img_ok and decoded and aud_ok and aud_size > 0:
			_ok(lf, "样本 " + wid, "jpg %dB 256px / mp3 %dB" % [img_size, aud_size])
		else:
			_fail(lf, "样本 " + wid, "img=%s dec=%s aud=%s" % [
				str(img_ok), str(decoded), str(aud_ok)])


func _check_srs(lf: File) -> void:
	lf.store_line("[srs]")
	var srs := Srs.new()
	var now := 1767258000
	var card := srs.new_card(now)

	card = srs.schedule(card, Srs.RATING_GOOD, now)
	if int(card["state"]) == Srs.STATE_LEARNING:
		_ok(lf, "新卡 Good", "进入学习中")
	else:
		_fail(lf, "新卡 Good", "state=%d" % int(card["state"]))

	card = srs.schedule(card, Srs.RATING_GOOD, now + 600)
	if int(card["state"]) == Srs.STATE_REVIEW and int(card["interval"]) >= 1:
		_ok(lf, "学习毕业", "interval=%d 天" % int(card["interval"]))
	else:
		_fail(lf, "学习毕业", "state=%d interval=%d" % [int(card["state"]), int(card["interval"])])

	var interval_before := int(card["interval"])
	card = srs.schedule(card, Srs.RATING_GOOD, now + 600 + interval_before * 86400)
	if int(card["interval"]) > interval_before:
		_ok(lf, "间隔递增", "%d -> %d" % [interval_before, int(card["interval"])])
	else:
		_fail(lf, "间隔递增", "%d -> %d" % [interval_before, int(card["interval"])])

	# 遗忘必须降低稳定度
	var s_before := float(card["stability"])
	card = srs.schedule(card, Srs.RATING_AGAIN, int(card["due"]))
	if float(card["stability"]) < s_before and int(card["state"]) == Srs.STATE_RELEARNING:
		_ok(lf, "遗忘重学", "s %.3f -> %.3f" % [s_before, float(card["stability"])])
	else:
		_fail(lf, "遗忘重学", "s %.3f -> %.3f state=%d" % [
			s_before, float(card["stability"]), int(card["state"])])

	# 记忆强度应在 0..1
	var r := srs.retrievability(card, int(card["due"]))
	if r >= 0.0 and r <= 1.0:
		_ok(lf, "记忆强度", "%.3f" % r)
	else:
		_fail(lf, "记忆强度", "%.3f 越界" % r)


func _check_save(lf: File) -> void:
	lf.store_line("[save]")
	var path := "user://smoke_profile.json"
	var payload := {
		"v": 1,
		"cards": {"ability": {"stability": 2.5, "difficulty": 5.0, "state": 2,
			"due": 1767258000, "last": 1767258000, "reps": 3, "lapses": 0, "interval": 3}},
		"streak": 4, "lastDay": "2026-11-25", "totalReviews": 12,
		"newToday": 3, "newDay": "2026-11-25", "settings": {"audio": true}, "cursor": 0,
	}
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		_fail(lf, "写入", "打不开")
		return
	f.store_string(JSON.print(payload))
	f.close()

	var back = _load_json(path)
	if back != null and back["cards"]["ability"]["stability"] == 2.5 and int(back["streak"]) == 4:
		_ok(lf, "存档往返", "卡片与统计一致")
	else:
		_fail(lf, "存档往返", "内容不一致")
	var d := Directory.new()
	d.remove(path)

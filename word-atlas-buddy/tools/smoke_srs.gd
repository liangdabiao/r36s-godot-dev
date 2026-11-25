extends SceneTree

# FSRS 对拍：用与 tools/make_ref.js 完全相同的复习序列跑一遍，
# 把 stability / difficulty / state 写进日志，交给 Python 比对。

const START := 1767258000
const SEQ := [
	[0, 3],
	[600, 3],
	[3 * 86400, 3],
	[7 * 86400, 1],
	[600, 3],
	[12 * 86400, 2],
	[30 * 86400, 4],
	[90 * 86400, 3],
	[200 * 86400, 1],
	[600, 3],
	[5 * 86400, 4],
]


func _init() -> void:
	var lf := File.new()
	lf.open("res://.cache/srs_check.txt", File.WRITE)
	lf.store_line("start")

	var srs := Srs.new()
	var now := START
	var card := srs.new_card(now)
	lf.store_line("0|0|0.0|0.0|0|0")

	for i in range(SEQ.size()):
		var delta: int = SEQ[i][0]
		var grade: int = SEQ[i][1]
		now += delta
		card = srs.schedule(card, grade, now)
		var interval := int(card.get("interval", 0))
		lf.store_line("%d|%d|%s|%s|%d|%d" % [
			i + 1,
			grade,
			String(str(card["stability"])),
			String(str(card["difficulty"])),
			int(card["state"]),
			interval,
		])
		lf.flush()

	lf.store_line("end")
	lf.close()
	quit()

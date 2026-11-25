extends SceneTree

# 本机复现：完全走 App 用的那条播放通路（AudioDirector.play）
# 只验证 player.play() 之后 playing 是否变 true、播放位置是否推进。

var audio
var row := -1
var started := 0
var step := 0


func _init() -> void:
	var repo = load("res://scripts/ContentRepository.gd").new()
	get_root().add_child(repo)
	if not repo.load_index():
		print("LOAD_INDEX_FAIL")
		quit()
		return
	audio = load("res://scripts/AudioDirector.gd").new()
	get_root().add_child(audio)
	audio.repo = repo

	for i in range(repo.count):
		if repo.has_audio(i):
			row = i
			break
	print("row=", row, " wid=", repo.word_id(row), " bytes=", repo.audio_bytes(row).size())
	audio.play(row)
	print("AFTER_PLAY playing=", audio.player.playing,
		" inside=", audio.player.is_inside_tree(),
		" stream_null=", audio.player.stream == null,
		" len=", audio.player.stream.get_length() if audio.player.stream != null else -1,
		" bus=", audio.player.bus,
		" mute=", AudioServer.is_bus_mute(0),
		" vol=", AudioServer.get_bus_volume_db(0))
	started = OS.get_ticks_msec()


func _idle(_delta: float) -> bool:
	var el := OS.get_ticks_msec() - started
	if step == 0 and el > 400:
		step = 1
		print("T+400ms playing=", audio.player.playing,
			" pos=", audio.player.get_playback_position())
	elif step == 1 and el > 1200:
		print("T+1200ms playing=", audio.player.playing,
			" pos=", audio.player.get_playback_position())
		print("PLAY_CHECK_DONE")
		quit()
	return false

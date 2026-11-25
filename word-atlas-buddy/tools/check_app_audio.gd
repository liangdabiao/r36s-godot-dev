extends SceneTree

# 验证：真实场景 Main.tscn 实例化后，走 App._play_word 这条路能不能出声
# （前面 check_play.gd 是手动注入 repo，掩盖了 App 漏设 audio.repo 的 bug，所以这里用真场景）

var app
var started := 0
var step := 0


func _init() -> void:
	var scn = load("res://scenes/Main.tscn")
	app = scn.instance()
	get_root().add_child(app)
	print("repo_null=", app.audio.repo == null, " rows=", app.repo.count)
	app._play_word(0)
	print("AFTER_PLAY playing=", app.audio.player.playing,
		" len=", app.audio.player.stream.get_length() if app.audio.player.stream != null else -1)
	started = OS.get_ticks_msec()


func _idle(_delta: float) -> bool:
	var el := OS.get_ticks_msec() - started
	if step == 0 and el > 450:
		step = 1
		print("T+450 playing=", app.audio.player.playing,
			" pos=", app.audio.player.get_playback_position())
	elif step == 1 and el > 1400:
		print("APP_AUDIO_DONE")
		quit()
	return false

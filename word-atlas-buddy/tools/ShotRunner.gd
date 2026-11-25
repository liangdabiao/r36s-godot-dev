extends Node

# 帧计数状态机式截图器：比 yield 协程稳，每步固定等待帧数。

var steps: Array = []
var index := 0
var wait := 0
var frames := 0
var log_file: File


func _ready() -> void:
	var dir := Directory.new()
	if not dir.dir_exists("user://shots"):
		dir.make_dir_recursive("user://shots")
	log_file = File.new()
	log_file.open("user://shot_progress.txt", File.WRITE)
	_log("runner ready")
	steps = []
	steps += [["wait", 18], ["shot", "01_home"]]

	steps += [["press", "accept"], ["wait", 5], ["shot", "02_review_front"]]
	steps += [["press", "accept"], ["wait", 5], ["shot", "03_review_back"]]
	steps += [["press", "accept"], ["wait", 5], ["shot", "04_review_next"]]
	steps += _home()

	steps += [["press", "nav_down"], ["press", "accept"], ["wait", 8], ["shot", "05_atlas"]]
	steps += [["press", "nav_right"], ["press", "nav_up"], ["wait", 5], ["shot", "06_atlas_moved"]]
	steps += [["press", "accept"], ["wait", 5], ["shot", "07_atlas_detail"]]
	steps += [["press", "cancel"], ["press", "cancel"]]
	steps += _home()

	steps += [["press", "nav_down"], ["press", "nav_down"], ["press", "accept"],
		["wait", 6], ["shot", "08_browse"]]
	steps += [["press", "nav_down"], ["press", "nav_down"], ["press", "accept"],
		["wait", 5], ["shot", "09_browse_detail"]]
	steps += [["press", "cancel"], ["press", "cancel"]]
	steps += _home()

	steps += [["press", "nav_down"], ["press", "nav_down"], ["press", "nav_down"],
		["press", "accept"], ["wait", 6], ["shot", "10_credits"]]
	set_process(true)


func _home() -> Array:
	# 回首页并把菜单光标压回顶部，避免多次流程后菜单漂移
	var out := []
	# 先退出当前界面（复习/星图/详情/Browse 都能用 cancel 退），再把菜单光标压回顶部
	for i in range(3):
		out.append(["press", "cancel"])
	for i in range(5):
		out.append(["press", "nav_up"])
	return out
	return out


func _log(msg: String) -> void:
	if log_file != null:
		log_file.store_line(msg)
		log_file.flush()


func _process(_delta: float) -> void:
	frames += 1
	if frames > 1200:
		_log("FRAME CAP HIT at index=%d" % index)
		_close()
		return
	if wait > 0:
		wait -= 1
		return
	if index >= steps.size():
		_log("DONE all steps")
		_close()
		return
	var step: Array = steps[index]
	index += 1
	match String(step[0]):
		"wait":
			wait = int(step[1])
		"press":
			_press(String(step[1]))
			wait = 2
		"shot":
			_capture(String(step[1]))
			wait = 2
		"end":
			_log("DONE")
			_close()


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _capture(name: String) -> void:
	var img: Image = get_viewport().get_texture().get_data()
	img.flip_y()
	var path := "user://shots/" + name + ".png"
	_log("SHOT %s -> %s" % [name, str(img.save_png(path))])


func _close() -> void:
	if log_file != null:
		log_file.close()
		log_file = null
	get_tree().quit()

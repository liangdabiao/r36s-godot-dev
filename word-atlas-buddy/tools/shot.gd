extends SceneTree

# 启动主场景并挂上截图器。

var lf: File


func _stage(msg: String) -> void:
	if lf != null:
		lf.store_line(msg)
		lf.flush()


func _init() -> void:
	lf = File.new()
	lf.open("user://shot_stage.txt", File.WRITE)
	_stage("init ok")
	call_deferred("_run")


func _run() -> void:
	_stage("run start root=%s" % str(root))
	change_scene("res://scenes/Main.tscn")
	for i in range(4):
		yield(self, "idle_frame")
	_stage("scene changed, current=%s" % str(current_scene))
	var runner := Node.new()
	runner.name = "ShotRunner"
	var script = load("res://tools/ShotRunner.gd")
	_stage("script loaded=%s" % str(script))
	runner.set_script(script)
	root.add_child(runner)
	_stage("runner added")

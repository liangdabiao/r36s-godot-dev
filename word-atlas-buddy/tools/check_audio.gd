extends SceneTree

# 校验 raw/aud 里的 mp3raw 能被 AudioStreamMP3 正确解码。

func _init() -> void:
	var dir := Directory.new()
	var ok := 0
	var bad := 0
	var sample := ""
	if dir.open("res://raw/aud") == OK:
		dir.list_dir_begin(true, true)
		var n := 0
		while true:
			var f := dir.get_next()
			if f == "":
				break
			if not f.ends_with(".mp3raw"):
				continue
			n += 1
			if n > 5:
				break
			var file := File.new()
			if file.open("res://raw/aud/" + f, File.READ) != OK:
				print("OPEN_FAIL ", f)
				bad += 1
				continue
			var bytes := file.get_buffer(file.get_len())
			file.close()
			var s := AudioStreamMP3.new()
			s.data = bytes
			var ln := s.get_length()
			if ln > 0.05:
				ok += 1
				if sample == "":
					sample = "%s len=%.2f bytes=%d" % [f, ln, bytes.size()]
			else:
				bad += 1
				print("BAD ", f, " len=", ln, " bytes=", bytes.size())
		dir.list_dir_end()
	print("AUDIO_OK=", ok, " BAD=", bad)
	print("SAMPLE ", sample)
	quit()

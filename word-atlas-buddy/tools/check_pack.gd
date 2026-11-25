extends SceneTree

# 从 PCK 内部验证：索引、词条块、原始 JPEG、原始 MP3 是否都能读出来。

func _init() -> void:
	var lf := File.new()
	lf.open("user://pack_check.txt", File.WRITE)

	var f := File.new()
	var err := f.open("res://data/index.json", File.READ)
	lf.store_line("index open=%d" % err)
	if err == OK:
		var parsed = JSON.parse(f.get_as_text())
		f.close()
		lf.store_line("index error=%d words=%d" % [parsed.error, parsed.result["words"].size()])

	f = File.new()
	err = f.open("res://data/chunks/00.json", File.READ)
	if err == OK:
		var parsed2 = JSON.parse(f.get_as_text())
		f.close()
		lf.store_line("chunk00 entries=%d" % parsed2.result.size())

	var wid := "ability"
	f = File.new()
	err = f.open("res://raw/img/%s.jpgraw" % wid, File.READ)
	lf.store_line("img open=%d" % err)
	if err == OK:
		var bytes := f.get_buffer(f.get_len())
		f.close()
		var img := Image.new()
		var derr := img.load_jpg_from_buffer(bytes)
		lf.store_line("img bytes=%d decode=%d size=%dx%d" % [
			bytes.size(), derr, img.get_width(), img.get_height()])

	f = File.new()
	err = f.open("res://raw/aud/%s.mp3raw" % wid, File.READ)
	lf.store_line("aud open=%d" % err)
	if err == OK:
		var abuf := f.get_buffer(f.get_len())
		f.close()
		var stream := AudioStreamMP3.new()
		stream.data = abuf
		lf.store_line("aud bytes=%d length=%.2f" % [abuf.size(), stream.get_length()])

	f = File.new()
	err = f.open("res://assets/fonts/ui.ttf", File.READ)
	lf.store_line("font open=%d" % err)
	if err == OK:
		f.close()

	lf.store_line("END")
	lf.close()

	quit()

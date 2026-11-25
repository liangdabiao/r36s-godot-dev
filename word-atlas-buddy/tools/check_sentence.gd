extends SceneTree

# 校验例句音频：索引位 + 文件可读 + 能解成 AudioStreamMP3。

func _init() -> void:
	var repo: ContentRepository = ContentRepository.new()
	root.add_child(repo)
	var ok := repo.load_index()
	print("index=", ok, " count=", repo.count)
	var n_ex := 0
	var n_ex2 := 0
	var shown := 0
	for i in range(min(50, repo.count)):
		if repo.has_sentence(i):
			n_ex += 1
			var b: PoolByteArray = repo.sentence_bytes(i)
			if b.size() > 0 and shown < 2:
				var s := AudioStreamMP3.new()
				s.data = b
				print("EX ", repo.word_id(i), " bytes=", b.size(), " len=", s.get_length())
				shown += 1
		if repo.has_sentence2(i):
			n_ex2 += 1
			var b2: PoolByteArray = repo.sentence2_bytes(i)
			if b2.size() > 0 and shown < 4:
				var s2 := AudioStreamMP3.new()
				s2.data = b2
				print("EX2 ", repo.word_id(i), " bytes=", b2.size(), " len=", s2.get_length())
				shown += 1
	print("前 50 词：ex=", n_ex, " ex2=", n_ex2)
	quit()

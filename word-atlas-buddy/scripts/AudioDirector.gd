extends Node
class_name AudioDirector

# 直接从 PCK 里的原始 MP3 字节构造 AudioStreamMP3，不走导入管线。
# 三类音源：单词英音、例句①、例句②（上游 ElevenLabs 预生成，64kbps 单声道）。

const CACHE_LIMIT := 24

var player: AudioStreamPlayer
var repo: ContentRepository
var _cache := {}
var _order := []
var _current := ""
var _last_bytes := 0
var _dbg_budget := 200


func _log(msg: String) -> void:
	if _dbg_budget <= 0:
		return
	_dbg_budget -= 1
	var f := File.new()
	if f.open("user://aud.txt", File.READ_WRITE) != OK:
		if f.open("user://aud.txt", File.WRITE) != OK:
			return
	else:
		f.seek_end()
	f.store_line(msg)
	f.flush()
	f.close()


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Master"
	add_child(player)


func play(i: int) -> void:
	_play(i, "word")


func play_sentence(i: int, second := false) -> void:
	_play(i, "ex2" if second else "ex")


func stop() -> void:
	player.stop()
	_current = ""


func is_playing() -> bool:
	return player.playing


func _play(i: int, kind: String) -> void:
	if repo == null:
		print("[AUD] repo is null")
		return
	var key := kind + ":" + repo.word_id(i)
	if key == _current and player.playing:
		print("[AUD] toggle-off ", key)
		player.stop()
		_current = ""
		return
	var stream := _stream_for(i, key, kind)
	if stream == null:
		print("[AUD] NO_STREAM ", key, " bytes=0")
		return
	_log("PRE key=%s inside=%s pnull=%s len=%s type=%s" % [
		key, str(player.is_inside_tree()), str(player == null),
		str(stream.get_length()), stream.get_class()])
	player.stream = stream
	player.play()
	_current = key
	_log("POST playing=%s active_stream=%s bus=%s mute=%s vol=%s" % [
		str(player.playing), str(player.stream != null), player.bus,
		str(AudioServer.is_bus_mute(0)), str(AudioServer.get_bus_volume_db(0))])
	print("[AUD] play ", key, " bytes=", _last_bytes, " playing=", player.playing,
		" mute=", AudioServer.is_bus_mute(0), " vol_db=", AudioServer.get_bus_volume_db(0))


func _stream_for(i: int, key: String, kind: String) -> AudioStreamMP3:
	if _cache.has(key):
		_touch(key)
		return _cache[key]
	var bytes := PoolByteArray()
	match kind:
		"word":
			bytes = repo.audio_bytes(i)
		"ex2":
			bytes = repo.sentence2_bytes(i)
		_:
			bytes = repo.sentence_bytes(i)
	_log("BYTES kind=%s size=%s" % [kind, str(bytes.size())])
	if bytes.size() == 0:
		_last_bytes = 0
		return null
	_last_bytes = bytes.size()
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	_cache[key] = stream
	_touch(key)
	return stream


func _touch(key: String) -> void:
	_order.erase(key)
	_order.push_back(key)
	while _order.size() > CACHE_LIMIT:
		_cache.erase(_order.pop_front())

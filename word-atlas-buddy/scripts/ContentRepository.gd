extends Node
class_name ContentRepository

# 词库访问层：索引常驻，词条块与图片按需加载并做 LRU。

const INDEX_PATH := "res://data/index.json"
const CHUNK_FMT := "res://data/chunks/%02d.json"
const IMG_FMT := "res://raw/img/%s.jpgraw"
const AUD_FMT := "res://raw/aud/%s.mp3raw"
const EX_FMT := "res://raw/ex/%s.mp3raw"
const EX2_FMT := "res://raw/ex2/%s.mp3raw"

const CHUNK_CACHE := 2      # 同时驻留的词条块数（每块 100 词）
const TEX_CACHE := 20       # 同时驻留的插画数（256x256 RGB8 ≈ 190 KB/张）

var index: Dictionary = {}
var rows: Array = []
var count := 0
var cefr_names: Array = []
var topics: Array = []
var ready := false

var _chunks := {}
var _chunk_order := []
var _textures := {}
var _tex_order := []


func load_index() -> bool:
	var file := File.new()
	if file.open(INDEX_PATH, File.READ) != OK:
		push_error("缺少 " + INDEX_PATH)
		return false
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK:
		push_error("索引解析失败: " + str(parsed.error_string))
		return false
	index = parsed.result
	rows = index["words"]
	count = rows.size()
	cefr_names = index["cefr"]
	topics = index["topics"]
	ready = true
	return true


# ---------------------------------------------------------------- 索引行

func word_id(i: int) -> String:
	return rows[i][0]


func display_word(i: int) -> String:
	return rows[i][1]


func brief_zh(i: int) -> String:
	return rows[i][2]


func phonetic(i: int) -> String:
	return rows[i][3]


func cefr(i: int) -> String:
	return cefr_names[rows[i][4]]


func topic_key(i: int) -> String:
	return topics[rows[i][5]][0]


func topic_label(i: int) -> String:
	return topics[rows[i][5]][1]


func has_image(i: int) -> bool:
	return (int(rows[i][6]) & 1) != 0


func has_audio(i: int) -> bool:
	return (int(rows[i][6]) & 2) != 0


func has_sentence(i: int) -> bool:
	return (int(rows[i][6]) & 4) != 0


func has_sentence2(i: int) -> bool:
	return (int(rows[i][6]) & 8) != 0


func find_id(wid: String) -> int:
	for i in range(count):
		if rows[i][0] == wid:
			return i
	return -1


# ---------------------------------------------------------------- 词条块

func entry(i: int) -> Dictionary:
	var chunk := i / 100
	if not _chunks.has(chunk):
		_load_chunk(chunk)
	if not _chunks.has(chunk):
		return {}
	var data: Array = _chunks[chunk]
	var pos := i - chunk * 100
	if pos < 0 or pos >= data.size():
		return {}
	return data[pos]


func _load_chunk(chunk: int) -> void:
	var path := CHUNK_FMT % chunk
	var file := File.new()
	if file.open(path, File.READ) != OK:
		push_error("缺少词条块 " + path)
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK:
		push_error("词条块解析失败 " + path)
		return
	_chunks[chunk] = parsed.result
	_touch_chunk(chunk)


func _touch_chunk(chunk: int) -> void:
	_chunk_order.erase(chunk)
	_chunk_order.push_back(chunk)
	while _chunk_order.size() > CHUNK_CACHE:
		_chunks.erase(_chunk_order.pop_front())


# ---------------------------------------------------------------- 图片

# 从 PCK 里的原始 JPEG 解码，不走 Godot 导入管线。
func texture_for(i: int) -> Texture:
	if not has_image(i):
		return null
	var wid := word_id(i)
	if _textures.has(wid):
		_touch_texture(wid)
		return _textures[wid]
	var file := File.new()
	if file.open(IMG_FMT % wid, File.READ) != OK:
		return null
	var bytes := file.get_buffer(file.get_len())
	file.close()
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK:
		return null
	var tex := ImageTexture.new()
	tex.create_from_image(image, Texture.FLAG_FILTER)
	_textures[wid] = tex
	_touch_texture(wid)
	return tex


func _touch_texture(wid: String) -> void:
	_tex_order.erase(wid)
	_tex_order.push_back(wid)
	while _tex_order.size() > TEX_CACHE:
		_textures.erase(_tex_order.pop_front())


func audio_bytes(i: int) -> PoolByteArray:
	if not has_audio(i):
		return PoolByteArray()
	return _read_raw(AUD_FMT % word_id(i))


func sentence_bytes(i: int) -> PoolByteArray:
	if not has_sentence(i):
		return PoolByteArray()
	return _read_raw(EX_FMT % word_id(i))


func sentence2_bytes(i: int) -> PoolByteArray:
	if not has_sentence2(i):
		return PoolByteArray()
	return _read_raw(EX2_FMT % word_id(i))


func _read_raw(path: String) -> PoolByteArray:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return PoolByteArray()
	var bytes := file.get_buffer(file.get_len())
	file.close()
	return bytes

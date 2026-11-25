"""word-atlas -> R36S 内容管线

从上游 designfuchen/word-atlas 抽取 B 档 3,000 词，转码为掌机可用资产。

用法：
    python tools/prepare_content.py all          # 全流程（可断点续跑）
    python tools/prepare_content.py meta         # 只拉索引 + 词条块
    python tools/prepare_content.py media        # 只拉插画 + 英音
    python tools/prepare_content.py convert      # 只做转码
    python tools/prepare_content.py emit         # 只生成 Godot 数据

产物：
    raw/img/<id>.jpg      256x256 JPEG q75
    raw/aud/<id>.mp3raw   上游原始 64kbps 单声道（直接复制，不重编码）
    data/index.json       精简索引
    data/chunks/NN.json   词条块（每块 100 词）
"""

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache", "upstream")
RAW_IMG = os.path.join(ROOT, "raw", "img")
RAW_AUD = os.path.join(ROOT, "raw", "aud")
RAW_EX = os.path.join(ROOT, "raw", "ex")
RAW_EX2 = os.path.join(ROOT, "raw", "ex2")
DATA = os.path.join(ROOT, "data")
CHUNKS = os.path.join(DATA, "chunks")

BASE = "https://raw.githubusercontent.com/designfuchen/word-atlas/main/"
UA = {"User-Agent": "word-atlas-buddy-builder"}

TARGET = 3000
CHUNK = 100
# A1 + A2 全量，余下名额给 B1（按主题轮转补齐）
TAKE_FULL = ("A1", "A2")
TAKE_PARTIAL = "B1"

IMG_SIZE = 256
JPG_Q = 75
AUD_BITRATE = "32k"


def log(msg):
    print(msg, flush=True)


def ensure_dirs():
    for d in (CACHE, RAW_IMG, RAW_AUD, RAW_EX, RAW_EX2, DATA, CHUNKS):
        os.makedirs(d, exist_ok=True)


def fetch(url, dest, retries=4):
    """下载到 dest，已存在则跳过。返回 True 表示可用。"""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return True
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                blob = r.read()
            if not blob:
                raise ValueError("empty body")
            tmp = dest + ".part"
            with open(tmp, "wb") as f:
                f.write(blob)
            os.replace(tmp, dest)
            return True
        except Exception as e:
            if attempt == retries - 1:
                log("  FAIL %s (%s)" % (url.rsplit("/", 1)[-1], e))
                return False
            time.sleep(1.5 * (attempt + 1))
    return False


# ---------------------------------------------------------------- meta

def stage_meta():
    ensure_dirs()
    log("[meta] 拉取 index.json")
    idx_path = os.path.join(CACHE, "index.json")
    if not fetch(BASE + "public/atlas/index.json", idx_path):
        raise SystemExit("index.json 下载失败")

    with open(idx_path, encoding="utf-8") as f:
        idx = json.load(f)
    total = len(idx["words"])
    n_chunks = (total + CHUNK - 1) // CHUNK
    log("[meta] 词条 %d，分块 %d" % (total, n_chunks))

    jobs = []
    for c in range(n_chunks):
        jobs.append(("public/atlas/entries/%d.json" % c,
                     os.path.join(CACHE, "entries", "%d.json" % c)))
    os.makedirs(os.path.join(CACHE, "entries"), exist_ok=True)

    ok = 0
    with ThreadPoolExecutor(max_workers=12) as ex:
        futs = {ex.submit(fetch, BASE + p, d): p for p, d in jobs}
        for fut in as_completed(futs):
            if fut.result():
                ok += 1
    log("[meta] 词条块 %d/%d 就绪" % (ok, n_chunks))


# ---------------------------------------------------------------- select

def select_words():
    """返回 (选中 id 列表, 上游 index 结构, dict id->entry)"""
    idx_path = os.path.join(CACHE, "index.json")
    with open(idx_path, encoding="utf-8") as f:
        idx = json.load(f)

    cefr_names = idx["cefr"]
    topics = idx["topics"]
    words = idx["words"]

    full, partial = [], []
    for row in words:
        wid, _w, _zh, _ipa, cefr_i, _topic_i, _m = row
        if cefr_i < len(cefr_names) and cefr_names[cefr_i] in TAKE_FULL:
            full.append(row)
        elif cefr_i < len(cefr_names) and cefr_names[cefr_i] == TAKE_PARTIAL:
            partial.append(row)

    need = max(0, TARGET - len(full))
    log("[select] A1+A2 全量 %d，还需从 B1 取 %d（B1 共 %d）"
        % (len(full), need, len(partial)))

    # B1 按主题轮转，避免全挤在某个主题
    buckets = {}
    for row in partial:
        buckets.setdefault(row[5], []).append(row)
    for k in buckets:
        buckets[k].sort(key=lambda r: r[0])

    picked = []
    order = sorted(buckets.keys())
    cursor = {k: 0 for k in order}
    while len(picked) < need:
        progressed = False
        for k in order:
            if len(picked) >= need:
                break
            if cursor[k] < len(buckets[k]):
                picked.append(buckets[k][cursor[k]])
                cursor[k] += 1
                progressed = True
        if not progressed:
            break

    selected = full + picked
    log("[select] 最终 %d 词" % len(selected))
    return selected, idx


def load_entries():
    """把全部词条块读进内存，返回 id -> entry"""
    entries = {}
    edir = os.path.join(CACHE, "entries")
    for name in sorted(os.listdir(edir), key=lambda s: int(s.split(".")[0])):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(edir, name), encoding="utf-8") as f:
            for e in json.load(f):
                entries[e["id"]] = e
    return entries


# ---------------------------------------------------------------- media

def stage_media():
    selected, _idx = select_words()
    ids = [r[0] for r in selected]
    log("[media] 待取 %d 词的插画与英音" % len(ids))

    jobs = []
    for wid in ids:
        jobs.append((BASE + "public/atlas/img/%s.webp" % wid,
                     os.path.join(CACHE, "img", "%s.webp" % wid)))
        jobs.append((BASE + "public/atlas/audio/uk/%s.mp3" % wid,
                     os.path.join(CACHE, "aud", "%s.mp3" % wid)))
    for sub in ("img", "aud"):
        os.makedirs(os.path.join(CACHE, sub), exist_ok=True)

    done, fail = 0, []
    total = len(jobs)
    with ThreadPoolExecutor(max_workers=24) as ex:
        futs = {ex.submit(fetch, url, dest): dest for url, dest in jobs}
        for i, fut in enumerate(as_completed(futs), 1):
            if fut.result():
                done += 1
            else:
                fail.append(futs[fut])
            if i % 200 == 0 or i == total:
                log("[media] %d/%d（失败 %d）" % (i, total, len(fail)))

    if fail:
        with open(os.path.join(CACHE, "media_failures.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(fail))
        log("[media] 失败清单已写入 .cache/upstream/media_failures.txt")
    log("[media] 完成 %d/%d" % (done, total))


# ---------------------------------------------------------------- sentence audio

def stage_sentences():
    """例句音频：上游 public/atlas/audio/ex|ex2/<id>.mp3，ElevenLabs 预生成，
    播放时不需要联网。ex = 第 1 条例句（日常），ex2 = 第 2 条（雅思语境）。"""
    ensure_dirs()
    selected, _idx = select_words()
    ids = [r[0] for r in selected]

    for sub, raw_dir in (("ex", RAW_EX), ("ex2", RAW_EX2)):
        src_dir = os.path.join(CACHE, sub)
        os.makedirs(src_dir, exist_ok=True)
        jobs = [(BASE + "public/atlas/audio/%s/%s.mp3" % (sub, w),
                 os.path.join(src_dir, "%s.mp3" % w)) for w in ids]
        done, miss = 0, []
        with ThreadPoolExecutor(max_workers=16) as ex:
            futs = {ex.submit(fetch, u, d, 2): d for u, d in jobs}
            for i, fut in enumerate(as_completed(futs), 1):
                if fut.result():
                    done += 1
                else:
                    miss.append(futs[fut])
                if i % 500 == 0 or i == len(jobs):
                    log("[sentence] %s %d/%d（缺失 %d）" % (sub, i, len(jobs), len(miss)))
        # 复制成 .mp3raw，保持 ElevenLabs 原始 64kbps，不重编码
        for w in ids:
            src = os.path.join(src_dir, "%s.mp3" % w)
            dst = os.path.join(raw_dir, "%s.mp3raw" % w)
            if os.path.exists(src) and os.path.getsize(src) > 0:
                shutil.copyfile(src, dst)
        log("[sentence] %s 就绪 %d 个 %.1f MB" % (
            sub, count_files(raw_dir), dir_size(raw_dir) / 1048576.0))


# ---------------------------------------------------------------- convert

def convert_image(src, dst):
    from PIL import Image
    im = Image.open(src).convert("RGB")
    if im.size != (IMG_SIZE, IMG_SIZE):
        im = im.resize((IMG_SIZE, IMG_SIZE), Image.LANCZOS)
    im.save(dst, "JPEG", quality=JPG_Q, optimize=True, progressive=False)


def convert_audio(src, dst):
    # 上游英音本身就是 64kbps 单声道 44.1k，再走一遍 ffmpeg 就是二次压缩
    # （实测 32k 重编码后齿音沙化）。这里直接复制原始字节，零损失。
    shutil.copyfile(src, dst)


def stage_convert():
    ensure_dirs()
    selected, _idx = select_words()
    ids = [r[0] for r in selected]

    todo_img = [(w, os.path.join(CACHE, "img", w + ".webp"),
                 os.path.join(RAW_IMG, w + ".jpgraw")) for w in ids]
    todo_img = [t for t in todo_img if os.path.exists(t[1])
                and not (os.path.exists(t[2]) and os.path.getsize(t[2]) > 0)]
    log("[convert] 插画待转 %d 张" % len(todo_img))
    fails = []

    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(convert_image, s, d): w for w, s, d in todo_img}
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                fut.result()
            except Exception as e:
                fails.append((futs[fut], str(e)))
            if i % 300 == 0 or i == len(todo_img):
                log("[convert] 插画 %d/%d" % (i, len(todo_img)))

    todo_aud = [(w, os.path.join(CACHE, "aud", w + ".mp3"),
                 os.path.join(RAW_AUD, w + ".mp3raw")) for w in ids]
    todo_aud = [t for t in todo_aud if os.path.exists(t[1])
                and not (os.path.exists(t[2]) and os.path.getsize(t[2]) > 0)]
    log("[convert] 音频待转 %d 个" % len(todo_aud))

    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(convert_audio, s, d): w for w, s, d in todo_aud}
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                fut.result()
            except Exception as e:
                fails.append((futs[fut], str(e)))
            if i % 300 == 0 or i == len(todo_aud):
                log("[convert] 音频 %d/%d" % (i, len(todo_aud)))

    if fails:
        with open(os.path.join(CACHE, "convert_failures.txt"), "w", encoding="utf-8") as f:
            for w, e in fails:
                f.write("%s\t%s\n" % (w, e))
    log("[convert] 失败 %d" % len(fails))

    # 注意：媒体用 .jpgraw/.mp3raw 这类 Godot 不认识的扩展名，
    # 这样既不会被导入管线处理（省 PCK、省内存），又能被 export include_filter 打进包。
    # 千万不要放 .gdignore —— 那会让 Godot 完全不扫描该目录，连打包都会漏掉。


# ---------------------------------------------------------------- emit

def stage_emit():
    ensure_dirs()
    selected, idx = select_words()
    entries = load_entries()
    cefr_names = idx["cefr"]
    topics = idx["topics"]

    missing = [r[0] for r in selected if r[0] not in entries]
    if missing:
        raise SystemExit("词条缺失 %d 个：%s" % (len(missing), missing[:10]))

    # 按 CEFR 再按 id 排序，让同级别词落在相邻块
    selected.sort(key=lambda r: (r[4], r[0]))
    ids = [r[0] for r in selected]

    # ---- 精简索引
    rows = []
    for r in selected:
        wid, word, zh, ipa, cefr_i, topic_i, m = r
        has_img = os.path.exists(os.path.join(RAW_IMG, wid + ".jpgraw"))
        has_aud = os.path.exists(os.path.join(RAW_AUD, wid + ".mp3raw"))
        has_ex = os.path.exists(os.path.join(RAW_EX, wid + ".mp3raw"))
        has_ex2 = os.path.exists(os.path.join(RAW_EX2, wid + ".mp3raw"))
        bits = ((1 if has_img else 0) | (2 if has_aud else 0)
                | (4 if has_ex else 0) | (8 if has_ex2 else 0))
        rows.append([wid, word, zh, ipa, cefr_i, topic_i, bits])

    index = {
        "v": 1,
        "source": "Word Atlas contributors - CC BY 4.0",
        "count": len(rows),
        "chunk": CHUNK,
        "cefr": cefr_names,
        "topics": topics,
        "fields": ["id", "word", "zh", "ipa", "cefr", "topic", "media"],
        "words": rows,
    }
    with open(os.path.join(DATA, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, separators=(",", ":"))

    # ---- 词条块
    for old in os.listdir(CHUNKS):
        if old.endswith(".json"):
            os.remove(os.path.join(CHUNKS, old))

    keep_keys = ("w", "uk", "us", "senses", "ex", "col", "fam",
                 "syn", "ant", "tip", "cefr", "topic", "id")
    for c in range(0, len(ids), CHUNK):
        batch = []
        for wid in ids[c:c + CHUNK]:
            e = entries[wid]
            row = {k: e[k] for k in keep_keys if k in e}
            # note 只有部分词有实质内容，空的丢掉
            if e.get("note"):
                row["note"] = e["note"]
            batch.append(row)
        name = "%02d.json" % (c // CHUNK)
        with open(os.path.join(CHUNKS, name), "w", encoding="utf-8") as f:
            json.dump(batch, f, ensure_ascii=False, separators=(",", ":"))

    # ---- 授权文件
    shutil.copy(os.path.join(CACHE, "LICENSE.txt"),
                os.path.join(ROOT, "LICENSE")) if os.path.exists(
        os.path.join(CACHE, "LICENSE.txt")) else None
    attrib = os.path.join(ROOT, "ATTRIBUTION.md")
    with open(attrib, "w", encoding="utf-8") as f:
        f.write(ATTRIBUTION)

    log("[emit] 索引 %d 行，词条块 %d 个" % (len(rows), (len(ids) + CHUNK - 1) // CHUNK))
    log_size("data/index.json", os.path.join(DATA, "index.json"))
    log("[emit] raw/img %d 个 %.1f MB" % (
        count_files(RAW_IMG), dir_size(RAW_IMG) / 1048576.0))
    log("[emit] raw/aud %d 个 %.1f MB" % (
        count_files(RAW_AUD), dir_size(RAW_AUD) / 1048576.0))
    log("[emit] 合计 %.1f MB" % (
        (dir_size(DATA) + dir_size(os.path.join(ROOT, "raw"))) / 1048576.0))


ATTRIBUTION = """# 署名 / Attribution

本应用（word-atlas-buddy）的学习内容改编自 **Word Atlas**。

- 来源：https://github.com/designfuchen/word-atlas
- 内容署名：**Word Atlas contributors — CC BY 4.0**
- 授权全文：https://creativecommons.org/licenses/by/4.0/
- 代码授权：MIT License

## 本应用做过的修改

1. **选词子集**：从上游 7,298 词中选取 3,000 词（CEFR A1、A2 全量，B1 按主题均衡补齐）。
2. **插画压缩**：上游 512×512 WebP 重新编码为 256×256 JPEG（quality 75），用于 640×480 屏幕。
3. **音频转码**：上游英音 MP3（44.1kHz 单声道 66kbps）重新编码为 32kbps 单声道。
4. **界面重制**：上游为 React 网页应用，本应用为 Godot 3.5 掌机应用，界面完全重写。
5. **词星图降级**：上游 WebGL2 三维星云改为 2D 径向布局。

## 上游声明（原样保留）

- 内容由 AI 模型按项目规范生成（文本：大语言模型；插画：图像模型；录音：ElevenLabs 合成语音），
  经过自动校验，未逐条人工审校，按现状提供，不作准确性担保。
- 录音授权只涉及这些完成的音频文件，不包含底层声音模型、声音身份或任何人的肖像、人格权，
  也不表示声音提供方为本项目背书。英音声音为 ElevenLabs "Alice"。
- 不是官方雅思（IELTS）词表，与雅思考试主办方无关。
- 单个英文单词与通用词表本身不主张专有权。
"""


def count_files(d):
    if not os.path.isdir(d):
        return 0
    return sum(1 for n in os.listdir(d) if not n.startswith("."))


def dir_size(d):
    if not os.path.isdir(d):
        return 0
    total = 0
    for n in os.listdir(d):
        p = os.path.join(d, n)
        if os.path.isfile(p):
            total += os.path.getsize(p)
    return total


def log_size(label, path):
    if os.path.exists(path):
        log("[emit] %s %.1f KB" % (label, os.path.getsize(path) / 1024.0))


def stage_license():
    ensure_dirs()
    fetch(BASE + "LICENSE", os.path.join(CACHE, "LICENSE.txt"))
    fetch(BASE + "CONTENT_LICENSE.md", os.path.join(CACHE, "CONTENT_LICENSE.md"))


def main():
    stage = sys.argv[1] if len(sys.argv) > 1 else "all"
    t0 = time.time()
    if stage in ("all", "meta"):
        stage_meta()
        stage_license()
    if stage in ("all", "media"):
        stage_media()
    if stage in ("all", "sentence"):
        stage_sentences()
    if stage in ("all", "convert"):
        stage_convert()
    if stage in ("all", "emit"):
        stage_emit()
    log("== %s 完成，用时 %.1f 分钟 ==" % (stage, (time.time() - t0) / 60.0))


if __name__ == "__main__":
    main()

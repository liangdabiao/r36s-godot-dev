"""补漏：只重试上一次因网络抖动失败的例句音频（跳过 404，避免无谓重试）。"""

import os
import re
import shutil
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache", "upstream")
LOG = os.path.join(ROOT, ".cache", "sentence_dl.log")
BASE = "https://raw.githubusercontent.com/designfuchen/word-atlas/main/public/atlas/audio/%s/%s.mp3"
UA = {"User-Agent": "Mozilla/5.0 (word-atlas-buddy prep)"}
RETRY_SUBS = ("ex", "ex2")


def fetch_once(url, dest, tries=3):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return True
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=45) as r:
                blob = r.read()
            if blob:
                with open(dest + ".part", "wb") as f:
                    f.write(blob)
                os.replace(dest + ".part", dest)
                return True
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return False
            time.sleep(1.0 + i)
        except Exception:
            time.sleep(1.0 + i)
    return False


def main():
    names = set()
    with open(LOG, encoding="utf-8", errors="ignore") as f:
        for line in f:
            m = re.search(r"FAIL (\S+) \((.*)\)\s*$", line)
            if not m:
                continue
            if "404" in m.group(2):
                continue
            names.add(m.group(1)[:-4])
    print("待补词条 %d" % len(names))

    jobs = []
    for wid in sorted(names):
        for sub in RETRY_SUBS:
            dest = os.path.join(CACHE, sub, "%s.mp3" % wid)
            if not (os.path.exists(dest) and os.path.getsize(dest) > 0):
                jobs.append((sub, wid, BASE % (sub, wid), dest))
    print("待补文件 %d" % len(jobs))

    ok = 0
    with ThreadPoolExecutor(max_workers=12) as ex:
        futs = {ex.submit(fetch_once, u, d): (s, w) for s, w, u, d in jobs}
        for i, fut in enumerate(as_completed(futs), 1):
            if fut.result():
                ok += 1
            if i % 200 == 0 or i == len(jobs):
                print("  %d/%d 成功 %d" % (i, len(jobs), ok))

    # 同步到 raw/
    for sub, raw_name in (("ex", "ex"), ("ex2", "ex2")):
        src = os.path.join(CACHE, sub)
        dst = os.path.join(ROOT, "raw", raw_name)
        os.makedirs(dst, exist_ok=True)
        n = 0
        for fn in os.listdir(src):
            if not fn.endswith(".mp3"):
                continue
            s = os.path.join(src, fn)
            d = os.path.join(dst, fn[:-4] + ".mp3raw")
            if os.path.getsize(s) > 0:
                shutil.copyfile(s, d)
                n += 1
        print("%s -> raw %d 个" % (sub, n))


if __name__ == "__main__":
    main()

"""按实际内容重建中文字体子集。

english-buddy 的 ui.ttf 是按它自己的课文做的子集，对 word-atlas 缺 2,167 字，
直接复用会整片豆腐块。这里扫描选中的 3,000 条词条，从系统字体重新裁剪。

用法：python tools/build_font.py
"""

import json
import os
import shutil
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import prepare_content as pc

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(HERE, "assets", "fonts")
CJK_SOURCE = "C:/Windows/Fonts/Deng.ttf"          # 等线，与 english-buddy 同族
IPA_SOURCE = os.path.join("D:/r36s-demo-main/english-buddy/assets/fonts/ipa.ttf")

# IPA 单独用 DejaVu 字形（等线没有音标扩展）
IPA_EXTRA = "æéðɑɒəɜɡɪʃʊʌʒŋɔːˈˌθðʃʒʔɚɝ"

# 标点/符号：中文排版用得到的
PUNCT_EXTRA = "、。，；：？！（）《》【】“”‘’—–…·「」～＋＝｜／％"


def collect_chars(ids, entries):
    texts = []
    for wid in ids:
        e = entries[wid]
        for s in e.get("senses", []):
            texts.append(s.get("zh", ""))
            texts.append(s.get("en", ""))
        for x in e.get("ex", []):
            texts.append(x.get("en", ""))
            texts.append(x.get("zh", ""))
        texts.extend(e.get("col", []))
        texts.extend(e.get("fam", []))
        texts.extend(e.get("syn", []))
        texts.extend(e.get("ant", []))
        texts.append(e.get("tip", ""))
        texts.append(e.get("note", ""))
        texts.append(e.get("w", ""))

    # 界面固定文案也必须覆盖
    texts.append(UI_TEXT)

    charset = set("".join(texts))
    charset |= set(chr(c) for c in range(0x20, 0x7F))  # 整个可打印 ASCII
    return charset


UI_TEXT = (
    "今日复习开始学习词星图词库浏览关于设置返回退出继续"
    "待复习新卡学习中重学记住忘记模糊简单下次天小时分"
    "个词条释义例句搭配词族近义词反义词提示发音英音播放"
    "连续打卡累计已学进度主题全部级别难度认识不认识跳过"
    "显示答案点击任意键翻面评分授权声明来源署名改编自"
    "版本内容由生成未经人工审校按现状提供不作担保"
    "第页共条筛选排序字母顺序随机本组完成正确错误"
    "原形过去式复数比较级最高级不可数及物不及物"
)


def main():
    os.makedirs(FONT_DIR, exist_ok=True)

    selected, _idx = pc.select_words()
    ids = [r[0] for r in selected]
    entries = pc.load_entries()
    charset = collect_chars(ids, entries)

    hanzi = [c for c in charset if "\u4e00" <= c <= "\u9fff"]
    print("汉字 %d 个，总字符 %d 个" % (len(hanzi), len(charset)))

    target = os.path.join(FONT_DIR, "ui.ttf")
    want = "".join(sorted(charset)) + PUNCT_EXTRA

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["DSIG"]

    font = subset.load_font(CJK_SOURCE, opts)
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(text=want)
    subsetter.subset(font)
    subset.save_font(font, target, opts)
    font.close()
    print("中文字体 -> %s  %.1f KB" % (target, os.path.getsize(target) / 1024.0))

    # IPA 字体：直接复用 english-buddy 那份 DejaVu 子集，但补齐本词库用到的音标
    ipa_target = os.path.join(FONT_DIR, "ipa.ttf")
    if os.path.exists(IPA_SOURCE):
        opts2 = subset.Options()
        opts2.layout_features = ["*"]
        opts2.name_IDs = ["*"]
        opts2.notdef_outline = True
        f2 = subset.load_font(IPA_SOURCE, opts2)
        s2 = subset.Subsetter(options=opts2)
        s2.populate(text="".join(sorted(set(IPA_EXTRA))) + " /.,;:()'-" +
                    "".join(chr(c) for c in range(0x20, 0x7F)))
        s2.subset(f2)
        subset.save_font(f2, ipa_target, opts2)
        f2.close()
        print("音标字体 -> %s  %.1f KB" % (ipa_target, os.path.getsize(ipa_target) / 1024.0))
    else:
        print("警告：找不到 IPA 源字体，音标将回落到中文字体")

    audit(target, ipa_target, charset)


def _cmap(path):
    font = TTFont(path, fontNumber=0)
    table = set()
    for t in font["cmap"].tables:
        table |= set(t.cmap.keys())
    font.close()
    return table


def audit(ui_path, ipa_path, charset):
    ui = _cmap(ui_path) if os.path.exists(ui_path) else set()
    ipa = _cmap(ipa_path) if os.path.exists(ipa_path) else set()

    need_cjk = [c for c in charset if "\u4e00" <= c <= "\u9fff"]
    miss_cjk = [c for c in need_cjk if ord(c) not in ui]
    print("汉字覆盖: %d/%d，缺 %d" % (len(need_cjk) - len(miss_cjk), len(need_cjk), len(miss_cjk)))
    if miss_cjk:
        print("  缺失样例:", "".join(miss_cjk[:40]))

    ipa_chars = set(IPA_EXTRA)
    miss_ipa = [c for c in ipa_chars if ord(c) not in ipa]
    print("音标覆盖: %d/%d，缺 %d" % (len(ipa_chars) - len(miss_ipa), len(ipa_chars), len(miss_ipa)))
    if miss_ipa:
        print("  缺失:", "".join(miss_ipa))


if __name__ == "__main__":
    main()

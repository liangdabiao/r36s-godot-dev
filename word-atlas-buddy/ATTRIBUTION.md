# 署名 / Attribution

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

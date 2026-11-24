# apiz-first APIs and fallback tools

Use `scripts/apiz_asset.py` for image, MiniMax-H3 video, speech, designed voices and music. It wraps the installed apiz CLI, uploads local references, submits once, polls by task id, downloads the result and records the real cost. Seedance 2 remains a compatible explicit video route. `asset_gen.py` is a legacy direct-provider fallback, not the default.

Set `APIZ` as shown in `SKILL.md`, then run commands with `python "$APIZ" ...`.

## Preflight, costs and resume

```bash
python "$APIZ" doctor
python "$APIZ" models --category image
python "$APIZ" models --category audio
python "$APIZ" docs apiz/gpt-image-2.6-flare
python "$APIZ" docs minimax/h3
python "$APIZ" docs st-ai/super-seed2
python "$APIZ" docs minimax/music-gen
```

- `doctor` is read-only and reports the CLI version, profile configuration, balance, ffmpeg and defaults.
- Authenticate with `apiz auth login`; the wrapper reads apiz's profile. `--profile`, `--config` and `--base-url` are available on generation commands.
- `--upload KEY=PATH` is repeatable. The wrapper uploads the local file and substitutes an array of public URLs into that model parameter.
- Every generation creates `<output>.apiz.json`. Rerun the identical command to resume polling or downloading. The request hash includes the model, prompt, parameters, local upload paths, output path and kind.
- `--no-wait` returns after submission. `--wait-timeout` controls local polling only; it does not cancel the remote task. The default is 3600 seconds because video queues can be long. A timeout is resumable.
- `--force` creates a new paid task even when matching state exists.
- `task TASK_ID -o OUTPUT --kind video|image|audio` adopts or downloads an existing task.
- Result stdout is JSON. Progress goes to stderr. Failed tasks and partially failed batches exit nonzero; their sidecar remains for diagnosis.

**Cost rule:** apiz returns `price` in credits. The wrapper reports both `price_credits` and `cost_cents`; they are the same number because **100 credits = ¥1**. Record the returned value in the asset manifest. Estimates belong in the pre-call confirmation, not in the final cost column.

## Images — `apiz/gpt-image-2.6-flare`

```bash
python "$APIZ" image \
  --prompt "A stout dwarf knight, full body, neutral T-pose, bold readable silhouette, flat game sprite, plain white background" \
  --quality high --size 1K --aspect-ratio 1:1 \
  -o assets/img/dwarf.png
```

- `--quality`: `low`, `medium`, `high`, `xhigh`, `max`; default `medium`.
- `--size`: `1K`, `2K`, `4K`, or `WIDTHxHEIGHT`. Custom dimensions require both sides and replace `aspect_ratio`/`size` in the request.
- `--aspect-ratio`: `auto`, `21:9`, `16:9`, `3:2`, `4:3`, `5:4`, `1:1`, `4:5`, `3:4`, `2:3`, `9:16`; default `1:1`.
- `--complexity`: `low`, `medium`, `high`; default `high`. Use `low` for a focused recolor, pose or edit and `high` for a new composition.
- `--image ref.png` is repeatable, 1–16 references. The wrapper uploads them into `reference_image_urls`.
- `--transparent` requires `.png` output and requests real alpha.
- Output extension selects `output_format`: `.png`, `.jpg`/`.jpeg`, `.webp`, `.gif`, `.svg`.
- GIF and SVG are text-to-image only in the current schema; do not pass references.
- `--params '{"key": value}'` merges advanced schema fields. The output extension still controls `output_format`.

Current pricing is token-based: text input 3500 credits/1M tokens, image input 5600, image output 21000. Quality, size, references, frames and SVG author model change the bill. There is no fixed per-image price to promise; use the returned task price.

### Image batches

Each JSONL line is an image job. The batch is sequential and has **no OpenAI Batch half-price claim**. All jobs are attempted; any failed job makes the command exit nonzero while the JSON result still lists every job outcome.

```jsonl
{"prompt":"A wooden supply crate, three-quarter view, matte finish, plain background","o":"assets/img/crate.png","quality":"medium"}
{"prompt":"The same crate with a reinforced iron lid; keep shape and style","o":"assets/img/crate_iron.png","image":"assets/img/crate.png","complexity":"low"}
{"prompt":"A distant forest village at dawn, layered parallax background","o":"assets/img/village_bg.png","size":"1920x1088","quality":"high"}
```

```bash
python "$APIZ" batch assets/img/jobs.jsonl
python "$APIZ" batch assets/img/jobs.jsonl --no-wait
```

Supported job keys include `prompt`, `o`, `model`, `image`/`references`, `quality`, `size`, `aspect_ratio`, `transparent`, `complexity`, `frames`, `frame_ms` and `params`. In JSONL, `params` may be a nested object; on the command line, pass it as a JSON string. A job cannot use another job's output from the same batch as its reference; derive the second set after the first downloads.

## Animated sprites

### GIF

The current Flare GIF path is text-to-image only. Describe a complete cycle and loop closure in the prompt; do not pass `--image`.

```bash
python "$APIZ" image \
  --prompt "The same dwarf knight walks right in a smooth side-view walk cycle, in place, fixed camera, bold flat sprite, eighth frame flows back into the first" \
  --frames 8 --frame-ms 100 --quality medium \
  -o assets/img/dwarf_walk.gif
```

- `--frames`: 2–9 in the wrapper, matching the current schema maximum. The model's prose says 2–16 but its machine schema says 2–9; use the conservative range until apiz resolves the mismatch.
- `--frame-ms`: 20–2000 ms; default 200.
- GIF alpha is 1-bit, so hard edges are expected.
- Only HTML plays GIF directly. Elsewhere extract frames and play them at the requested delay:

```bash
magick dwarf_walk.gif -coalesce frames/%02d.png
# or: ffmpeg -i dwarf_walk.gif frames/%04d.png
```

### Transparent GIF sprites

Flare's current machine schema guarantees alpha only for transparent PNG output; it does not expose a transparent-GIF switch, and GIF generation remains text-to-image only. Do not pass `--transparent` with a `.gif` output. For animated game sprites, generate transparent PNG key poses with references, then assemble them locally:

```bash
mkdir -p frames
python "$APIZ" image \
  --prompt "Full-body dwarf knight, neutral standing pose, centered, plain transparent background, bold flat game sprite" \
  --transparent --quality high -o frames/01.png

python "$APIZ" image \
  --prompt "The same dwarf knight in the next walk pose, identical scale, colors and camera, transparent background" \
  --image frames/01.png --transparent --complexity low -o frames/02.png

magick -delay 10 -dispose previous -loop 0 -layers Optimize \
  frames/*.png assets/img/dwarf_walk_transparent.gif
```

Use zero-padded frame names so lexical order is playback order. GIF alpha is 1-bit: inspect hard edges and accidental halos, and keep the PNG master frames for higher-quality engine playback.

### Sprite video

For smoother or longer motion: **reference → pose → video → extract frames → loop-trim**.

1. Generate a solid-background reference with apiz image generation. Video does not receive alpha matting; choose a background distinct from the subject.
2. Generate each action pose from the reference with `--image reference.png --complexity low`.
3. Generate a MiniMax-H3 clip from the pose.
4. Extract frames.
5. For walk/idle loops, find a matching loop frame and discard later frames; one-shots do not need loop trimming.

```bash
python "$APIZ" video --first-frame assets/img/dwarf_pose.png \
  --duration 4 --aspect-ratio 1:1 --resolution 768P \
  --prompt "The dwarf walks right in place, smooth side-view game cycle, fixed camera, consistent silhouette and colors" \
  -o motion_src/dwarf_walk.mp4

ffmpeg -i motion_src/dwarf_walk.mp4 -vsync 0 frames/%04d.png
python "$ASSET_SKILL/scripts/find_loop_frame.py" frames/
```

Reuse one character reference across actions. Keep reference-to-video chains short; long chains drift. Normalize all frames to the smallest source resolution before engine import, inspect the actual video fps with `ffprobe`, and drive playback from elapsed time rather than a guessed 24 fps.

## MiniMax-H3 video — `minimax/h3` (default)

The `video` command builds H3's native `content` array: one `text` item plus typed `image_url`, `video_url` or `audio_url` items with explicit roles. It does not send Seedance's top-level `prompt`, `functionMode` or `filePaths` fields.

Text-to-video, using the wrapper defaults (`768P`, 5 seconds, `16:9`):

```bash
python "$APIZ" video \
  --prompt "A slow cinematic push-in, the dwarf raises the sword, warm forge light, subtle smoke" \
  --duration 5 --resolution 768P --aspect-ratio 16:9 \
  -o assets/video/dwarf_intro.mp4
```

First and last frames:

```bash
python "$APIZ" video \
  --prompt "The dwarf completes a steady sword raise, consistent character and lighting" \
  --first-frame assets/img/dwarf_first.png --last-frame assets/img/dwarf_last.png \
  --duration 5 --resolution 768P --aspect-ratio 16:9 \
  -o assets/video/dwarf_intro.mp4
```

Mixed image, video and audio references:

```bash
python "$APIZ" video \
  --prompt "画面中的人物按照参考视频的动作跳舞，镜头缓慢环绕，动作节奏与参考音频同步" \
  --reference-image assets/img/dwarf.png \
  --reference-video motion_src/dance_ref.mp4 \
  --reference-audio assets/audio/beat.mp3 \
  --duration 5 --resolution 768P --aspect-ratio adaptive \
  -o assets/video/dwarf_dance.mp4
```

- No media: text-to-video. `--image PATH` remains an alias for one first frame or two first/last frames; do not combine it with `--first-frame`/`--last-frame`.
- `--first-frame` and `--last-frame` each accept one image. `--reference-image`, `--reference-video` and `--reference-audio` are repeatable.
- Duration: integer 4–15 seconds; default 5.
- Resolution: `480p`, `768P`, `1080p`, `2K`; default `768P`.
- Ratio: `adaptive`, `21:9`, `16:9`, `4:3`, `1:1`, `3:4`, `9:16`. Text-to-video cannot use `adaptive`; the wrapper defaults text-only jobs to `16:9` and media jobs to `adaptive` unless overridden.
- Text content: at most 7000 characters.
- `--params '{"aigc_watermark":false}'` may set the optional watermark flag. Seedance-only params are rejected.

| Resolution | Credits/s for output and reference video | 4s example | 15s example |
|---|---:|---:|---:|
| `480p` | 12 | 55 | 187 |
| `768P` | 18 | 79 | 277 |
| `1080p` | 28 | 119 | 427 |
| `2K` | 30 | 127 | 457 |

Each request adds 7 Context credits. The first 5 images are free; additional images cost 7 credits each. Reference video is billed at the same per-second rate as output, with its duration rounded up. The table excludes reference-video and excess-image charges. Use the task's returned `price` as the final cost.

### H3 through `generate`

`generate` also maps local uploads into typed H3 content. Valid keys are `first_frame`, `last_frame`, `reference_image`, `reference_video` and `reference_audio`; `image_url`, `video_url` and `audio_url` are reference-role aliases.

```bash
python "$APIZ" generate \
  --model minimax/h3 --kind video \
  --prompt "人物按照参考视频跳舞，动作与音频节奏同步" \
  --upload first_frame=assets/img/dwarf.png \
  --upload reference_video=motion_src/dance_ref.mp4 \
  --upload reference_audio=assets/audio/beat.mp3 \
  --params '{"resolution":"768P","duration":5,"ratio":"adaptive"}' \
  -o assets/video/dwarf_dance.mp4
```

The wrapper uploads each local file, inserts its public URL under the matching content type and records the local paths in the request hash for safe resume.

## Seedance 2.0 compatibility — `st-ai/super-seed2`

Seedance remains supported when explicitly selected; it is not the default. The `video` command uses `first_last_frames` mode:

```bash
python "$APIZ" video --model st-ai/super-seed2 \
  --prompt "A slow cinematic push-in, the dwarf raises the sword, warm forge light, subtle smoke" \
  --image assets/img/dwarf_first.png --image assets/img/dwarf_last.png \
  --duration 5 --aspect-ratio 16:9 --variant fast \
  -o assets/video/dwarf_intro_seedance.mp4
```

- No `--image`: text-to-video.
- One `--image`: image-to-video first frame.
- Two `--image` values: first and last frame.
- Duration: integer 4–15 seconds; default 5.
- Ratio: `21:9`, `16:9`, `4:3`, `1:1`, `3:4`, `9:16`.
- `--variant`: `fast`, `fast_vip`, `standard`, `standard_vip`; default `fast`.
- H3-only frame, reference and resolution options are rejected on this route.
- `video --params` may refine this mode but cannot switch to Omni. Use `generate --upload` for Omni reference arrays.

| Wrapper variant | Inner model | Catalogue credits/s without video reference | Catalogue credits/s with video reference |
|---|---|---:|---:|
| `fast` | `seedance_2.0_fast` | 60 | 120 |
| `fast_vip` | `seedance_2.0_fast_vip` | 120 | 240 |
| `standard` | `seedance_2.0` | 90 | 180 |
| `standard_vip` | `seedance_2.0_vip` | 150 | 300 |

The catalogue implies 300 credits (¥3) for a 5-second Fast text/image clip and 600 credits (¥6) with a video reference. Live routing or promotions can return a different model alias and lower `price`; the submitted/completed task price is authoritative and is what the wrapper records.

### Seedance Omni reference mode

Use `generate` when the prompt needs mixed image, video and audio references. Limits: 9 images, 3 videos, 3 audio clips; referenced video duration is at most 15 seconds total.

```bash
python "$APIZ" generate \
  --model st-ai/super-seed2 --kind video \
  --prompt "@image_file_1 中的人物按照 @video_file_1 的动作跳舞，镜头缓慢环绕，@audio_file_1 的节奏与动作同步" \
  --upload image_files=assets/img/dwarf.png \
  --upload video_files=motion_src/dance_ref.mp4 \
  --upload audio_files=assets/audio/beat.mp3 \
  --params '{"model":"seedance_2.0_fast","functionMode":"omni_reference","ratio":"16:9","duration":5}' \
  -o assets/video/dwarf_dance.mp4
```

The Nth upload in each array corresponds to `@image_file_N`, `@video_file_N` or `@audio_file_N`. Keep the placeholders in the prompt. Do not use `filePaths` in Omni mode; it belongs to first/last-frame mode.

## Speech — Minimax through `apiz speak`

```bash
python "$APIZ" voices --status active --search Grukk --limit 10
python "$APIZ" speech \
  --text "Aye, that blade will hold. Forged it meself, three nights without sleep." \
  --voice VOICE_ID --speed 1.0 --model speech-2.8-hd \
  -o assets/audio/dwarf_01.ogg
```

- `--text` is spoken verbatim; do not place direction or stage instructions in it.
- `--text-file dialogue/dwarf_01.txt` avoids shell escaping and preserves UTF-8 text.
- `--voice` is an apiz/Minimax voice id. Omit it only when automatic selection is acceptable.
- `voices` prints at most 25 matches by default and reports `total`/`truncated`; use `--search TEXT`, `--limit N`, or `--limit 0` for all.
- `--speed`: 0.5–2.0; default 1.0.
- Models exposed by the CLI: `speech-2.8-hd`, `speech-2.8-turbo`, `speech-2.6-hd`, `speech-2.6-turbo`; default `speech-2.8-hd`.
- Output can be `.mp3`, `.ogg`, `.wav` or `.flac`; non-MP3 conversion requires ffmpeg.
- Generate one file per line for ordinary games. For dialogue that must overlap in one clip, use separate lines and mix them, or use the explicit Gemini fallback below.

The wrapper calls `apiz speak` without `--output-file`, reads `audio_url`, downloads the MP3, converts if requested, and records the returned `price`, duration and voice id in the sidecar.

## Designed voices — `minimax/voice-design`

```bash
python "$APIZ" voice-design \
  --prompt "A small wiry cave goblin, high nasal raspy voice, quick and mischievous, dry chuckle" \
  --preview-text "You call that a lock? I opened it before you finished knocking." \
  --voice-id GrukkCaveVoice \
  -o voices/grukk_audition.mp3

python "$APIZ" voices --status active
python "$APIZ" speech --voice GrukkCaveVoice \
  --text "That is exactly what I wanted you to think." \
  -o assets/audio/grukk_01.ogg
```

- Describe permanent traits in 1–2 sentences: age, timbre, texture, accent and attitude.
- `voice_id` must start with a letter and contain 8–256 letters, digits, underscores or hyphens.
- Record the returned `voice_id` next to the character in the asset manifest.
- Designed voices are temporary and auto-delete after **7 days of inactivity**. Use `voices --status expired|all` to inspect them.
- First TTS use of a designed voice has a separate **1000-credit (¥10)** fee. Voice creation and preview text can also bill; use the returned price, not an estimate.
- Do not design a child voice unless the service allows the intended use and policy; choose an appropriate public voice or local TTS otherwise.

## Music — `minimax/music-gen`

```bash
python "$APIZ" music \
  --prompt "Cozy village shop theme, 85 BPM, F major, warm Rhodes piano, soft vinyl crackle, brushed drums, upright bass, instrumental" \
  --lyrics "[Inst]\nInstrumental only, no vocals" \
  --music-model music-2.5 \
  -o music_src/shop_theme.mp3
```

- `lyrics` is required, 1–3500 characters. Use `[Inst]` for instrumental sections and newline-separated structure tags such as `[Intro]`, `[Verse]`, `[Chorus]`, `[Bridge]`, `[Outro]`.
- `prompt` describes style, mood, instruments and tempo, up to 2000 characters.
- `music-2.5`: 100 credits (¥1)/song. `music-2.0`: 25 credits (¥0.25)/song.
- The wrapper requests URL output and downloads immediately; the model's URL is valid for 24 hours.
- Output can be MP3, OGG, WAV or FLAC; non-MP3 requires ffmpeg.

Make loops by cutting whole bars at the requested BPM and crossfading across the cut:

```bash
python "$ASSET_SKILL/scripts/loop_audio.py" music_src/shop_theme.mp3 \
  --bpm 85 --bars 8 --start-bars 1 -o assets/audio/shop_loop.ogg
```

If the generated tempo differs from the prompt, cut by measured seconds instead of bars. `--start-bars` skips an intro.

## 3D — Tripo fallback

Keep the existing Tripo workflow when local generation is unavailable or non-humanoid rigging is required. The `tripo` CLI owns submission, polling, download, credit pre-check and failure refunds.

```bash
tripo docs --llm
tripo make ref.png --name car -p face_limit=30000 -p auto_size=true --json --yes -o assets/glb
tripo make ref.png --name hero --then rig-check,rig:model=v1.0-20240301 --json --yes -o assets/glb
tripo anim retarget @hero --animation preset:biped:walk preset:biped:idle --json --yes -o assets/glb
tripo balance
```

- `make` is blocking. Do not add a shorter timeout or resubmit because a task id appeared. If the process dies, `tripo task watch <id> --download` finishes the same task.
- Read `model_file`, `preview.png` and `credits_consumed` from the JSON result. Output normally lands in `<-o>/<name>-<id8>/` with `model.glb`, `preview.png` and `task.json`.
- `--name X` makes the task addressable as `@X`. Retarget reuses the rig task; do not re-rig for each clip.
- Inspect imported clip names before wiring engine playback; preset names are not guaranteed to survive unchanged.
- Source reference: 3/4 elevated view, solid white/gray background, matte finish, opaque glass, one centered subject. Do not use transparency. Use a T-pose for characters.
- Check `tripo docs --topic commands/process`, `examples/animation` and `common-errors` for current options, model defaults, credit costs and preset availability.
- Record the CLI's actual `credits_consumed`; do not copy an old credit estimate into the manifest.

## Legacy direct-provider fallback

Use `scripts/asset_gen.py` only when apiz cannot provide the exact requested capability or the user explicitly chooses a direct provider. It requires `scripts/requirements.txt` and the corresponding user-owned key.

| Capability | Default route | Direct fallback |
|---|---|---|
| Stills, GIF, ordinary image-to-video | apiz | `asset_gen.py image` / `video` only on explicit request |
| Single-line speech | apiz `speech` | `asset_gen.py speech` with Gemini when its acting/tags are required |
| Two-speaker staged dialogue | separate apiz lines or audio mix | Gemini `asset_gen.py speech --speakers` |
| Designed voice | apiz `voice-design` | Gemini `asset_gen.py voice design/list` |
| Music | apiz `music` | Gemini/Lyria `asset_gen.py music` only on explicit request |
| 3D | local or Tripo | no apiz replacement in this workflow |

Gemini fallback keys: `GEMINI_API_KEY` or `GOOGLE_API_KEY`. OpenAI/xAI fallbacks use `OPENAI_API_KEY`/`XAI_API_KEY`; they are not part of the default path.

```bash
python "$ASSET_SKILL/scripts/asset_gen.py" speech \
  --voice Algenib --style "proud, a little amused" \
  --text "<chuckle> Aye, that blade will hold. <short pause> Forged it meself." \
  -o assets/audio/dwarf_01.ogg

python "$ASSET_SKILL/scripts/asset_gen.py" speech \
  --speakers "Guard=Orus,Grukk=VOICE_ID" \
  --text "Guard (bored): Toll is five coppers. |five?!| Five.
Grukk (outraged): FIVE? <gasp> For a BRIDGE?" \
  -o assets/audio/bridge_toll.ogg
```

Gemini text is spoken verbatim. Keep speaker identity in the selected voice, whole-line delivery in `--style`, and moment-level vocal bursts such as `<laugh>`, `<sigh>` or `<gasp>` inline. Use the current Google prompting guide for supported tags and languages; do not reuse stale price tables.

## Output and logging

- Default apiz commands print one JSON result to stdout and progress to stderr.
- Sidecars contain task metadata and public result URLs, not API keys. Downloaded local files are the deliverable; remote URLs may expire.
- The local GPU tools must run sequentially. Independent apiz tasks may be submitted separately, but keep paid parallelism deliberate and within the user's budget.
- Never overwrite an unrelated existing output. Use a new filename, or `--force` only when the user intentionally wants a new paid generation.

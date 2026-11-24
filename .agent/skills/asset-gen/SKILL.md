---
name: asset-gen
description: Generate and optimize game or video assets with apiz-first images, MiniMax-H3 video (Seedance 2 compatible), speech, music and voice design; preserve local free godogen_assets, Blender, Tripo 3D, custom motion and asset-manifest workflows. Use whenever a project needs generated art, animation, 3D, sound or voice.
---

# Asset Generator

`api.md`, `motion.md` and `scripts/` sit next to this file. Commands run from the project, so use full paths. Set:

```bash
ASSET_SKILL=".agent/skills/asset-gen"
APIZ="$ASSET_SKILL/scripts/apiz_asset.py"
```

Run paid commands with `python "$APIZ" ...` on Windows or `python3 "$APIZ" ...` elsewhere.

## Route the request

Choose by asset type, then respect the user's budget words: **free**, **local only**, **best quality**, or an explicit cost cap.

- **Images, GIFs and ordinary video:** apiz is the default. Image: `apiz/gpt-image-2.6-flare`. Video: `minimax/h3` (MiniMax-H3) by default; `st-ai/super-seed2` remains available when explicitly selected.
- **Speech, designed voices and music:** apiz is the default. Speech: `speech-2.8-hd`. Voice design: `minimax/voice-design`. Music: `minimax/music-gen`.
- **Free/local images, SFX, TTS, rigs and generated moves:** use `godogen_assets` below when installed.
- **3D:** local `gen3d`/Blender first. Use Tripo when local generation is unavailable or a non-humanoid rig is needed.
- **Exact mechanical or articulated 3D:** author it in Blender.
- **Gameplay motion, held props and contact:** read `motion.md`; do not replace gameplay state with a generated clip.

Paid calls cost real money. Confirm the first paid call and its estimate unless the user already authorized spending. Never claim a price from an old table: record the task's returned `price_credits`/`cost_cents`. **100 credits = ¥1, so the numeric credit value equals cents.**

Use Flare for ordinary image work. Its current schema exposes transparent PNG, not a direct transparent-GIF switch; for transparent animated sprites, generate referenced transparent PNG poses and assemble the GIF locally as shown in `api.md`.

## apiz preflight

The wrapper uses the installed apiz CLI and only needs Python 3.11+; ffmpeg is needed for audio/video conversion.

```bash
python "$APIZ" doctor
python "$APIZ" models --category video --search h3
python "$APIZ" docs minimax/h3
# Optional Seedance compatibility route
python "$APIZ" docs st-ai/super-seed2
```

If setup is missing:

```bash
curl -fsSL https://apiz.ai/cli | APIZ_INSTALL_DIR="$HOME/.local/bin" sh
apiz auth login
python "$APIZ" doctor
```

The wrapper discovers `--apiz`, `APIZ_BIN`, `apiz`/`apiz-cli` on `PATH`, then `~/.local/bin/apiz.exe` or `~/.local/bin/apiz`. Authentication lives in apiz's profile; do not copy API keys into project files, prompts, manifests or logs.

Every generation writes `<output>.apiz.json`. It stores the request hash, uploaded URL parameters, task id, status, returned price and downloaded files. Rerun the identical command to resume; do not resubmit a paid task because it is slow. Local polling defaults to 3600 seconds and never cancels the remote task. `--no-wait` submits and returns the task id. `--force` intentionally creates a new paid call.

See `api.md` for exact schemas, commands, pricing factors, H3 mixed references, Seedance compatibility/Omni references, Tripo and the direct-provider fallback.

## Local: godogen_assets

[godogen_assets](https://github.com/htdt/godogen_assets) runs local generators on this machine's GPU, one command per task, for free. Its docs are authoritative; this is the project-facing summary.

```bash
p=$(command -v gen3d) && GODOGEN_ASSETS=$(dirname "$(dirname "$(readlink -f "$p")")")
```

If `gen3d` is not on `PATH`, local generation is not set up. Read `$GODOGEN_ASSETS/README.md` once, then each tool's README up to `How it works` before first use.

| Command | Makes | README |
|---|---|---|
| `qwen-image` | basic PNGs; `rgba` for alpha; `edit -i ref.png` for image-to-image | `image/` |
| `gen3d` | textured GLB from an image | `mesh/` |
| `mia-rig` | Mixamo-rigged humanoid from a GLB | `rig/` |
| `add-moves`, `gen-moves` | idle/walk/run/jump and custom text-prompted moves | `motion/` |
| `grip-prop` | holdable prop; use with `add-moves --hold` | `motion/` |
| `lipsync` | speaking mouth and lip-synced clip | `lipsync/` |
| `stable-audio` | SFX and seamless ambience loops | `sfx/` |
| `qwen-tts` | described or reference-cloned voice lines | `voice/` |

A character pipeline: transparent T-pose reference (`apiz_asset.py image --transparent`, or `qwen-image rgba`) → `gen3d` → `mia-rig --fingers --anim none` → `add-moves`; add `gen-moves` for custom motion and `lipsync` for speech. Props stop after `gen3d`; a held prop continues through `grip-prop` and `add-moves --hold`, not an engine-tuned offset.

- Always pass `-o` into the project.
- Run one GPU job at a time, sequentially, with a long timeout or in the background.
- For game characters, use real-time budgets such as `gen3d --faces 30000 --tex 1024`.
- Generate one hero asset and derive the rest with `--image` (`api.md`) or `qwen-image edit -i`.
- Design small sprites at display sizes of at least 128 px, or generate a kit and split it with `scripts/grid_slice.py kit.png -o out/ --grid 2x2 --names "a,b,c,d"`.
- Generate one facing direction and flip it at runtime.
- Pick audio format from the output extension; Bevy's default decoder expects Ogg Vorbis.
- Inspect GLBs by rendering them and audio by reading a spectrogram, following the local tool docs.

## Blender

A headless `bpy` script (`blender -b -P make_part.py`, exporting with `bpy.ops.export_scene.gltf`) handles exact/articulated shapes, generated-GLB cleanup, pivots, decimation and mechanical or procedural animation. If `blender` is not on `PATH`, `asset-blender script.py -- args` can use godogen_assets' Blender.

## Asset manifest

Track generated assets in the project's `README.md`, including the size used in the scene. `gen3d` output has no meaningful real-world scale, so decide it here.

- 3D: meters (`4m long`, `1.8m tall`, `0.3m`).
- Textures: tile size (`2m tile`).
- Backgrounds: pixel size and behavior (`1920x1080, fullscreen`).
- Sprites: display pixels (`128x128 px`).
- Audio: length and use (`1.2 s one-shot`, `8 bars / 22.6 s loop`).

| Name | Description | Size | Path | Cost |
|---|---|---|---|---|
| crate | wooden supply crate | 0.8m | assets/glb/crate.glb | local |
| theme | village shop music | 8 bars / 22.6 s loop | assets/audio/shop_loop.ogg | 100 credits |

Use the real returned cost; do not prefill an estimate as fact.

## Setup

- **Default apiz path:** install apiz, authenticate, then run `doctor`. No Python provider packages are required by `apiz_asset.py`.
- **Conversion:** install ffmpeg on `PATH` for OGG/WAV/FLAC output and frame extraction.
- **Local generation:** follow godogen_assets' Setup only when the user wants it; it needs an NVIDIA GPU, substantial disk, a Hugging Face token and long downloads.
- **Blender:** install the current release, or use godogen_assets' bundled `asset-blender`.
- **Legacy direct providers:** only for an explicitly chosen fallback in `api.md`; install `scripts/requirements.txt` in a venv when needed. Direct provider keys are not part of the default workflow.

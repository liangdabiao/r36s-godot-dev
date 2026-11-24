---
name: engine-guide
description: Build, test and deploy games or engine-rendered video with Godot 3.5 or Godot 4 (GDScript/C#), Bevy, Babylon.js, three.js or HTML. Covers existing-project version detection, R36S/PortMaster/FRT handheld deployment, toolchain setup, headless screenshots/video and silent runtime traps. Use when starting or working on a game, interactive 2D/3D page, presentation, explainer, trailer or product showcase.
---

# Engine guide

One guide per engine sits next to this file: the stack, a project sketch, build commands, headless capture, and the traps that pass a build and break at runtime. Read the chosen engine's guide before writing the project. `setup.md` installs what the engine needs.

## Existing-project gate — do this first

1. Read `project.godot`, the script language and any `.csproj` before choosing a guide. Run `godot --version` when an editor is installed; record the exact major/minor version.
2. **Preserve the project's engine and language.** Godot 3.5 normally has `config_version=4`; Godot 4 has `config_version=5`. In Godot 3 use `godot-3.md`; in Godot 4 use the matching guide below. Do not open, migrate or export a Godot 3 project with Godot 4 unless the user explicitly asks for migration.
3. Match `config_version` and version-sensitive settings to that installed toolchain. A missing toolchain is a setup task, not permission to upgrade the project. New projects use the current stable release resolved by `setup.md`.
4. For an existing handheld/FRT target, also read `r36s-portmaster.md`. A desktop export is not proof that the PCK or launcher works on the device.

| Guide | Stack | Pick it for |
|---|---|---|
| `godot-3.md` | Godot 3.5, GDScript | this R36S project; existing Godot 3 editor projects; PortMaster/FRT deployment |
| `godot.md` | Godot 4, C# | desktop 2D or 3D; the fewest runtime surprises in long unattended runs |
| `godot-gdscript.md` | Godot 4, GDScript | a Godot 4 project the user will keep developing in the editor |
| `bevy.md` | Bevy, Rust | a Rust codebase: ECS, no editor, many entities |
| `babylon.md` | Babylon.js, TypeScript | a browser game that leans on engine systems: physics, GUI, particles, animation |
| `threejs.md` | three.js, TypeScript | a browser piece that leans on its look: custom shaders, stylized rendering, a light page |
| `html.md` | DOM + canvas and three.js, TypeScript | 2D that is mostly text and UI: interactive fiction, cards, grid roguelikes, puzzles, management |

## Choosing

Every engine gets the same loop (build, generate assets, capture), so the choice comes down to what the user holds at the end and how they watch along the way. When the brief leaves it open, it is the user's call as much as yours: it decides what they get, and a switch later is a rewrite. What's already installed can tip a close call: `godot --version` (`mono` in it means the .NET build), `dotnet --version`, `cargo --version`, `node --version`.

- **How the user watches.** On a remote box or steering from a phone, a browser engine wins: the dev server is a URL they refresh while you edit. Godot and Bevy run as desktop apps; from a headless server the user sees them in a recorded video, or pulls the repo and runs it. On the user's own desktop the engines are even.
- **2D.** Godot has a dedicated 2D engine (pixel-space nodes, tilemaps, 2D physics). Bevy handles 2D well. Babylon.js and three.js are 3D-first and draw 2D as sprites and planes. For 2D that is mostly text, panels and buttons, `html` builds on the DOM: type and CSS are the art, with canvas and three.js for motion, effects and 3D moments.
- **Godot: version, then language.** First identify Godot 3 versus 4. Godot 3.5 uses the standard editor for GDScript (`KinematicBody2D`, `move_and_slide(velocity)`, `export`, `onready`); Godot 4 uses `CharacterBody2D`, `move_and_slide()`, `@export`, `@onready` and typed signals. C# exists in both but needs the matching Mono/.NET build and SDK; it is not required for this GDScript project. GDScript exports everywhere Godot does; check current C# platform support before a web export.
- **Babylon.js or three.js.** Babylon.js is a full engine: Havok physics, GUI, particles, animation groups and an inspector come in the box, so there are fewer seams to wire, at the cost of a heavier bundle. three.js is a renderer: you pick and wire physics (Rapier), UI (HTML over the canvas) and audio, and get the deepest pool of web 3D examples, the most control over the look (custom shaders, postprocessing, WebGPU and TSL node materials) and a small bundle.
- **Bevy** is for a project that should be Rust: code only, ECS, compile-time guarantees, headroom for many entities. It compiles slowest, and its API moves between releases faster than training data catches up, so its guide reads the installed source.
- **No strong preference:** `babylon` for a user who watches and steers from anywhere; `godot` for a desktop game they'll receive as a video or run themselves.

## Beyond games

Godot 4's movie writer, Bevy's offscreen binary and three.js's stepped capture advance a fixed timestep per saved frame: render cost never shows up in the result, and every frame lands exactly where it was scheduled. Godot 3.5 does not use that movie-writer workflow; use the viewport PNG capture in `godot-3.md`. That makes an engine a studio for more than games. The guides say "the game"; read it as whatever is being built.

- **Video**: a presentation, explainer, trailer, product showcase, data story, music visualization. The capture is the deliverable. Script camera, animation and text on one timeline, place generated voice-over and music (the asset-gen skill) on the same timeline, and mux with ffmpeg. Godot is the strongest pick: Godot 4 has deterministic `--write-movie` with scene audio, while Godot 3 uses `--fixed-fps` plus viewport PNGs; 3D, 2D, text, particles and tweens stay in one toolset. Use three.js when the look is shader-driven or the piece should also live on the web.
- **Interactive pages**: a product configurator, an interactive explainer or data visualization, a 3D landing scene. three.js or Babylon.js, or `html` when it is mostly text and UI.

# Godot engine guide (3.5 / GDScript)

Stack: **Godot 3.5.3 standard editor**, **GDScript**. The R36S project is pinned to this version; do not migrate it to Godot 4 as part of an ordinary fix or deployment.

## Detect and preserve the version

```bash
godot --version
```

Expect `3.5.3.stable...` here. Read `project.godot`: `config_version=4` is normal for Godot 3.5, while Godot 4 uses `config_version=5`. If the installed editor is 4.x, obtain the official 3.5.3 editor before opening or exporting this project. A missing export template does not justify changing engine versions.

## Project shape

- `project.godot` — display, input, rendering and main scene. Preserve `config_version=4`.
- `scripts/*.gd` or `character/scripts/*.gd` — runtime behavior.
- `scenes/*.tscn` — scenes; `assets/` contains only files the running game loads.
- `export_presets.cfg` — export presets. This project uses `Linux/X11` as the pack preset even though the deliverable is a PCK loaded by FRT.

This project's compatibility settings are intentional:

```ini
[display]
window/size/width=640
window/size/height=480
window/stretch/mode="2d"

[rendering]
quality/driver/driver_name="GLES2"
vram_compression/import_etc=true
vram_compression/import_etc2=false
```

GLES2 + ETC1 targets the R36S Mali-G31. Keep these unless the target hardware and runtime have been retested.

## Godot 3 language and node rules

- Use `export var`, `onready var`, `func _ready():`, `yield(...)`, `instance()` and lowercase signals such as `pressed`.
- 2D movement uses `KinematicBody2D` and `move_and_slide(velocity)`. `CharacterBody2D`, `move_and_slide()` without a velocity, `@export`, `@onready`, `await` and Godot 4 signal syntax belong to Godot 4.
- Static typing exists in 3.5, but do not paste Godot 4-only typed APIs into it. Prefer explicit types at boundaries and run the path in a smoke test.
- `Camera2D.zoom = Vector2(0.5, 0.5)` means **2× magnification** in Godot 3. A value below 1 zooms in; it is not a percentage to multiply by 0.5 again.
- Put the camera under the moving player when it must follow. Set limits in world coordinates and enable smoothing.
- For a scaled `TileMap`, set the node's `scale`, not only `cell_custom_transform`: the custom transform changes drawing but does not reliably scale collision cells. Keep the walkable ground unobstructed by overlapping water cells.
- A runtime `SCRIPT ERROR` can abort one callback while the process still exits 0. Gate runs on both exit code and log contents.

## Build and validation gate

Use the pinned executable directly when it is not on `PATH`:

```bash
GODOT=/tmp/godot-3.5.3/Godot_v3.5.3-stable_win64.exe
"$GODOT" --version

timeout 180 "$GODOT" --headless --path "D:/r36s-demo-main" --editor --quit
"$GODOT" --headless --path "D:/r36s-demo-main" --script res://character/scripts/Player.gd --check-only
"$GODOT" --path "D:/r36s-demo-main" --no-window --quit
```

- The editor/import run refreshes imported textures and class caches after asset or `class_name` changes.
- `--check-only` needs `--script`; it catches parse/type errors but does not prove gameplay works.
- Godot 3 uses `--quit`, not `--quit-after`. It has no `--import` subcommand; use the headless editor run above.
- Treat `SCRIPT ERROR`, `ERROR:`, parse failures and missing-resource messages as failures even when the exit code is 0. RID/ObjectDB leak notices on headless exit are benign.
- Run a `SceneTree` smoke script that loads the real main scene, calls `_physics_process` or moves the body, and asserts player/camera/collision state. Delete temporary diagnostics afterward.

## Scene serialization

Generate scenes with a one-shot `extends SceneTree` builder when practical:

```gdscript
extends SceneTree

func _initialize() -> void:
    var root := Node2D.new()
    get_root().add_child(root)
    set_owner_recursive(root, root)
    var packed := PackedScene.new()
    if packed.pack(root) != OK:
        quit(1)
        return
    var test := packed.instance()
    var before := count_nodes(root)
    var after := count_nodes(test)
    test.free()
    if before != after:
        push_error("nodes dropped while packing")
        quit(1)
        return
    var err := ResourceSaver.save("res://scenes/Generated.tscn", packed)
    quit(0 if err == OK else 1)

func set_owner_recursive(node: Node, owner_node: Node) -> void:
    if node != owner_node:
        node.owner = owner_node
    for child in node.get_children():
        if child.get_filename() == "":
            set_owner_recursive(child, owner_node)

func count_nodes(node: Node) -> int:
    var total := 1
    for child in node.get_children():
        total += count_nodes(child)
    return total
```

- Set `owner` on every serialized descendant, but do not recurse into instantiated `.tscn`/GLB nodes (`get_filename()` is non-empty).
- Godot 3 calls `ResourceSaver.save(path, resource)`; Godot 4 uses `ResourceSaver.save(resource, path)`. A wrong argument order can be a parse error that still exits 0, so inspect logs.
- Attach a GDScript with `set_script()` before assigning its `export` properties.
- Build leaf scenes before parents that `load()` them; a not-yet-generated `preload()` is a parse error.
- For hand-edited `.tscn`, keep `load_steps` consistent and declare `SubResource` blocks before nodes reference them. Validate by opening the scene, not only by reading the text.
- Use primitive collision shapes for imported meshes. Do not create trimesh/convex collision for every GLB mesh on low-power hardware.

## PCK export for FRT

Godot 3.5 `--export-pack` needs a preset but **does not need binary export templates**:

```bash
mkdir -p .build/demo
"$GODOT" --headless --path "D:/r36s-demo-main" \
  --export-pack "Linux/X11" "D:/r36s-demo-main/.build/demo/demo.pck"
```

Then launch the pack with the same major/minor engine:

```bash
"$GODOT" --video-driver GLES2 --main-pack .build/demo/demo.pck --no-window --quit
```

Record PCK file count, byte size and SHA-256. For R36S deployment, read `r36s-portmaster.md`; a successful desktop launch is only the first gate.

## Screenshots and frame sequences

Godot 3.5's exposed command line here has `--fixed-fps`, but not the Godot 4 `--write-movie` workflow. Capture viewport PNGs from a dedicated `SceneTree` script, then encode with ffmpeg:

```gdscript
extends SceneTree

var frames := -2

func _initialize() -> void:
    connect("idle_frame", self, "_capture")
    change_scene("res://scenes/Game.tscn")

func _capture() -> void:
    if frames >= 120:
        quit()
        return
    var dir := Directory.new()
    if dir.make_dir_recursive("res://screenshots/result") != OK:
        push_error("could not create capture directory")
        quit(1)
        return
    if frames >= 0:
        var texture := get_root().get_texture()
        if texture == null:
            push_error("root viewport texture is null")
            return
        var image := texture.get_data()
        if image == null or image.get_width() == 0 or image.get_height() == 0:
            push_error("root viewport image is empty")
            return
        image.flip_y()
        if image.save_png("res://screenshots/result/frame_%04d.png" % frames) != OK:
            push_error("could not save capture")
            quit(1)
            return
    frames += 1
```

```bash
"$GODOT" --path "D:/r36s-demo-main" --resolution 640x480 \
  --fixed-fps 30 --script res://test/capture.gd --no-window
ffmpeg -y -framerate 30 -i screenshots/result/frame_%04d.png \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart screenshots/result/video.mp4
```

`idle_frame` is the Godot 3 callback used here; `_idle_process` is not invoked for this script path. The first two frames are warm-up and are not saved. Run rendering captures with a real GPU/display path; this example was verified with the Godot 3.5.3 OpenGL renderer. Pre-position the camera before capture and drive input from the capture script.

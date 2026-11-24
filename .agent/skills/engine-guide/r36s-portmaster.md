# R36S / PortMaster / FRT deployment

Use this guide with `godot-3.md` for the current project. FRT is a Godot 3 platform layer; it is not a Godot 4 runtime and does not provide C#/Mono.

## Verified target

| Item | Current project/device |
|---|---|
| Desktop editor/export | Godot 3.5.3 standard, GDScript |
| Device runtime | PortMaster `frt_3.5.2` = FRT 2.1.0 + Godot 3.5.2 |
| Device | R36S, RK3326, Mali-G31, 640×480 |
| Renderer/textures | GLES2 / ETC1 |
| PortMaster | `/opt/system/Tools/PortMaster` on this device |
| Runtime image | `/opt/system/Tools/PortMaster/libs/frt_3.5.2.squashfs` |
| Game directory | `/roms/ports/demo` |

Re-read the device information before deployment: IP addresses, firmware and PortMaster paths can change. Connection details live in the project's `r36s.md`; do not copy credentials into source files or logs.

## Version rule

Godot 3.5's PCK validation ignores the patch number, so the verified 3.5.3 PCK loads on the 3.5.2 runtime. This is **not** a general compatibility promise. Keep the same major/minor (3.5.x), and do not infer that a newer runtime will work merely because its version check accepts an older pack. If either side changes minor version, re-export and test on the device.

## Package layout

```text
demo.zip
├── demo.sh
└── demo/
    ├── demo.pck
    └── demo.gptk
```

`demo.sh` must be at the ZIP root, executable after extraction, and use paths consistent with where PortMaster places it. Keep the PCK and gptokeyb config beside the launcher's working directory.

## Launcher contract

The current launcher is the reference implementation in `.build/demo.sh`:

1. Source PortMaster's `control.txt`, `device_info.txt` and optional firmware module.
2. Resolve `GAMEDIR`, create its config directory, set `XDG_CONFIG_HOME`/`XDG_DATA_HOME`, export `SDL_GAMECONTROLLERCONFIG`, then `cd "$GAMEDIR"`.
3. Check for the FRT squashfs. If absent, use PortMaster's `harbourmaster` runtime installer; do not download an arbitrary engine binary.
4. Mount the squashfs at `$HOME/godot` and prepend it to `PATH`.
5. Disable FRT's own exit shortcuts, then route the desired key through FRT:

```bash
export FRT_NO_EXIT_SHORTCUTS=1
export FRT_EXIT_SHORTCUT=esc
GODOT_OPTS="${GODOT_OPTS:-} --video-driver GLES2"
```

6. Make `/dev/uinput` writable when required by the device, start `gptokeyb` with the game's config, then launch:

```bash
"$runtime" $GODOT_OPTS --main-pack "demo.pck"
```

7. After the runtime exits, unmount the squashfs, stop only the gptokeyb process started by this launcher, restore event handling and clear the display. Prefer saving `$!` and a cleanup trap over broad `pkill`/`pidof` cleanup in new launchers.

## Input mapping

The project binds movement actions to both WASD and native joypad axes, so keyboard, FRT gamepad events and gptokeyb-generated keys share `Input.get_axis()`.

The current `demo.gptk` maps:

| Physical control | Generated input |
|---|---|
| D-pad | W / A / S / D |
| Left stick | W / A / S / D |
| Start | Esc |
| Back | Enter |
| Face/trigger buttons | mouse left (existing demo behavior) |

Do not map the left stick to mouse movement for this game. Keep Start → Esc → FRT exit; setting only one of the two FRT exit variables is not the verified configuration for this runtime.

## Desktop gate

Before copying to the device:

- Run the Godot 3.5.3 import/editor pass and parse-check every changed script.
- Run the real scene and assert camera follow, movement, water collision and visible map layers.
- Export the PCK with `--export-pack`; templates are not required for this operation.
- Launch the PCK with `--video-driver GLES2 --main-pack ... --no-window --quit` and inspect logs, not only the exit code.
- Record `sha256sum` for `demo.sh`, `demo.pck` and `demo.gptk`.

## Device deployment and verification

Use the SSH client available on the host. Pin the host key recorded in `r36s.md`; never use a blind `StrictHostKeyChecking=no` fallback.

```bash
plink -ssh -P 22 -hostkey "<VERIFIED_HOST_KEY>" USER@DEVICE_IP \
  "mkdir -p /roms/ports/demo && uname -m && df -h /roms"
pscp -hostkey "<VERIFIED_HOST_KEY>" \
  .build/demo.sh USER@DEVICE_IP:/roms/ports/demo.sh
pscp -hostkey "<VERIFIED_HOST_KEY>" \
  .build/demo/demo.pck .build/demo/demo.gptk USER@DEVICE_IP:/roms/ports/demo/
```

Then verify remote hashes, executable bit and nonempty files. Some ArkOS `/roms` filesystems report permissive modes unusually; execution and matching hashes matter more than the displayed `777`.

Run the runtime over SSH with a temporary read-only mount and capture its exit status:

```bash
plink -ssh -P 22 -batch -hostkey "<VERIFIED_HOST_KEY>" USER@DEVICE_IP \
  "d=\$(mktemp -d /tmp/r36s-demo-godot.XXXXXX); cleanup(){ sudo umount \"\$d\" >/dev/null 2>&1 || true; rmdir \"\$d\" 2>/dev/null || true; }; trap cleanup EXIT; sudo mount -o ro /opt/system/Tools/PortMaster/libs/frt_3.5.2.squashfs \"\$d\" || exit 20; cd /roms/ports/demo || exit 21; PATH=\"\$d:\$PATH\" timeout 30s frt_3.5.2 --video-driver GLES2 --main-pack demo.pck --no-window --quit --verbose; rc=\$?; echo RUNTIME_EXIT=\$rc; exit \$rc"
```

Expected evidence includes Godot `3.5.2.stable.custom_build`, GLES2, Mali-G31, `res://scenes/Game.tscn` loading and exit 0. An ALSA `underrun occurred` warning was nonfatal in the verified run; repeated audio failures or missing resources are not.

SSH proves loading, not physical button/display behavior. The current demo has already been confirmed by the user as visible and playable on the R36S. For a later redeployment, repeat the physical gate: map visible, player moves with D-pad and left stick, water blocks movement, camera follows, and Start exits cleanly back to PortMaster/EmulationStation.

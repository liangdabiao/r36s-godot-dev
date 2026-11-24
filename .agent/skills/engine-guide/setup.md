# Setup

Resolve "latest" at install time (release page/API or package manager), never from memory. **On an existing project, keep the versions it pins.** Do not install the newest engine merely because it is newest. System packages need root; when you don't have it, give the user the one command to run.

## All engines

- `ffmpeg` (encoding captures), ImageMagick (`magick`), and on headless Linux `xvfb` (a virtual display) and `vulkan-tools` (`vulkaninfo`).
- Video capture wants a hardware GPU path; software rendering (`llvmpipe`, `lavapipe`, SwiftShader) is good for stills only. On Linux, `vulkaninfo --summary` names the device; with an NVIDIA GPU, `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json` selects it.
- macOS has no `timeout`, which the Godot guide wraps every call in: `brew install coreutils` provides it as `gtimeout`.

## Godot

Run `godot --version` first and read `project.godot`. Keep an existing project's major/minor version and `config_version` (normally `4` for Godot 3.5, `5` for Godot 4). The R36S project uses **Godot 3.5.3 standard + GDScript** on the desktop and a Godot 3.5.2 FRT runtime on the device; read `godot-3.md` and `r36s-portmaster.md` instead of the Godot 4 instructions.

For a new project, the current stable is the newest release on GitHub: `curl -s https://api.github.com/repos/godotengine/godot/releases/latest` gives the tag (`X.Y.Z-stable`) and its asset names. For an existing Godot 3 project, obtain the exact 3.5.x editor from the official Godot downloads/releases rather than substituting a 4.x binary.

The following .NET rules apply **only to Godot 4 C#**:
- **C# needs the .NET build** (`..._mono_linux_x86_64.zip`). The standard build (`..._linux.x86_64.zip`) runs only GDScript; the .NET build runs both. `godot --version` ends in `.mono` for the .NET build.
- **`GodotSharp/` must sit next to the binary** that runs. The .NET zip holds both: move them together, e.g. the binary to `/usr/local/bin/godot` and `GodotSharp/` to `/usr/local/bin/GodotSharp/` (or both into `~/.local/bin/` without root).
- **macOS:** `brew install --cask godot-mono` for C#; the plain `godot` cask's command runs without C#. Make `godot` on `PATH` a wrapper script, not a symlink — `exec /Applications/Godot_mono.app/Contents/MacOS/Godot "$@"` — since Godot looks for `GodotSharp/` beside the path it was invoked as, and through a symlink it hangs on a fatal-error modal that `--headless` can't dismiss.
- **.NET SDK for C#:** resolve the supported SDK at install time; install from dot.net into `~/.dotnet`, with `DOTNET_ROOT` set and it on `PATH` (`brew install dotnet` on macOS). Match the SDK/package versions to the project's `.csproj`.
- **Check Godot 4:** `timeout 60 godot --headless --quit` (RID/ObjectDB-leak warnings are harmless). Assembly errors on Linux, or a timeout with output ending at `.NET: Initializing module...` on macOS, mean `godot` can't find `GodotSharp/`.

For Godot 3, use `timeout 60 godot --no-window --quit`; do not pass Godot 4-only flags such as `--quit-after`.

## Bevy

Rust through rustup on current stable (`rustup update stable`). Linux builds link system libraries (ALSA, udev, X11 or Wayland): Bevy's `docs/linux_dependencies.md` lists the packages per distro.

## Babylon.js, three.js, HTML

- Node.js at the current LTS, from nodejs.org or a version manager. Vite's minimum rises with its releases, and `npm create vite@latest` says when the installed Node is too old.
- Chrome or Chromium for headless runs; set `CHROME_BIN` when it isn't on a common path. Babylon.js and three.js capture, and HTML games that use three.js, need hardware WebGL2 (their guides, Capture).

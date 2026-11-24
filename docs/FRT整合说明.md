# 与本工程整合使用 FRT 的说明

> 本文讲的是：**怎么把本工程的 Godot 3.5 游戏跑在 FRT 上**，以及 FRT 和 PortMaster、Godot 版本之间那些容易混淆的对应关系。
>
> 参考来源：FRT 官方仓库 <https://github.com/efornara/frt>、FRT Releases、SourceForge 历史版本页、PortMaster 的 Godot 运行时装包。
>
> 文中的结论分三种标注：
>
> - **【已核实】**：本次直接读了源码、二进制或文件后确认；
> - **【官方说明】**：来自 FRT / PortMaster / Godot 官方文档或仓库；
> - **【需实测】**：按代码和输入路径推断，必须在你的机器上跑一遍确认。

---

## 目录

- [0. 结论速览](#0-结论速览)
- [1. 先分清三个"版本号"](#1-先分清三个版本号)
- [2. FRT 是什么，什么时候该用它](#2-frt-是什么什么时候该用它)
- [3. 本工程和 FRT 的整合点](#3-本工程和-frt-的整合点)
- [4. 方式 A：PCK + 现成 FRT 运行时（推荐）](#4-方式-apck--现成-frt-运行时推荐)
- [5. 方式 B：用 FRT 做自定义导出模板](#5-方式-b用-frt-做自定义导出模板)
- [6. 去哪下载、怎么选对版本](#6-去哪下载怎么选对版本)
- [7. 命令行参数](#7-命令行参数)
- [8. 退出快捷键与进程行为](#8-退出快捷键与进程行为)
- [9. 视频、音频、输入在 FRT 下的表现](#9-视频音频输入在-frt-下的表现)
- [10. R36S 上的完整操作步骤](#10-r36s-上的完整操作步骤)
- [11. 故障排查表](#11-故障排查表)
- [12. 和当前 PortMaster 模板的差异](#12-和当前-portmaster-模板的差异)
- [13. 上线前检查清单](#13-上线前检查清单)
- [附录 A：命令速查](#附录-a命令速查)
- [附录 B：参考链接](#附录-b参考链接)

---

## 0. 结论速览

| 问题 | 结论 | 依据 |
|---|---|---|
| 本工程的 PCK 是什么版本 | Godot **3.5.3** 导出，745,856 字节（约 728 KiB） | 【已核实】`sha256sum` 与导出日志 |
| 掌机上 `frt_3.5.2` 到底是什么 | **FRT 2.1.0（commit 400ec48）+ Godot 3.5.2**，32 位 ARM 可执行文件 | 【已核实】PortMaster 运行时二进制内字符串 |
| 3.5.3 的 PCK 能跑在 3.5.2 的运行时上吗 | 能。Godot 3.5 的 PCK 校验**不校验补丁号** | 【已核实】Godot 3.5 `core/io/file_access_pack.cpp` |
| 能不能用最新的 3.6.3 运行时跑这个 PCK | 版本检查**不会拦**（它只拒绝比引擎新的包），但资源/GDScript 兼容性本工程未实测；稳妥仍用 3.5.x 运行时 | 【已核实】校验是单向的；兼容性【需实测】 |
| 最小启动命令 | `frt_3.5.2 --video-driver GLES2 --main-pack demo.pck` | 【已核实】`demo.sh` 第 55、59 行 + FRT 参数透传 |
| 运行时依赖 | 动态链接 **`libSDL2-2.0.so.0`** | 【已核实】`readelf -d` |
| 退出快捷键怎么配 | FRT 2.0.x 用 `FRT_NO_EXIT_SHORTCUTS`；FRT 2.1.0+ 用 `FRT_EXIT_SHORTCUT`。当前脚本同时设置两者，并把新版设为 `esc`，配合 Start → Esc 退出 | 【已核实】FRT 两个版本的源码 |
| 本工程有没有原生插件 | 没有，只有 Git 插件的描述文件，不涉及 ABI 对齐 | 【已核实】PCK 文件表 |
| 掌机输入 | `demo.gptk` 把十字键/左摇杆映射成 W/A/S/D；A/Y/R1→J 剑击，B/R2/L2→K 闪避，X/L1→L 技能，Select→P 暂停，Start→Esc 退出 | 【已核实】`demo.gptk` 与 InputMap |

一句话：**地图显示、相机跟随、水域碰撞、掌机方向输入和退出键已完成代码整合，通过电脑桌面验证，并于 2026-11-24 在真实 R36S 上确认游戏显示和可玩。**

---

## 1. 先分清三个"版本号"

网上关于 FRT 的说法乱，绝大多数是因为把下面三个版本号混成了一个。

### 1.1 三个版本

| 名称 | 例子 | 含义 |
|---|---|---|
| **FRT 平台版本** | `2.1.0`、`3.6.3-1` | FRT 这个"Godot 运行环境"自己的版本 |
| **Godot 引擎版本** | `3.5.2`、`3.5.3`、`3.6.3` | 里面打包的 Godot 引擎版本 |
| **PortMaster 运行时装包名** | `frt_3.5.2` | PortMaster 给这个包起的名字，**这里的 3.5.2 指的是 Godot 版本，不是 FRT 版本** |

最容易踩的坑：

> PortMaster 里那个叫 `frt_3.5.2` 的运行时，**不是** FRT 3.5.2，而是 **FRT 2.1.0 + Godot 3.5.2**。

这不是猜的。直接看 PortMaster 运行时的二进制：

```text
$ strings frt_armhf_3.5.2 | grep -E "2\.1\.0|400ec48|3\.5\.2"
2.1.0
stable
400ec48
3.5.2.stable.custom_build
FRT_EXIT_SHORTCUT
```

并且 `--frt -v` 输出的是 `2.1.0.stable.400ec48`。【已核实】

### 1.2 FRT 的两代文件命名

| 年代 | 命名格式 | 例子 | 解析 |
|---|---|---|---|
| 旧（2.x） | `frt_<FRT版本>_<Godot版本>_<架构>.bin` | `frt_210_352_arm32v7.bin` | FRT 2.1.0 + Godot 3.5.2 + arm32v7 |
| 新（3.x） | `frt_<Godot版本>-<修订>_<架构>_<变体>` | `frt_3.6.3-1_arm64_release` | Godot 3.6.3、修订 1、arm64、release 变体 |

所以看到 `frt_210_352_arm64v8.bin`，要读成「FRT 2.1.0 / Godot 3.5.2 / arm64v8」，而不是「3.5.2 版 FRT」。

### 1.3 版本必须怎么配

| 你的 PCK | 能用的运行时 | 说明 |
|---|---|---|
| 3.5.3（本工程现状） | Godot 3.5.x 的 FRT（如 PortMaster `frt_3.5.2`、SourceForge `frt_210_352_*`） | 补丁号不同不拦，最稳 |
| 3.5.3，想用 3.6.x 运行时 | Godot 3.6.x 的 FRT（GitHub 最新 release） | 版本检查放行旧包，但脚本/资源兼容需实测 |
| 3.6.x 重新导出 | Godot 3.6.x 的 FRT | 同版本最省心 |
| 4.x | FRT 不支持 | FRT 只做 Godot 3 |

原因在 Godot 3.5 / 3.6 的 PCK 校验代码（`core/io/file_access_pack.cpp`）：

```cpp
uint32_t version = f->get_32();
uint32_t ver_major = f->get_32();
uint32_t ver_minor = f->get_32();
f->get_32(); // patch number, not used for validation.
...
if (ver_major > VERSION_MAJOR ||
    (ver_major == VERSION_MAJOR && ver_minor > VERSION_MINOR)) {
    ERR_FAIL_V_MSG(false, "Pack created with a newer version of the engine: ...");
}
```

也就是说：

- **补丁号完全不看**，所以 3.5.3 的包能在 3.5.2 上开；
- 校验是**单向**的，只拒绝"比引擎新"的包；
- 所以 3.5.x 的包在 3.6.x 运行时上**不会**被版本检查拦住（但资源/GDScript 是否完全兼容，本工程没有实测）；
- 反过来，3.6.x 的包在 3.5.x 运行时上会被拒绝，报 `Pack created with a newer version of the engine`。

【已核实】3.5 与 3.6 的 `PACK_FORMAT_VERSION` 都是 1，校验逻辑一致。

稳妥做法仍然是：**PCK 和运行时用同一个 Godot 版本导出/下载**。版本检查通过只是第一关，不是兼容性承诺。

---

## 2. FRT 是什么，什么时候该用它

【官方说明】FRT 的定位是：**在单板计算机（SBC）上运行 Godot 3 游戏的平台层**，底层用 SDL2 提供窗口、输入和音频，支持 GLES2 / GLES3。

它解决的问题是：

- 设备没有完整桌面环境（没有 X11），只有 KMS/DRM、FBDEV 或 Wayland；
- 官方 Godot ARM 导出模板默认假设有 X11；
- 需要直接读手柄、直接输出音频，不依赖桌面服务。

FRT 官方 README 的建议顺序是：

1. **优先用 Godot 官方 ARM 导出模板**（有 X11 的板子）；
2. 只有在没有 X11（KMS/DRM、FBDEV、Wayland）时，才需要 FRT 这类平台层；
3. FRT 提供 Docker 构建脚本（`frt-pull` / `frt-compile`）来产出导出模板或运行时。

和本工程的关系：

- 本工程跑在 R36S 这类掌机上，PortMaster 的 Godot 运行时就是 FRT；
- 所以你在掌机上看到的"Godot 运行时"，本质是「FRT + Godot」；
- 你不需要为 FRT 改一行 GDScript。

**不适合用 FRT 的场景：**

- Godot 4 项目（不支持）；
- 有完整 X11 桌面、且官方 ARM 模板能跑通的设备（没必要多一层）；
- 需要 Godot 的 C# / Mono（FRT 的构建是标准 Godot 3，不额外提供 Mono）。

---

## 3. 本工程和 FRT 的整合点

把工程的实际情况逐项对照 FRT 的能力：

| 工程现状 | 对 FRT 的要求 | 结论 |
|---|---|---|
| Godot 3.5.3 导出的 PCK | 运行时必须是 Godot 3.5.x | 用 `frt_3.5.2` 即可，补丁号不校验 |
| 渲染器 `GLES2`（`project.godot` 第 80 行） | FRT 支持 GLES2 | `demo.sh` 已追加 `--video-driver GLES2` |
| `import_etc=true`、`import_etc2=false` | GLES2 走 ETC1 | 匹配，不需要改 |
| 分辨率 640×480、`stretch/mode="2d"` | 由 FRT/Godot 的窗口参数决定 | 启动时传 `--resolution 640x480 -f` 或沿用 PortMaster 的 `$GODOT_OPTS` |
| 没有原生插件（PCK 里只有 Git 插件的 `.gdns`/`.gdnlib` 描述） | 不涉及 so/ABI | 不需要为架构重新编译任何东西 |
| 没有音频 | FRT 的 SDL2 音频用不上 | 以后加音频再验证 |
| 没有存档、没有用户目录读写 | FRT 用 XDG 路径 | 仍建议把 `XDG_*` 指到游戏目录，保持可移植 |
| 输入：键盘 A/D/W/S + 手柄轴 0/1，统一走 `Input.get_axis()` | FRT 直接读原始 SDL 手柄 | gptokeyb 把十字键和左摇杆都转成 WASD，详见第 9 节 |
| 启动器 `demo.sh` 用 `$GODOT_OPTS --video-driver GLES2 --main-pack demo.pck` | FRT 把非 `--frt` 参数透传给 Godot | 完全兼容 |

### 3.1 为什么这个工程"特别好迁"

- **纯 2D + GLES2**：没有 3D 后处理、没有依赖桌面 GL 的特性；
- **无原生扩展**：不用关心 armhf/aarch64 的 `.so` 版本；
- **单场景、单脚本**：启动即进 `scenes/Game.tscn`，没有复杂的资源加载路径；
- **无用户数据**：不依赖 `user://` 的读写，XDG 配错也不会崩。

### 3.2 输入与地图：已经处理好的两个整合点

#### 输入

`Player.gd` 现在统一使用：

```gdscript
var axis_x := Input.get_axis("move_left", "move_right")
var axis_y := Input.get_axis("move_up", "move_down")
```

`project.godot` 里这四个动作同时绑了键盘 A/D/W/S 和手柄轴 0/1，所以键盘、原生手柄和 gptokeyb 模拟的键盘都走同一条路径，不再有 `using_gamepad` 模式切换。

掌机上的链路：

```text
物理十字键 → gptokeyb → 虚拟键盘 W/A/S/D → Input.get_axis()
物理左摇杆 → gptokeyb → 虚拟键盘 W/A/S/D → Input.get_axis()
原生手柄轴 → FRT → InputEventJoypadMotion → Input.get_axis()
```

即使 gptokeyb 和 FRT 同时提供输入，也不会再出现"按一次手柄就永久切分支"的问题。若两路同时推方向，InputMap 会按动作强度合成；正常使用不会同时冲突。

#### 地图碰撞

原场景有两个会影响上机的问题：

1. `Water` 节点 `visible = false`，作为子节点的草地也一起被隐藏；
2. `cell_custom_transform = 32` 只放大绘制，**不会同步放大 TileMap 的碰撞形状和格子坐标**，直接加水碰撞会与画面错位。

现在的处理：

- 打开 `Water` 显示；
- 移除与草地外圈重叠的 36 个水格，让 10×10 草地全部可走；
- 水 tile 17 增加 16×16 矩形碰撞形状；
- 用 `Water` 节点的 `scale = Vector2(2, 2)` 同时缩放绘制和碰撞，`Grass` 子节点继承缩放；
- `Camera2D` 移到 `Player` 下，开启平滑跟随并限制在水域范围。

桌面实测：角色从原点向右移动，会在草地右边缘 `x ≈ 137.9` 被水挡住，相机跟随到同一位置，地图和角色都正常显示。

---

## 4. 方式 A：PCK + 现成 FRT 运行时（推荐）

这是 PortMaster 现在的做法，也是本工程最省事的路线：**游戏只出 PCK，运行时用别人编译好的 FRT 二进制**。

```text
FRT 运行时（可执行文件）
        +
demo.pck（游戏资源 + 编译后的 GDScript）
        ↓
      启动
```

### 4.1 导出 PCK

**图形界面（最稳）：**

1. 用 **Godot 3.5.x** 打开本工程（版本尽量和运行时一致，当前运行时是 3.5.2）；
2. `项目 → 导出`；
3. 选中现有的 `Linux/X11` 预设（`export_presets.cfg` 第 3 行，预设名就是 `Linux/X11`）；
4. 点 **导出 PCK/Zip**，保存为 `demo.pck`。

**命令行：**

```bash
godot --path . --export-pack "Linux/X11" demo.pck
```

> Godot 3.5 的 `--export-pack` 可以直接导出 PCK/ZIP，不需要先下载二进制导出模板。本工程的 PCK 已通过该方式成功导出。

导出时注意：

- 当前预设是 `export_filter="all_resources"`（`export_presets.cfg` 第 7 行），所以**所有资源都会进包**，包括 76 张没被引用的角色图，PCK 因此有 25 MB 左右；
- 这是"能跑"的配置，不是"最小"的配置。想减体积再单独处理导出过滤，别在上线前顺手改；
- PCK 里的脚本是编译后的 `res://character/scripts/Player.gdc`，不需要附带 `.gd` 源文件。

### 4.2 准备运行时

有两种来源，选一种即可。

#### 4.2.1 用 PortMaster 的 squashfs（掌机常规做法）

文件位置：

```text
/roms/ports/PortMaster/libs/frt_3.5.2.squashfs
```

启动器做的事（对应 `demo.sh` 第 35–51 行）：

```bash
runtime="frt_3.5.2"
godot_dir="$HOME/godot"
godot_file="$controlfolder/libs/${runtime}.squashfs"

mkdir -p "$godot_dir"
umount "$godot_file" || true
mount "$godot_file" "$godot_dir"
export PATH="$godot_dir:$PATH"
```

说明：

- 需要内核支持 squashfs，且脚本有权限执行 `mount`（PortMaster 脚本通常以 root 运行）；
- squashfs 是**按架构做的**，armhf 设备和 aarch64 设备不能混用；
- squashfs 里已经把运行所需的库一起打包了，这是它比裸二进制省心的原因；
- 如果本地没有这个文件，`demo.sh` 会调用 `harbourmaster` 去下载（第 37–44 行）。

#### 4.2.2 用 SourceForge 的裸二进制

历史版本页可以拿到 FRT 2.1.0 / Godot 3.5.2 的独立可执行文件：

```text
frt_210_352_arm32v6.bin   33,269,568 字节
frt_210_352_arm32v7.bin   32,188,240 字节
frt_210_352_arm64v8.bin   31,978,736 字节
```

用法：

```bash
chmod +x frt_210_352_arm32v7.bin
./frt_210_352_arm32v7.bin --main-pack demo.pck
```

注意：

- 这是**裸二进制**，不会自带依赖；
- 它动态链接 `libSDL2-2.0.so.0`，系统里没有就会报 `error while loading shared libraries`；
- 架构必须匹配（见第 6 节）；
- 没有 PortMaster 的日志、gptokeyb、热键管理，适合调试，不适合直接当成品启动器。

### 4.3 最小启动命令

进入游戏目录后：

```bash
cd /roms/ports/demo
export XDG_CONFIG_HOME="$PWD/conf"
export XDG_DATA_HOME="$PWD/conf"

/home/ark/godot/frt_3.5.2 \
  --resolution 640x480 -f \
  --main-pack demo.pck
```

参数顺序不敏感，但要注意：**`--frt` 是分界线**，它前面的参数给 Godot，后面的参数给 FRT 自己。本工程的启动不需要任何 `--frt` 选项。

### 4.4 启动器里涉及的环境变量

| 变量 | 谁用 | 作用 | 本工程现状 |
|---|---|---|---|
| `XDG_CONFIG_HOME` / `XDG_DATA_HOME` | Godot / FRT | 配置与数据目录 | `demo.sh` 指到 `$GAMEDIR/conf` |
| `SDL_GAMECONTROLLERCONFIG` | SDL GameController 接口 | 手柄映射数据库 | PortMaster 的 `get_controls` 生成；FRT 不读取 |
| `FRT_NO_EXIT_SHORTCUTS` | FRT **2.0.x** | 关闭默认退出快捷键 | `demo.sh` 第 53 行设为 `1`；在 2.1.0 上是空操作 |
| `FRT_EXIT_SHORTCUT` | FRT **2.1.0+** | 指定退出快捷键，`none`/`shift-enter`/`win-q`/`esc` | `demo.sh` 第 54 行设为 `esc`，配合 Start → Esc |
| `SDL_VIDEO_RPI_OPTIONS` | FRT | 树莓派视频参数，FRT 自己设置 | 不要手动覆盖 |
| `GODOT_OPTS` | PortMaster | 追加的 Godot 参数 | `demo.sh` 直接展开 |

关于两个退出变量为什么可以同时在：**每个版本只认自己的那个**，另一个会被忽略，所以两个都写上不会互相打架。

---

## 5. 方式 B：用 FRT 做自定义导出模板

这条路适合：你想让 FRT 作为「导出模板」直接产出可执行文件，而不是"二进制 + PCK"。

【官方说明】FRT 仓库提供 Docker 构建流程：

- `frt-pull`：拉取构建镜像；
- `frt-compile`：在容器里编译 Godot/FRT，产出模板；
- 新版本还区分 release / debug、不同架构和不同发行版变体。

大致流程：

1. 在能跑 Docker 的机器上按 FRT README 的说明编译；
2. 把产出的模板放进 Godot 的模板目录（Linux 下一般是 `~/.local/share/godot/templates/3.5.3/` 之类，具体以你的 Godot 版本目录为准）；
3. 在导出预设里指定 `custom_template/release` / `custom_template/debug`；
4. 正常导出 Linux 可执行文件。

但是，对本工程来说：

- **没有必要**。R36S + PortMaster 的现成组合就是「FRT 二进制 + PCK」，这也是官方 PortMaster 运行时的形态；
- 编译模板耗时、受宿主环境影响大，而且你还要自己解决 SDL2 链接、架构、glibc 版本；
- 如果你只是要把游戏跑起来，直接用方式 A。

> 本节只说明"有这条路"，未在本机执行编译；具体命令和依赖以 FRT 仓库当前 README 为准。

---

## 6. 去哪下载、怎么选对版本

### 6.1 两个下载入口

| 入口 | 内容 | 适用 |
|---|---|---|
| GitHub Releases <https://github.com/efornara/frt/releases> | 跟随最新 Godot 3（截至 2026-11-24 为 3.6.1-1、3.6.2-1、3.6.3-1），提供 arm32/arm64 以及 trixie 的 arm64/armhf/riscv64 变体 | 新项目，或愿意用 3.6.x 重新导出 |
| SourceForge <https://sourceforge.net/projects/frt/files/> | 历史版本，含 FRT 2.1.0 / Godot 3.5.2 的 arm32v6、arm32v7、arm64v8 | 要跑 3.5.x 的 PCK（包括本工程） |
| PortMaster `libs/` | `frt_3.5.2.squashfs` 等运行时装包 | 掌机上的常规用法 |

**关键点**：本工程的 PCK 是 3.5.3。GitHub 上最新的 3.6.x 运行时**不会在版本检查阶段拒绝它**（只拒绝比引擎新的包），但 3.6.x 对 3.5.3 资源和编译脚本的兼容性需要实测。稳妥选择是：用 3.5.x 运行时；如果你确实想用 3.6.x，建议用 Godot 3.6.x 重新导出 PCK。

### 6.2 架构怎么选

在设备上先查，不要凭型号猜：

```bash
uname -m
getconf LONG_BIT
file /bin/bash
```

| 查询结果 | 选哪个 |
|---|---|
| `armv7l` | `arm32v7` / `armhf` |
| `armv6l` | `arm32v6` |
| `aarch64` 且用户态是 64 位 | `arm64v8` / `aarch64` |
| `aarch64` 内核但用户态是 32 位 | 选 `armhf`（32 位用户态装不了 64 位程序） |

判断用户态是不是 32 位，看 `getconf LONG_BIT`：输出 `32` 就是 32 位用户态，输出 `64` 才是完整 64 位。

> R36S 不同 CFW / 不同批次的系统位数并不完全一样，**必须以设备上的 `uname -m` + `getconf LONG_BIT` 为准**。这也是"同一个包在别人机器能跑、在我这报 Exec format error"的常见原因。

### 6.3 选版本的顺序

1. 先确定 PCK 的 Godot 版本（本工程 3.5.3）；
2. 选同主/次版本的运行时（3.5.x）；
3. 再按 `uname -m` 选架构；
4. 有 squashfs 就优先 squashfs（依赖最全）；
5. 裸二进制只用于调试或自制启动器。

【官方说明】FRT README 里还提到 arm32 上存在 `Illegal instruction` 的已知问题，与 CPU 指令集和构建变体有关。遇到时优先换匹配的 arm32v7/v6 构建，或改用 arm64。

---

## 7. 命令行参数

### 7.1 参数分界

FRT 的用法是：

```text
frt [Godot 参数...] [--frt [FRT 参数...]]
```

- `--frt` 之前：原样交给 Godot 的 `Main::setup`；
- `--frt` 之后：由 FRT 自己解析，**不会**传给 Godot。

【已核实】FRT 的入口会先找 `--frt`，找到了就把 `argc` 截断到它之前，再调用 Godot 的主函数。

### 7.2 常用的 Godot 参数

| 参数 | 作用 | 本工程建议 |
|---|---|---|
| `--main-pack demo.pck` | 直接加载 PCK | 必用 |
| `--path <目录>` | 指定工程目录（跑源码而非 PCK） | 调试用 |
| `--resolution 640x480` | 窗口/输出分辨率 | 掌机上配合 `-f` |
| `-f` | 全屏 | 掌机必用 |
| `--video-driver GLES2` | 强制 GLES2 | 驱动只支持 GLES2 时用 |
| `--audio-driver <名字>` | 指定音频驱动 | 本工程无音频，暂不需要 |
| `--verbose` | 详细日志 | 排查启动问题必用 |
| `--quit` | 启动后立刻退出 | 冒烟测试 |

PortMaster 的 `$GODOT_OPTS` 在新版运行时里通常是：

```bash
GODOT_OPTS="--resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} -f"
```

也就是"按设备分辨率全屏"。本工程是 `stretch/mode="2d"`，会自己缩放到窗口，不需要精确等于 640×480。

### 7.3 FRT 自己的参数

FRT 2.1.0+ 支持：

| 参数 | 作用 |
|---|---|
| `--frt -v` | 打印 FRT 版本（PortMaster 运行时实测输出 `2.1.0.stable.400ec48`） |
| `--frt -l` | 打印许可证并退出 |
| `--frt -h` | 打印用法并退出 |

注意：**FRT 2.0.x 的 `--frt` 解析器是空的**，只起到"截断参数"的作用，没有 `-v`/`-l`/`-h` 这些选项。所以用 `--frt -v` 来判断"这个运行时是 2.x 还是 2.1.0+"是可行的：有输出就是 2.1.0+。

---

## 8. 退出快捷键与进程行为

### 8.1 两代规则

| FRT 版本 | 环境变量 | 默认行为 | 取值 |
|---|---|---|---|
| 2.0.x | `FRT_NO_EXIT_SHORTCUTS` | 默认启用 **Alt+Enter** 和 **手柄 6 号键** 退出 | 设置成任意值即关闭 |
| 2.1.0+ | `FRT_EXIT_SHORTCUT` | 默认 **无快捷键** | `none`、`shift-enter`、`win-q`、`esc` |

本工程 `demo.sh` 第 53–54 行写的是：

```bash
export FRT_NO_EXIT_SHORTCUTS=1
export FRT_EXIT_SHORTCUT=esc
```

当前 `frt_3.5.2` 运行时使用 FRT 2.1.0，实际生效的是第二行；第一行只为旧版运行时关闭默认退出快捷键。

### 8.2 那游戏怎么退出

当前退出链路是：

```text
Start 键 → gptokeyb 转成 Esc → FRT 2.1.0 的退出快捷键 → 游戏进程退出
```

`demo.gptk` 第 2 行是 `start = esc`，启动器第 54 行是 `FRT_EXIT_SHORTCUT=esc`，两边已经对齐。游戏脚本本身不处理退出，也不会有暂停菜单。2026-11-24 真机已确认游戏显示和移动；退出链路按当前 FRT 2.1.0 规则配置。

如果 Start 不能退出，先确认掌机上的 `demo.gptk` 和 `demo.sh` 都是当前版本，再检查 `/roms/ports/demo/log.txt` 是否正常启动。不要只改其中一个文件。

### 8.3 进程行为

- FRT 是前台进程，游戏退出后进程才返回；
- `demo.sh` 随后执行 `umount`、杀掉 `gptokeyb`、重启 `oga_events`（第 61–63 行）；
- 如果游戏异常崩溃，这些清理仍会执行，但 squashfs 可能残留挂载，下次启动前脚本会先 `umount` 一次（第 49 行）。

---

## 9. 视频、音频、输入在 FRT 下的表现

### 9.1 视频

| 项目 | 说明 |
|---|---|
| 后端 | SDL2 窗口 + GLES2/GLES3 |
| 本工程渲染器 | GLES2（`project.godot` 第 80 行） |
| 纹理压缩 | ETC1 开启、ETC2 关闭，与 GLES2 匹配 |
| 分辨率 | 640×480，`stretch/mode="2d"` |
| 全屏 | `-f` |
| 强制 GLES2 | `demo.sh` 第 55 行把它追加到 `$GODOT_OPTS` 后面 |

如果设备 GL 驱动只支持 GLES2，而运行时默认尝试 GLES3，表现可能是：启动即退出、shader 编译报错、黑屏。当前启动器已经显式传入 `--video-driver GLES2`，无需再手动添加；直接手写启动命令时才需要补上。

FRT 在树莓派类设备上会自己设置 `SDL_VIDEO_RPI_OPTIONS`，**不要手动覆盖**，除非你明确知道要改什么。

### 9.2 音频

- FRT 用 SDL2 输出音频（【官方说明】）；
- Godot 的混音参数仍是 `audio/mix_rate`、`audio/output_latency` 等；
- 本工程**没有任何音频节点和音频资源**，所以这一块目前不会出问题；
- 以后加音频时，先确认设备的 SDL2 音频后端（ALSA/PulseAudio/PipeWire）可用。

### 9.3 输入

FRT 的输入模型（【官方说明】+【已核实】源码）：

- 直接读 SDL 的 **原始 joystick**（`SDL_JoystickOpen`，不用 GameController API），最多支持 **16 个手柄设备**（源码常量 `MAX_JOYSTICKS = 16`）；
- **不做** SDL GameController 的数据库重映射；
- 因此 `SDL_GAMECONTROLLERCONFIG` 对 FRT 的原始按键编号**没有影响**（它服务于使用 SDL GameController 接口的程序，而 FRT 走 `SDL_JoystickOpen`）；
- 手柄事件会被转换成 Godot 的 `InputEventJoypadMotion` / `InputEventJoypadButton`。

这和 PortMaster 的 gptokeyb 是两套并行机制：

```text
物理手柄
├── gptokeyb：按 demo.gptk 转成虚拟键盘/鼠标 → Godot 键盘动作
└── FRT：直接读原始 joystick → Godot 手柄事件
```

### 9.4 输入在 FRT 下的实际路径

结合本工程的具体配置：

| 操作 | gptokeyb（`demo.gptk`） | FRT 原始手柄 | 游戏实际反应 |
|---|---|---|---|
| 十字键 | W/A/S/D | hat 事件 | 移动角色 |
| 左摇杆 | W/A/S/D | 轴 0/1 | 两条路径都能移动角色 |
| A / Y / R1 | J | 按键事件 | 剑击 / 确认 |
| B / R2 / L2 | K | 按键事件 | 闪避 |
| X / L1 | L | 按键事件 | 范围技能 |
| Start | Esc | 按键事件 | 通过 FRT 的 Esc 退出快捷键结束游戏 |
| Select / back | P / Enter | 按键事件 | 暂停 / 确认 |

`Player.gd` 用 `Input.get_axis()` 读移动，用 `Input.is_action_just_pressed()` 读 attack / dash / special。移动动作在 InputMap 中同时绑定 A/D/W/S 和手柄轴 0/1；attack/dash/special/pause 还绑定了 J/K/L/P 和手柄按钮 0/1/2/9。十字键主要走 gptokeyb 的虚拟键盘路径；左摇杆既可以走 gptokeyb 的 WASD 路径，也可以走 FRT 的轴 0/1 路径。

现在没有 `using_gamepad` 分支，也不会因为收到一次手柄事件就永久切换输入模式。InputMap 的轴死区是 0.5，gptokeyb 自己也有死区配置。

后续回归时分别测试：

1. 只按十字键，角色应四方向移动；
2. 只推左摇杆，角色应四方向移动；
3. A 剑击、B 闪避、X 范围技能、Select 暂停 / 恢复应有对应反应；
4. 按 Start，游戏应退出并执行启动器尾部清理；
5. 观察 `/roms/ports/demo/log.txt`，确认没有输入设备、资源或脚本错误。

如果十字键不动而摇杆能动，优先检查 gptokeyb 是否启动、`/dev/uinput` 是否可写，以及掌机上的 `demo.gptk` 是否为当前版本。当前 InputMap 没有直接绑定手柄 hat，因此十字键依赖 gptokeyb 这一层。

---

## 10. R36S 上的完整操作步骤

下面按"从零到能玩"的顺序走。命令里的路径以常见 PortMaster 布局为例，实际以你的 CFW 为准。

### 第 1 步：确认架构和依赖

```bash
uname -m
getconf LONG_BIT
ls -l /usr/lib/libSDL2*
```

记录结果，决定后面下载哪个运行时。

### 第 2 步：准备 PCK

两种选择：

- **直接用现成的**：`.build/demo/demo.pck`（3.5.3，745,856 字节，约 728 KiB）；
- **自己重新导出**：用 Godot 3.5.x 打开工程，导出 `Linux/X11` 预设的 PCK。

如果要修改游戏内容，必须重新导出；只换启动器则不用。

### 第 3 步：在掌机上摆好文件

```text
/roms/ports/
├── demo.sh                  ← 来自 .build/demo.sh
└── demo/
    ├── demo.pck             ← 来自 .build/demo/demo.pck
    ├── demo.gptk            ← 来自 .build/demo/demo.gptk
    └── log.txt              ← 运行后自动生成
```

注意：`demo.sh` 里写死了 `GAMEDIR="/roms/ports/demo"`（第 23 行），换目录要同步改脚本。

### 第 4 步：准备运行时

- 如果 PortMaster 已装好：确认 `libs/frt_3.5.2.squashfs` 存在，不存在就让 `harbourmaster` 下载；
- 如果是裸二进制调试：把对应架构的 `frt_210_352_*.bin` 放到 `demo/` 下并 `chmod +x`，同时确认 `libSDL2-2.0.so.0` 存在。

### 第 5 步：先做冒烟测试

在启动器之外，手动跑一次，排除脚本因素：

```bash
cd /roms/ports/demo
chmod +x ./frt_210_352_arm32v7.bin   # 按实际架构替换
./frt_210_352_arm32v7.bin --frt -v
./frt_210_352_arm32v7.bin --resolution 640x480 -f --video-driver GLES2 --main-pack demo.pck --verbose
```

预期：

- `--frt -v` 打印 FRT 版本；
- 游戏窗口出现，能看到草地、外围水域和角色；
- 十字键与左摇杆都能移动角色，角色会被水挡住，相机跟随移动；
- 日志里能看到 PCK 加载和资源加载信息。

### 第 6 步：用 PortMaster 启动器跑

```bash
/roms/ports/demo.sh
```

然后看 `demo/log.txt`。脚本会把 stdout/stderr 都 tee 进去（第 33 行），这是排查掌机问题最直接的入口。

### 第 7 步：验证输入

- 十字键：应能移动；
- 左摇杆：应能移动，`demo.gptk` 已把它映射成 W/A/S/D；
- 走到草地边缘：应被水挡住，不能继续向外走；
- Start：应通过 Esc 触发 FRT 退出，而不是打开暂停菜单。

如果方向输入不灵，回到 [9.4](#94-输入在-frt-下的实际路径) 检查输入路径。

---

## 11. 故障排查表

先看日志：`/roms/ports/demo/log.txt`。下面是按报错关键词查。

| 现象 / 日志关键词 | 大概率原因 | 处理 |
|---|---|---|
| `error while loading shared libraries: libSDL2-2.0.so.0` | 裸二进制缺 SDL2 | 装 SDL2 运行库，或改用自带依赖的 squashfs 运行时 |
| `cannot execute binary file: Exec format error` | 架构不匹配 | 按 `uname -m` / `getconf LONG_BIT` 重选 armhf / arm64 |
| `Illegal instruction` | arm32 构建与 CPU 指令集不匹配（FRT 已知问题） | 换 arm32v7/v6 对应构建，或改用 arm64 |
| `Pack created with a newer version of the engine` | PCK 比运行时新（如 3.6 PCK + 3.5 运行时） | 换成与 PCK 同版本或更新的运行时，或用低版本重新导出 |
| `Pack version unsupported` | PCK 格式版本不对（损坏或非标准打包） | 重新导出 PCK |
| 启动即退出，日志末尾是 GL/shader 错误 | 运行时尝试 GLES3，设备只支持 GLES2 | 确认 `demo.sh` 第 55 行已追加 `--video-driver GLES2` |
| 黑屏但进程还在 | 分辨率/全屏/输出设备问题 | 加 `--resolution 640x480 -f`；检查 `/dev/dri`、`/dev/fb0` 权限 |
| `Unable to open file: res://...` | PCK 不完整或路径不对 | 确认在 `demo` 目录下启动，`--main-pack` 用相对/绝对正确路径 |
| 脚本报错 `Invalid call. Nonexistent function` | 用低版本运行时跑高版本脚本（虽然 3.5 补丁间一般兼容） | 用与导出相同的 3.5.x 版本重新导出 |
| 十字键不动 | gptokeyb 未启动 / `/dev/uinput` 权限 / gptk 映射 | 检查 `demo.sh` 是否启动 gptokeyb，`chmod 666 /dev/uinput`，核对 `demo.gptk` 的 `up/down/left/right` |
| 左摇杆不动 | gptokeyb 摇杆映射缺失，或 FRT 轴未被 InputMap 接收 | 核对 `demo.gptk` 的 `left_analog_*` 和 `project.godot` 的轴 0/1 映射 |
| Start 不退出 | 映射或 FRT 退出变量没有同步 | 确认 `demo.gptk` 是 `start = esc`，`demo.sh` 是 `FRT_EXIT_SHORTCUT=esc` |
| `frt: unrecognized option` | 参数放在了 `--frt` 后面 | Godot 参数放 `--frt` 前，FRT 参数放后面 |
| 没有声音 | 本工程没有音频 | 不是故障 |
| 画面比例不对 | 设备分辨率与 640×480 不同 | `stretch/mode="2d"` 会缩放；必要时核对 `$GODOT_OPTS` |
| 退出后卡住 / 黑屏 | 清理流程未完成，或 `oga_events` 未重启 | 检查 `demo.sh` 尾部；手动 `umount ~/godot` |

### 11.1 如果 3.5.3 的 PCK 在 3.5.2 上报脚本错误

理论上补丁号不校验，实际也通常没问题。但如果你遇到 GDScript 层面的报错：

1. 用 **Godot 3.5.2** 重新导出 PCK（版本与运行时严格对齐）；
2. 确认没有用到 3.5.3 新增的 API；
3. 确认导出时脚本已编译（PCK 里是 `Player.gdc`，不是明文 `.gd`）。

---

## 12. 和当前 PortMaster 模板的差异

本工程的 `demo.sh` 是**旧版模板**。它现在能用，但和新版 PortMaster 的 Godot 启动模板有几处差异。

| 项目 | 本工程 `demo.sh`（旧版） | 新版 PortMaster 模板 | 影响 |
|---|---|---|---|
| 运行时形态 | `libs/*.squashfs` 挂载到 `$HOME/godot` | `runtimes/godot_3.5.2/` + `runtime.json` + `runtimes/godot_3.5.2.txt` | 新版更容易做多架构、多 CFW 适配 |
| 启动变量 | 直接 `"$runtime" $GODOT_OPTS --main-pack` | `GODOT_RUN="$ESUDO $RUNTIME_DIR/$GODOT_BINARY $GODOT_OPTS"`，再 `$GODOT_RUN ...` | 新版统一处理 sudo/路径 |
| 分辨率 | 依赖 `$GODOT_OPTS` | 明确 `--resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} -f` | 新版对非 640×480 设备更友好 |
| ROCKNIX | 不区分 | ROCKNIX 选 X11 二进制，其他用 FRT | 新版在 ROCKNIX 上不依赖 FRT |
| 退出快捷键 | 同时设置 `FRT_NO_EXIT_SHORTCUTS=1` 和 `FRT_EXIT_SHORTCUT=esc` | 按运行时版本处理 | 当前 FRT 2.1.0 用 Esc，Start 经 gptokeyb 触发退出 |
| 平台钩子 | 无 | `pm_platform_helper`、`pm_finish` | 新版与 PortMaster 生命周期集成更好 |
| 目录绑定 | 无 | `bind_directories`、`PM_CAN_MOUNT` | 存档/配置管理更规范 |
| 输入 | 直接起 gptokeyb | 可选 libcrusty / `CRUSTY_BLOCK_INPUT=1` | 输入管理更复杂，但更统一 |

### 12.1 要不要升级

**不建议为了"看起来新"而改。** 现在这套在 R36S + `frt_3.5.2` 上是自洽的：

- FRT 2.1.0 通过 `FRT_EXIT_SHORTCUT=esc` 接收退出快捷键，Start 已由 gptokeyb 映射为 Esc；
- `GODOT_OPTS` 由 PortMaster 提供，脚本另外追加 GLES2 参数；
- gptokeyb + `demo.gptk` 的键盘映射和游戏代码匹配。

真正需要动启动器的场景只有：

1. 目标设备不是 640×480，且 `$GODOT_OPTS` 没有正确设置；
2. 需要支持多种架构/CFW，想复用新版运行时的目录结构；
3. 需要 `pm_finish` 之类的生命周期钩子；
4. 想显式控制退出快捷键。

这些都属于"有明确需求再改"，不要在只写文档/只验证的阶段顺手改 `demo.sh`。

### 12.2 当前退出配置为什么这样写

```bash
export FRT_NO_EXIT_SHORTCUTS=1
export FRT_EXIT_SHORTCUT=esc
```

第一行关闭 FRT 2.0.x 的默认退出快捷键；第二行让 FRT 2.1.0+ 把 Esc 作为退出键。当前目标运行时是 2.1.0，因此第二行配合 `demo.gptk` 的 `start = esc` 生效。

不要把第二行改成 `none`，否则当前启动器会失去 Start 退出链路。若以后只针对 FRT 2.0.x，需要另外设计退出方式，不能沿用这套 Start → Esc 方案。

---

## 13. 上线前检查清单

- [ ] PCK 的 Godot 版本与运行时主/次版本一致（本工程：3.5.3 / 3.5.2，兼容）；
- [ ] 运行时的 CPU 架构与设备一致（`uname -m` + `getconf LONG_BIT`）；
- [ ] 运行时能找到 `libSDL2-2.0.so.0`（裸二进制场景）；
- [ ] 启动命令是 `--main-pack demo.pck`，且工作目录正确；
- [ ] 需要全屏时带 `-f`，需要固定分辨率时带 `--resolution`；
- [ ] 启动器已追加 `--video-driver GLES2`；
- [ ] `XDG_CONFIG_HOME` / `XDG_DATA_HOME` 指向游戏目录（可选但推荐）；
- [ ] `FRT_EXIT_SHORTCUT=esc` 与 `demo.gptk` 的 `start = esc` 已同时部署；
- [ ] gptokeyb 已启动、`/dev/uinput` 可写、`demo.gptk` 与输入预期一致；
- [ ] 十字键和左摇杆都实测可移动；
- [ ] Start 实测可退出游戏；
- [ ] 日志 `demo/log.txt` 中没有资源加载错误、shader 错误、脚本错误；
- [ ] 退出后 `~/godot` 已卸载，`gptokeyb` 已结束，`oga_events` 已重启。

---

## 附录 A：命令速查

### A.1 查看版本

```bash
# FRT 自己的版本（2.1.0+ 才有输出）
frt_3.5.2 --frt -v

# PCK 表头（前 4 字节是 GDPC）
xxd -l 32 demo.pck

# 运行时依赖
readelf -d frt_3.5.2 | grep NEEDED
```

### A.2 手动启动

```bash
cd /roms/ports/demo

export XDG_CONFIG_HOME="$PWD/conf"
export XDG_DATA_HOME="$PWD/conf"

# squashfs 已挂载到 ~/godot，或二进制就在当前目录
export FRT_EXIT_SHORTCUT=esc
./frt_3.5.2 --resolution 640x480 -f --video-driver GLES2 --main-pack demo.pck --verbose
```

### A.3 挂载/卸载 PortMaster 运行时

```bash
sudo mkdir -p "$HOME/godot"
sudo umount "$HOME/godot" 2>/dev/null || true
sudo mount /roms/ports/PortMaster/libs/frt_3.5.2.squashfs "$HOME/godot"
export PATH="$HOME/godot:$PATH"

# 用完
sudo umount "$HOME/godot"
```

### A.4 导出 PCK

```bash
# 图形界面：项目 → 导出 → Linux/X11 → 导出 PCK/Zip
# 命令行：Godot 3.5 可直接导出 PCK/ZIP
godot --path . --export-pack "Linux/X11" demo.pck
```

### A.5 看设备信息

```bash
uname -m
getconf LONG_BIT
cat /etc/os-release
ls -l /dev/dri /dev/fb0 /dev/uinput 2>/dev/null
```

---

## 附录 B：参考链接

- FRT 官方仓库（README）：<https://github.com/efornara/frt>
- FRT Releases：<https://github.com/efornara/frt/releases>
- FRT 历史版本（SourceForge）：<https://sourceforge.net/projects/frt/files/>
- PortMaster 新运行时仓库：<https://github.com/PortsMaster/PortMaster-New-Runtimes>
- PortMaster 官网：<https://portmaster.games/>
- Godot 3.5 PCK 校验源码：<https://github.com/godotengine/godot/blob/3.5/core/io/file_access_pack.cpp>
- Godot 3.5 命令行参数文档：<https://docs.godotengine.org/en/3.5/tutorials/editor/command_line_tutorial.html>
- Godot 3.5 导出文档：<https://docs.godotengine.org/en/3.5/tutorials/export/exporting_projects.html>

---

## 附：本文结论的证据来源

| 结论 | 证据 |
|---|---|
| PCK 为 3.5.3、175 文件、26,913,696 字节 | 解析 `demo.pck` 表头与文件表 |
| PortMaster 运行时是 FRT 2.1.0 + Godot 3.5.2 | 运行时二进制内字符串 `2.1.0`、`400ec48`、`3.5.2.stable.custom_build`、`FRT_EXIT_SHORTCUT`、`--frt` |
| 运行时动态依赖 SDL2 | `readelf -d` 的 NEEDED 含 `libSDL2-2.0.so.0` |
| 3.5.3 PCK 可在 3.5.2 运行 | Godot 3.5 `file_access_pack.cpp` 不校验 patch，且只拒绝比引擎新的包 |
| FRT 参数透传规则 | `frt_exe.cc`：检测 `--frt` 后截断 `argc` 再调用 Godot |
| 退出快捷键两代规则 | `sdl2_adapter.h`：2.0.1 用 `FRT_NO_EXIT_SHORTCUTS`，2.1.0 用 `FRT_EXIT_SHORTCUT` |
| 本工程统一输入路径 | `character/scripts/Player.gd` 第 13–14、17–25 行 |
| 启动器行为 | `.build/demo.sh` 第 32–64 行 |
| 手柄映射 | `.build/demo/demo.gptk` |

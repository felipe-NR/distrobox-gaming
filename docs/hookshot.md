# Hookshot: Ocarina of Time for Switch 2 (`install_hookshot`)

[NotRexed/Hookshot](https://github.com/NotRexed/Hookshot) is a **static
recompilation** of *The Legend of Zelda: Ocarina of Time* for Nintendo Switch 2.
The AArch64 game code is lifted to C and compiled into a native Linux ELF,
Horizon OS is reimplemented, and NVN2 graphics run on **Vulkan 1.3 with mesh
shaders**. No emulator runs.

The release ships **no game code**. Its AppImage is Hookshot Builder, with its
own clang, sysroot and Python, and it builds the game on this box from your own
dump. This role drives that headlessly.

## Requirements

- Your dump of program `0400486024DEC000` with update **v131072, build
  `e0f3ccfa`**, as a `.nup` package or as extracted `romfs/` + `exefs/` folders.
  Other versions are refused by the builder's `--check`.
- A GPU exposing `VK_EXT_mesh_shader` (`vulkaninfo | grep mesh`). NVIDIA RTX 20+,
  AMD RX 6000+ / RDNA3 iGPUs on RADV, Intel Arc. RDNA1 and older do not work.
- A CPU with AVX2, 16 GB RAM (a run uses about 10 GB), about 60 GB free during
  the build.

## Install

```sh
cd ansible
ansible-playbook install-hookshot.yml        # or: site.yml --tags hookshot
```

Put the dump at `dg_hookshot_nup` (default
`ROMS_FINAL/switch2/The Legend of Zelda Ocarina of Time/zelda-oot.nup`), or
`romfs/` + `exefs/` in `dg_hookshot_dump_dir`. Without a dump the role installs
the builder, the launcher and the menu entry, reports where the dump goes, and
skips the build. Rerun after placing it.

Launcher `bin/hookshot`; host entry **"Ocarina of Time · Hookshot"**; `ogm` id
`hookshot`. Revert with `-e dg_hookshot_revert=true` (saves and the dump are
untouched).

## How it works

- Downloads the pinned `Hookshot-v2.2.0-rc.1-x86_64.AppImage` (sha256 in
  `group_vars/all/hookshot.yml`) and extracts it with `--appimage-extract`,
  because the restricted box has no FUSE. `AppRun --cli` runs `nx2/make_game.py`
  with the bundled Python.
- `AppRun --cli --check` verifies the dump, then
  `AppRun --cli --nup <dump> --out ~/Games/Hookshot --language pt-BR` builds it
  (10 to 45 minutes). The build is skipped while `.dg-built-ref` in the game
  folder matches the pinned tag, so a release bump rebuilds once.
- The launcher starts `bin/hookshot` from the game folder the way the builder's
  Play does: without `LD_LIBRARY_PATH`, with `HOOKSHOT_NO_UPDATE_CHECK=1`. The
  game folder's own `hookshot` launcher is not used: it offers in-place updates
  past the pin.

## Graphics

Seeded into `hookshot_options.ini` only when a key is missing
(`dg_hookshot_options_defaults`), so in-game menu changes survive reruns:

| Key | Value | Why |
|-|-|-|
| `quality_preset` | `3` (Balanced, 8 GB) | Matches an 8 GB GPU: the RTX 4060, or the 780M's 8 GiB carve-out. Use `5` (Ultra) on a 16 GB+ card |
| `output_res` | `1920x1080` | The panel's native size. Use `3840x2160` on a 4K display |
| `fullscreen` | `1` | |
| `controller_in_background` | `1` | Pad keeps working if focus moves |

The role also sets `dg_hookshot_options_enforced` on every run, over the menu:
`anisotropic_filtering=4` (16x). Hookshot's own default is 16x, but an options
file from an older build carried `anisotropic_filtering=1`, which v2.2.0 reads
as 2x (0 the game's own, 1 2x, 2 4x, 3 8x, 4 16x). The frame cap defaults to
60 FPS, so the role leaves it. The in-game menu opens with **Insert**, **F1**
or **Esc**, or **Home** (or Select+Start) on a pad. Upscaler choice is in-game
only: *Graphics → Upscaler*. The first visit to each area stutters while
shaders compile; later visits are smooth.

### NVIDIA DLSS / DLAA (opt-in, RTX)

The release's renderer has no NVIDIA code, so the Upscaler row shows "DLSS and
DLAA: not in this build". To get them, set both of these in
`host_vars/localhost.yml` and rerun `install-hookshot.yml`:

```yaml
dg_hookshot_dlss: true
dg_hookshot_nvidia_license_accepted: true   # accepts the NVIDIA RTX SDKs license
```

The builder then fetches NVIDIA's DLSS SDK (v310.9.16, sha256-pinned upstream)
into `dg_hookshot_ngx_sdk_dir`, compiles its own `hookshot_vk.so` against it and
puts `libnvidia-ngx-dlss.so.*` (DLSS) and, from v2.2.0, `libnvidia-ngx-dlssg.so.*`
(DLSS Frame Generation) in the game folder's `ngx/`. NGX's core,
`libnvidia-ngx.so`, comes from the host driver through the NVIDIA runtime. The
build is marked `v2.2.0-rc.1+dlss` in `.dg-built-ref`, so toggling the flag rebuilds.
Under NVIDIA's license, **never share or publish a game folder built this way.**
On Linux, NGX loads the runtime only from a folder whose path is all ASCII.

The v2.2.0-rc.1 AppImage cannot build with DLSS on its own: it ships only
`zbic.so` in `third_party/zbic/`, and the DLSS build compiles `zstd.c` into the
renderer and reads `zstd.h` and `zstd_errors.h` (upstream #2928/#3007, fixed
after rc.1 by #2935). The role copies those three files from the rc.1 tag into
the extracted builder, sha256-checked, through `dg_hookshot_builder_patch_files`.
The entry is keyed by release tag, so the next release ignores it.

Right after a DLSS build the role sets `dg_hookshot_dlss_options`: `dlss=1`
(DLSS) with `resolution=3` (Quality, 67%), `dlss_model=0` (Transformer K, the
one upstream tested most) and `sharpness=80` (upstream's advice: DLSS and DLAA
look softer than the game's own upscaler). The menu shows DLAA as Upscaler
**NVIDIA DLSS** with Render resolution **Native (DLAA, …)**, and one step on
that row turns it into DLSS Quality.

Measured on the RTX 4060 (8 GB, on OCuLink) at a 1080p output on a 60 Hz panel
without VRR, in gameplay (the menu over the title screen draws almost nothing and
always shows 60):

| Release | Mode | Kakariko | Hyrule Field | GPU a frame |
|-|-|-|-|-|
| v2.1.0 | DLSS Quality | 53 FPS | | 9.4 ms |
| v2.1.0 | DLAA | 42 FPS | | 17.1 ms |
| v2.2.0-rc.1 | DLSS Quality | 40-54 FPS | | 12-15 ms |
| v2.2.0-rc.1 | DLAA | 44-48 FPS | ~29 FPS | 13 / 24 ms |
| v2.2.0-rc.1 | DLAA + Frame generation 2x | 58-60 shown, base 30 | | |
| v2.2.0-rc.1 | DLSS Quality + Frame generation Auto (built-in) | ~60 shown, base 40-50, 0 late | | 12-15 ms |

On this box DLSS Quality misses 60 with GPU time to spare: the log's
`GPU-bound wait` is 0 ms and the time goes to the CPU replay (~10 ms a frame)
and to readbacks of GPU results (3.6-4.5 ms each), so lower render settings do
not help. Frame generation fills the gap in two ways. A fixed **2x** on a 60 Hz
panel switches V-Sync Auto to FIFO and locks the game at 30 real frames, which
adds a frame of input delay. **Auto** (`frame_generation=1`) makes a frame only
for a refresh the game has not filled, keeps mailbox and a 40-50 base; with
**Frame generation by: Built-in FG** (`frame_generation_by=1`) and **NVIDIA
Reflex: On + Boost** (`nvidia_reflex=2`) that was the best mix of delay and
smoothness here. These are menu choices; set them in `dg_hookshot_dlss_options`
in `host_vars/localhost.yml` to have a DLSS rebuild apply them. DLAA stays an
in-game choice for a stronger card. Check the `vk: status:` lines in the log for VRAM
use and the `GPU time` lines for the frame cost.
`vk: NVIDIA DLSS:` lines say whether DLSS
started and why not. NGX starts only when the menu first opens or at the first
gameplay upscale, so the title screen has no NGX lines.

With `dg_nvidia_enabled` the launcher sets `VK_ICD_FILENAMES` to the NVIDIA
Vulkan ICD, so the game sees only the NVIDIA card and `RX_VK_DEVICE` is not
needed. The box also lists the iGPU, so without the pin Hookshot could start
on it. Check the `vk: device` lines in `hookshot_log.txt` for the card in use.

## Gamepad

Native SDL3 input: the 8BitDo (and any Xbox, DualSense or Switch Pro pad) works
without mapping, with rumble and gyro where the pad has them. Bindings live in
`hookshot_options.ini` (`key_<button>`), which is backed up with the saves.

The launcher sets `SDL_JOYSTICK_DISABLE_UDEV=1`. The box runs in its own network
namespace, so udev's hotplug events never reach it, and SDL with udev only sees
pads that were connected when the game started: a pad plugged in later, or one
that reconnects through the receiver, stays dead until a restart. Without udev
SDL watches `/dev/input` with inotify and picks the pad up again. To check which
input node the game holds, run on the host:
`ls -l /proc/$(pgrep -x hookshot)/fd | grep /dev/input`.

## Saves

`~/.local/share/hookshot` in the box home (XDG), plus `hookshot_options.ini`,
registered in `dg_save_sets` as `hookshot`. To move a save from an emulator,
see upstream `docs/saves.md`.

## Logs

`~/Games/Hookshot/hookshot_log.txt` (last run, `.1` to `.4` before it). A
`vk: status:` line every 600 frames shows VRAM use against the driver's budget.

Only the Windows build writes that file itself. On Linux the game logs to
stderr, which is lost when it starts from the menu, so the launcher redirects
stderr to `hookshot_log.txt` and rotates the older runs the same way. Started
from a terminal, the game prints there instead.

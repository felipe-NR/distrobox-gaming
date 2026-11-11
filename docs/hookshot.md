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

- Downloads the pinned `Hookshot-v2.0.14-x86_64.AppImage` (sha256 in
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
| `quality_preset` | `3` (Balanced, 8 GB) | Matches the MS-A1's 8 GiB iGPU carve-out. Use `5` (Ultra) on a 16 GB+ card |
| `output_res` | `1920x1080` | The panel's native size. Use `3840x2160` on a 4K display |
| `fullscreen` | `1` | |
| `controller_in_background` | `1` | Pad keeps working if focus moves |

Anisotropic filtering defaults to 16x and the frame cap to 60 FPS, so the role
leaves them. The in-game menu opens with **Insert/F1**, or **Home** (or
Select+Start) on a pad. Upscaler choice (AMD FSR 3.1 on Radeon) is in-game only:
*Graphics → Upscaler*. The first visit to each area stutters while shaders
compile; later visits are smooth.

## Gamepad

Native SDL3 input: the 8BitDo (and any Xbox, DualSense or Switch Pro pad) works
without mapping, with rumble and gyro where the pad has them. Bindings live in
`hookshot_options.ini` (`pad_<button>`), which is backed up with the saves.
Check `hookshot_log.txt` in the game folder for the controller line.

## Saves

`~/.local/share/hookshot` in the box home (XDG), plus `hookshot_options.ini`,
registered in `dg_save_sets` as `hookshot`. To move a save from an emulator,
see upstream `docs/saves.md`.

## Logs

`~/Games/Hookshot/hookshot_log.txt` (last run, `.1` to `.4` before it). A
`vk: status:` line every 600 frames shows VRAM use against the driver's budget.

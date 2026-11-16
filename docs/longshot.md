# Longshot: Ocarina of Time for Switch 2 (`install_longshot`)

[MagicBeanDev/Longshot](https://git.magicbean.dev/MagicBeanDev/Longshot) is a
**static recompilation** of *The Legend of Zelda: Ocarina of Time* for Nintendo
Switch 2, and the continuation of [Hookshot](hookshot.md): Hookshot's top
maintainers moved there. The AArch64 game code is lifted to C and compiled into
a native Linux ELF, Horizon OS is reimplemented, and the graphics run on
**Vulkan 1.3 with mesh shaders**. No emulator runs.

This role is separate from `install_hookshot`. Both can be installed at once;
they share only your dump, which each builds from on its own. Neither role
changes the other's files. The one exception is a one-time **copy** of
Hookshot's saves into Longshot (see [Saves](#saves)).

The release ships **no game code**. Its AppImage carries the builder and its
Python. The build tools (clang + lld, a glibc 2.35 sysroot, FFmpeg, SDL2, the
Vulkan headers) are not in it: the first `AppRun --cli` downloads them from the
release's `tools.lock`, checked by size and sha256 (about 170 MB).

## Requirements

- Your dump of program `0400486024DEC000` with update **v131072, build
  `e0f3ccfa`**, as a `.nup` package or as extracted `romfs/` + `exefs/` folders.
  This is the same dump Hookshot uses. Other versions are refused by the
  builder's `--check`. An incomplete dump (about 23.3 GB instead of 23.8 GB)
  still builds, but the build writes `longshot_damaged_files.txt`.
- A GPU exposing `VK_EXT_mesh_shader` (`vulkaninfo | grep mesh`). Without it a
  compute fallback runs, slower and with some draws missing.
- 16 GB RAM or more (the game alone uses 13 to 19 GiB on Linux/NVIDIA), and
  about 60 GB free during the build.
- On AMD or Intel, access to `/dev/udmabuf`, or GPU imports fall back to slow
  host-pointer imports. NVIDIA can ignore that warning.

## Install

```sh
cd ansible
ansible-playbook install-longshot.yml        # or: site.yml --tags longshot
```

The dump path defaults to Hookshot's: `dg_longshot_nup` is
`ROMS_FINAL/switch2/The Legend of Zelda Ocarina of Time/zelda-oot.nup`, with
`romfs/` + `exefs/` in `dg_longshot_dump_dir` as the fallback. Without a dump
the role installs the builder, the launcher and the menu entry, reports where
the dump goes, and skips the build. Rerun after placing it.

Launcher `bin/longshot`; host entry **"Ocarina of Time · Longshot"**; `ogm` id
`longshot`. Revert with `-e dg_longshot_revert=true` (saves and the dump are
untouched).

## How it works

- Downloads the pinned `Longshot-v3.0.0-rc.4-x86_64.AppImage` from the Forgejo
  release (sha256 from its `SHA256SUMS`, kept in `group_vars/all/longshot.yml`)
  and extracts it with `--appimage-extract`, because the restricted box has no
  FUSE. There is no stable release yet; the first will be v3.0.0. Pin `rc` tags
  until then, never a `nightly-<n>-<sha>` tag: one is cut on every push and only
  the newest five are kept.
- `LONGSHOT_BUILDER_HOME` points at `tools/longshot/home`, so the downloaded
  toolchains land under `tools/longshot` and not beside the saves in
  `~/.local/share/longshot/builder`.
- `AppRun --cli --check` verifies the dump, then
  `AppRun --cli --nup <dump> --out ~/Games/Longshot --language pt-BR` builds it
  (about 15 minutes on 12 cores). The build is skipped while `.dg-built-ref` in
  the game folder matches the pinned tag, `+dlss` and the hash of our source
  patches, so a release bump or a patch change rebuilds once.
- Before the build the role applies `dg_longshot_source_patches` (role
  `files/`) to the builder's bundled source with `patch -p1`. A tag bump that
  no longer takes a patch fails the play: check whether upstream fixed the bug,
  then drop or rebase the patch. See *Crash: swapchain rebuild on NVIDIA*.
- The launcher starts `bin/longshot` from the game folder the way the builder's
  `--play` does: without `LD_LIBRARY_PATH` and the AppImage's `LONGSHOT_*`
  variables, with `LONGSHOT_NO_UPDATE_CHECK=1`. The game folder's own
  `longshot` launcher is not used: it offers in-place updates past the pin.

## Graphics

The build's shader-preparation step starts the game headless, and it writes a
full `longshot_options.ini` with its own Auto choices (`quality_preset=6`, a
2560x1440 output because it has no display to read, windowed). So the first
run after the role's first build sets `dg_longshot_options_defaults` over that
file and writes `.dg-options-seeded` in the game folder. Later runs only add
missing keys, so in-game menu changes survive. Delete the marker to have the
next run set the defaults again. A menu row's key is its name in lowercase with
spaces as underscores; the values match Hookshot's:

| Key | Value | Why |
|-|-|-|
| `quality_preset` | `3` (Balanced, 8 GB) | Matches an 8 GB GPU such as the RTX 4060. Use `5` (Ultra) on a 16 GB+ card |
| `output_res` | `1920x1080` | The panel's native size. Use `3840x2160` on a 4K display |
| `fullscreen` | `1` | |
| `controller_in_background` | `1` | Pad keeps working if focus moves |

The role also sets `dg_longshot_options_enforced` on every run, over the menu:
`anisotropic_filtering=4` (16x; 0 the game's own, 1 2x, 2 4x, 3 8x, 4 16x).
The in-game menu opens with **Insert**, **F1** or **Esc**. FSR 3.1 is in every
build; the upscaler is chosen in-game under *Graphics → Upscaler*. The first
visit to each area stutters while shaders compile; later visits are smooth.

### NVIDIA DLSS / DLAA (opt-in, RTX)

Set both of these in `host_vars/localhost.yml` and rerun `install-longshot.yml`:

```yaml
dg_longshot_dlss: true
dg_longshot_nvidia_license_accepted: true   # accepts the NVIDIA RTX SDKs license
```

The builder then runs with `--fetch-ngx-sdk --accept-nvidia-license`, fetches
NVIDIA's DLSS SDK into `dg_longshot_ngx_sdk_dir`, and puts
`libnvidia-ngx-dlss.so.*` and `libnvidia-ngx-dlssg.so.*` (frame generation) in
the game folder's `ngx/`. The build is marked `v3.0.0-rc.4+dlss` in
`.dg-built-ref`, so toggling the flag rebuilds. Under NVIDIA's license, **never
share or publish a game folder built this way.** On Linux, NGX loads the
runtime only from a folder whose path is all ASCII.

Right after a DLSS build the role sets `dg_longshot_dlss_options`: `dlss=1`
(the Upscaler row: DLSS), `resolution=3` (Quality), `dlss_model=0` (Transformer
K) and `sharpness=80`, the same as Hookshot. To have a DLSS rebuild also set
frame generation and Reflex, add them to `dg_longshot_dlss_options` in
`host_vars` (`frame_generation`: 0 off, 1 Auto, 2 to 8 for 2x to 8x;
`nvidia_reflex`: 0 off, 1 on, 2 on + boost).

With `dg_nvidia_enabled` the launcher sets `VK_ICD_FILENAMES` to the NVIDIA
Vulkan ICD, so the game sees only the NVIDIA card.

### HDR (Hyprland)

The game presents a native HDR10 swapchain (Wayland window, no gamescope). The
log confirms it with `present: ... format 64 ... HDR10 swapchain yes: the
game's PQ picture (Native)`. For the display to receive an HDR signal,
Hyprland needs two settings outside this repo:

- `render.cm_auto_hdr = 1` (in `~/.config/hypr/looknfeel.lua` on Omarchy).
  Omarchy's default is `0`, which keeps the output in sRGB and tone-maps the
  game's HDR down to SDR, so the TV never switches. With `1` the output moves
  to HDR while a fullscreen window presents HDR and back to SDR when it leaves.
- `bitdepth = 10` on the display's `hl.monitor` rule (`monitors.lua`).
  Without it the output stays `XRGB8888` and Hyprland warns that HDR is not
  running at 10 bit. Check with `hyprctl monitors`: `currentFormat` should read
  `XBGR2101010`.

The HDR rows live in `longshot_options.ini`, which `longshot-settings` backs
up; the role does not seed them because they depend on the display. Match
*HDR Peak Brightness* to the display's peak, read from its EDID with
`edid-decode /sys/class/drm/card*-<output>/edid` (*Maximum luminance*). Values
used on a Hisense 4K TV whose EDID reports ~750 nits peak with local dimming:

| Key | Value | Menu |
|-|-|-|
| `hdr` | `2` | Native (the game's own HDR) |
| `hdr_paper_white` | `150` | 150 nits; 200 in a bright room |
| `hdr_peak_brightness` | `800` | The menu's nearest step above ~750; drop to 700 if bright highlights clip |
| `hdr_contrast` | `100` | |
| `hdr_tone_mapper` | `1` | PsychoV35 |

On the TV: Game picture mode, local dimming high, and the TV's own dynamic
tone mapping off, since the game already maps to the peak set above. Keep
V-Sync on or Auto: the output runs at 60 Hz without VRR, and Off tears.

## Gamepad

Native SDL input: the 8BitDo (and any Xbox, DualSense or Switch Pro pad) works
without mapping. Bindings live in `longshot_options.ini` (`pad_<button>`,
`key_<button>`), which is backed up.

The launcher sets `SDL_JOYSTICK_DISABLE_UDEV=1` for the same reason as
Hookshot's: the box runs in its own network namespace, so udev's hotplug events
never reach it. Without udev SDL watches `/dev/input` with inotify and picks a
reconnected pad up again.

## Saves

`~/.local/share/longshot/save` in the box home (XDG), registered in
`dg_save_sets` as `longshot`. Only `save/` is backed up: `launcher/` and
`builder/` beside it hold tool data. `longshot_options.ini` and
`longshot_env.txt` go in the `longshot-settings` set, and `mods/` in
`longshot-mods`.

Longshot reads the same save files as Hookshot. On its first run the role
copies `~/.local/share/hookshot/save` to `~/.local/share/longshot/save`, only
while the Longshot folder does not exist yet, so an existing Longshot save is
never replaced. Hookshot's folder is only read. Turn this off with
`dg_longshot_import_hookshot_saves: false`. After the copy the two games keep
separate saves.

## Logs

`~/Games/Longshot/logs/longshot_log.txt` (last run, `.1` to `.4` before it).
The game writes that file itself only when it has no usable stderr. Started
from the menu, its stderr is distrobox's pipe, so the launcher redirects stderr
there and rotates the older runs the same way. Started from a terminal, the
game prints there instead.

## Crash: swapchain rebuild on NVIDIA

Seen once on v3.0.0-rc.4 with driver 615.78.08 (RTX 4060), right after the
Insert menu's *Restart now*, as the title screen's frame interpolation came
up: `CRASH: exception 0xc0000005 ... libnvidia-glcore.so.615.78.08+0xe1f599`,
straight after the log's `vk: swapchain ...` and `vk: NVIDIA Reflex: on +
boost` lines.

`bin/longshot_vk.so` is not stripped, so `addr2line -f -C -e
bin/longshot_vk.so <offset>` names the game's frames:
`replay_thread_main` → `submit_job` → `run_submit` →
`memory_begin_submission`. That last one calls `vkGetSemaphoreCounterValue`
on `sparse_tl`, the sparse mirrors' timeline. Inside the driver that call
walks a table on the device and read an entry that had just been freed. The
presenter thread was rebuilding the swapchain at that moment. That runs under
`dev.present_mu`, and the replay thread's timeline reads do not take it, so
the two calls ran in the driver at the same time.

`longshot-swapchain-guard.patch` adds a `std::shared_mutex`: timeline counter
reads (the `vkGetSemaphoreCounterValue` wrapper in `vk_work.h`) take it
shared, and `vkCreateSwapchainKHR` and `vkDestroySwapchainKHR` in
`vk_main.cpp` take it exclusively. Each side holds it across that one driver
call only, so it cannot deadlock, and the replay thread waits only while a
swapchain is being made. Not reported upstream yet.

If it comes back, the workaround is NVIDIA Reflex Off and fewer swapchain
rebuilds (Fullscreen, V-Sync, HDR and the Frame generation rows each rebuild
it).

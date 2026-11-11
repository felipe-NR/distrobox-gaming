#!/usr/bin/env sh
# Sweep the gaming box after a pacman -Syu for two update-breakage classes:
# 1. AUR packages built from source keep linking the OLD library soname and
#    fail at launch ("error while loading shared libraries: lib<old>.so ...").
# 2. Wine prefix DPI drift (xenia-manager LogPixels != 96) — wine 11.18's
#    monitor-DPI-awareness fix made DPI-aware apps honor it; 192 renders the UI
#    at 2x with unreachable controls.
#
# Run after every box package update. Exit 1 (and list offenders) when anything
# is broken so the caller can rebuild the affected AUR packages from source —
# `yay -S <pkg>` only reinstalls the cached binary; use makepkg:
#   cd /tmp && git clone https://aur.archlinux.org/<pkg>.git && cd <pkg> && makepkg -srci --noconfirm
#
# See docs/rebuild-runbook.md ("AUR source packages break on soname bumps").
set -eu

box="${1:-gaming}"

broken=$(distrobox-enter --no-workdir -n "$box" -- sh -lc '
  for pkg in $(pacman -Qmq); do pacman -Qlq "$pkg" 2>/dev/null; done \
    | grep -E "/usr/(bin|lib)/[^/]*$" \
    | while read -r f; do
        if file "$f" 2>/dev/null | grep -q "ELF.*dynamically linked"; then
          miss=$(ldd "$f" 2>/dev/null | grep "not found" | head -3)
          [ -n "$miss" ] && { echo "BROKEN: $f"; echo "$miss" | sed "s/^/    /"; }
        fi
      done
  true
')

if [ -n "$broken" ]; then
  printf '%s\n' "$broken"
  echo "Rebuild the owning AUR packages from source (makepkg -srci) — see docs/rebuild-runbook.md." >&2
  exit 1
fi
echo "box-soname-sweep: all AUR package binaries link clean."

# Wine prefix DPI audit — behavioral breakage class, not linker-level: wine
# 11.18's "fix monitor DPI awareness" made DPI-aware apps (Avalonia: Xenia
# Manager) actually honor the prefix LogPixels, so 192 suddenly rendered the UI
# at 2x with unreachable controls (2026-09-28). install_xenia enforces 96
# (dg_xenia_wine_dpi); flag any drift here so a box update that changes DPI
# behavior is caught before the user hits it.
box_home=$(distrobox-enter --no-workdir -n "$box" -- sh -c 'printf %s "$HOME"')
reg="$box_home/wineprefixes/xenia-manager/user.reg"
if [ -f "$reg" ]; then
  hex=$(grep -m1 '"LogPixels"' "$reg" | sed -n 's/.*dword:0*\([0-9a-fA-F]*\).*/\1/p')
  dpi=$(printf '%d' "0x${hex:-60}" 2>/dev/null || echo 96)
  if [ "$dpi" != "96" ]; then
    echo "BROKEN: xenia-manager prefix LogPixels=$dpi (want 96) — DPI-aware Wine apps will render oversized." >&2
    echo "Fix: cd ansible && ansible-playbook install-xenia.yml (enforces dg_xenia_wine_dpi=96)." >&2
    exit 1
  fi
fi
echo "wine-dpi-audit: xenia-manager prefix LogPixels=96 (ok)."

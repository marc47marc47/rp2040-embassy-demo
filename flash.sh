#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP="rp2040-embassy-demo"
TARGET="thumbv6m-none-eabi"
PROFILE="release"
ELF="target/${TARGET}/${PROFILE}/${APP}"
UF2="target/${TARGET}/${PROFILE}/${APP}.uf2"
MODE="${1:-auto}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1" >&2
    exit 1
  fi
}

show_board_probe() {
  if command -v usbipd-rs.exe >/dev/null 2>&1; then
    echo "=== usbipd-rs probe ==="
    usbipd-rs.exe --probe | sed -n '/2e8a:0003/p;/RP2 Boot/p;/Board Probe/,$p' || true
    echo
  fi
}

build_uf2() {
  need_cmd cargo
  need_cmd elf2uf2-rs

  echo "=== Build ${APP} ==="
  cargo build --release
  elf2uf2-rs "$ELF" "$UF2"
  echo "UF2: $UF2"
  echo
}

find_rpi_rp2_drive() {
  for drive in /{c..z}; do
    [[ -f "${drive}/INFO_UF2.TXT" ]] || continue
    if grep -qi 'Board-ID: RPI-RP2\|Model: Raspberry Pi RP2\|RP2' "${drive}/INFO_UF2.TXT"; then
      printf '%s\n' "$drive"
      return 0
    fi
  done
  return 1
}

flash_by_uf2_drive() {
  local drive
  drive="$(find_rpi_rp2_drive)" || return 1

  echo "=== Flash by RPI-RP2 USB drive ==="
  echo "RPI-RP2 drive: $drive"
  cp "$UF2" "$drive/"
  sync || true
  echo "Done. The Pico Zero should reboot and run the program."
}

flash_by_picotool() {
  need_cmd picotool

  echo "=== Flash by picotool ==="
  picotool load -v -x "$UF2" -t uf2
  echo "Done. The Pico Zero should reboot and run the program."
}

usage() {
  cat <<'EOF'
Usage:
  bash flash.sh          Build and flash automatically
  bash flash.sh auto     Prefer RPI-RP2 drive, fallback to picotool
  bash flash.sh uf2      Flash only by copying UF2 to RPI-RP2 drive
  bash flash.sh picotool Flash only by picotool
  bash flash.sh build    Build UF2 only
  bash flash.sh probe    Show Pico Zero USB probe info only

Pico Zero BOOTSEL mode:
  Hold BOOTSEL, plug USB into the PC, then run: bash flash.sh
EOF
}

case "$MODE" in
  auto)
    show_board_probe
    build_uf2
    if ! flash_by_uf2_drive; then
      flash_by_picotool
    fi
    ;;
  uf2)
    show_board_probe
    build_uf2
    flash_by_uf2_drive
    ;;
  picotool)
    show_board_probe
    build_uf2
    flash_by_picotool
    ;;
  build)
    build_uf2
    ;;
  probe)
    show_board_probe
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

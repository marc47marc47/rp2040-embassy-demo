#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-uf2}"
ELF="target/thumbv6m-none-eabi/release/rp2040-embassy-demo"
UF2="target/thumbv6m-none-eabi/release/rp2040-embassy-demo.uf2"

cargo build --release
elf2uf2-rs "$ELF" "$UF2"
echo "UF2 created: $UF2"

find_rpi_rp2() {
  for drive in /{d..z}; do
    [[ -f "$drive/INFO_UF2.TXT" ]] || continue
    if grep -qi "RP2" "$drive/INFO_UF2.TXT"; then
      printf '%s\n' "$drive"
      return 0
    fi
  done
  return 1
}

case "$MODE" in
  uf2)
    if mount_path="$(find_rpi_rp2)"; then
      cp "$UF2" "$mount_path/"
      echo "Flashed by copying UF2 to $mount_path"
    else
      echo "No RPI-RP2 boot drive found. Hold BOOTSEL, plug in Pico Zero, then run:"
      echo "  bash scripts/build_flash.sh uf2"
    fi
    ;;
  probe)
    probe-rs run --chip RP2040 "$ELF"
    ;;
  *)
    echo "Usage: bash scripts/build_flash.sh [uf2|probe]" >&2
    exit 2
    ;;
esac

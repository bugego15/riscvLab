#!/usr/bin/env bash
# M1-A1：OpenSBI(fw_dynamic) + S 模式 U-Boot（优先用源码构建产物，回退 apt 版）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

if [ -z "${FW_DYNAMIC:-}" ]; then
  if [ -f "$IMAGES/fw_dynamic.bin" ]; then FW_DYNAMIC="$IMAGES/fw_dynamic.bin"; else FW_DYNAMIC="/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin"; fi
fi
if [ -z "${UBOOT_S:-}" ]; then
  if [ -f "$IMAGES/u-boot-s.bin" ]; then UBOOT_S="$IMAGES/u-boot-s.bin"; else UBOOT_S="/usr/lib/u-boot/qemu-riscv64_smode/u-boot.bin"; fi
fi
[ -f "$FW_DYNAMIC" ] || die "缺少 OpenSBI fw_dynamic：$FW_DYNAMIC"
[ -f "$UBOOT_S" ] || die "缺少 S 模式 U-Boot：$UBOOT_S"
LOG="$LOGS/m1-a1-opensbi-uboot-s.log"
RUN_TIMEOUT="${RUN_TIMEOUT:-35}"

log "运行 OpenSBI fw_dynamic + U-Boot S 模式"
{
  sleep 8
  printf 'version\nbdinfo\n'
  sleep 5
} | timeout "$RUN_TIMEOUT" qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW_DYNAMIC" -kernel "$UBOOT_S" 2>&1 | tee "$LOG" || true

log "日志：$LOG"
grep -E 'OpenSBI|Platform Name|Firmware Base|Next Address|Next Mode|U-Boot|DRAM:' "$LOG" | head -25 || true

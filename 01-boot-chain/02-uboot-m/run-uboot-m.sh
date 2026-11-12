#!/usr/bin/env bash
# M0/M1-A2：U-Boot 以 M 模式直接作 bios（优先用源码构建产物，回退 apt 版）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/run-uboot-m.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

if [ -z "${UBOOT_M:-}" ]; then
  if [ -f "$IMAGES/u-boot-m.bin" ]; then UBOOT_M="$IMAGES/u-boot-m.bin"; else UBOOT_M="/usr/lib/u-boot/qemu-riscv64/u-boot.bin"; fi
fi
[ -f "$UBOOT_M" ] || die "缺少 M 模式 U-Boot：$UBOOT_M"
LOG="$LOGS/m1-a2-uboot-m-mode.log"
RUN_TIMEOUT="${RUN_TIMEOUT:-35}"

log "运行 U-Boot M 模式 bios（$UBOOT_M）"
{
  sleep 6
  printf 'version\nbdinfo\n'
  sleep 6
} | timeout "$RUN_TIMEOUT" qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$UBOOT_M" 2>&1 | tee "$LOG" || true

log "日志：$LOG"
grep -E 'U-Boot|CPU:|Model:|DRAM:|Loading Environment|=>' "$LOG" | head -20 || true

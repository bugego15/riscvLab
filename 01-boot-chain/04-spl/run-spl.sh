#!/usr/bin/env bash
# M1-A3：运行 SPL 两段式启动链并抓日志
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/04-spl/run-spl.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

SPL="$IMAGES/u-boot-spl.bin"
ITB="$IMAGES/u-boot.itb"
LOG="$LOGS/m1-a3-spl.log"
RUN_TIMEOUT="${RUN_TIMEOUT:-35}"

[ -f "$SPL" ] || die "缺少 SPL：$SPL（先跑 build-uboot-spl.sh）"
[ -f "$ITB" ] || die "缺少 u-boot.itb：$ITB"

log "运行 SPL 两段式：SPL(M-mode) -> u-boot.itb(OpenSBI+U-Boot proper)"
{
  sleep 8
  printf 'version\n'
  sleep 3
} | timeout "$RUN_TIMEOUT" qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$SPL" \
  -device loader,file="$ITB",addr=0x80200000 2>&1 | tee "$LOG" || true

log "日志：$LOG"
grep -E 'SPL|OpenSBI|U-Boot|Firmware Base|Next Address|Next Mode' "$LOG" | head -25 || true

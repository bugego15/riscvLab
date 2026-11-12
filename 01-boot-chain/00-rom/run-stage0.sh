#!/usr/bin/env bash
# M1-A0：运行“自写 stage0 -> OpenSBI -> 自写 stage1”链条，抓串口日志
# 用法：wsl -d Ubuntu-24.04 -e bash /mnt/d/1212D/riscv-boot-lab/01-boot-chain/00-rom/run-stage0.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

ROM="$BUILD/rom"
LOG="$LOGS/m1-a0-stage0-opensbi-stage1.log"
RUN_TIMEOUT="${RUN_TIMEOUT:-20}"
MEM="${MEM:-512M}"

for f in "$ROM/stage0.bin" "$ROM/stage1.bin" "$ROM/fw_jump_0x80200000.bin"; do
  [ -f "$f" ] || die "缺少产物：$f（先跑 build-rom.sh）"
done

log "运行：QEMU reset -> stage0(0x80000000) -> OpenSBI(0x80200000) -> stage1(0x80400000)"
# 注意：QEMU 的 stdin 必须重定向为 /dev/null。
# 在交互式终端里直接运行时 stdin 是 TTY、stdout 是管道（tee），
# QEMU -nographic 的 stdio 串口会没有任何输出（日志变成 0 字节）。
timeout "$RUN_TIMEOUT" qemu-system-riscv64 \
  -M virt -m "$MEM" -nographic -no-reboot \
  -bios "$ROM/stage0.bin" \
  -device loader,file="$ROM/fw_jump_0x80200000.bin",addr=0x80200000 \
  -device loader,file="$ROM/stage1.bin",addr=0x80400000 \
  < /dev/null 2>&1 | tee "$LOG" || true

log "日志：$LOG"
grep -E 'stage0|stage1|OpenSBI|Platform Name|Firmware Base|Next Address|Next Mode' "$LOG" | head -40 || true

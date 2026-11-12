#!/usr/bin/env bash
# 运行一个 lab 实验（lab.mode=<mode>），串口日志保存到 ~/riscv-lab/logs 与 results/
# 用法：LAB_MODE=buddy bash lab/run-lab.sh
#       LAB_MODE=meminit LAB_EXTRA="memblock=debug" bash lab/run-lab.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

MODE="${LAB_MODE:-${1:-}}"
[ -n "$MODE" ] || die "用法：LAB_MODE=<mode> bash run-lab.sh"
EXTRA="${LAB_EXTRA:-}"
TIMEOUT="${LAB_TIMEOUT:-180}"
IMAGE="$KOUT/arch/riscv/boot/Image"
INITRD="$IMAGES/lab-initramfs.cpio.gz"
FW="${FW_JUMP:-$IMAGES/fw_jump.bin}"
LOG="$LOGS/lab-${MODE}.log"

[ -f "$INITRD" ] || die "缺少 lab initramfs（先跑 lab/mk-lab-initramfs.sh）"
[ -f "$IMAGE" ] || die "缺少内核 Image"
[ -f "$FW" ] || FW="/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin"

case "$MODE" in
  proc) RD="$BUILD/results/m4" ;;
  *)    RD="$BUILD/results/m3" ;;
esac

log "运行 lab 实验：mode=$MODE extra='$EXTRA'"
timeout "$TIMEOUT" qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$IMAGE" -initrd "$INITRD" \
  -append "console=ttyS0 earlycon loglevel=7 lab.mode=${MODE} ${EXTRA}" \
  < /dev/null > "$LOG" 2>&1 || true

mkdir -p "$RD"
cp -f "$LOG" "$RD/lab-${MODE}.log"

log "日志：$LOG"
echo "========== 关键输出（lab 模式 $MODE） =========="
grep -E '\[lab\]|=====|M3|M4|buddy_demo|slab_demo|pgwalk:|task_walk:|LAB DONE|LAB BOOT|panic|Oops' "$LOG" | head -80 || true

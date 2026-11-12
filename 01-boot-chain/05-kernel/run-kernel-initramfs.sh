#!/usr/bin/env bash
# M0/A5：OpenSBI fw_jump + Linux Image + BusyBox initramfs，自动执行命令后关机
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

if [ -z "${FW_JUMP:-}" ]; then
  if [ -f "$IMAGES/fw_jump.bin" ]; then FW_JUMP="$IMAGES/fw_jump.bin"; else FW_JUMP="/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin"; fi
fi
IMAGE="$KOUT/arch/riscv/boot/Image"
INITRD="$IMAGES/initramfs.cpio.gz"
MEM="${MEM:-512M}"
RUN_TIMEOUT="${RUN_TIMEOUT:-90}"
LOG="$LOGS/m0-kernel-initramfs.log"

[ -f "$FW_JUMP" ] || die "缺少 OpenSBI fw_jump：$FW_JUMP"
[ -f "$IMAGE" ] || die "缺少内核 Image：$IMAGE（先跑 01-boot-chain/05-kernel/build-kernel.sh）"
[ -f "$INITRD" ] || die "缺少 initramfs：$INITRD（先跑 01-boot-chain/06-init/mk-initramfs.sh）"

log "启动 Linux ${KVER} + initramfs（$MEM）"
{
  sleep 12
  printf 'uname -a\ncat /proc/cmdline\nhead -5 /proc/meminfo\ncat /proc/iomem | head -12\n'
  sleep 3
  printf 'poweroff -f\n'
} | timeout "$RUN_TIMEOUT" qemu-system-riscv64 \
  -M virt -m "$MEM" -nographic -no-reboot \
  -bios "$FW_JUMP" -kernel "$IMAGE" -initrd "$INITRD" \
  -append "console=ttyS0 earlycon keep_bootcon" 2>&1 | tee "$LOG" || true

log "日志：$LOG"
grep -E 'Linux version|Memory:|initramfs|Run /init|userspace|SBI|riscv' "$LOG" | head -25 || true

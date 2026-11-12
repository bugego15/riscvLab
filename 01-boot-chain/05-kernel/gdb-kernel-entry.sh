#!/usr/bin/env bash
# M1-A4 GDB：观察 Linux 内核入口（a0=hartid, a1=DTB）—— 从 QEMU 直接 -kernel 启动
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/gdb-kernel-entry.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

if [ -z "${FW_JUMP:-}" ]; then
  if [ -f "$IMAGES/fw_jump.bin" ]; then FW_JUMP="$IMAGES/fw_jump.bin"; else FW_JUMP="/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin"; fi
fi
IMAGE="$KOUT/arch/riscv/boot/Image"
INITRD="$IMAGES/initramfs.cpio.gz"
VMLINUX="$KOUT/vmlinux"
LOG="$LOGS/m1-a4-gdb-kernel.log"
GLOG="$LOGS/m1-a4-gdb-kernel-transcript.log"
PORT="${GDB_PORT:-1234}"

[ -f "$IMAGE" ] || die "缺少内核 Image"
[ -f "$VMLINUX" ] || die "缺少 vmlinux"
[ -f "$INITRD" ] || die "缺少 initramfs"

log "启动 QEMU（-S -s）：fw_jump + Image@0x80200000 + initramfs"
qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW_JUMP" -kernel "$IMAGE" -initrd "$INITRD" \
  -append "console=ttyS0 earlycon keep_bootcon" \
  -S -gdb "tcp::$PORT" < /dev/null > "$LOG" 2>&1 &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT
sleep 1

log "GDB 连接（带 vmlinux 符号）"
timeout 120 gdb-multiarch -batch -q \
  -ex 'set pagination off' \
  -ex 'set confirm off' \
  -ex 'set architecture riscv:rv64' \
  -ex "file $VMLINUX" \
  -ex "target remote :$PORT" \
  -ex 'echo \n===== [1] reset vector =====\n' \
  -ex 'info registers pc a0 a1' \
  -ex 'x/6i $pc' \
  -ex 'b *0x80000000' \
  -ex 'echo \n===== [2] OpenSBI entry @0x80000000 (M-mode) =====\n' \
  -ex 'continue' \
  -ex 'info registers pc sp a0 a1 mstatus' \
  -ex 'x/6i $pc' \
  -ex 'b *0x80200000' \
  -ex 'echo \n===== [3] Linux kernel entry @0x80200000: a0=hartid a1=DTB =====\n' \
  -ex 'continue' \
  -ex 'info registers pc sp a0 a1 sstatus' \
  -ex 'x/16i $pc' \
  -ex 'echo \n===== [4] kernel symbols (vmlinux) =====\n' \
  -ex 'info address start_kernel' \
  -ex 'info address setup_arch' \
  -ex 'info address paging_init' \
  -ex 'info address mm_init' \
  -ex 'detach' 2>&1 | tee "$GLOG" || true

kill "$QPID" 2>/dev/null || true
log "GDB 记录：$GLOG"

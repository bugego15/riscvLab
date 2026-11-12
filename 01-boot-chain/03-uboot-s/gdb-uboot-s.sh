#!/usr/bin/env bash
# M1-A1 GDB：观察 OpenSBI（M 模式）-> U-Boot（S 模式）交接时的寄存器
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/gdb-uboot-s.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

FW="$IMAGES/fw_dynamic.bin"
UB="$IMAGES/u-boot-s.bin"
[ -f "$FW" ] || FW="/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin"
[ -f "$UB" ] || UB="/usr/lib/u-boot/qemu-riscv64_smode/u-boot.bin"
[ -f "$UB" ] || die "缺少 U-Boot（先跑 build-uboot-s.sh）"
LOG="$LOGS/m1-a1-gdb.log"
GLOG="$LOGS/m1-a1-gdb-transcript.log"
PORT="${GDB_PORT:-1234}"

log "启动 QEMU（-S -s）：OpenSBI@0x80000000 + U-Boot@0x80200000"
qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$UB" \
  -S -gdb "tcp::$PORT" < /dev/null > "$LOG" 2>&1 &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT
sleep 1

log "GDB 连接"
timeout 90 gdb-multiarch -batch -q \
  -ex 'set pagination off' \
  -ex 'set confirm off' \
  -ex 'set architecture riscv:rv64' \
  -ex "target remote :$PORT" \
  -ex 'echo \n===== [1] reset vector (QEMU ROM) =====\n' \
  -ex 'info registers pc a0 a1' \
  -ex 'x/6i $pc' \
  -ex 'b *0x80000000' \
  -ex 'echo \n===== [2] OpenSBI entry @0x80000000 (M-mode) =====\n' \
  -ex 'continue' \
  -ex 'info registers pc sp a0 a1 mstatus' \
  -ex 'x/6i $pc' \
  -ex 'b *0x80200000' \
  -ex 'echo \n===== [3] U-Boot proper entry @0x80200000 (S-mode) =====\n' \
  -ex 'continue' \
  -ex 'info registers pc sp a0 a1 sstatus' \
  -ex 'x/6i $pc' \
  -ex 'detach' 2>&1 | tee "$GLOG" || true

kill "$QPID" 2>/dev/null || true
log "GDB 记录：$GLOG"

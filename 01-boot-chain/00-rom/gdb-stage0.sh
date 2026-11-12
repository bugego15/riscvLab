#!/usr/bin/env bash
# M1-A0 GDB：观察 QEMU 复位向量、stage0、OpenSBI、stage1 的逐级交接
# 用法：wsl -d Ubuntu-24.04 -e bash /mnt/d/1212D/riscv-boot-lab/01-boot-chain/00-rom/gdb-stage0.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

ROM="$BUILD/rom"
LOG="$LOGS/m1-a0-gdb.log"
GLOG="$LOGS/m1-a0-gdb-transcript.log"
PORT="${GDB_PORT:-1234}"

for f in "$ROM/stage0.bin" "$ROM/stage1.bin" "$ROM/fw_jump_0x80200000.bin"; do
  [ -f "$f" ] || die "缺少产物：$f（先跑 build-rom.sh）"
done

log "启动 QEMU（-S -s，GDB 端口 $PORT）"
qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$ROM/stage0.bin" \
  -device loader,file="$ROM/fw_jump_0x80200000.bin",addr=0x80200000 \
  -device loader,file="$ROM/stage1.bin",addr=0x80400000 \
  -S -gdb "tcp::$PORT" < /dev/null > "$LOG" 2>&1 &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT
sleep 1

log "GDB 连接：复位向量 -> 单步 6 条指令到 stage0 -> 断点看 OpenSBI/stage1 入口"
timeout 90 gdb-multiarch -batch -q \
  -ex 'set pagination off' \
  -ex 'set confirm off' \
  -ex 'set architecture riscv:rv64' \
  -ex "target remote :$PORT" \
  -ex 'echo \n===== [1] QEMU built-in reset vector @0x1000 =====\n' \
  -ex 'info registers pc a0 a1 mstatus' \
  -ex 'x/8i $pc' \
  -ex 'si' -ex 'si' -ex 'si' -ex 'si' -ex 'si' -ex 'si' \
  -ex 'echo \n===== [2] after 6 single-steps: ROM code jumped to 0x80000000 (stage0) =====\n' \
  -ex 'info registers pc sp a0 a1' \
  -ex 'x/6i $pc' \
  -ex 'b *0x80200000' \
  -ex 'echo \n===== [3] continue -> OpenSBI entry 0x80200000 (M-mode firmware) =====\n' \
  -ex 'continue' \
  -ex 'info registers pc sp a0 a1 mstatus' \
  -ex 'x/6i $pc' \
  -ex 'b *0x80400000' \
  -ex 'echo \n===== [4] continue -> stage1 entry 0x80400000 (S-mode payload) =====\n' \
  -ex 'continue' \
  -ex 'info registers pc sp a0 a1 sstatus' \
  -ex 'x/6i $pc' \
  -ex 'detach' 2>&1 | tee "$GLOG" || true

kill "$QPID" 2>/dev/null || true
log "GDB 记录：$GLOG"

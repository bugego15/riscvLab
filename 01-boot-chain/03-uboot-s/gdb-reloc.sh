#!/usr/bin/env bash
# M1-A1 GDB：观察第三阶段 U-Boot 的"接管与重定位"
#   ① U-Boot 入口 0x80200000（S 模式，来自 OpenSBI）
#   ② board_init_f 入口（重定位前，仍在链接地址运行）
#   ③ relocate_code 入口（准备把自己搬到 RAM 高地址）
#   ④ 重定位后的 board_init_r（PC 已在高地址，证明重定位完成）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/gdb-reloc.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

FW="$IMAGES/fw_dynamic.bin"
UB="$IMAGES/u-boot-s.bin"
UBELF="$IMAGES/u-boot-s.elf"
[ -f "$FW" ] || FW="/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin"
[ -f "$UB" ] || UB="/usr/lib/u-boot/qemu-riscv64_smode/u-boot.bin"
[ -f "$UB" ]    || die "缺少 U-Boot bin（先跑 build-uboot-s.sh）"
[ -f "$UBELF" ] || die "缺少 U-Boot ELF（符号/调试信息）：$UBELF"

LOG="$LOGS/m1-a1-gdb-reloc.log"
GLOG="$LOGS/m1-a1-gdb-reloc-transcript.log"
PORT="${GDB_PORT:-1234}"

log "启动 QEMU（-S -s）：OpenSBI@0x80000000 + U-Boot@0x80200000"
qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$UB" \
  -S -gdb "tcp::$PORT" < /dev/null > "$LOG" 2>&1 &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT
sleep 1

log "GDB 观察：U-Boot 入口 -> board_init_f -> relocate_code -> 重定位后 board_init_r"
timeout 120 gdb-multiarch -batch -q \
  -ex 'set pagination off' \
  -ex 'set confirm off' \
  -ex 'set architecture riscv:rv64' \
  -ex "file $UBELF" \
  -ex "target remote :$PORT" \
  -ex 'echo \n===== [1] U-Boot 入口 0x80200000（S 模式，来自 OpenSBI）=====\n' \
  -ex 'b *0x80200000' \
  -ex 'continue' \
  -ex 'info registers pc sp a0 a1 sstatus' \
  -ex 'x/6i $pc' \
  -ex 'echo \n===== [2] board_init_f 入口（重定位前，仍在链接地址运行）=====\n' \
  -ex 'b board_init_f' \
  -ex 'continue' \
  -ex 'info registers pc gp' \
  -ex 'p/x ((gd_t *)$gp)->relocaddr' \
  -ex 'p/x ((gd_t *)$gp)->ram_top' \
  -ex 'x/8i $pc' \
  -ex 'echo \n===== [3] relocate_code 入口（即将把自己搬到 RAM 高地址）=====\n' \
  -ex 'b relocate_code' \
  -ex 'continue' \
  -ex 'info registers pc gp' \
  -ex 'p/x ((gd_t *)$gp)->relocaddr' \
  -ex 'x/12i $pc' \
  -ex 'echo \n===== [4] 重定位之后的 board_init_r：PC 应等于 relocaddr+偏移 =====\n' \
  -ex 'set $reloc = ((gd_t *)$gp)->relocaddr' \
  -ex 'b *($reloc + ((long)board_init_r - (long)_start))' \
  -ex 'continue' \
  -ex 'info registers pc gp' \
  -ex 'x/6i $pc' \
  -ex 'detach' 2>&1 | tee "$GLOG" || true

kill "$QPID" 2>/dev/null || true
log "GDB 记录：$GLOG"

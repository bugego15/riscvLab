#!/usr/bin/env bash
# 第二阶段观察（GDB）：
#   复位向量 -> OpenSBI 入口(M) -> sbi_hart_switch_mode -> mret 前(mstatus.MPP=S) -> 0x80200000(S)
# 默认：fw_dynamic + 演示 payload；可通过 FW/FWELF/NEXT_IMG 环境变量切换变体。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

FW="${FW:-$IMAGES/fw_dynamic.bin}"
FWELF="${FWELF:-$IMAGES/fw_dynamic.elf}"
NEXT_IMG="${NEXT_IMG:-$IMAGES/payload-0x80200000.bin}"
[ -f "$FW" ]       || die "缺少 OpenSBI 固件：$FW（先跑 build-opensbi.sh）"
[ -f "$FWELF" ]    || die "缺少 OpenSBI ELF（符号表）：$FWELF"
[ -f "$NEXT_IMG" ] || die "缺少下一级镜像：$NEXT_IMG（先跑 build-payload.sh）"

LOG="$LOGS/m1-stage2-gdb.log"
GLOG="$LOGS/m1-stage2-gdb-transcript.log"
PORT="${GDB_PORT:-1234}"
BASE=$((0x80000000))          # OpenSBI 加载地址（ELF 链接基址为 0）

# 从 ELF 符号表取 sbi_hart_switch_mode 偏移
# 注意：awk 不能提前 exit（否则 nm 收到 SIGPIPE，pipefail 会把脚本判为失败）
SW_OFF=$(riscv64-linux-gnu-nm "$FWELF" | awk '$3=="sbi_hart_switch_mode"{print $1}')
SW_OFF=$(printf '%s\n' "$SW_OFF" | head -1)
[ -n "$SW_OFF" ] || die "找不到 sbi_hart_switch_mode 符号"
SW_ADDR=$(printf '0x%x' $((BASE + 0x${SW_OFF})))

# 在该函数范围内找第一条 mret
MRET_OFF=$(riscv64-linux-gnu-objdump -d "$FWELF" \
  --start-address=$((0x${SW_OFF})) --stop-address=$((0x${SW_OFF} + 0x200)) 2>/dev/null \
  | awk '$3=="mret"{gsub(":","",$1); if (!f) { print $1; f=1 }}')
MRET_OFF=$(printf '%s\n' "$MRET_OFF" | head -1)
[ -n "$MRET_OFF" ] || die "在 sbi_hart_switch_mode 中找不到 mret"
MRET_ADDR=$(printf '0x%x' $((BASE + 0x${MRET_OFF})))

log "OpenSBI 符号：sbi_hart_switch_mode 偏移=0x$SW_OFF -> 运行地址 $SW_ADDR；mret 运行地址 $MRET_ADDR"

qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$NEXT_IMG" \
  -S -gdb "tcp::$PORT" < /dev/null > "$LOG" 2>&1 &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT
sleep 1

log "GDB 观察：复位 -> OpenSBI(M) -> switch_mode -> mret 前/后"
timeout 120 gdb-multiarch -batch -q \
  -ex 'set pagination off' \
  -ex 'set confirm off' \
  -ex 'set architecture riscv:rv64' \
  -ex "target remote :$PORT" \
  -ex 'echo \n===== [1] QEMU 复位瞬间（PC=0x1000）=====\n' \
  -ex 'info registers pc a0 a1 a2 mstatus' \
  -ex 'x/6i 0x1000' \
  -ex 'echo \n===== [2] OpenSBI 入口 0x80000000（M 模式）=====\n' \
  -ex 'b *0x80000000' \
  -ex 'continue' \
  -ex 'info registers pc a0 a1 a2 mstatus' \
  -ex 'x/6i $pc' \
  -ex 'echo \n===== [3] sbi_hart_switch_mode 入口：参数（a0=hartid a1=dtb a2=next_addr a3=next_mode）=====\n' \
  -ex "b *$SW_ADDR" \
  -ex 'continue' \
  -ex 'info registers pc a0 a1 a2 a3 a4 mstatus' \
  -ex 'echo \n--- 函数开头 ---\n' \
  -ex 'x/12i $pc' \
  -ex 'echo \n===== [4] 即将 mret：mstatus.MPP 应为 S(1)，mepc=下一级地址 =====\n' \
  -ex "b *$MRET_ADDR" \
  -ex 'continue' \
  -ex 'info registers pc mstatus mepc' \
  -ex 'echo \n===== [5] 让 mret 执行，在 0x80200000 停下（此时已进入 S 模式）=====\n' \
  -ex 'b *0x80200000' \
  -ex 'continue' \
  -ex 'info registers pc sstatus a0 a1' \
  -ex 'x/6i $pc' \
  -ex 'detach' 2>&1 | tee "$GLOG" || true

kill "$QPID" 2>/dev/null || true
log "GDB 记录：$GLOG"

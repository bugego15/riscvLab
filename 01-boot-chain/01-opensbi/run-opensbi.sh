#!/usr/bin/env bash
# 第二阶段演示：OpenSBI(fw_dynamic) + 自写 S 模式 payload（0x80200000）
# 观察 OpenSBI 日志 + payload 通过 SBI ecall 打印的版本信息。
# 可通过 FW 环境变量换用 fw_jump.bin（下一级地址来自编译常量）。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

FW="${FW:-$IMAGES/fw_dynamic.bin}"
PAYLOAD="${PAYLOAD:-$IMAGES/payload-0x80200000.bin}"
[ -f "$FW" ]      || die "缺少 OpenSBI 固件：$FW（先跑 build-opensbi.sh）"
[ -f "$PAYLOAD" ] || die "缺少演示 payload：$PAYLOAD（先跑 build-payload.sh）"

LOG="$LOGS/m1-stage2-opensbi-demo.log"
RUN_TIMEOUT="${RUN_TIMEOUT:-20}"

log "运行：复位 -> OpenSBI(0x80000000, M) -> payload(0x80200000, S)"
timeout "$RUN_TIMEOUT" qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$PAYLOAD" \
  < /dev/null 2>&1 | tee "$LOG" || true

log "日志：$LOG"
grep -E 'OpenSBI|Firmware Base|Runtime SBI|Next Address|Next Arg1|Next Mode|SBI spec|SBI impl|stage1' "$LOG" | head -25 || true

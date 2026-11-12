#!/usr/bin/env bash
# 第二阶段演示 payload：复用第一阶段的 S 模式代码（../00-rom/stage1.S/.c），
# 重新链接到 0x80200000，作为 OpenSBI 交接后的"下一级"（不需要 U-Boot 即可演示第二阶段）。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

ROM="$HERE/../00-rom"
OUT="$BUILD/opensbi-demo"
mkdir -p "$OUT"

CC="${CROSS}gcc"
OBJCOPY="${CROSS}objcopy"
CFLAGS="-march=rv64gc -mabi=lp64d -mcmodel=medany -nostdlib -ffreestanding -O2 -Wall -Wextra -fno-stack-protector -fno-pic"

log "编译 S 模式 payload（0x80200000，复用 ../00-rom/stage1.S/.c）"
"$CC" $CFLAGS -T "$HERE/payload-0x80200000.ld" \
  -o "$OUT/payload-0x80200000.elf" "$ROM/stage1.S" "$ROM/stage1.c"
"$OBJCOPY" -O binary "$OUT/payload-0x80200000.elf" "$OUT/payload-0x80200000.bin"
cp "$OUT/payload-0x80200000.bin" "$IMAGES/"
cp "$OUT/payload-0x80200000.elf" "$IMAGES/" 2>/dev/null || true

log "产物："
ls -lh "$OUT/payload-0x80200000.elf" "$OUT/payload-0x80200000.bin"
"${CROSS}readelf" -h "$OUT/payload-0x80200000.elf" | head -6
log "下一步：bash 01-boot-chain/01-opensbi/run-opensbi.sh"

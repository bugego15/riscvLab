#!/usr/bin/env bash
# 第二阶段：从源码构建 OpenSBI（PLATFORM=generic，加载地址 0x80000000）
# 产物：fw_dynamic.bin / fw_jump.bin（及对应 ELF，带符号便于 GDB 观察）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

OUT="$BUILD/opensbi"
rm -rf "$OUT"

log "构建 OpenSBI（PLATFORM=generic，FW_TEXT_START 默认 0x80000000）"
make -C "$SRC/opensbi" O="$OUT" PLATFORM=generic CROSS_COMPILE="$CROSS" -j"$JOBS"

cp "$OUT/platform/generic/firmware/fw_dynamic.bin" "$IMAGES/"
cp "$OUT/platform/generic/firmware/fw_jump.bin"    "$IMAGES/"
cp "$OUT/platform/generic/firmware/fw_dynamic.elf"  "$IMAGES/" 2>/dev/null || true
cp "$OUT/platform/generic/firmware/fw_jump.elf"     "$IMAGES/" 2>/dev/null || true

log "产物："
ls -lh "$IMAGES"/fw_dynamic.* "$IMAGES"/fw_jump.* 2>/dev/null || true
log "下一步：bash 01-boot-chain/01-opensbi/build-payload.sh"

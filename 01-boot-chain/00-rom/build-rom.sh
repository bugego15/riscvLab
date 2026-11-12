#!/usr/bin/env bash
# M1-A0：构建自写 stage0/stage1 + 定制加载地址的 OpenSBI fw_jump
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/build-rom.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

ROMBUILD="$BUILD/rom"
mkdir -p "$ROMBUILD"
CC="${CROSS}gcc"
OBJCOPY="${CROSS}objcopy"
CFLAGS="-march=rv64gc -mabi=lp64d -mcmodel=medany -nostdlib -ffreestanding -O2 -Wall -Wextra -fno-stack-protector -fno-pic"

log "编译 stage0（M-mode, 0x80000000）"
"$CC" $CFLAGS -T "$HERE/stage0.ld" -o "$ROMBUILD/stage0.elf" "$HERE/stage0.S" "$HERE/stage0.c"
"$OBJCOPY" -O binary "$ROMBUILD/stage0.elf" "$ROMBUILD/stage0.bin"

log "编译 stage1（S-mode, 0x80400000）"
"$CC" $CFLAGS -T "$HERE/stage1.ld" -o "$ROMBUILD/stage1.elf" "$HERE/stage1.S" "$HERE/stage1.c"
"$OBJCOPY" -O binary "$ROMBUILD/stage1.elf" "$ROMBUILD/stage1.bin"

log "构建定制 OpenSBI fw_jump（FW_TEXT_START=0x80200000, FW_JUMP_ADDR=0x80400000）"
OPENSBI_OUT="$BUILD/opensbi-rom"
rm -rf "$OPENSBI_OUT"
make -C "$SRC/opensbi" O="$OPENSBI_OUT" PLATFORM=generic CROSS_COMPILE="$CROSS" \
  FW_TEXT_START=0x80200000 FW_JUMP_ADDR=0x80400000 -j"$JOBS"
cp "$OPENSBI_OUT/platform/generic/firmware/fw_jump.bin" "$ROMBUILD/fw_jump_0x80200000.bin"

log "产物："
ls -lh "$ROMBUILD"/*.elf "$ROMBUILD"/*.bin
"${CROSS}readelf" -h "$ROMBUILD/stage0.elf" | head -6
"${CROSS}readelf" -h "$ROMBUILD/stage1.elf" | head -6

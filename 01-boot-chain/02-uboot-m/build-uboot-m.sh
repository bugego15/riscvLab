#!/usr/bin/env bash
# M1-A2：源码构建 M 模式 U-Boot（直接作为 -bios，无 OpenSBI）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/build-uboot-m.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

OUT="$BUILD/uboot-m"
rm -rf "$OUT"

log "配置 U-Boot M 模式（qemu-riscv64_defconfig）"
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" qemu-riscv64_defconfig

# 生成 GDB 可用的 ELF（U-Boot 默认保留符号表）
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" olddefconfig >/dev/null

log "编译 U-Boot M 模式（-j$JOBS）"
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" -j"$JOBS"

cp "$OUT/u-boot.bin" "$IMAGES/u-boot-m.bin"
[ -f "$OUT/u-boot" ] && cp "$OUT/u-boot" "$IMAGES/u-boot-m.elf"
log "产物："
ls -lh "$IMAGES/u-boot-m.bin" "$IMAGES/u-boot-m.elf" 2>/dev/null || true

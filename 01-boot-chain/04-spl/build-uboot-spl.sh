#!/usr/bin/env bash
# M1-A3：源码构建 SPL 两段式 U-Boot（qemu-riscv64_spl_defconfig）
# SPL 在 M 模式加载 u-boot.itb（内含 OpenSBI fw_dynamic + U-Boot proper）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/04-spl/build-uboot-spl.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

OUT="$BUILD/uboot-spl"
FW_DYNAMIC="${FW_DYNAMIC:-$IMAGES/fw_dynamic.bin}"
rm -rf "$OUT"

if [ ! -f "$FW_DYNAMIC" ]; then
  log "缺少 OpenSBI fw_dynamic.bin，先构建 OpenSBI"
  bash "$HERE/../01-opensbi/build-opensbi.sh"
fi
[ -f "$FW_DYNAMIC" ] || die "缺少 $FW_DYNAMIC"

log "配置 U-Boot SPL（qemu-riscv64_spl_defconfig）"
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" qemu-riscv64_spl_defconfig

log "编译 U-Boot SPL（使用 OpenSBI: $FW_DYNAMIC）"
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" \
  OPENSBI="$FW_DYNAMIC" -j"$JOBS"

cp "$OUT/spl/u-boot-spl.bin" "$IMAGES/u-boot-spl.bin"
[ -f "$OUT/spl/u-boot-spl" ] && cp "$OUT/spl/u-boot-spl" "$IMAGES/u-boot-spl.elf"
cp "$OUT/u-boot.itb" "$IMAGES/u-boot.itb"

log "产物："
ls -lh "$IMAGES/u-boot-spl.bin" "$IMAGES/u-boot.itb" 2>/dev/null || true
log "u-boot.itb 内容："
"$SRC/u-boot/tools/dumpimage" -l "$IMAGES/u-boot.itb" 2>/dev/null | head -20 || true

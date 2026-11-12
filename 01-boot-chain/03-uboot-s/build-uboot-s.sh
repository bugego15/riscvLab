#!/usr/bin/env bash
# M1-A1/A4/M2：源码构建 S 模式 U-Boot（需要 OpenSBI 提供 SBI；带 virtio-blk/FAT/env 支持）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/build-uboot-s.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

OUT="$BUILD/uboot-s"
FRAG="$HERE/../../02-uboot-ota/uboot-fragment.config"
rm -rf "$OUT"

log "配置 U-Boot S 模式（qemu-riscv64_smode_defconfig）"
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" qemu-riscv64_smode_defconfig

if [ -f "$FRAG" ]; then
  log "叠加实验配置片段：$FRAG"
  while IFS= read -r line; do
    case "$line" in
      '' ) continue ;;
      '# CONFIG_'*)
        key="$(printf '%s\n' "$line" | sed -n 's/^# \(CONFIG_[A-Za-z0-9_]*\).*/\1/p')"
        ;;
      '#'* ) continue ;;
      *)
        key="${line%%=*}"
        ;;
    esac
    [ -n "${key:-}" ] || continue
    # 删除同名配置（含禁用形式）再追加，避免重复定义
    sed -i "\|^${key}=|d; \|^# ${key} is not set|d" "$OUT/.config" 2>/dev/null || true
    printf '%s\n' "$line" >> "$OUT/.config"
  done < "$FRAG"
fi
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" olddefconfig >/dev/null

log "编译 U-Boot S 模式（-j$JOBS）"
make -C "$SRC/u-boot" O="$OUT" ARCH=riscv CROSS_COMPILE="$CROSS" -j"$JOBS"

cp "$OUT/u-boot.bin" "$IMAGES/u-boot-s.bin"
[ -f "$OUT/u-boot" ] && cp "$OUT/u-boot" "$IMAGES/u-boot-s.elf"
log "产物："
ls -lh "$IMAGES/u-boot-s.bin" "$IMAGES/u-boot-s.elf" 2>/dev/null || true

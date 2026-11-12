#!/usr/bin/env bash
# 构建 lab 内核模块与静态测试程序
# 用法：wsl -d Ubuntu-24.04 -e bash lab/build-lab.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

LAB="$HERE"
BL="$BUILD/lab"
rm -rf "$BL/mods" "$BL/tests"
mkdir -p "$BL/mods" "$BL/tests"

if [ ! -f "$KOUT/Module.symvers" ]; then
  [ -f "$KOUT/vmlinux.symvers" ] || die "缺少 vmlinux.symvers，先构建内核"
  cp -f "$KOUT/vmlinux.symvers" "$KOUT/Module.symvers"
fi

log "构建内核模块（外部模块，针对 $KVER）"
cp -a "$LAB/mods"/. "$BL/mods"/
make -C "$KSRC" O="$KOUT" M="$BL/mods" ARCH=riscv CROSS_COMPILE="$CROSS" modules

log "模块产物："
ls -lh "$BL"/mods/*.ko
for m in "$BL"/mods/*.ko; do
  "${CROSS}objdump" -f "$m" | head -3 >/dev/null
done

log "编译静态测试程序（目标 rootfs 为 BusyBox）"
cp -a "$LAB/tests"/. "$BL/tests"/
for c in "$BL/tests"/*.c; do
  out="${c%.c}"
  "${CROSS}gcc" -static -O2 -Wall -o "$out" "$c"
  file "$out"
done

log "完成：$BL"

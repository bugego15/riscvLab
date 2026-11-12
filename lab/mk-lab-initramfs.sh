#!/usr/bin/env bash
# 制作 lab initramfs（BusyBox + 实验模块 + 静态测试程序 + runner 脚本 + /init）
# 用法：wsl -d Ubuntu-24.04 -e bash lab/mk-lab-initramfs.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

BL="$BUILD/lab"
ROOT="$BL/rootfs"
BBINSTALL="$BUILD_ROOT/rootfs/busybox-install"
KREL="$(cat "$KOUT/include/config/kernel.release" 2>/dev/null || echo "$KVER-riscv-lab")"
OUT="$IMAGES/lab-initramfs.cpio.gz"

[ -d "$BBINSTALL/bin" ] || die "缺少 BusyBox 安装树：$BBINSTALL"
[ -d "$BL/mods" ] || die "缺少 lab 模块（先跑 lab/build-lab.sh）"

log "构建 lab initramfs：kernel release = $KREL"
rm -rf "$ROOT"
mkdir -p "$ROOT"
cp -a "$BBINSTALL"/. "$ROOT"/
mkdir -p "$ROOT"/{proc,sys,dev,tmp,root,etc}
mkdir -p "$ROOT/lib/modules/$KREL/extra"
mkdir -p "$ROOT/root/lab/mods" "$ROOT/root/lab/tests"

cp "$BL"/mods/*.ko "$ROOT/lib/modules/$KREL/extra/"
cp "$BL"/mods/*.ko "$ROOT/root/lab/mods/"
cp "$BL"/tests/fork_exec "$BL"/tests/cow_test "$ROOT/root/lab/tests/"
cp "$HERE"/overlay/*.sh "$ROOT/root/lab/"
cp "$HERE/overlay/init" "$ROOT/init"

chmod +x "$ROOT/init"
chmod +x "$ROOT"/root/lab/*.sh
chmod +x "$ROOT"/root/lab/tests/*
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOT/etc/passwd"
printf 'root:x:0:\n' > "$ROOT/etc/group"
printf 'riscv-lab\n' > "$ROOT/etc/hostname"

log "打包：$OUT"
(
  cd "$ROOT"
  find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$OUT"
)
ls -lh "$OUT"

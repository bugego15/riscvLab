#!/usr/bin/env bash
# M0：制作 BusyBox initramfs（内置 /init，启动后进入交互 shell）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/06-init/mk-initramfs.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

BB="${TOOLS}/busybox-riscv64"
BBINSTALL="${BBINSTALL:-${BUILD_ROOT}/rootfs/busybox-install}"
ROOT="$BUILD/initramfs"
OUT="$IMAGES/initramfs.cpio.gz"

[ -x "$BB" ] || die "缺少 riscv64 busybox：$BB（先跑 00-env/build-busybox.sh）"

rm -rf "$ROOT"
mkdir -p "$ROOT"

if [ -d "$BBINSTALL/bin" ]; then
  log "使用 BusyBox install 树：$BBINSTALL"
  cp -a "$BBINSTALL"/. "$ROOT"/
else
  log "手动创建 BusyBox applet 链接"
  mkdir -p "$ROOT"/{bin,sbin,usr/bin,usr/sbin}
  install -m 0755 "$BB" "$ROOT/bin/busybox"
  APPLETS="sh ash ls cat echo mkdir rmdir rm cp mv ln mount umount mknod dmesg ps kill sleep \
poweroff reboot sync chmod chown df du grep sed awk sort head tail wc tr cut find \
true false test env date hostname uname printf more vi free top"
  for a in $APPLETS; do ln -sf busybox "$ROOT/bin/$a"; done
  ln -sf ../bin/busybox "$ROOT/sbin/init"
fi

mkdir -p "$ROOT"/{proc,sys,dev,tmp,root,run,etc}
[ -e "$ROOT/sbin/init" ] || ln -sf ../bin/busybox "$ROOT/sbin/init"

cat > "$ROOT/init" <<'EOF'
#!/bin/busybox sh
# 实验用最小 init：挂载伪文件系统后进入交互 shell
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
echo ""
echo "=================================================="
echo "  RISC-V initramfs: userspace init (/init) 已运行"
echo "  pid=$$  cmdline: $(cat /proc/cmdline)"
echo "  现在可以将此 shell 交给后续实验（分区/OTA/模块）"
echo "=================================================="
exec /bin/sh
EOF
chmod +x "$ROOT/init"

printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOT/etc/passwd"
printf 'root:x:0:\n' > "$ROOT/etc/group"
printf 'riscv-lab initramfs\n' > "$ROOT/etc/hostname"

log "打包 cpio.gz：$OUT"
(
  cd "$ROOT"
  find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$OUT"
)
ls -lh "$OUT"

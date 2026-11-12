#!/usr/bin/env bash
# M2：制作 A/B rootfs（BusyBox init 根文件系统，ext4 镜像）
# 用法：
#   SLOT=a bash mk-rootfs.sh
#   SLOT=b FAIL=1 bash mk-rootfs.sh      # 生成“故意启动失败”的坏槽（演示回退）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

SLOT="${SLOT:-a}"
FAIL="${FAIL:-0}"
SIZE_MB="${SIZE_MB:-48}"
OUT="${OUT:-$IMAGES/rootfs-${SLOT}.img}"
BBINSTALL="$BUILD_ROOT/rootfs/busybox-install"
ROOTDIR="$BUILD/rootfs-${SLOT}"

[ -d "$BBINSTALL/bin" ] || die "缺少 BusyBox 安装树：$BBINSTALL（先跑 00-env/build-busybox.sh）"

log "创建 rootfs 目录树：slot=$SLOT fail=$FAIL -> $ROOTDIR"
rm -rf "$ROOTDIR"
mkdir -p "$ROOTDIR"
cp -a "$BBINSTALL"/. "$ROOTDIR"/
mkdir -p "$ROOTDIR"/{proc,sys,dev,tmp,run,data,root,etc/init.d,usr/sbin,var/log}

printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOTDIR/etc/passwd"
printf 'root:x:0:\n' > "$ROOTDIR/etc/group"
printf '%s\n' "$SLOT" > "$ROOTDIR/etc/slot"
printf 'riscv-lab-slot-%s\n' "$SLOT" > "$ROOTDIR/etc/hostname"
[ "$FAIL" = "1" ] && touch "$ROOTDIR/etc/fail-boot"

cat > "$ROOTDIR/etc/inittab" <<'EOF'
::sysinit:/etc/init.d/rcS
::askfirst:/bin/sh
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
EOF

cat > "$ROOTDIR/etc/init.d/rcS" <<'EOF'
#!/bin/sh
# 应用层初始化：BusyBox init -> /etc/inittab -> 本脚本 -> shell
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
SLOT=$(cat /etc/slot)
hostname "riscv-lab-${SLOT}" 2>/dev/null

echo ""
echo "=================================================="
echo "  RISC-V rootfs slot: ${SLOT}"
echo "  (BusyBox init: /etc/inittab -> rcS -> shell)"
echo "=================================================="

# 故意制造“坏镜像”：启动即失败并复位，用于演示 A/B 回退
if [ -f /etc/fail-boot ]; then
  echo "LAB BOOT FAIL: slot ${SLOT} is intentionally broken (simulating bad OTA image)"
  sync
  reboot -f
  sleep 10
  exit 0
fi

# 挂载 OTA 状态/数据分区（GPT p4）
mkdir -p /data
if mount -t ext4 /dev/vda4 /data 2>/dev/null; then
  # 有待安装的 OTA 包则自动执行用户态 OTA agent
  if [ -f /data/pkg/do-ota ]; then
    /usr/sbin/ota-agent.sh || true
  fi
  # 正常启动成功：确认当前槽，清除 upgrade_available / bootcount
  cat > /data/ota.env <<EOE
slot=${SLOT}
upgrade_available=0
bootcount=0
bootlimit=3
EOE
  sync
fi

echo "LAB BOOT OK: slot ${SLOT}"
EOF
chmod +x "$ROOTDIR/etc/init.d/rcS"

cp "$HERE/ota-agent.sh" "$ROOTDIR/usr/sbin/ota-agent.sh"
chmod +x "$ROOTDIR/usr/sbin/ota-agent.sh"

log "生成 ext4 镜像：$OUT (${SIZE_MB}MiB)"
rm -f "$OUT"
mke2fs -q -t ext4 -b 1024 -F -d "$ROOTDIR" -L "rootfs_${SLOT}" "$OUT" $(( SIZE_MB * 1024 ))
ls -lh "$OUT"

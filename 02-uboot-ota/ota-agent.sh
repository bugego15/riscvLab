#!/bin/sh
# 用户态 OTA agent（运行在 BusyBox rootfs 内，演示“应用层升级”）
# 职责：校验包 -> 写非活动槽(/dev/vda3) -> 更新 OTA 状态(ota.env) -> 重启
# 由 /etc/init.d/rcS 在发现 /data/pkg/do-ota 时自动执行
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

PKGDIR=/data/pkg
GZ="$PKGDIR/rootfs_b.img.gz"
SHAFILE="$PKGDIR/rootfs_b.sha256"
TARGET=/dev/vda3
STATEFILE=/data/ota.env

echo "[ota-agent] ===== userspace OTA agent start ====="
if [ ! -f "$GZ" ] || [ ! -f "$SHAFILE" ]; then
    echo "[ota-agent] OTA REJECTED: package files missing"
    rm -f "$PKGDIR/do-ota"
    sync
    exit 1
fi

EXPECTED=$(cat "$SHAFILE")
ACTUAL=$(sha256sum "$GZ" | awk '{print $1}')
echo "[ota-agent] package      : $GZ"
echo "[ota-agent] expected hash: $EXPECTED"
echo "[ota-agent] actual   hash: $ACTUAL"

if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "[ota-agent] OTA REJECTED: checksum mismatch (bad package NOT applied)"
    mv "$PKGDIR/do-ota" "$PKGDIR/do-ota.rejected" 2>/dev/null || true
    sync
    exit 1
fi

echo "[ota-agent] checksum OK, writing inactive slot B ($TARGET) ..."
gunzip -c "$GZ" | dd of="$TARGET" bs=1M 2>/dev/null
sync
echo "[ota-agent] slot B written"

cat > "$STATEFILE" <<EOF
slot=b
upgrade_available=1
bootcount=0
bootlimit=3
EOF
rm -f "$PKGDIR/do-ota"
sync
echo "[ota-agent] ota.env updated (pending upgrade to slot=b); rebooting"
reboot -f

#!/usr/bin/env bash
# M2：制作完整的 A/B OTA 磁盘镜像（256MiB GPT）
#   p1 FAT16  64MiB : boot.scr + slot_a.itb + slot_b.itb
#   p2 ext4   48MiB : rootfs_a
#   p3 ext4   48MiB : rootfs_b
#   p4 ext4   32MiB : data（ota.env + OTA 包）
# 用法：
#   SCENARIO=none   bash mk-ab-disk.sh     # 普通盘（不预置 OTA 包）
#   SCENARIO=normal bash mk-ab-disk.sh     # 预置正常 OTA 包（自动升级到 b）
#   SCENARIO=bad    bash mk-ab-disk.sh     # 预置损坏包（校验失败拒绝）
#   SCENARIO=broken bash mk-ab-disk.sh     # 预置“坏槽 b”包（启动失败 -> 自动回退）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

SCENARIO="${SCENARIO:-none}"
DISK="$IMAGES/ab-disk.img"
DISK_MB=256
P1_START=2048;  P1_SIZE=131072    # 1MiB   .. 65MiB   FAT  64MiB
P2_START=133120; P2_SIZE=98304    # 65MiB  .. 113MiB  rootfs_a 48MiB
P3_START=231424; P3_SIZE=98304    # 113MiB .. 161MiB  rootfs_b 48MiB
P4_START=329728; P4_SIZE=65536    # 161MiB .. 193MiB  data 32MiB

BOOTSCR="$BUILD/boot.scr"
FATIMG="$BUILD/ab-fat.img"
DATAIMG="$BUILD/ab-data.img"
DATAROOT="$BUILD/ab-data-root"
DTB="$BUILD/virt.dtb"
ROOTFS_A="$BUILD/rootfs_a.img"
ROOTFS_B="$BUILD/rootfs_b.img"

log "构建 U-Boot 启动脚本 boot.scr"
mkimage -A riscv -T script -C none -n "riscv-lab A/B boot script" -d "$HERE/boot-ab.cmd" "$BOOTSCR" >/dev/null

log "创建 ${DISK_MB}MiB 磁盘并写 GPT"
rm -f "$DISK"
truncate -s "${DISK_MB}M" "$DISK"
printf 'label: gpt\nstart=%d, size=%d, type=U\nstart=%d, size=%d, type=L\nstart=%d, size=%d, type=L\nstart=%d, size=%d, type=L\n' \
  "$P1_START" "$P1_SIZE" "$P2_START" "$P2_SIZE" "$P3_START" "$P3_SIZE" "$P4_START" "$P4_SIZE" | sfdisk -q "$DISK"

log "生成 QEMU virt DTB（包含 virtio-blk 节点）"
rm -f "$DTB"
qemu-system-riscv64 -M "virt,dumpdtb=$DTB" -m 512M -nographic \
  -drive "file=$DISK,format=raw,if=none,id=hd0" -device virtio-blk-device,drive=hd0 < /dev/null >/dev/null
[ -s "$DTB" ] || die "DTB 生成失败"
ls -l "$DTB"

log "构建两个槽的 FIT（kernel+dtb，gzip+sha256）"
OUT="$BUILD/slot_a.itb" bash "$HERE/mk-fit.sh" >/dev/null
OUT="$BUILD/slot_b.itb" bash "$HERE/mk-fit.sh" >/dev/null

log "构建 rootfs A/B 镜像"
SLOT=a OUT="$ROOTFS_A" bash "$HERE/mk-rootfs.sh" >/dev/null
SLOT=b OUT="$ROOTFS_B" bash "$HERE/mk-rootfs.sh" >/dev/null

case "$SCENARIO" in
  none)
    log "场景 none：不预置 OTA 包"
    ;;
  corruptfit)
    log "场景 corruptfit：破坏 slot_a FIT（模拟下载不完整/被篡改），验证 hash 校验与槽回退"
    ;;
  normal|bad|broken)
    log "场景 $SCENARIO：预置 OTA 包"
    if [ "$SCENARIO" = "broken" ]; then
      SLOT=b FAIL=1 OUT="$BUILD/rootfs_b_broken.img" bash "$HERE/mk-rootfs.sh" >/dev/null
      SRCIMG="$BUILD/rootfs_b_broken.img"
    else
      SRCIMG="$ROOTFS_B"
    fi
    gzip -9 -c "$SRCIMG" > "$BUILD/pkg-rootfs_b.img.gz"
    sha256sum "$BUILD/pkg-rootfs_b.img.gz" | awk '{print $1}' > "$BUILD/pkg-rootfs_b.sha256"
    ;;
  *)
    die "未知 SCENARIO=$SCENARIO（none|normal|bad|broken|corruptfit）"
    ;;
esac

# corruptfit：在写入 FAT 前损坏 slot_a.itb 的一个字节（保留 FIT 结构，只让 hash 不匹配）
if [ "$SCENARIO" = "corruptfit" ]; then
  printf '\xff' | dd of="$BUILD/slot_a.itb" bs=1 seek=$(( 0x3000 )) conv=notrunc status=none
  log "已损坏 slot_a.itb @0x3000（bad FIT hash 场景）"
fi

log "制作 FAT 分区镜像（boot.scr + 两个槽的 FIT）"
rm -f "$FATIMG"
truncate -s 64M "$FATIMG"
mkfs.fat -F 16 -n BOOT "$FATIMG" >/dev/null
mcopy -i "$FATIMG" "$BOOTSCR" ::/boot.scr
mcopy -i "$FATIMG" "$BUILD/slot_a.itb" ::/slot_a.itb
mcopy -i "$FATIMG" "$BUILD/slot_b.itb" ::/slot_b.itb
mdir -i "$FATIMG" ::/

log "制作 data 分区镜像（ext4：ota.env + OTA 包）"
rm -rf "$DATAROOT"; mkdir -p "$DATAROOT/pkg"
case "$SCENARIO" in
  normal|bad|broken)
    cp "$BUILD/pkg-rootfs_b.img.gz" "$DATAROOT/pkg/rootfs_b.img.gz"
    cp "$BUILD/pkg-rootfs_b.sha256" "$DATAROOT/pkg/rootfs_b.sha256"
    touch "$DATAROOT/pkg/do-ota"
    if [ "$SCENARIO" = "bad" ]; then
      # 破坏包的第一个数据字节，但保留原始 sha256 -> agent 校验失败
      printf '\xff' | dd of="$DATAROOT/pkg/rootfs_b.img.gz" bs=1 seek=2000 conv=notrunc status=none
      log "已注入损坏字节（bad 场景）"
    fi
    ;;
esac
rm -f "$DATAIMG"
truncate -s 32M "$DATAIMG"
# 关键：U-Boot 的 ext4write 不支持 metadata_csum/64bit/orphan_file 等特性，
# 因此 data 分区必须用“可写”的 ext4 特性组合（内核端照常读写）。
mke2fs -q -t ext4 -b 1024 -F \
  -O ^metadata_csum,^metadata_csum_seed,^64bit,^orphan_file \
  -d "$DATAROOT" -L data "$DATAIMG" $(( 32 * 1024 ))

log "把各分区写入磁盘镜像"
dd if="$FATIMG"     of="$DISK" bs=1M seek=1   conv=notrunc status=none
dd if="$ROOTFS_A"   of="$DISK" bs=1M seek=65  conv=notrunc status=none
dd if="$ROOTFS_B"   of="$DISK" bs=1M seek=113 conv=notrunc status=none
dd if="$DATAIMG"    of="$DISK" bs=1M seek=161 conv=notrunc status=none

log "分区表："
sfdisk -l "$DISK" | head -14
log "完成：$DISK (scenario=$SCENARIO)"

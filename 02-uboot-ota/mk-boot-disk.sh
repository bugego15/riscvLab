#!/usr/bin/env bash
# M1-A4：制作带 FAT 启动分区的磁盘镜像（Image + initramfs + boot.scr），供 U-Boot 加载
# 做法：单独造 FAT 分区镜像（mkfs.fat + mtools）→ dd 到 GPT 分区偏移处，全程离线无需 loop 设备
# 用法：wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/mk-boot-disk.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

IMG="$IMAGES/boot-disk.img"
FATIMG="$BUILD/boot-fat.img"
IMAGE="$KOUT/arch/riscv/boot/Image"
INITRD="$IMAGES/initramfs.cpio.gz"
UINITRD="$BUILD/initramfs.uimg"
SCR="$BUILD/boot.scr"
DISK_MB="${DISK_MB:-64}"
BOOT_START_MB=1
BOOT_SIZE_MB=$(( DISK_MB - BOOT_START_MB - 1 ))    # 留 1MiB 尾部余量

[ -f "$IMAGE" ] || die "缺少内核 Image：$IMAGE（先跑 01-boot-chain/05-kernel/build-kernel.sh）"
[ -f "$INITRD" ] || die "缺少 initramfs：$INITRD（先跑 06-init/mk-initramfs.sh）"

log "创建 ${DISK_MB}MiB 磁盘镜像：$IMG"
rm -f "$IMG"
truncate -s "${DISK_MB}M" "$IMG"

log "写 GPT 分区表（FAT 启动分区 @${BOOT_START_MB}MiB，大小 ${BOOT_SIZE_MB}MiB）"
printf 'label: gpt\nstart=%d, size=%d, type=U\n' \
  $(( BOOT_START_MB * 2048 )) $(( BOOT_SIZE_MB * 2048 )) | sfdisk -q "$IMG"

log "制作 FAT16 分区镜像：$FATIMG"
rm -f "$FATIMG"
truncate -s "${BOOT_SIZE_MB}M" "$FATIMG"
mkfs.fat -F 16 -n BOOT "$FATIMG" >/dev/null

log "打包 boot.scr：$SCR"
mkimage -A riscv -T script -C none -n "riscv-lab boot script" -d "$HERE/boot.cmd" "$SCR" >/dev/null

log "打包 uInitrd（U-Boot booti 需要的 ramdisk 格式）：$UINITRD"
mkimage -A riscv -O linux -T ramdisk -C gzip -n "riscv-lab initramfs" -d "$INITRD" "$UINITRD" >/dev/null

log "写入 FAT 分区内容"
mcopy -i "$FATIMG" "$IMAGE" ::/Image
mcopy -i "$FATIMG" "$UINITRD" ::/initramfs.uimg
mcopy -i "$FATIMG" "$SCR" ::/boot.scr
mdir -i "$FATIMG" ::/

log "合并到磁盘镜像（偏移 ${BOOT_START_MB}MiB）"
dd if="$FATIMG" of="$IMG" bs=1M seek="$BOOT_START_MB" conv=notrunc status=none

log "分区表："
sfdisk -l "$IMG" | head -12
log "完成：$IMG"

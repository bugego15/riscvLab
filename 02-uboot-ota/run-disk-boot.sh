#!/usr/bin/env bash
# M1-A4：U-Boot 从 virtio-blk 的 FAT 分区加载内核（booti）并启动到用户态
# 用法：wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/run-disk-boot.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

FW="$IMAGES/fw_dynamic.bin"
UB="$IMAGES/u-boot-s.bin"
DISK="$IMAGES/boot-disk.img"
LOG="$LOGS/m1-a4-uboot-booti.log"
RUN_TIMEOUT="${RUN_TIMEOUT:-90}"

[ -f "$FW" ] || die "缺少 OpenSBI fw_dynamic.bin（先跑 01-opensbi/build-opensbi.sh）"
[ -f "$UB" ] || die "缺少 U-Boot S 模式（先跑 03-uboot-s/build-uboot-s.sh）"
[ -f "$DISK" ] || die "缺少磁盘镜像（先跑 02-uboot-ota/mk-boot-disk.sh）"

log "启动：OpenSBI -> U-Boot(S) -> 从 virtio-blk FAT 加载 Image/initramfs -> booti -> Linux"
timeout "$RUN_TIMEOUT" qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$UB" \
  -drive "file=$DISK,format=raw,if=none,id=hd0" \
  -device virtio-blk-device,drive=hd0 \
  < /dev/null 2>&1 | tee "$LOG" || true

log "日志：$LOG"
grep -E 'U-Boot|boot.scr|fatload|booti|Linux version|Run /init|RISC-V initramfs|VirtIO|virtio' "$LOG" | head -30 || true

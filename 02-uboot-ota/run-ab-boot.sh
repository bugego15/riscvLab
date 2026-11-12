#!/usr/bin/env bash
# M2：连续启动 N 次的测试驱动（模拟“失败自动重启 -> bootcount 累加 -> 回退”）
# 每次 QEMU 启动 = 一次上电；guest 内 reboot -f 会让 QEMU 退出（-no-reboot），
# 于是脚本自动开始下一次上电。日志逐次保存，最后复制到 results/m2。
# 用法：TAG=normal MAX_BOOTS=3 bash run-ab-boot.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

FW="$IMAGES/fw_dynamic.bin"
UB="$IMAGES/u-boot-s.bin"
DISK="$IMAGES/ab-disk.img"
TAG="${TAG:-run}"
MAX_BOOTS="${MAX_BOOTS:-8}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-30}"
OUTDIR="$LOGS/ab-$TAG"
RESULT_DIR="${RESULT_DIR:-$BUILD/results/m2/$TAG}"

[ -f "$DISK" ] || die "缺少 A/B 磁盘：$DISK（先跑 mk-ab-disk.sh）"
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

log "A/B 测试：tag=$TAG max_boots=$MAX_BOOTS timeout=${BOOT_TIMEOUT}s"
success=0
for i in $(seq 1 "$MAX_BOOTS"); do
  LOG="$OUTDIR/boot$i.log"
  log "----- power-on #$i -----"
  timeout "$BOOT_TIMEOUT" qemu-system-riscv64 \
    -M virt -m 512M -nographic -no-reboot \
    -bios "$FW" -kernel "$UB" \
    -drive "file=$DISK,format=raw,if=none,id=hd0" \
    -device virtio-blk-device,drive=hd0 \
    < /dev/null > "$LOG" 2>&1 || true

  grep -E '\[boot.scr\]' "$LOG" | head -8 | sed 's/^/  | /' || true
  if grep -q 'LAB BOOT OK' "$LOG"; then
    grep -E 'rootfs slot|LAB BOOT OK' "$LOG" | sed 's/^/  | /' || true
    log "结果：第 $i 次上电成功启动（LAB BOOT OK）"
    success=1
    break
  fi
  if grep -q 'LAB BOOT FAIL' "$LOG"; then
    log "  该槽启动失败（LAB BOOT FAIL），等待下一次上电..."
  fi
done

mkdir -p "$RESULT_DIR"
cp -f "$OUTDIR"/*.log "$RESULT_DIR"/ 2>/dev/null || true
# 提取最终 data 分区里的 ota.env（从磁盘镜像直接读）
SKIP=$(( 161 * 1024 * 1024 ))
dd if="$DISK" of="$BUILD/ab-data-final.img" bs=1M skip=161 count=32 status=none
if debugfs -R "cat /ota.env" "$BUILD/ab-data-final.img" 2>/dev/null > "$OUTDIR/final-ota.env"; then
  log "最终 ota.env 状态："
  sed 's/^/  | /' "$OUTDIR/final-ota.env" || true
  cp -f "$OUTDIR/final-ota.env" "$RESULT_DIR/final-ota.env"
else
  log "（无法读取 data 分区里的 ota.env）"
fi

log "日志目录：$OUTDIR（已复制到 $RESULT_DIR）"
exit $(( success == 1 ? 0 : 1 ))

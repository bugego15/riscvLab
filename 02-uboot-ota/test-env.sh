#!/usr/bin/env bash
# M2：验证 U-Boot 环境变量持久化到 virtio-blk FAT 分区（脚本化、无需交互按键）
#   1) 复制 A/B 磁盘，把 FAT 里的 boot.scr 换成“执行 setenv+saveenv”的测试脚本
#   2) 启动一次 -> saveenv 把环境写入 FAT 的 uboot.env
#   3) 抽出 FAT 检查 uboot.env 文件
#   4) 换回标准 boot.scr，再启动一次 -> 应从 FAT 读回环境，并打印 testvar
# 用法：wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/test-env.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

FW="$IMAGES/fw_dynamic.bin"
UB="$IMAGES/u-boot-s.bin"
SRCDISK="$IMAGES/ab-disk.img"
DISK="$BUILD/ab-env-test.img"
FATIMG="$BUILD/ab-env-fat.img"
STDSCR="$BUILD/boot.scr"
ENVSCR="$BUILD/env-test.scr"
ENVCMD="$BUILD/env-test.cmd"
LOG1="$LOGS/m2-env-save.log"
LOG2="$LOGS/m2-env-load.log"
RESULT_DIR="${RESULT_DIR:-$BUILD/results/m2}"

[ -f "$SRCDISK" ] || die "缺少 A/B 磁盘：$SRCDISK"

log "===== 第 1 步：制作含 setenv+saveenv 的临时启动脚本 ====="
cat > "$ENVCMD" <<'EOF'
echo "=== env persistence test: set + save ==="
setenv testvar hello_uboot_persist
saveenv
echo "ENV_SAVE_DONE testvar=${testvar}"
EOF
mkimage -A riscv -T script -C none -n envtest -d "$ENVCMD" "$ENVSCR" >/dev/null

log "===== 第 2 步：复制磁盘并把 FAT 中的 boot.scr 换成测试脚本 ====="
cp -f "$SRCDISK" "$DISK"
dd if="$DISK" of="$FATIMG" bs=1M skip=1 count=64 status=none
mcopy -o -i "$FATIMG" "$ENVSCR" ::/boot.scr
dd if="$FATIMG" of="$DISK" bs=1M seek=1 conv=notrunc status=none

log "===== 第 3 步：启动一次，让 U-Boot 执行 saveenv ====="
timeout 25 qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$UB" \
  -drive "file=$DISK,format=raw,if=none,id=hd0" \
  -device virtio-blk-device,drive=hd0 \
  < /dev/null > "$LOG1" 2>&1 || true
grep -E 'Saving Environment|ENV_SAVE_DONE|Saving to FAT|uboot.env|OK' "$LOG1" | head -8 || true

log "===== 第 4 步：抽出 FAT 分区，确认 uboot.env 文件已生成 ====="
dd if="$DISK" of="$FATIMG" bs=1M skip=1 count=64 status=none
mdir -i "$FATIMG" ::/ 2>/dev/null | head -12 || true
HASENV=0
if mdir -i "$FATIMG" ::/ 2>/dev/null | grep -q 'UBOOT.ENV'; then HASENV=1; fi
# mtools 输出大写文件名，兼容一下
if [ "$HASENV" = "0" ] && mdir -i "$FATIMG" ::/ 2>/dev/null | grep -qi 'uboot.env'; then HASENV=1; fi
log "FAT 中 uboot.env 存在：$HASENV"

log "===== 第 5 步：换回标准 boot.scr，再启动一次，验证环境被读回 ====="
mkimage -A riscv -T script -C none -n "riscv-lab A/B boot script" -d "$HERE/boot-ab.cmd" "$STDSCR" >/dev/null
dd if="$DISK" of="$FATIMG" bs=1M skip=1 count=64 status=none
mcopy -o -i "$FATIMG" "$STDSCR" ::/boot.scr
dd if="$FATIMG" of="$DISK" bs=1M seek=1 conv=notrunc status=none

timeout 35 qemu-system-riscv64 \
  -M virt -m 512M -nographic -no-reboot \
  -bios "$FW" -kernel "$UB" \
  -drive "file=$DISK,format=raw,if=none,id=hd0" \
  -device virtio-blk-device,drive=hd0 \
  < /dev/null > "$LOG2" 2>&1 || true
grep -E 'Loading Environment from FAT|persisted env var|LAB BOOT OK' "$LOG2" | head -8 || true

mkdir -p "$RESULT_DIR"
cp -f "$LOG1" "$LOG2" "$RESULT_DIR"/ 2>/dev/null || true

if grep -q 'persisted env var: testvar=hello_uboot_persist' "$LOG2"; then
  log "✅ 验证通过：U-Boot env 已持久化到 virtio-blk FAT，重启后仍可读回"
  exit 0
else
  log "❌ 验证失败：重启后没有读回 testvar（见 $LOG2）"
  exit 1
fi

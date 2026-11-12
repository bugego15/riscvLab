#!/usr/bin/env bash
# M2：三个 OTA 演示场景一键测试
#   1) normal   正常升级：slot a -> 安装包 -> 重启进 slot b 并确认
#   2) bad      坏包：sha256 校验失败，拒绝安装，继续从 slot a 启动
#   3) rollback 坏镜像：slot b 启动失败 -> 反复复位 -> bootcount 超限 -> 自动回退 slot a
# 用法：wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/test-ota.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

# 说明：本实验的 U-Boot 配置下，FIT 内 gzip 内核解压路径会挂起（已在 M2 记录为发现），
# 因此统一使用未压缩 FIT（25MB/槽，HASH 校验等机制不变）。
export COMPRESSION="${COMPRESSION:-none}"

run_case() {
  local scenario="$1" tag="$2" maxboots="$3"
  log "########## OTA 场景：$tag（scenario=$scenario） ##########"
  SCENARIO="$scenario" bash "$HERE/mk-ab-disk.sh" >/dev/null
  TAG="$tag" MAX_BOOTS="$maxboots" BOOT_TIMEOUT="${BOOT_TIMEOUT:-30}" bash "$HERE/run-ab-boot.sh"
  local rc=$?
  log "场景 $tag 结束：rc=$rc"
  return $rc
}

RESULTS_DIR="${RESULTS_DIR:-$BUILD/results/m2}"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR"/*.log "$RESULTS_DIR"/*-final-ota.env
FAILED=0

run_case normal   normal    3 || FAILED=1
run_case bad      bad       2 || FAILED=1
run_case broken   rollback  8 || FAILED=1
run_case corruptfit fit_hash_fallback 1 || FAILED=1

log "========== 总结 =========="
if [ "$FAILED" -eq 0 ]; then
  log "四个 OTA 场景全部通过（正常升级 / 坏包拒绝 / 坏镜像自动回退 / FIT 哈希校验回退）"
else
  log "有场景未通过，请查看 $BUILD/results/m2 下日志"
fi
exit "$FAILED"

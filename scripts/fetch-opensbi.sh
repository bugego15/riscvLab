#!/usr/bin/env bash
# 下载 OpenSBI v1.7 源码到构建根（默认 ~/riscv-lab/src/opensbi）
# 使用 gitee 镜像（GitHub 直连受限时可用）；如可访问 GitHub 也可自行改 URL。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/common.sh"

if [ -d "$SRC/opensbi" ]; then
  log "OpenSBI 源码已存在：$SRC/opensbi"
else
  log "下载 OpenSBI v1.7（gitee 镜像）到 $SRC/opensbi"
  git clone --depth 1 --branch v1.7 https://gitee.com/mirrors/opensbi.git "$SRC/opensbi"
fi

log "OpenSBI 源码就绪："
ls -d "$SRC/opensbi" && head -3 "$SRC/opensbi/README.md" 2>/dev/null || true

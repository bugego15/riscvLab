#!/usr/bin/env bash
# M2：把内核(gzip)+DTB 打包成 FIT（带 sha256 校验）
# 用法：OUT=$BUILD/slot_a.itb bash mk-fit.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

OUT="${OUT:-$BUILD/slot_a.itb}"
DTB="${DTB:-$BUILD/virt.dtb}"
KERNEL="${KERNEL:-$KOUT/arch/riscv/boot/Image}"
KERNEL_GZ="$BUILD/Image.gz"
ITS="$BUILD/slot.its"
COMPRESSION="${COMPRESSION:-gzip}"     # gzip | none

[ -f "$KERNEL" ] || die "缺少内核 Image：$KERNEL"
[ -f "$DTB" ] || die "缺少 DTB：$DTB（先跑 mk-ab-disk.sh 生成）"

if [ "$COMPRESSION" = "gzip" ]; then
  log "压缩内核（gzip，FIT 内压缩）：$KERNEL_GZ"
  gzip -9 -c "$KERNEL" > "$KERNEL_GZ"
  KDATA="$KERNEL_GZ"
else
  log "使用未压缩内核数据"
  KDATA="$KERNEL"
fi

cat > "$ITS" <<EOF
/dts-v1/;
/ {
    description = "riscv-lab A/B slot FIT";
    #address-cells = <1>;
    images {
        kernel@1 {
            description = "Linux 6.12 riscv-lab";
            data = /incbin/("$KDATA");
            type = "kernel";
            arch = "riscv";
            os = "linux";
            compression = "$COMPRESSION";
            load = <0x80200000>;
            entry = <0x80200000>;
            hash@1 { algo = "sha256"; };
        };
        fdt@1 {
            description = "QEMU virt DTB";
            data = /incbin/("$DTB");
            type = "flat_dt";
            arch = "riscv";
            compression = "none";
            hash@1 { algo = "sha256"; };
        };
    };
    configurations {
        default = "conf";
        conf {
            description = "riscv-lab slot config";
            kernel = "kernel@1";
            fdt = "fdt@1";
        };
    };
};
EOF

log "生成 FIT：$OUT"
mkimage -f "$ITS" "$OUT" >/dev/null
ls -lh "$OUT"
"$SRC/u-boot/tools/dumpimage" -l "$OUT" 2>/dev/null | head -12 || mkimage -l "$OUT" | head -12

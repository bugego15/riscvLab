# M2：U-Boot A/B 启动脚本（用 mkimage -T script 打包成 boot.scr）
# 流程：读 data 分区 ota.env 状态 → 待升级则 bootcount+1，超限回退 → 按槽加载 FIT → bootm
# 说明：
#   - envaddr 用 0x87000000，避免 env import/export 缓冲区覆盖位于 0x8e000000 的脚本自身
#   - data 分区是“无 metadata_csum 的 ext4”，这是 U-Boot ext4write 能写的格式
echo ""
echo "=== [boot.scr] RISC-V A/B boot flow ==="
setenv fitaddr 0x88000000
setenv envaddr 0x87000000

# 验证项：U-Boot 环境变量是否从 FAT 持久化读回（test-env.sh 会设置 testvar）
if test -n "${testvar}"; then
  echo "[boot.scr] persisted env var: testvar=${testvar}"
fi

# 首次启动默认状态
if test -z "${slot}"; then
  setenv slot a
  setenv upgrade_available 0
  setenv bootcount 0
  setenv bootlimit 3
fi

# 从 data 分区（GPT p4, ext4）读取 OTA 状态
if ext4load virtio 0:4 ${envaddr} ota.env; then
  env import -t ${envaddr} ${filesize}
  echo "[boot.scr] ota state: slot=${slot} upgrade=${upgrade_available} bootcount=${bootcount}/${bootlimit}"
else
  echo "[boot.scr] no ota.env yet (first boot)"
fi

# 待升级槽的启动计数与自动回退
if test "${upgrade_available}" = "1"; then
  setexpr bootcount ${bootcount} + 1
  echo "[boot.scr] pending upgrade attempt: bootcount=${bootcount}/${bootlimit} slot=${slot}"
  if test ${bootcount} -gt ${bootlimit}; then
    if test "${slot}" = "b"; then setenv slot a; else setenv slot b; fi
    echo "[boot.scr] !!! ROLLBACK -> slot ${slot} (too many failed boots)"
    setenv upgrade_available 0
    setenv bootcount 0
  fi
  # 持久化状态到 data 分区（模拟重启前保存；掉电后状态不丢）
  env export -t ${envaddr}
  if ext4write virtio 0:4 ${envaddr} ota.env ${filesize}; then
    echo "[boot.scr] state saved to data partition (ota.env)"
  else
    echo "[boot.scr] WARN: state save failed"
  fi
fi

# 选择槽对应的 FIT 与 rootfs 分区
if test "${slot}" = "b"; then
  setenv slotfile slot_b.itb
  setenv rootdev /dev/vda3
  setenv slotname B
else
  setenv slotfile slot_a.itb
  setenv rootdev /dev/vda2
  setenv slotname A
fi
echo "[boot.scr] >>> booting slot ${slotname}: ${slotfile}, root=${rootdev}"
fatload virtio 0:1 ${fitaddr} ${slotfile}
setenv bootargs "console=ttyS0 earlycon root=${rootdev} rw rootwait"
bootm ${fitaddr}

# 走到这里说明 bootm 失败（FIT 校验失败/镜像损坏）-> 尝试另一个槽
echo "[boot.scr] !!! bootm failed for slot ${slotname} (bad FIT/hash); trying other slot"
if test "${slot}" = "b"; then
  setenv slotfile slot_a.itb
  setenv rootdev /dev/vda2
  setenv slotname A
else
  setenv slotfile slot_b.itb
  setenv rootdev /dev/vda3
  setenv slotname B
fi
fatload virtio 0:1 ${fitaddr} ${slotfile}
setenv bootargs "console=ttyS0 earlycon root=${rootdev} rw rootwait"
bootm ${fitaddr}
echo "[boot.scr] !!! both slots failed; hang"

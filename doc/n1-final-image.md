# N1 最终镜像流程（6.5GiB）

这份流程用于将 `QEMU 测试镜像` 产出为 `N1 可刷镜像`：

- 输出 `img`（逻辑 6.5GiB）
- 输出 `img.gz`
- 输出 `sha256`

## 1. 为什么要做这一步

QEMU 测试镜像为了验证服务通常会扩得很大（例如 200GiB），但 N1 实机容量有限：

- `mmcblk1` 约 7.28GiB
- `sda` 约 28.83GiB

所以发布给 N1 的最终镜像必须单独缩容。

## 2. 脚本入口

脚本：`scripts/pack/finalize_n1_image.sh`

### 依赖

目标机器（例如 `10.0.0.199`）需要：

- `parted`
- `losetup`
- `mount` / `umount`
- `btrfs`
- `qemu-img`
- `gzip`
- `sha256sum`

## 3. 手工执行示例（推荐先在 199 跑通）

```bash
bash scripts/pack/finalize_n1_image.sh \
  --source-img /root/ImmortalWrt_amlogic_s905d_k6.6.122_2026.03.02_btf.img \
  --output-prefix /root/ImmortalWrt_amlogic_s905d_k6.6.122_2026.03.02_n1_6.5g_btf \
  --target-size-gib 6.5 \
  --btrfs-size-mib 5500 \
  --stop-qemu \
  --qemu-pidfile /root/imwrt-qemu.pid \
  --qemu-pattern 'qemu-system-aarch64.*ImmortalWrt_amlogic_s905d_k6.6.122_2026.03.02_btf.img' \
  --qemu-start-script /root/start_imwrt_btf_qemu.sh
```

完成后会得到：

- `/root/ImmortalWrt_amlogic_s905d_k6.6.122_2026.03.02_n1_6.5g_btf.img`
- `/root/ImmortalWrt_amlogic_s905d_k6.6.122_2026.03.02_n1_6.5g_btf.img.gz`
- `/root/ImmortalWrt_amlogic_s905d_k6.6.122_2026.03.02_n1_6.5g_btf.sha256`

## 4. GitHub Actions 入口

工作流：`.github/workflows/N1-Final-Image.yml`

触发方式：`workflow_dispatch`

说明：

- 该任务默认 `runs-on: [self-hosted, Linux]`
- 建议把 runner 挂在 `10.0.0.199`
- 输入参数可覆盖源镜像、目标大小和 QEMU 启停参数

## 5. 产物校验

```bash
shasum -a 256 -c ImmortalWrt_amlogic_s905d_k6.6.122_2026.03.02_n1_6.5g_btf.local.sha256
```

如果 `sha256` 文件里是绝对路径，可先改成相对路径再校验。

## 6. 刷机后扩容（当目标盘大于 6.5GiB）

示例（安装到 28.8GiB 的 `/dev/sda` 后）：

```bash
parted /dev/sda resizepart 2 100%
btrfs filesystem resize max /
```

这样可以把 root 分区扩满整盘。

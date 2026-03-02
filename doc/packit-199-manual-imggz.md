# 在 10.0.0.199 手动打包 `img.gz`（`rootfs.tar.gz + kernel.bin`）

本文记录在 `10.0.0.199` 上，将 OpenWrt 编译产物：

- `immortalwrt-armsr-armv8-generic-rootfs.tar.gz`
- `immortalwrt-armsr-armv8-generic-kernel.bin`

打包为最终升级文件 `*.img.gz` 的完整流程。

## 1. 目录约定

- OpenWrt 编译目录：`/root/build_openwrt_from_local/work/openwrt`
- packit 目录：`/root/packit_tmp/amlogic-s9xxx-openwrt`
- 目标产物目录：`/root/packit_tmp/amlogic-s9xxx-openwrt/openwrt/out`

## 2. 前置依赖

先安装 packit 依赖清单，再补齐常见缺失工具：

```bash
apt-get update -y
apt-get install -y $(cat /root/packit_tmp/amlogic-s9xxx-openwrt/make-openwrt/scripts/ubuntu2404-make-openwrt-depends)
apt-get install -y parted dosfstools libarchive-tools p7zip-full zip
```

关键命令应存在：

```bash
command -v mkfs.vfat
command -v bsdtar
command -v 7z
command -v zip
```

## 3. 准备 packit 仓库

```bash
mkdir -p /root/packit_tmp
cd /root/packit_tmp
git clone --depth=1 https://github.com/ffuqiangg/amlogic-s9xxx-openwrt.git
```

## 4. 执行打包（核心）

清理残留 loop 设备后，执行 `remake`：

```bash
losetup -D || true
cd /root/packit_tmp/amlogic-s9xxx-openwrt
./remake \
  -b s905d \
  -r ffuqiangg/kernel_6.6.y \
  -u stable \
  -k 6.6.122 \
  -a false \
  -p 192.168.1.99 \
  -s 820 \
  -d $(date +%Y.%m.%d)
```

说明：

- 输入是 `rootfs.tar.gz + kernel.bin`。
- 输出是最终可分发的 `*.img.gz`。

## 5. 校验产物

```bash
ls -lh /root/packit_tmp/amlogic-s9xxx-openwrt/openwrt/out
sha256sum /root/packit_tmp/amlogic-s9xxx-openwrt/openwrt/out/*.img.gz
```

## 6. 回传到本地

在本地主机执行：

```bash
mkdir -p /Users/csfei/Downloads/build_openwrt/artifacts_remote
scp root@10.0.0.199:/root/packit_tmp/amlogic-s9xxx-openwrt/openwrt/out/*.img.gz \
  /Users/csfei/Downloads/build_openwrt/artifacts_remote/
```

## 7. 常见报错与修复

### 7.1 `[💔] [ 11 ] attempts to mount failed.`

常见根因：`mkfs.vfat` 不存在，导致 FAT 分区未格式化，后续 `mount -t vfat` 失败。

修复：

```bash
apt-get install -y dosfstools
```

### 7.2 `bsdtar` 缺失导致解包失败

修复：

```bash
apt-get install -y libarchive-tools
```

### 7.3 仍有历史残留导致失败

修复建议：

```bash
losetup -D
```

然后重新执行 `remake`。

# `openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz` 来源与 sda2 扩容核对

## 结论

- **这是 OpenWrt 官方发布的 25.12.5 x86/64 镜像**，不是第三方固件的命名。官方目录列出了完全相同的文件名，SHA-256 为 `23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461`。25.12.5 官方发布日期为 2026-06-29。
- **支持扩容第 2 分区中的 ext4 rootfs**。官方 x86 文档明确说 ext4 combined 镜像的可读写 ext4 根分区可扩展到占满大容量磁盘；典型 SATA/SCSI 命名下它就是 `/dev/sda2`。
- **不是刷入后默认自动扩容**。官方镜像默认只创建固定大小的第 2 分区，剩余磁盘空间未分配。用户要么手动扩展“分区 + ext4 文件系统”，要么安装官方 Wiki 提供的 `expand-root.sh`。该脚本安装并首次触发后，会分两阶段扩容、重启两次，并可保留到后续固件升级后自动再执行。
- **25.12 及之后包管理器是 `apk`**，官方步骤为先安装 `parted losetup resize2fs blkid`，不要照搬旧版 `opkg` 命令。

## 命名与分区含义

- `x86-64`：x86_64 目标。
- `generic`：通用 x86 机型。
- `ext4`：第 2 分区是可读写 ext4 rootfs，可用 `resize2fs` 扩展。
- `combined`：整盘镜像，包含引导分区、rootfs 分区和分区表；会覆盖目标盘原有分区表。
- 文件名没有 `-efi`：这是 **Legacy BIOS/GRUB** 引导版，不是 UEFI 版。

OpenWrt 当前 x86 文档仍以 `/dev/sda1` 作为引导分区、`/dev/sda2` 作为 rootfs 分区的典型布局。但实际设备名可能是 `/dev/vda2`、`/dev/mmcblk0p2` 等，不应未核对就硬写 `/dev/sda2`。

## 官方扩容方式

### 手动方式（确认根盘真是 `/dev/sda` 时）

1. `apk update && apk add parted losetup resize2fs blkid`
2. 用 `parted -l -s` 确认根盘和第 2 分区。
3. `parted -f -s /dev/sda resizepart 2 100%`
4. 重启。
5. `losetup /dev/loop0 /dev/sda2 2>/dev/null`
6. `resize2fs -f /dev/loop0`
7. 再重启并用 `df -h` / `lsblk` 核对。

官方文档说 ext4 可在 OpenWrt 运行中扩容，但也明确表示离线扩容可降低文件系统损坏概率。

### 官方 Wiki 的自动化脚本

官方 `expand_root` 页面提供 `expand-root.sh`，能自动识别根分区/文件系统，用未分配空间扩展分区，再扩展 ext4；25.12+ 需先用 `apk` 安装上述四个包。这里的“自动”是指**用户安装/触发脚本之后**的自动识别、重启和后续 sysupgrade 自动重跑，不代表 25.12.5 原始镜像自带首启扩容。

## 条件与风险

1. **必须先有连续的未分配空间**：实体磁盘通常是镜像尾部自带空间；虚拟机则要先扩大底层虚拟磁盘/镜像，再扩分区。
2. **分区扩大不等于文件系统扩大**：要先扩第 2 分区，重启让内核读到新分区表，再用 `resize2fs` 扩 ext4；只做其中一步不会得到可用容量。
3. **NVMe 当前明确禁用该官方脚本/指引**：官方 Wiki 警告，已知 NVMe 问题可导致首次重启后系统无法登录，实际上可将安装“变砖”。
4. **不要误操作磁盘**：先核对 `parted -l -s`、`lsblk`和实际 root 映射；虚拟机很可能是 `vda`，而非 `sda`。
5. **先备份，避免断电**：修改分区表和在线改 ext4 都有损坏风险；重要配置应先导出。
6. **升级方式很关键**：官方 x86 文档警告，如果将 `combined.img.gz` 再次整盘写入，会重写分区表，将 rootfs 退回镜像默认尺寸，还会删掉自建的额外分区。官方扩容脚本的 uci-defaults 会写入 `/etc/sysupgrade.conf`，用于在正常固件升级后再扩容；但整盘 `dd` combined 镜像不是同一件事。
7. **ext4 镜像的取舍**：因为 rootfs 可读写，官方文档指出它没有依赖只读 squashfs 的 Failsafe Mode / Factory Reset 能力。

## 证据与来源

1. OpenWrt 官方 25.12.5 x86/64 发布目录：文件名、大小、SHA-256  
   https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/
2. OpenWrt 官方下载首页：25.12.5 的稳定版身份与发布日期  
   https://downloads.openwrt.org/
3. OpenWrt 官方 x86 安装文档：镜像类型、分区布局、手动扩容、升级/重写 combined 镜像风险  
   https://openwrt.org/docs/guide-user/installation/openwrt_x86
4. OpenWrt 官方扩容文档：自动化脚本、25.12+ 的 `apk` 命令、重启流程、sysupgrade 保留、NVMe 警告  
   https://openwrt.org/docs/guide-user/advanced/expand_root
5. OpenWrt 官方 x86 镜像构建定义：combined 镜像由引导分区和指定大小的 rootfs 分区组合生成  
   https://github.com/openwrt/openwrt/blob/main/target/linux/x86/image/Makefile

## 一句话答复

**支持。** `openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz` 是官方 BIOS 版 x86/64 ext4 整盘镜像，其第 2 根分区可扩容；但原始镜像不会首启自动扩满，25.12.5 需用 `apk` 安装扩容工具后手动或运行官方脚本，而且官方目前明确警告不要在 NVMe 设备上照此执行。

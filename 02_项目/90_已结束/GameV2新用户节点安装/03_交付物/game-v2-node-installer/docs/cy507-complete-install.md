# cy507 Game V2 完整安装与恢复手册

## 1. 当前结论与用途

现网 `50.7/cy507` 已完成并收口，已有业务验收证据：Xbox NAT 为开放、实际联机正常、Xbox DNS 正常。

本手册对应 `1.3.0` 双端安装包，用于以后在已清理且确认无旧对象的目标上全新安装，或在灾难恢复时重建。它不会接管当前现网，也不能直接覆盖升级现存 cy507。脚本发现现存接口、服务、配置、端口或 nftables 表后会停止，需先人工判断现场和恢复路径。

## 2. 固定范围

| 对象 | 固定值 |
| --- | --- |
| 用户 | `cy507` |
| 荷兰 VPS | `91.223.119.134`，WAN `ens3` |
| OpenWrt | `192.168.50.7`，x86_64 |
| Xbox | `192.168.50.126`，游戏端口 UDP `3074` |
| WireGuard | VPS UDP `51872`，`10.77.2.1/30` ↔ `10.77.2.2/30` |
| FakeTCP | VPS TCP `40972`，OpenWrt 本地 `31972` |
| speederv2 | VPS UDP `40972`，OpenWrt 本地 `30972` |
| 公网固定端口 | UDP `23074` → Xbox UDP `3074` |
| 策略路由 | 表 `51872`，来源 `192.168.50.0/24` |
| DNS | Xbox 53/TCP+UDP → `10.77.2.1:53` |

参数真源是 `config/fleet/cy507.conf`，两份入口脚本对关键常量做固定校验。

## 3. 所有权和硬门禁

VPS 的唯一全表恢复入口是 `netfilter-persistent.service`。`iptables.service`、`ip6tables.service`、`nftables.service` 必须保持 `masked/inactive`。本包只创建并周期恢复自己的 `ip game_v2_cy507_fixed_nat` 表，不修改 `/etc/iptables/rules.v4`，不执行全局 flush，也不重启全表恢复服务。

以下对象绝对不属于本次范围：国内直播跨境推流系统、容器 `domestic-live-relay-mediamtx`、接口 `wg-data` 与 `wg-data-direct`、端口 `1935/8554/8890/9998` 及其路由和规则。VPS 入口不会引用或修改这些对象。

旧 `unbound.service` 即使失败也保持原状。cy507 DNS 使用 `/etc/unbound/unbound-cy507.conf`、`/var/lib/unbound/cy507` 和 `unbound-cy507.service`。

## 4. 安装前准备

在目标机外准备并人工核验：

- 本版本发布包；
- VPS x86_64 的 `speederv2` 和 `udp2raw` 可执行文件；
- VPS 已安装 WireGuard、nftables、unbound、systemd、OpenSSL 和 `flock`；
- OpenWrt 25.12 x86_64 已具备 WireGuard、nftables/fw4、UCI、`nslookup`、`setsid`；
- VPS 现有权威防火墙已允许 TCP `40972` 和 UDP `51872`；
- 安装期间没有并行修改 OpenWrt 的 `/etc/config/network` 与 `/etc/config/firewall`。

安装器不会通过 apt/apk 安装依赖，避免包安装脚本改动防火墙或启动无关服务。

## 5. 人工检查

执行前检查这三份文件：

```sh
less scripts/game-v2-cy507-vps.sh
less bundles/cy507-openwrt/install.sh
less docs/cy507-complete-install.md
```

重点核对：固定 IP 和端口、只出现 cy507 所有权对象、VPS 回滚为 systemd 本地定时任务、OpenWrt 回滚脱离 SSH 会话运行、没有全局 flush/save/restore、没有受保护直播对象。

先只读执行 VPS 预检：

```sh
sudo sh scripts/game-v2-cy507-vps.sh preflight \
  /secure/bin/speederv2 \
  /secure/bin/udp2raw
```

预检通过只代表目标与前置条件匹配，不代表取得生产施工授权。

## 6. VPS 施工

取得本次明确授权后执行一份 VPS 脚本：

```sh
sudo sh scripts/game-v2-cy507-vps.sh install \
  /secure/bin/speederv2 \
  /secure/bin/udp2raw \
  bundles/cy507-openwrt/install.sh
```

脚本依次完成：

1. 再次核对全新目标、依赖、防火墙恢复控制面和端口占用。
2. 把本次范围、监听与路由基线写入 `/var/backups/game-v2-cy507/<事务>/`。
3. 先安排服务器本地 15 分钟自动回滚。
4. 创建 cy507 WireGuard、FakeTCP、speederv2、固定端口 NAT、独立 unbound 与最小 reconcile。
5. 完成 VPS 定向验证；失败立即运行回滚。
6. 在 `/var/lib/game-v2-cy507/package/` 生成含专属秘密的 OpenWrt 包。

成功后回滚仍然生效。立刻从一个新的 SSH 会话执行：

```sh
sudo sh scripts/game-v2-cy507-vps.sh status
sudo sh scripts/game-v2-cy507-vps.sh verify
```

此时先不要执行 VPS `commit`，需要在回滚期限内完成 OpenWrt 和端到端验收。

## 7. OpenWrt 施工

通过可信通道把完整 `/var/lib/game-v2-cy507/package/` 复制到 `192.168.50.7`。其中 `enrollment.env` 含客户端私钥和共享密钥，权限必须保持严格，不得提交到源码或粘贴到聊天。

在 OpenWrt 包目录先预检：

```sh
./install.sh preflight
```

取得本次 OpenWrt 写入授权后执行：

```sh
./install.sh apply
```

脚本先备份 `/etc/config/network` 与 `/etc/config/firewall`，再启动脱离 SSH 的 15 分钟本地回滚，然后创建：

- `gv2_cy507` WireGuard；
- udp2raw FakeTCP 客户端与本地 speederv2；
- 表 `51872` 和两条固定策略规则；
- 仅 Xbox 的 DNS DNAT、无本地 SNAT和入站 UDP 3074 规则；
- 两个 procd 服务及开机启用状态。

从新的 OpenWrt 管理会话执行：

```sh
./install.sh status
./install.sh verify
```

## 8. 端到端验收与提交

在两个回滚期限内逐项确认：

- 新 SSH/管理连接正常；
- VPS 和 OpenWrt 的 cy507 服务均 active；
- `gv2_cy507` 有近期 WireGuard 握手；
- OpenWrt 到 `10.77.2.1:53` 的 DNS 探针成功；
- Xbox 重新进行网络测试后 DNS 正常；
- Xbox NAT 为开放；
- 实际联机正常。

全部通过后，先取消 OpenWrt 回滚，再取消 VPS 回滚：

```sh
# OpenWrt
./install.sh commit

# VPS
sudo sh scripts/game-v2-cy507-vps.sh commit
```

`commit` 会再次运行定向技术验证。没有 Xbox 人工结果时只能记录“技术施工完成，业务未确认”。

## 9. 失败与回滚

施工命令或内置验证失败时，脚本会立即恢复本次创建的对象。SSH 中断、未及时验收或没有提交时，目标机本地定时任务会在 15 分钟后恢复。

仍可连接且需要提前恢复时执行：

```sh
# OpenWrt
./install.sh rollback

# VPS
sudo sh scripts/game-v2-cy507-vps.sh rollback
```

OpenWrt 回滚恢复施工前的两个 UCI 配置文件并 reload 网络和防火墙。VPS 回滚只删除本次新建的 cy507 对象；它不会恢复或刷新全局防火墙，不会处理其他服务。

回滚后验证管理连接、原网络和受影响业务。不要通过 flush、重启 VPS、重启 Docker 或重启全局网络服务进行试错。

## 10. 重启后的恢复机制

- WireGuard、FakeTCP、speederv2 和专用 DNS 由各自 systemd unit 恢复。
- `game-v2-cy507-reconcile.timer` 在 `netfilter-persistent.service` 之后运行，只恢复 cy507 NAT 表、Xbox 主机路由和该 peer 的 AllowedIPs。
- OpenWrt 的两个 procd 服务按 `START=90/91` 启动，并由 fw4 从固定片段加载 NAT/DNS 规则。
- 全局 VPS 防火墙仍由 `netfilter-persistent.service` 唯一管理。

这样，cy507 运行对象有明确唯一入口，同时保留 VPS 全表安全控制面和直播系统的独立所有权。

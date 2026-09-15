# Game V2 cy507 双端安装包

当前版本：`1.3.0`。

本包把 cy507 已验收的完整线路收敛为一个双端交付物：VPS 入口负责 WireGuard、FakeTCP、固定端口 NAT、专用 DNS 和客户端包生成；生成的 OpenWrt 包负责本地 WireGuard、FakeTCP、策略路由、Xbox NAT 与 DNS 劫持。

现网 `50.7/cy507` 已完成并收口：Xbox NAT 开放、联机正常、Xbox DNS 正常。`1.3.0` 用于以后全新安装或灾难重建，**不是现网迁移或修补脚本**；检测到任何现存 cy507 对象时会拒绝执行。

完整步骤和验收标准见 [cy507 完整安装与恢复手册](docs/cy507-complete-install.md)。

## 默认入口

```text
scripts/game-v2-cy507-vps.sh       VPS 唯一入口
bundles/cy507-openwrt/install.sh   随 VPS 生成包下发的 OpenWrt 唯一入口
config/fleet/cy507.conf            cy507 非秘密参数真源
docs/cy507-complete-install.md     安装、验证、提交和回滚手册
tests/test-cy507-v13.sh            1.3.0 定向离线门禁
```

仓库不保存 speederv2、udp2raw 正式二进制，也不保存 WireGuard 私钥或共享密钥。VPS 安装时传入两个已核验的 x86_64 二进制，脚本在目标机生成密钥和只属于 cy507 的 OpenWrt 安装包。

## 运行边界

- 范围固定为 `cy507`、VPS `91.223.119.134`、路由器 `192.168.50.7`、Xbox `192.168.50.126`。
- VPS 全表防火墙恢复入口仍是 `netfilter-persistent.service`；本包不保存或恢复全表。
- 本包只拥有 `ip game_v2_cy507_fixed_nat`、`gv2_cy507`、cy507 专用服务、文件和路由。
- 不执行全局 flush，不重启 `netfilter-persistent`、Docker、其他 WireGuard 或直播服务。
- 不处理旧 `unbound.service`；DNS 使用独立的 `unbound-cy507.service`。
- 国内直播跨境推流系统的容器、端口、接口、路由和规则不在本包所有权内。
- 不扩展 `yhz187`、`zj717`、`jzg37` 或其他用户。

`config/fleet/` 保留其他用户的非秘密参数记录，供未来独立任务查阅；这些记录不会进入 1.3.0 发布包，也不会被 cy507 安装入口读取或执行。

## 安全流程

两个入口都执行同一套流程：限定范围并检查全新目标 → 备份 → 安排目标机本地 15 分钟回滚 → 写入 → 定向验证 → 等待从新会话和 Xbox 验收 → `commit` 取消回滚。执行或验证失败会立即恢复。

安装前必须人工检查实际版本的两份脚本和手册。任何实质修改都应先重新检查受影响部分；不使用哈希冻结或循环重审。

## 离线验证与发布

```sh
sh tests/run.sh
sh scripts/build-release.sh /secure/release
```

发布时生成的 SHA-256 仅用于传输完整性校验，不是施工准入冻结。

# zj717 受控迁移手册

状态：zj717 基础迁移、既有页面切换、`1.5.3` 状态修复、`1.5.4` 纯前端整页重装及 `1.5.5` 状态延迟修正事务均已提交；`1.5.5` 设备内及 Nebula HTTP 技术验证通过，用户于 2026-09-16 确认页面目前表现良好。Xbox NAT、DNS 和实际联机的人工业务验收待确认。

## 目标与范围

- 荷兰 VPS：`91.223.119.134`，保留已经在线的 `gv2_zj717` WireGuard 与 UDPspeeder 基座。
- 赵杰 OpenWrt：LAN `192.168.7.17`，优先从 Nebula `192.168.66.30` 管理。
- Xbox：`192.168.7.108`，本地 UDP `3074`，公网唯一 UDP `23075`。
- 交付能力：FakeTCP、全 LAN 源路由、Xbox 固定端口 NAT、Xbox 专属荷兰 DNS。

VPS 采用增量叠加，因为现有 zj717 基座、密钥和端口归属正常。OpenWrt 定向替换旧赵杰线路，因为旧客户端仍使用 `wg_zj/10.10.17.2`，与现有 VPS `gv2_zj717/10.77.3.0/30` 不匹配且握手陈旧。候选不会重建健康的 VPS 基座。

## 唯一脚本

```sh
scripts/game-v2-zj717-migrate.sh inspect
scripts/game-v2-zj717-migrate.sh apply
scripts/game-v2-zj717-migrate.sh repair-panel
scripts/game-v2-zj717-migrate.sh repair-status-latency
scripts/game-v2-zj717-migrate.sh verify
scripts/game-v2-zj717-migrate.sh status
scripts/game-v2-zj717-migrate.sh commit
scripts/game-v2-zj717-migrate.sh rollback
```

脚本在上传前固定两端 ED25519 指纹，并在远端再次核对地址、接口、平台、旧对象和受保护业务。Nebula 不可达时才尝试 `192.168.7.17`，仍要求同一主机指纹和双地址身份同时成立。

## 写入边界

VPS 只允许写入：

- zj717 自有 FakeTCP unit、独立 `unbound-zj717.service` 和运行目录；
- `ip game_v2_zj717_fixed_nat`、`GAME_V2_ZJ717_INPUT`、`GAME_V2_ZJ717_FORWARD`；
- zj717 主机路由、WireGuard peer 的 `192.168.7.108/32` AllowedIPs；
- 全局 Game reconcile 服务的单个 zj717 `ExecStartPost` drop-in。

OpenWrt 只允许删除已确认的赵杰旧 UCI/service/nft 对象，并写入新的 `gv2_zj717`、两个 zj717 init 服务、策略表 `51873` 和三个 zj717 nft 片段。

脚本不会 flush、save 或 restore 全局防火墙，不重启 VPS、Docker、WireGuard 基础服务、`netfilter-persistent`、直播容器或直播 WireGuard；不处理失败的全局 `unbound.service`，也不执行旧 p3。国内直播跨境推流系统相关端口、服务、容器、路由和防火墙规则均为硬排除项。

## 施工和回滚

`apply` 的固定顺序为：双端只读门禁 → 双端对象级备份 → 双端各自挂 30 分钟本地回滚 → 上传同一脚本 → VPS 叠加 → 加密材料直接转交 OpenWrt → OpenWrt 定向替换 → 双端技术验证。

备份目录按事务生成：

- VPS：`/var/backups/game-v2-zj717-migrate/<transaction>`
- OpenWrt：`/root/game-v2-zj717-backups/<transaction>`

任一步失败会立即请求双端恢复；控制端断线或未及时验收时，两端本地定时任务独立恢复。回滚只移除本候选新增对象，并恢复 OpenWrt 施工前的赵杰旧配置。候选使用 enabled marker 和互斥锁阻止每分钟 reconcile 在回滚后重新写回。

OpenWrt 回滚会恢复施工前完整的 `/etc/config/network` 和 `/etc/config/firewall`。从 `apply` 开始到 `commit` 或 `rollback` 完成之间必须保持独占变更窗口，不得同时修改这两个文件，否则回滚会恢复备份版本并覆盖并发修改。

## 验收与提交

技术验证通过后，两个回滚仍保持计时。此时在 Xbox 上逐项确认：

1. NAT 类型显示“开放”，不再显示双重 NAT。
2. DNS 正常，可以登录并解析在线服务。
3. 实际联机正常。

三项均通过后才运行 `commit`；它会再次执行双端技术验证，然后取消两个回滚并删除短期客户端密钥包。任一业务项失败或结果不确定，运行 `rollback`，并在恢复后重新执行 `inspect`。不要在同一事务上原样重试。

提交顺序固定为 VPS 后 OpenWrt，因为新 OpenWrt 数据面依赖 VPS 叠加层。提交进程取得端点锁后会重新核对事务身份，先写入提交状态，再取消该端定时回滚。若 VPS 已提交而 OpenWrt 提交结果不确定，应立即运行 `status`：OpenWrt 仍为 `pending` 时可在截止前重跑 `commit`；若 OpenWrt 已自动恢复，则旧线路继续在线，VPS 仅留下不承载客户端流量的 zj717 叠加对象，后续应单独决定继续迁移或清理，不能盲目重跑 `apply`。

## 2026-09-16 生产结果

- 事务：`zj717-20260915T234215Z-86178`。
- 备份：VPS `/var/backups/game-v2-zj717-migrate/zj717-20260915T234215Z-86178`；OpenWrt `/root/game-v2-zj717-backups/zj717-20260915T234215Z-86178`。
- `apply` 完成双端写入及即时验证；随后独立 `verify` 再次通过。VPS 的全局 Game V2 防火墙 reconcile 在安装后真实触发，触发后 zj717 规则仍在，证明新对象已纳入恢复控制面。
- `commit` 依次完成 VPS 和 OpenWrt 提交并取消两端自动回滚；提交后的 `status` 显示两端均为 `COMMITTED`，最终 `verify` 再次通过。
- 收口时 Xbox 邻居记录存在，但 DNS、固定 SNAT/DNAT 和入站放行规则计数均为 0；因此技术施工已完成，Xbox NAT 开放、DNS 正常和实际联机仍为“业务未确认”，计数为 0 不能算通过。
- 受保护的国内直播跨境推流系统端口、服务、容器、路由和防火墙规则未纳入写入；脚本在每次 VPS 验证时检查其容器启动时间、监听和两条 WireGuard。

## 2026-09-16 控制页面修复

- 最终页面修复事务：`zj717-panel-20260916T070230Z-25107`。
- 本次对象级备份：VPS `/var/backups/game-v2-zj717-panel/zj717-panel-20260916T070230Z-25107`；OpenWrt `/root/game-v2-zj717-panel-backups/zj717-panel-20260916T070230Z-25107`。初次页面替换备份 `zj717-panel-20260916T061543Z-12140` 继续保留。
- OpenWrt 的 `/www/wgpanel.html` 采用 cy507 页面结构；后端只使用 zj717 自有 profile、节点名、端口和受限 FEC 配对入口，不复制 cy507 身份、密钥或运行参数。
- `1.5.1` 将前端动作超时调整为 120 秒，并修正控制锁所有权、异常请求遗留锁及定时回滚争锁；脚本以故意制造的空锁和 8 秒确认期限证明 watchdog 能恢复原档。`1.5.2` 在动作进行期间暂停后台状态轮询，并忽略静默刷新与控制锁并发产生的瞬时 HTTP 409，避免成功切换被页面误报为失败。
- 脚本级 QA 已完成 `light → confirm → original → confirm`，并验证双端档位一致；浏览器随后真实完成 `original → light → 保留 → original → 保留`。本轮页面日志没有 HTTP 409、请求超时或应用失败。
- 后续复核发现，原状态钩子没有执行公网探测并始终返回空 `WG_LATENCY_MS`，页面因此把健康线路误报为“目标未响应”；此前将该提示解释为正常现象的结论失效。只读实测确认 `gv2_zj717` 承载 `1.1.1.1` 路由，绑定该接口的真实探测 3/3 成功、平均约 191.2 ms，隧道 DNS 查询成功；当前只读档位为 `WG_FEC_MODE=extreme`、`WG_FEC_EFFECTIVE=extreme`，事务已确认。
- 双端 30 分钟本地回滚在写入前挂载；脚本与浏览器 QA 通过后均已取消。页面修复结果为 `ZJ717_PANEL_REPAIR_PASS`。
- `1.5.3` 状态修复事务 `zj717-panel-status-20260916T080734Z-45970` 已执行并提交；页面状态接口可返回真实网络可达性和延迟，当前档位保持 `extreme`。
- `1.5.4` 纯前端整页重装事务 `zj717-panel-page-20260916T082249Z-50903` 已执行并提交，施工对象只有 OpenWrt `/www/wgpanel.html`。页面直接沿用当前 cy507 生产版本，只在前端把 `nl-zhaojie-v2` 的节点列表和当前状态标签显示为“荷兰”；profile、label、CGI、controller、status hook、服务和 VPS 均未修改。生产脚本验证 `fec=extreme`、`network=reachable`、`backend=unchanged`；真实浏览器首次显示“荷兰 / 极限 / 目标已响应 / 147 ms”，点击刷新后前端再次调用成功并更新为 `1113 ms`。15 分钟 OpenWrt 本机回滚已取消；旧页备份保留于 `/root/game-v2-zj717-panel-page-backups/zj717-panel-page-20260916T082249Z-50903`。
- 后续截图出现“读取失败”，因此“1.5.4 页面状态稳定”的完成判断失效；这不改变前端文件确实来自 cy507 且后端未被该事务修改的事实。只读计时确认现用 FEC 协调器的例行 `status` 串行执行两次 VPS SSH：先 `read_remote`，再由 `pair_verify` 执行 `remote verify`。单次远程调用约 `2.15–2.31s`，完整状态接口曾耗时 `7.299s`，逼近页面固定的 `8s` 超时。
- `1.5.5` 候选新增 `repair-status-latency`：只备份并原子替换 OpenWrt `/usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh`，将例行状态读取收敛为一次远程档位读取、双端档位一致性检查和本地 endpoint 健康检查；切换动作和显式 `verify/verify-transport` 仍保留双端验证。页面、状态钩子、两个 CGI、profile、当前 FEC、服务及 VPS 均设为不可变校验对象。脚本在写入前挂 15 分钟 OpenWrt 本机回滚；状态钩子和本机 HTTP 状态接口，以及控制端沿页面使用的 `192.168.66.30` 地址读取页面、状态和节点接口，任一失败或状态接口耗时达到 7 秒即恢复旧协调器，全部通过后才取消回滚。生产事务 `zj717-panel-status-latency-20260916T091133Z-64179` 已执行；设备内状态钩子 2 秒、HTTP 状态接口 3 秒，沿 `192.168.66.30` 外部读取页面、状态和节点接口通过，FEC 保持 `extreme`；15 分钟回滚已取消。备份：`/root/game-v2-zj717-panel-status-latency-backups/zj717-panel-status-latency-20260916T091133Z-64179`。用户于 2026-09-16 确认页面目前表现良好，页面问题据此收口。

## 已完成的候选检查

- `sh -n scripts/game-v2-zj717-migrate.sh`：通过。
- 帮助与动作分发：通过。
- 范围静态检查：只有 zj717 自有链/table 的定向删除或清空，无全局 flush/save/restore，无受保护服务重启。
- 2026-09-16 双端 `inspect`：通过；VPS 通用 zj717 服务 active/active、`netfilter-persistent` active、叠加对象 absent；OpenWrt 旧服务 running、旧接口 `10.10.17.2/32`、新对象 absent。
- 首轮 `apply` 事务 `zj717-20260915T222734Z-68906`：VPS 完成备份并挂回滚后，OpenWrt 在备份前置检查发现缺少 `ss`，立即停止；OpenWrt 没有待回滚事务，VPS 已回滚。随后只读复核确认 VPS 叠加对象 absent、旧 OpenWrt 服务 running、新对象 absent。
- 同一候选将 OpenWrt 两处端口占用检查改为设备现有的 BusyBox `netstat`；施工范围、参数和运行配置未变化。
- `verify/status/commit/rollback` 通过标准输入执行本地唯一候选，不依赖回滚后可能已不存在的远端 `/tmp` 控制脚本。
- 第二次 `apply` 事务 `zj717-20260915T223603Z-71012`：双端完成备份并挂回滚；VPS 在启动 `unbound-zj717.service` 时停止，OpenWrt 尚未进入新配置写入。脚本随后完成双端恢复，只读复核确认 VPS 叠加对象 absent、OpenWrt 旧服务 running、新对象 absent，且两端均无待回滚事务。
- 失败日志证明 `unbound-checkconf` 无法穿越 `unbound:unbound 0700` 的专用状态目录；该启动前检查以 root 身份运行，但服务能力边界不含 `CAP_DAC_OVERRIDE`。候选保持能力边界不变，仅对齐现有 `/var/lib/unbound` 与公开 `root.key` 的 `0755/0644` 权限。
- 第三次 `apply` 事务 `zj717-20260915T224401Z-72754`：专用 Unbound 配置检查和服务启动均通过，随后在 VPS `AllowedIPs` 校验处停止并完成双端恢复；只读复核确认旧 OpenWrt 线路仍在运行、VPS 叠加对象与新 OpenWrt 对象均不存在、两端无待回滚事务。
- 现网脱敏核对确认 `wg show ... allowed-ips` 的多地址输出是“peer＋每个地址各占一个空白分隔字段”。旧校验只取 `$2`，会漏掉第二条 Xbox 地址；候选现在读取完整字段并要求只包含客户端和 Xbox 两条 `/32`，不改变任何运行配置。
- `1.4.4` 自审关闭了回滚与提交竞争：两端都在共享锁内认领事务，拿锁后重新核对同一事务；OpenWrt 先写 PID 候选文件，再用同目录硬链接原子取得锁，避免进程在“建锁目录、写 PID”之间退出而阻断定时回滚；提交状态落盘后才取消定时器，手工回滚恢复并验收成功后才取消定时器。恢复失败时自动回滚仍可继续接管。
- `1.4.4` 首次生产执行在 OpenWrt TCP DNS 探针停止；两端均报告回滚成功，随后 `status + inspect` 确认旧线路运行、新对象 absent、无待回滚事务。目标 BusyBox `nc` 仅支持 `nc IP PORT`，不支持候选使用的 `-w 5`。`1.4.5` 使用临时请求/响应文件和 `setsid` 管理无选项 `nc`，最多轮询 5 秒后主动结束探针；同一实现已在目标 OpenWrt 对公网 DNS 得到 63 字节 TCP 响应且无残留进程。
- VPS 回滚现在验证防火墙恢复控制面、受保护直播容器与监听、通用 zj717 WireGuard/UDPspeeder 基座、路由和叠加对象清理结果；OpenWrt 回滚精确比对备份的 network/firewall，并验证旧服务恢复、新对象消失后才清除事务状态。
- OpenWrt 策略规则在启动、停止和回滚时按自有优先级去重；FakeTCP 本地 `31973` 按真实 UDP 监听检查冲突。
- VPS 执行前新增只读基座门禁，确认通用 `gv2_zj717` 双向转发和 `10.77.3.2` 出口 masquerade 均存在；整段 LAN 流量由 OpenWrt 自有 masquerade 汇聚到 `10.77.3.2`，Xbox 则保留源地址并进入专用固定 NAT。
- 当前脚本以 `sh -n`、`bash -n` 通过；从同一候选实际生成的 VPS/OpenWrt 回滚脚本也均以 `sh -n` 通过。静态范围检查未发现全局防火墙 flush/save/restore、受保护服务重启或其他用户对象写入。

上述检查只证明候选内部控制逻辑和已知执行前基线匹配，不替代生产执行后的双端技术验证和 Xbox 人工验收。

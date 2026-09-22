# `lovewhowho.net` 证书自动续期与下发

## 真源关系

- 本目录是证书自动续期、下发、巡检和告警接入文件的工作区真源；变更应先在这里完成审查和定向验证，再部署到荷兰 VPS。
- `../../跨地域局域网运行手册.md` 的“`lovewhowho.net` 公网证书下发边界”是运行方式、覆盖边界和人工操作入口的说明真源。
- 荷兰 VPS 上的 `/root/.acme.sh/lovewhowho.net_ecc/` 是当前证书正文的生成位置，不是自动化脚本的编辑真源；证书正文、私钥、Cloudflare 凭据和日志中的敏感内容不得写回工作区。
- VPS 上的下列文件是本目录对应文件的运行副本。除紧急止损外，不直接在远端形成长期分叉；发生紧急修改后必须回填本目录、复验并更新运行手册。

## 文件与部署位置

| 工作区文件 | 荷兰 VPS 运行位置 | 用途 |
| --- | --- | --- |
| `deploy-lovewhowho-wildcard-cert.sh` | `/usr/local/bin/deploy-lovewhowho-wildcard-cert.sh` | 动态发现 OpenResty 实际证书路径，备份、原子下发、检查、平滑重载及失败回滚 |
| `check-lovewhowho-wildcard-cert.sh` | `/usr/local/bin/check-lovewhowho-wildcard-cert.sh` | 检查源证书、部署文件和线上 SNI；默认允许修复，`--check-only` 只读 |
| `deploy-line-cert.sh` | `/usr/local/bin/deploy-line-cert.sh` | 旧入口兼容委托，统一转交主下发脚本 |
| `extra_probe.py` | `/opt/ops-monitor/bin/extra_probe.py` | 运维监控附加探针执行器 |
| `extra_targets.json` | `/opt/ops-monitor/conf/extra_targets.json` | `lovewhowho_certificate` 证书探针定义 |
| `lovewhowho-cert-logrotate` | `/etc/logrotate.d/lovewhowho-cert` | ACME 与证书巡检日志轮转 |
| `install-cert-automation.sh` | 不常驻安装 | 2026-09-22 首次安装的受控施工脚本；包含当时旧文件哈希前置条件，不得作为后续通用安装器直接重跑 |

Root crontab 也属于运行配置，当前应包含：

```cron
40 6,18 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" >> /var/log/lovewhowho-acme.log 2>&1
50 6,18 * * * /usr/local/bin/check-lovewhowho-wildcard-cert.sh >> /var/log/lovewhowho-cert-check.log 2>&1
```

## 下发链路

```text
acme.sh 续签成功
  -> deploy hook 调用统一下发脚本
  -> 扫描当前生效的 OpenResty conf.d
  -> 解析所有实际 ssl_certificate / ssl_certificate_key 路径
  -> 校验 SAN、有效期及证书/私钥匹配
  -> 备份目标文件并原子替换
  -> OpenResty 配置检查与平滑重载
  -> 逐域检查线上 SNI 指纹
  -> 任一步失败则自动恢复本次备份

独立兜底巡检
  -> 比对 ACME 源证书、部署文件和线上 SNI
  -> 发现漂移时调用同一统一下发脚本修复
```

覆盖目标不维护静态域名清单：以下发时 OpenResty 当前生效配置中引用 `lovewhowho.net` 通配符证书的实际路径和域名为准。新增或删除站点时，无需再手工维护一份容易遗漏的路径表，但必须通过下述验收确认新目标已被发现。

## 变更与验收

1. 先修改本目录文件，运行最小定向检查：Shell 文件执行 `bash -n`，Python 文件执行语法检查，JSON 文件执行 `python3 -m json.tool`。
2. 部署前只读核对远端运行副本、crontab、OpenResty 配置和本次覆盖范围，并备份将修改的文件。
3. 把本目录对应文件部署到上表中的固定位置；修改 crontab 时同步核对两条任务，不得只更新其中一条。
4. 运行 `check-lovewhowho-wildcard-cert.sh --check-only`，必要时运行主下发脚本；随后核对 OpenResty 配置、所有发现域名的线上 SNI 指纹、证书链和主机名。
5. 对六个常驻运行文件比较工作区与 VPS 的 SHA-256。只有内容一致、检查通过且线上域名全部提供当前证书，才算完成。
6. 目标范围、运行路径或安全边界变化时，同步更新本文件、运行手册和 `PROJECT.md` 的证书真源记录。

仅 ACME cron 成功、仅 `panel` 域名正常、仅文件复制成功，或仅旧 SSH 会话仍存活，都不能算证书下发通过。

## 设备边界

- 公网域名当前均由荷兰 VPS 的 OpenResty 终止 TLS；NAS 等后端终端不接收该通配符证书。
- 资产清单中的 OpenWrt 使用设备自签名证书并通过 IP 管理，不是本链路的下发目标。不得向这些终端复制公网通配符私钥。
- 若以后改为终端直接终止公网 TLS，应先确定独立主机名和逐设备证书方案，再把新的部署位置、回滚与验收写入本真源，不能在远端临时加一条复制命令。

## 当前关闭证据

2026-09-22 的部署与外部验证结果：动态发现 `26` 个证书目标文件、`30` 个 TLS 域名；外部逐域证书链、主机名和指纹验证为 `30/30`。当时线上证书到期时间为 `2026-12-21 03:42:10 UTC`，本次证书文件备份位于荷兰 VPS `/var/backups/lovewhowho-cert/20260922T070658Z`，自动化配置备份位于 `/var/backups/lovewhowho-cert-automation/20260922T070657Z`。

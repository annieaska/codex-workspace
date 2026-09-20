# AGENTS、Skill 与 Token 规则整改记录

2026-09-05。状态：本批修改已写入正式文件并完成回读核验。范围为 2 份 AGENTS、8 个 Skill 和 5 个必要关联文件，共修改 15 个已有文件，另增加本记录。Memmy 留待后续。

## 已落实的行为

- 默认轻量高效，采用最小可靠方案和与真实风险匹配的验证。服务器、Docker、文件数量、普通依赖、原型和跨窗口不自动触发复杂流程。
- 只有证据表明轻量方式不足时，说明局限、升级收益、成本和推荐方法，由用户选择是否进入标准工程、大型项目或 Matt；继续不依赖该选择的已授权工作。
- Skill 按实际任务需要触发。清楚的局部修改直接执行；需求已确认时不重复访谈，不固定追加 SOP 问题，不自动串联完整工作流。
- 区分进度检查、质量检查与人工决策：汇报后继续；验证失败先定位并修复授权内问题；只有缺少实质决定或必要授权时等待。保留既有业务审批及安全门禁，同一范围的有效授权不重复索取。
- 执行计划取消固定批次暂停。完成开发时沿用用户已选交付方式，不固定展示四选一，也不把创建 PR 或合并视为删除工作树的授权。
- 设计微调继承已确认方向；只有方向确实未定或明确要求重新选型时进入比较。取消自动多 agent、装饰数量、固定复验轮数和无限等待；保留当前工作区明确要求重新选型时的四方向规则。

## Token 与上下文规则

- 先限定目录、对象、时间窗和结果数量，在执行端筛选、统计，再回传关键证据；相关 context-mode 工具不可用时使用精简脚本。
- 安装、构建、检测及 SSH 命令返回完成状态、退出码与相关摘要，失败后按需展开。日志末尾或截断输出不能证明没有错误；不反复回传全量远端日志。
- 等待和重试有截止条件，优先事件、退避和增量结果；无变化时不重复分析。未经请求不转成永久监控，超时不等于用户批准。
- 复用仍有效的读取和验证证据，只重跑被变化或新风险影响的部分。其他任务先取紧凑状态，编排层只输出所需字段。
- 默认单 agent，不按固定上下文百分比自动压缩、拆 agent 或换模型。保留目标、授权、已确认决定、活跃错误、精确标识、验证状态和下一动作。

这些是执行规则，不是运行时 Token 硬限额。本次没有配置计费监控、改变模型或测量实际节省比例；也没有验证所有已打开任务会自动重载新规则。

## 修改文件

| 对象 | 正式文件与本次修改 |
|---|---|
| 全局规则 | [AGENTS.md](/Users/chengyu/.codex/AGENTS.md)：需求审查、复杂度选择、授权延续和 Token 控制 |
| 工作区规则 | [AGENTS.md](/Users/chengyu/12_打工人程宇/AGENTS.md)：轻量路由、Matt 人工选择、阶段检查和交接冲突处理 |
| Superpowers 入口 | [using-superpowers](/Users/chengyu/.codex/superpowers/skills/using-superpowers/SKILL.md)：收窄触发，按需选用流程 |
| 需求探索 | [brainstorming](/Users/chengyu/.codex/superpowers/skills/brainstorming/SKILL.md)：只处理会改变结果的未决事项 |
| 计划执行 | [executing-plans](/Users/chengyu/.codex/superpowers/skills/executing-plans/SKILL.md)：取消固定批次暂停和失败即询问 |
| 开发收尾 | [finishing-a-development-branch](/Users/chengyu/.codex/superpowers/skills/finishing-a-development-branch/SKILL.md)：复用交付选择，明确清理授权范围 |
| 需求质询 | [grill-mode](/Users/chengyu/.codex/skills/grill-mode/SKILL.md) 与 [openai.yaml](/Users/chengyu/.codex/skills/grill-mode/agents/openai.yaml)：收窄触发，移除固定 SOP 问题；元数据只改默认提示 |
| 实施前核验 | [Confidence Check](/Users/chengyu/.codex/skills/confidence-check/SKILL.md)：按相关证据判断，不使用主观分数作为审批门禁 |
| 上下文优化 | [context-optimization](/Users/chengyu/.codex/skills/context-optimization/SKILL.md) 与 [optimization_techniques.md](/Users/chengyu/.codex/skills/context-optimization/references/optimization_techniques.md)：先缩小输入，取消固定阈值与未经测量的收益承诺 |
| 设计执行 | [qiaomu-design](/Users/chengyu/.codex/skills/qiaomu-design/SKILL.md)、[style-preview.md](/Users/chengyu/.codex/skills/qiaomu-design/references/style-preview.md)、[craft-loop.md](/Users/chengyu/.codex/skills/qiaomu-design/references/craft-loop.md)、[preflight.md](/Users/chengyu/.codex/skills/qiaomu-design/references/preflight.md)：区分诊断、继承方向和重新选型，相关引用同步消除冲突 |

4 个 Superpowers Skill 修改的是软链接指向的真实源文件，入口软链接保持原样。本批没有批量重写其他 Skill。

## 验证结果与边界

- 写入前核验 15 个正式文件仍与当前快照一致，保留工作区原有未提交修改；写入后 15 个文件的 SHA-256 与预期一致，权限未变。
- 30 份修改前后备份内容校验通过；4 个 Superpowers 入口仍指向预期源文件。
- 使用现有 Ruby Psych 解析器验证 8 个 Skill frontmatter 和 1 个元数据 YAML，并检查名称延续、描述限制、代码围栏及占位项。`context-optimization` 原有描述中的未引用冒号导致 YAML 错误，已随本次改写修复。
- 现有 Python 环境缺少 PyYAML，因此未运行官方 `quick_validate.py`，采用本地静态检查，未安装依赖。`Confidence Check` 原有名称含大写和空格，不符合该验证器的命名正则；本次保留现有身份，未重命名。
- 逐段比对确认：全局 Memmy 区块、工作区业务与交付规范、能力告知、上下文及 QA 路由保持原样；上下文引用中的记忆集成示例和设计预览 HTML 示例也未改动。
- 以下是文本场景复核，不是实际运行这些工程任务或对模型行为作统计测试：

| 场景 | 修改后规则要求 |
|---|---|
| 已授权计划超过三个步骤 | 按依赖和自然检查点继续，不固定停在第三步 |
| 相关检查失败 | 定位、修复并复验授权内问题，只阻断依赖失败的步骤 |
| 已确认样式的间距微调 | 继承方向，检查受影响 UI，不重做四方案选择 |
| 明确要求重新选型 | 遵循项目候选数量，真实选择或代选授权后继续 |
| 安装或远程检测 | 采用必要检查、有限等待和精简日志，不按类别升级流程 |
| 出现真实复杂流程需求 | 提供证据、收益与成本，由用户选择升级 |
| 仅要求诊断或方案 | 交付分析，不自行扩大为施工或发布 |
| 涉及受保护操作 | 保留实际审批要求，复用覆盖同一动作的已有授权 |

Memmy 的配置、Hook、数据库、自动化、导出与迁移未处理；未运行记忆流程。未修改 Skill 的运行时代码、设计偏好账本或自动更新机制，也未进行提交、推送或发布。后续上游更新若覆盖本地 Skill，可依据本记录及备份对照恢复所需规则。

## 备份与复查

备份目录：`/Users/chengyu/.codex/backups/20260905-agents-skills-115549-640061`。

- [逐文件清单及修改前后哈希](/Users/chengyu/.codex/backups/20260905-agents-skills-115549-640061/manifest.json)
- [完整修改差异](/Users/chengyu/.codex/backups/20260905-agents-skills-115549-640061/review.diff)
- [写入前静态验证记录](/Users/chengyu/.codex/backups/20260905-agents-skills-115549-640061/validation.json)
- [写入结果](/Users/chengyu/.codex/backups/20260905-agents-skills-115549-640061/apply-result.json)

如需回滚，按清单定点恢复对应 `backup_before`；先核验正式文件是否仍匹配本次 `after_sha256`，避免覆盖后续工作。

实际能力调用：`skill-creator` 用于修改规范；Codex `load_workspace_dependencies` 用于寻找现有校验环境；基础文件工具完成精确修改、备份与验证。上述 8 个 Skill 是修改对象，没有启动其业务执行流程。

## 2026-09-08 读取优化审核与远程收口

- 审核结论：本轮工作区读取与验证规则整改通过。摘要仅作导航，关键判断回查原文；未安装 shunt、未启用小模型或新增外部服务，未测量节省比例。
- 修复：工作区详细规则和项目模板不再将普通 Git 推送套入业务上线测试；默认样式入口指向迁移后的规则，并标明业务 HTML 仅为本地参考。
- 定向验证：修改文件空白与冲突标记检查、QA 路由存在性、远程三个发布文件的完整差异审查、隐私模式与本地 Markdown 链接检查、暂存差异检查均通过。此次是文档规则审核，未重跑业务测试或历史全局 Skill/Hook 验证。
- 远程已切换为脱敏蓝图且与本地业务历史分离。因此从远程基线 `8131820f` 建立隔离副本，仅发布通用规则到 `AGENTS.md`、`docs/context-and-memory.md`、`templates/PROJECT.template.md`；没有合并或强推本地旧历史。
- 已推送 `main`：`96d637854373048bca9a75a056c2c0615617279c`。推送成功，随后 `git ls-remote origin refs/heads/main` 核验一致。
- 仓库：https://github.com/annieaska/codex-workspace/commit/96d637854373048bca9a75a056c2c0615617279c
- 本地业务资料、个人 Skill 清单、全局配置、整改历史记录及其他未提交内容没有上传；本地业务目录仍保留原有历史和未提交修改，并非与公开蓝图同步的干净检出。

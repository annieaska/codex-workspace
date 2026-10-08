# Skill 与 MCP：目录、配置与运行机制

核对日期：2026-10-08。以下是本地实践的可迁移说明；`$HOME` 表示用户主目录，`<workspace>` 表示当前工作区，`$CODEX_HOME` 默认对应 `$HOME/.codex`。这里只公开路径结构与机制，不包含实际 Skill、MCP 程序、个人配置或凭据；路径存在不代表当前会话已启用该能力。

## Skill 目录与配置入口

| 位置 | 用途 |
| --- | --- |
| `$HOME/.agents/skills/` | 用户级 Skill 存放位置 |
| `<workspace>/.agents/skills/` | 工作区 Skill 存放位置 |
| `$CODEX_HOME/skills/` | 本机保留的 Skill 目录；`.system/` 为系统 Skill |
| `$CODEX_HOME/plugins/cache/` | 客户端管理的插件缓存；插件可携带 Skill 和 MCP，版本目录由客户端管理 |
| `$CODEX_HOME/skill-catalog/skills.tsv` | 本地自建的按需检索索引，不是 Codex 原生注册表 |
| `$CODEX_HOME/config.toml` | 用户级配置；本地通过 `skills.config` 的逐路径开关控制部分 Skill 是否参加原生发现 |
| `<workspace>/.codex/config.toml` | 项目级配置入口；是否采用受客户端、配置项与项目信任状态影响 |

目录是本机已核对的布局，不能据此承诺所有客户端都会自动扫描这些位置。旧目录与系统、插件目录不应互相复制覆盖。

## Skill 的运行方式

原生机制先提供 Skill 的名称、描述等发现信息；选中后读取 `SKILL.md`，再按需读取引用资料或运行脚本。Skill 是工作流说明及资源的集合，不是读取后就自动执行的常驻服务。具体规则见 [官方 Skill 文档](https://learn.chatgpt.com/docs/build-skills)。

本工作区另有一套按需路由：根据任务用中英文关键词检索 `skills.tsv`，最多返回 8 个候选，再读取匹配的 `SKILL.md` 及必要资源。首次使用说明名称与用途；用户要求先选择时等待选择。安装、更新或移动 Skill 后刷新索引，普通任务不预加载全部 Skill，也不自动安装。被禁用原生发现的文件仍可按路径读取，但不保证出现在菜单或自动匹配中；索引检索不能等同于原生启用。

Skill 选择不扩大执行授权。用户当前指令优先；涉及暂停、额外确认或偏离目标的要求应引用具体 Skill 条款。脚本、安装和外部写入仍遵守任务授权、沙箱和工具审批。

## MCP 没有统一安装目录

MCP 的配置入口与程序安装位置不同。用户级入口是 `$CODEX_HOME/config.toml`，项目级入口是 `<workspace>/.codex/config.toml`，服务器通常在 `mcp_servers` 下声明。插件还可以自带 MCP 配置，由插件管理；不应从个人配置整文件复制到公共仓库。

本机已核对的代表性布局：

| 位置 | 用途 |
| --- | --- |
| `$CODEX_HOME/mcp-servers/pubmed/`、`$CODEX_HOME/mcp-servers/openalex/` | 本地 Node 服务及其依赖，配置指向包内入口 |
| `/opt/homebrew/bin/` | 部分 MCP 命令及 Node、npx、uv 等运行器入口；命令路径不等于包源码目录 |
| `$HOME/.local/bin/` | 部分本地 MCP 包装命令入口 |
| `$HOME/Library/Application Support/davinci-resolve-mcp/` | DaVinci Resolve MCP 的本地虚拟环境 |
| `<workspace>/.basic-memory/run_mcp.sh` | Basic Memory 的本地启动脚本；记忆存储机制见上下文文档 |
| `<workspace>/04_能力库/07_摄影工具/lightroom-classic-mcp/.venv/` | 工作区 Lightroom MCP 虚拟环境 |
| `/Applications/<应用>.app/Contents/Resources/` | 应用自带 MCP 资源的代表性布局；部分应用入口在其他 bundle 子目录 |

还有直接放在项目中的服务；其路径随项目而变，公开模板不列私人项目目录。`npx`、`uv` 等运行器可能使用包缓存，不能把运行器目录当作固定安装目录。远程 HTTP MCP 连接服务端，客户端通常没有对应的服务源码安装目录。

## MCP 的运行方式与 Skill 的关系

本地 STDIO 服务由客户端按配置启动子进程，通过标准输入输出通信；远程 HTTP 服务通过端点连接。配置声明不证明连接成功，实际可用工具以当前会话和服务连接状态为准。详情见 [官方 MCP 文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。

MCP 提供工具，Skill 指导何时、如何组合工具，二者可独立存在。读取 Skill 不等于安装或连接 MCP；调用 MCP 不等于允许生产写入。只加载本次任务需要的说明与工具结果，较大结果先筛选，再纳入当前工作集。其余上下文与记忆规则统一见 [context-and-memory.md](context-and-memory.md)，不另建第二份状态真源。

迁移时按目标机器重新安装依赖、确认运行入口、配置权限并检查连接；不要复制插件缓存、虚拟环境、账户连接信息或完整个人 `config.toml` 作为安装方案。

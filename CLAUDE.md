@AGENTS.md

## 调用 Codex（仅 Claude 适用）
- 仅在不要菲斯哥明确要求时调用；消耗其 ChatGPT 订阅的 Codex 额度，具备能力不等于授权。
- CLI 打包在 ChatGPT.app 内、不在 PATH：`/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`。随 app 更新，调用前先核对路径和 `--version`。
- 新会话用 `codex exec -s read-only -C <目录> "<指令>" </dev/null`；默认只读，需要写文件时先确认范围再用 `-s workspace-write`。默认推理强度是 xhigh，简单任务加 `-c model_reasoning_effort='"low"'`。
- 带 app 会话上下文用 `codex exec fork --ephemeral -c sandbox_mode='"read-only"' <会话id> "<指令>"`（`fork`/`resume` 不接受 `-s`）；会带入整段历史，耗额度大。
- app 正在打开的会话不能 `resume`（报 active writer），不绕过。
- 2026-10-09 在 codex-cli 0.160.0 验证：问答、读项目文件、PubMed MCP、写文件、分叉可用。

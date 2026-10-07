# 剪辑语义定稿协议 V2

本目录定义 `video.semantic_blueprint.finalize` 的独立协议 `semantic-blueprint.v2`。首批实现严格为 `fixture_only`：只处理 `hard-sun-protection/source.fixture.v2.json` 中的 `unit-001`，不接受生产输入，不兼容、迁移或双写 V1。

真实字幕输入最小纵切独立于 fixture adapter：调用方必须显式提供一个 SRT 路径、仓库相对 POSIX `source_ref`、预期 raw SHA-256、钉住的 `SrtParserBuildManifest`、协议根和可选运行目录。执行器先校验原始字节身份，再按 `srt-cue-parser.v1` 严格解析并封存唯一 `SrtCueArtifact`；若提供运行目录，唯一持久输出为 `srt-cue-artifact.v2.json`。它不扫描或猜测输入，不自动选择 unit，也不生成 `ConfirmedUnitInput` 或任何 SourceSnapshot 之后的工件。

`ConfirmedUnitInput` 是显式人工决定封存后的机器工件，不是要求用户填写的技术表单。用户只需确认一个可唯一映射到完整连续 cues 的字幕段，以及该段的 NFC、非空白 `logic_role`；不得要求用户提供或确认 `unit_id`、`opaque_confirmation_id`、`cue_ids`、`start_ms` / `end_ms`、四项 `source_invariants`、引用、`object_id` 或任何哈希。若用户描述不能唯一定位字幕段，只澄清具体候选字幕段；解析器和系统不得自动选择语义单元、自动切片、聚类或推断 `logic_role`。

字幕段唯一定位后，调用编排层在 `sealConfirmedUnitInput` 前，从 exact `SrtCueArtifact` 自动派生连续 `cue_ids`、首 cue 的 `start_ms`、末 cue 的 `end_ms` 与双引用，并在系统内部生成身份字段。首次逻辑单元生成新的 `unit_id`；仅当调用上下文显式绑定既有 `ConfirmedUnitInput` 或其 exact reference 时复用该 `unit_id`，否则生成新的 `unit_id`，禁止按字幕相似度或 `logic_role` 推断“同一单元”。系统同时生成独立的 `opaque_confirmation_id` 和由两者确定的 `object_id`。

四项 `source_invariants` 是机器验证事实，不是用户声明。机器校验 cue id、顺序、时间和文本均未变化后自动写入四项 `true`；任一项失败时停止封存并返回既有结构化错误，不询问用户是否接受，也不得写入 `false`。日常用户门禁默认字幕不变；只有用户主动明确要求修改或更换字幕时，才创建新的不可变 SRT 工件及受影响的新链，旧工件不得覆盖、迁移或双写，新链的四项不变量仍须由机器验证为 `true`。SRT raw bytes 是来源字节真源，只证明 cue id/time/text；`SrtCueArtifact` 是确定性 cue 真源，`ConfirmedUnitInput` 才能封存人工确认的 unit boundary 与 `logic_role`。

工件链严格串行：`SourceSnapshot → UnitVisualPlan → GateResult → UnitRevision → UnitPreviewManifest → ApprovalInput → ApprovalRecord → RequestScopeManifest + FinalizeInputV2 → SemanticBlueprint`。组件事实只来自 component catalog，跨元素规则只来自 visual policy；Gate 是唯一视觉规则判定者，Finalizer 只验证显式选择链、exact refs、哈希、范围、顺序和覆盖，不重新解释视觉 policy。只有 SemanticBlueprint 具有 `final_semantic_authority`。

JSON 哈希使用 SHA-256(RFC 8785 JCS UTF-8)，格式为 `sha256:<64位小写十六进制>`；字符串必须已是 NFC 且不得含孤立 UTF-16 surrogate。`semantic_input_refs`、`exact_dependencies`、`violations`、`fact_refs`、`policy_refs`、`source_field_refs`、`local_resource_hashes` 是无序集合：封存前按冻结稳定键排序，并拒绝稳定键重复；`ordered_required_unit_ids`、`selected_approval_refs`、`stages` 等有语义顺序数组保持调用方顺序。预览文件按原始字节计算同格式 SHA-256。所有封存工件使用原子 no-replace 并清理未发布临时文件；Preview 采用 manifest-last。

运行时在读取、阶段交接、封存和 finalize 边界校验 `semantic-blueprint.v2.schema.json` 中的严格契约；未知字段、错误 `object_type` / `authority_scope`、非法引用形状与状态组合一律拒绝。领域结果为 `PASS | REWORK | BLOCKED`：`PASS` 不带 `blocking_kind`，`REWORK` 只配 `PLAN_REWORK`，`BLOCKED` 只配 `MISSING_EVIDENCE | MISSING_SOURCE | HUMAN_REVIEW_REQUIRED`。机器真源无效属于执行错误，不得伪装成 `BLOCKED`。

验收分三段且不得越级：P01 生成 fixture snapshot、计划和 GateResult；Gate 必须执行冻结 policy 的全部适用规则，并校验 catalog provenance。P02 只接受调用方提供且完整封存的 ApprovalInput，执行器不得代注入 revision/preview 引用或默认批准。P03 只接受调用方显式提供的 RequestScopeManifest、FinalizeInputV2 与有序 `selected_approval_refs`，不得扫描目录、推断 latest 或隐式选择。每个 dependency role 必须唯一，payload ref、exact dependency 与 scope expected ref 必须闭合一致。通过只表示 fixture 纵切自测完成，报告必须保持 `fixture_only: true`、`production_ready: false`。

结构化执行错误固定携带 `code`、`stage`、`retryable`、`exit_code`。关键映射为：`CONTRACT_INVALID=2`、`INTEGRITY_MISMATCH=3`、`STALE_DEPENDENCY=4`、`PREVIEW_INCOMPLETE=5`、`OUTPUT_EXISTS=6`、`UNSUPPORTED_ATOMIC_PUBLISH=7`、`FIXTURE_ONLY_INPUT=8`、`POLICY_SNAPSHOT_INVALID=9`、`SOURCE_INVARIANT_VIOLATION=10`、`SRT_INPUT_INVALID=11`、`CONFIRMED_UNIT_INVALID=12`、`INTERNAL_ERROR=70`。SRT 输入错误在 `srt_decode | srt_parse` 阶段返回单个严格 `InputViolation`；人工单元关系错误在 `confirmed_unit_validate` 阶段返回单个严格 `InputViolation`，不得退化为 70。有效领域结果不作为执行错误。

```bash
env SBV2_PROTOCOL_ROOT="$PWD/04_能力库/06_能力定义/01_内容能力/01_剪辑语义定稿/protocols/semantic-blueprint.v2" \
  SBV2_EXECUTOR_ROOT='/Users/chengyu/.local/share/codex-tools/semantic-blueprint-v2' \
  node --test --test-reporter=spec \
  '/Users/chengyu/.local/share/codex-tools/semantic-blueprint-v2/semantic-blueprint-v2.test.mjs'
```

真实 SRT 最小纵切验收入口：

```bash
SBV2_PROTOCOL_ROOT='/Users/chengyu/12_打工人程宇/04_能力库/06_能力定义/01_内容能力/01_剪辑语义定稿/protocols/semantic-blueprint.v2' \
SBV2_REAL_SRT_PATH='/Users/chengyu/12_打工人程宇/02_项目/01_进行中/视频生产/YouTube/2026/2026-08-16_修丽可大盘点/01_输入/修丽可字幕粗.srt' \
SBV2_REAL_SRT_SOURCE_REF='02_项目/01_进行中/视频生产/YouTube/2026/2026-08-16_修丽可大盘点/01_输入/修丽可字幕粗.srt' \
SBV2_REAL_SRT_EXPECTED_HASH='sha256:85cffc343ab83e5b37565ed09a5cff3a878f8e0c823ebd96be22787cce800a88' \
node --test '/Users/chengyu/.local/share/codex-tools/semantic-blueprint-v2/semantic-blueprint-v2-srt.test.mjs'
```

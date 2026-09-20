# 01XC 构思增强版

## 当前交付周期（唯一主控锚点）

- 原始目标：保留原 01X，独立克隆增强版，借鉴 article-metaphor-illustrator 分析原文、建立构思卡；能力链接入另议。
- 授权：2026-09-10 用户要求主控建立四个标准窗口并完成实施，已取代此前“仅设计方案”的阶段边界。
- 当前状态：本轮实现与定向验收完成，四窗口已交付并停写；无本轮范围内技术阻塞，等待用户效果验收。
- 交付：独立可运行 01XC、严格契约与方法、构思编译/权限校验、六类派生交付、四句示例及验证证据。
- 确认决定：仅接收 V3；producer=01XC，输出 source01xc-storyboard.v1，计划 storyboard-conception-plan.v1，authority=01XC_source_bound_interpretation；保留 source01x-evidence.v1 输入证据身份。
- 不做项：原 01X 修改、能力链/索引接入、固定猫/配色/画幅、自动生图、音频成片、Git 提交推送及发布；不跑旧全链测试或全文长稿。
- 下一动作：用户打开样例，验收构思是否贴切、阅读顺序是否清楚；接链另行讨论，不自动启动。

## 交付入口

[运行说明](README.md) · [样例网页](examples/short-group/output/分镜头剧本-V1.html) · [逐拍构思审阅](evidence/sample-review.md)

自编四句业务稿形成两张卡（事实对比、接力隐喻）、五个阅读拍。原文只描述业务关系，跑道/交棒映射由执行者编制；不是照搬原文现成比喻。六类产物全部保存在 examples/short-group/output。

明日效果验收重点：两张卡是否忠于原意；接力映射是否使交接关系更清楚；五拍显隐及限定是否符合预期。本轮未绘制插图或验证实际画面、音频、成片；文本审阅与机器通过不代表用户确认。

## 整改关闭证据

| 要求 | 状态与关闭证据 |
| --- | --- |
| 原版隔离 | 20 个文件的集合与 SHA-256 均和克隆前一致；见 evidence/original-baseline.json、evidence/original-integrity.json |
| 拍末揭示与跨卡真实可见状态 | 已实现并通过同句未来信息、拍首、未显示操作、非法继承等定向反例；见 evidence/validation.md |
| 证据用途与递归依赖 | 已实现前提、关系端点和来源闭包，阻断 understanding_only 上屏；正反例通过 |
| 六类交付独立校验 | JSON、Markdown、HTML 可见内容/内嵌下载、B-roll、两份报告均按源重算；9 类篡改及缺报告反例通过 |
| 独立运行 | 仅带增强版 scripts/resources/contracts 和自带三份输入的临时副本，真实 compile/validate CLI 通过 |
| 业务原文到构思 | 执行者文本审阅完成；见 evidence/sample-review.md。实际视觉及用户验收未验证，不能以测试通过代替 |

## 验证范围、版本与停止条件

增强版根目录执行：

```sh
python3 -m unittest discover -s tests -p 'test_conception_handoff.py'
```

最终 7 个测试方法通过（1.087 秒），包括 26 个核心非法输入、9 类产物篡改、缺报告、六件套真实 CLI 和独立临时副本 CLI。计划与输出通过本地有限 schema 子集检查，不宣称完整 JSON Schema 标准实现；跨字段及来源权限由语义检查补足。

首次运行因样例单元内序号误用全篇编号，在加载阶段退出（0 tests）。仅修正样例及其指纹后复验同一范围通过，无产品脚本/schema 修复项。通过后只写说明和证据，没有增加测试轮次。

详细记录见 [validation.md](evidence/validation.md)，版本见 [validation.json](evidence/validation.json)。主控已核对 34 个被记录业务文件与验证版本一致。快照误收录的 macOS `.DS_Store` 因系统自动变化已排除并注明，不属于运行代码或产物；未改动被测内容，复用有效结果。readability/human_review 始终为 unverified。

历史 tests/test_source01x.py 绑定原长稿与下游能力，不是本版验收入口。没有运行全量套件、浏览器视觉、真实音频或成片检查。相关定向检查通过且本轮缺陷关闭后停止，不追加审核或测试。

## 四窗口与主控责任

主控是本 PROJECT 的唯一维护者。文件负责人完成后均已停写；本轮不再派生窗口或子 agent。

| 窗口 | 责任及交付 | 任务 ID |
| --- | --- | --- |
| A 契约与构思方法 | README、BRD、contracts、构思方法及上游 MIT 归属，完成 | 01a08873-8156-7121-b961-4efc340c89f2 |
| B 核心编译与权限 | conception_handoff、semantic_handoff，完成 | 01a08873-9605-75f1-894c-2d6468418143 |
| C 交付与独立校验 | pipeline、compile/validate CLI、构思卡阅读视图，完成 | 01a08873-b4d4-72d3-aa4e-fbfa0f648b09 |
| D 定向验收与样例 | tests、examples、验证与文本审阅证据，完成 | 01a08873-c6d3-70b0-83af-d2b221144173 |

## 方案与后续

已审阅方案：[01X增强版整改方案](evidence/01X增强版整改方案.md)；原方案审核任务：01a0886c-11a1-7673-980b-dcda419b3c0a。方案中的两项阻断定义已落实并获得本轮验证证据。2026-09-20 目录整理将方案原文归入本能力 evidence，业务状态与原验收结论不变。

本轮已收口。原 01X 保持可用，增强版未自动激活到业务项目。无需部署或 Git 操作；用户次日效果验收结论待补，能力链接入另行决定。

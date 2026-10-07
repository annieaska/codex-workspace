# 剪辑语义定稿

## 能力定义

把已确定的口播内容、带时间字幕和逐单元画面语义，定稿为唯一权威制品 `SemanticBlueprint`。后续 HTML、SVG、字幕动画预演和出片输入都只能从该蓝图派生，不能反向覆盖蓝图。

能力 ID：`video.semantic_blueprint.finalize`

当前协议：`semantic-blueprint.v1`

## 阶段关系

`00_基础剪辑语义文稿` 是独立第一阶段，负责从字幕或文字稿生成可人工确认的基础文字语义。该阶段通过人工确认后，本能力才继续接收已确定的文字语义与后续画面语义，并定稿最终 `SemanticBlueprint`。

本能力不再承担基础剪辑语义文稿的生成职责。本次拆分不改动现有 V1 输入、输出协议和历史制品；下游输入契约的正式修订留到后续独立里程碑，不建立兼容层。

## 边界

- 输入：`NormalizedEditRequest`，包含来源引用、字幕、语义单元、三幅画面语义及已声明的组件选择。
- 唯一权威输出：`SemanticBlueprint`。
- 组件决策：内部领域服务；后续负责推荐或校验组件选择，不注册为独立业务能力。
- 视觉合规：内部质量门禁；后续在蓝图定稿前给出阻断或通过结论。
- 字幕动画预演：只读蓝图的派生渲染器；不得产生新的语义真源。
- 非目标：成片渲染、Resolve 操作、素材生成、自动改写字幕与事实。

## 真源与派生关系

1. `contracts/normalized-edit-request.schema.json` 定义统一输入。
2. `component-catalog.json` 是组件目录唯一机器可读真源。
3. `contracts/semantic-blueprint.schema.json` 定义权威输出。
4. `acceptance/` 保存可执行验收案例；生成的蓝图、HTML、SVG 和动画文件不纳入能力定义目录。
5. 执行器在仓库外运行，入口和校验命令见 `06_系统说明/03_工具说明/剪辑语义定稿执行器.md`。

## 当前最小纵切

执行器读取输入与组件目录，检查字幕覆盖、时间顺序、语义单元顺序、起中落三幅、组件编号与样式，然后生成不可覆盖的 `SemanticBlueprint`。组件推荐、视觉合规和字幕预演尚未接入，详见 `IMPLEMENTATION.md`。

## 验收

使用 `acceptance/hard-sun-protection/input.json` 运行工具说明中的命令，应满足：

- 生成结果通过 `semantic-blueprint.v1` 的运行时校验。
- 三幅画面的组件名称、动作和必变信息均来自 `component-catalog.json`。
- 输出记录组件目录版本与 SHA-256 指纹，不复制第二份目录。
- 输入中的字幕、来源引用与语义说明原样进入蓝图。
- 目标文件已存在时拒绝覆盖。

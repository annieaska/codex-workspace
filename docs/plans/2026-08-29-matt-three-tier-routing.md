# Matt 三级路由实施计划

**Goal**
- 在当前个人工作区接入可自动重判的轻量／中等／Matt 复杂三级路由，同时保护正在执行的任务不被中途换轨。

**Scope**
- In scope: 根路由规则、项目内 Matt 过程文件位置、领域资料读取顺序、阶段门禁自动重判和降级规则。
- Out of scope: 修改全局 Skills、改写当前视频项目状态、创建 GitHub 工单、预建每个项目的 Matt 目录。

**Context**
- Repo/Module: `/Users/chengyu/12_打工人程宇`
- Related files: `AGENTS.md`, `docs/agents/issue-tracker.md`, `docs/agents/domain.md`
- Constraints/assumptions: 个人自用，默认轻量；`PROJECT.md` 始终是项目状态真源；全局 Matt Skills 已安装。

**Implementation Plan**
1. 固化三级自动路由
   - Files: `AGENTS.md`
   - Action: 定义三级触发证据、在途任务保护、阶段门禁自动重判、升级与降级规则。
   - Verify: `rg -n '三级路由|阶段门禁|在途任务|Matt 复杂' AGENTS.md`
   - Expected: 四类关键规则均可定位。
2. 配置项目内 Matt 过程文件
   - Files: `docs/agents/issue-tracker.md`
   - Action: 将复杂任务产物限定到对应项目的 `02_工作区/Matt执行`，禁止根级 `.scratch` 和外部工单系统。
   - Verify: `rg -n '02_工作区/Matt执行|PROJECT.md|\.scratch|GitHub' docs/agents/issue-tracker.md`
   - Expected: 位置、回写与禁止项明确。
3. 配置领域读取与状态真源
   - Files: `docs/agents/domain.md`
   - Action: 定义按需读取顺序，禁止创建重复状态体系。
   - Verify: `rg -n 'PROJECT.md|03_知识库|04_能力库|05_确认记录|CONTEXT.md' docs/agents/domain.md`
   - Expected: 真源和资料边界明确。
4. 做静态回归检查
   - Files: 上述全部文件
   - Action: 检查格式、路径、全局 Skill 存在性及工作树差异。
   - Verify: `git diff --check`
   - Expected: 无格式错误；用户既有改动未被修改。

**Testing Strategy**
- Unit: 不适用；本仓库为文档与业务工作区。
- Integration/E2E: 用轻量、中等、复杂三个纸面样例逐项核对路由结果。
- Regression focus: 当前剪辑语义定稿不被中途换轨；到最近阶段门禁后必须自动重判。

**Risks and Rollback**
- Risk: 仅凭任务规模误判复杂度。Mitigation: 只按不确定性、依赖、回归和连续性证据升级。
- Risk: Matt 过程文件取代业务状态。Mitigation: 强制 `PROJECT.md` 为唯一状态真源。
- Rollback: 删除新增的 `docs/agents` 配置并移除 `AGENTS.md` 的 Matt 路由章节。

**Done Definition**
- [x] 三级路由与阶段门禁自动重判已写入
- [x] Matt 项目内产物规则已配置
- [x] 领域读取规则已配置
- [x] 静态验证通过

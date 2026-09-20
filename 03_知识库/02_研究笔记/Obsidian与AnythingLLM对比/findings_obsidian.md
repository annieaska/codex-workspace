# Obsidian 官方能力研究

## 结论

Obsidian 很适合做复杂知识体系的长期「知识真源」，尤其适合由人主导的逻辑建模：论证链、概念关系、决策依据、项目状态和方案比较。它的核心优势不是 AI 自动问答，而是本地文件可控、关系可追溯、结构可逐步演化。

对复杂、逻辑性强的使用场景，最合适的组合是：

```text
Markdown 正文承载论证
  → 链接／反向链接表达知识关系
  → Properties 定义对象类型与状态
  → Bases 聚合、筛选与计算
  → Canvas 展示局部论证链和系统关系
```

## 官方能力与适用性

### 1. 本地 Markdown 知识真源

Obsidian 将笔记保存为 Vault 中的 Markdown 纯文本文件；Vault 本质上是本地文件夹。文件可被其他编辑器和文件管理工具直接处理，Obsidian 对外部修改会自动刷新。缓存与界面配置不取代底层文件，元数据缓存失常时也可重建。

这意味着它很适合做长期真源：内容不被锁在专有数据库里，可使用 Git 版本管理、普通文件备份、脚本和其他工具。

来源：[How Obsidian stores data](https://obsidian.md/help/Files%2Band%2Bfolders/How%2BObsidian%2Bstores%2Bdata)

### 2. 链接和反向链接

Obsidian 支持链接到整篇笔记、标题或具体文本块；重命名文件时可自动更新内部链接。反向链接面板可显示「已链接提及」与「未链接提及」，有助于发现某个概念在其他论证中的使用位置。

这比只有目录树更适合复杂知识：同一概念可以同时属于多条论证链，且能反向审计「谁在引用它」。

边界：块引用是 Obsidian 特定语法，不是标准 Markdown；离开 Obsidian 后，块级跳转的互操作性会降低。

来源：[Internal links](https://obsidian.md/help/links)、[Backlinks](https://obsidian.md/help/plugins/backlinks)

### 3. Properties 结构化层

Properties 可为每篇笔记定义文本、列表、数字、布尔、日期、日期时间和标签等类型化数据，底层以 YAML 保存在 Markdown 文件顶部。它可用来表达知识对象的类型、状态、来源、负责人、时间和关联对象。

边界：

- 官方明确列出尚不支持嵌套 Properties。
- 不支持原生深度批量编辑，官方建议在需要时使用 VS Code、脚本或社区插件。
- Properties 不渲染 Markdown，它们被定位为小型、原子化、人和机器均可读的信息，不适合承载复杂嵌套对象或长论证。

来源：[Properties](https://obsidian.md/help/properties)

### 4. Bases 数据库式视图

Bases 是核心插件，可基于 Vault 中的文件与 Properties 进行查看、编辑、排序、筛选、分组和公式计算，并提供表格、列表、卡片等视图。原始数据仍在本地 Markdown 和 Properties 中；视图定义以 YAML 格式的 `.base` 文件或 Markdown 代码块存储。

对复杂场景的价值是：同一批知识对象可以按「未确认结论」「特定领域」「引用某个对象」「最近修改」等规则生成多种派生视图，无需复制原文。

边界：

- 官方将 Bases 定位为「database-like views」，它不是完整的关系型数据库。
- Bases 的数据集默认是整个 Vault，使用筛选条件缩小范围；官方语法明确说没有 SQL 或 Dataview 式的 `from` / `source`。
- 它可做布尔筛选、基础运算、函数和汇总，但并不提供复杂多表联结、事务、严格约束或业务工作流引擎。
- 部分文件属性查询存在性能或自动刷新限制，例如官方标注 `file.backlinks` 性能开销高，`file.backlinks` 与 `file.properties` 在 Vault 改变时不会自动刷新结果。

来源：[Introduction to Bases](https://obsidian.md/help/bases)、[Bases syntax](https://obsidian.md/help/bases/syntax)

### 5. Canvas 可视化逻辑建模

Canvas 是核心插件，可在无限二维画布上排布笔记、附件、网页和纯文本卡片，用有方向的连线、标签、分组和颜色表示关系。Canvas 文件采用开放的 JSON Canvas 格式。

它适合处理：论证地图、因果链、概念辨析、系统架构、方案对比和时间线。

边界：

- Canvas 连线和布局主要是人工视觉语义，不是可执行规则、逻辑证明或自动推理引擎。
- Canvas 中未转成文件的纯文本卡片不会出现在 Backlinks 中；要让内容进入全局知识网，需将其转为正式笔记。

来源：[Canvas](https://obsidian.md/help/plugins/canvas)

## 总体边界

Obsidian 强在「人主导的知识建模」，不应把以下能力当成它的原生主职：

- 自动摄取多种文档并切片；
- 自然语言跨文档问答与 RAG；
- 根据语义自动发现全部关系；
- 图谱逻辑推理、事务约束或规则执行；
- 复杂、多人、强约束的工作流自动化。

这些需要社区插件或外部 AI、检索、图数据库和工作流层。因此，在「复杂逻辑知识库」中，Obsidian 更合适成为底层知识真源和人工编辑界面，而不是唯一的执行平台。


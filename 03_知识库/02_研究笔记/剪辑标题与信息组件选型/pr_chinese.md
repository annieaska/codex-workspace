# Premiere Pro 中文科普口播：简单标题 / 信息组件调研

> 核验日期：2026-09-03。仅使用厂商官网与官方帮助中心。重点是标题、数字、形状、图标、标注、教程提示等信息组件；产品内即使含有转场，本稿也不评价复杂转场。

## 先给结论

1. **最适合作为主方案：Mister Horse Animation Composer for Premiere（原 Premiere Composer）**。免费层已经能试用标题、文本框、计数器和图形组件；若中文实测通过，再买订阅。它的 `Text Presets for Premiere` 明确写着 “Any text. Any font”，`Essential Typography` 也明确写着可配合任意字体，中文科普常用的标题卡、要点条、数字强调、简洁标注最齐全。
2. **最适合屏幕教程 / 软件演示：MotionVFX mTutorial Pr**。高亮、指向、放大、鼠标与键盘提示、对比和技术注释很贴合教程类科普，但官方技术规格同时列出 **After Effects 2022+**，且没有找到中文 / Unicode / CJK 或自定义系统字体的明确保证。应把它视为“先试后买”的专项工具，而不是中文标题主库。
3. **中文最稳的兜底：Premiere 原生 Graphics / MOGRT**。Adobe 官方明确说明 Premiere 可使用电脑已安装或 Adobe Fonts 激活的字体；旧版官方参考手册明确列出 CJK 文字排版支持。原生标题、形状、文字与数字可直接在 Premiere 建模并导出为可复用 MOGRT，不需要 AE。
4. **MotionVFX mLowers Simple Pr 只适合作为窄补充**：它只有 30 个极简下三分之一标题，信息组件广度远不如前两者；官网也没有中文 / Unicode 说明。

## 方案对比

| 方案 | 中文 / 字体证据 | 信息组件能力 | AE 要求 | 当前兼容性 | 当前价格 / 授权 | 建议 |
|---|---|---|---|---|---|---|
| Mister Horse Animation Composer for Premiere | 官方对 Text Presets 写明 “Any text. Any font”；Essential Typography 写明适配任意字体。Premiere 插件更新记录也出现 font picker 修复。但**未找到厂商对 Unicode / CJK / 中文的逐字承诺** | 标题、文字框、计数器、文字动画、形状、覆盖层、背景、图标、手绘箭头 / 线条 / 标注等；用户库还可导入 MOGRT、图片和声音 | Premiere 版本官网没有列出 AE 为最低要求；作为 Premiere 内插件运行 | 当前产品页要求 Premiere 2025+；插件更新记录的 2.1.12（2026-08-12）支持 macOS、Windows、Windows on Arm | 免费：$0、1,000+ 素材；年付：$198/年（页面折算 $16.50/月）；月付：$19.90/月。单用户最多 2 台电脑 | **首选**。先用免费层以思源黑体 / Noto Sans CJK 做真实中文压力测试，再决定订阅 |
| MotionVFX mTutorial Pr | 官方只写 fully customizable；**未找到中文、Unicode、CJK、任意字体或系统字体的明确说明** | 72 Titles + 28 Effects；可高亮、指向、放大、显示鼠标 / 键盘提示、做对比和技术注释；另含 7 个转场但本稿不评价 | **官网最低要求明确列出 After Effects 2022+**，因此不能当作“完全不需要 AE”的方案 | macOS / Windows；Premiere Pro 2022+；仅横屏 | $119，一次性购买；用免费 mInstaller 安装到 Premiere 的 Graphics Templates / Essential Graphics 体系 | **屏幕教程专项推荐**，但先向售前确认中文字体与 AE 依赖，或用试用版验证 |
| Premiere 原生 Graphics / MOGRT | Adobe 当前文档明确可使用电脑已安装或 Adobe Fonts 激活的字体；Adobe 官方参考手册明确列出 CJK 支持 | 标题、下三分之一、按钮、形状、文字、图片、视频层；可创建矩形 / 椭圆 / 多边形 / 自由路径；可做响应式布局并导出 MOGRT；数据驱动 MOGRT 支持文本、颜色、数字及图表 | Premiere 原生图形不需要 AE；但**由 AE 制作的某些 MOGRT 可能要求电脑安装 AE** | Premiere 25.0 起 Essential Graphics 已改名为 Graphics Templates；官方文档更新至 2026-08 | Premiere 自带，无额外插件费；Adobe Stock 模板可能免费或付费 | **中文保底与自建品牌模板首选**；适合固定的“标题 + 数字 + 色块 + 箭头”体系 |
| MotionVFX mLowers Simple Pr | 未找到中文 / Unicode / CJK 官方说明；页面只说明可在 Premiere 内自定义。旧版 CC2018 还明确存在不能改字体 / 文本格式的限制 | 30 个极简 lower thirds；适合人物名、机构名、章节提示，不覆盖图标、计数器和丰富标注 | 产品包含 Premiere 标题及 AE 工程；官网技术区应按购买页面核对具体工作流 | 官网列 Premiere Pro CC 2018+；页面仍在售，但规格较老 | $89，一次性购买 | 仅在喜欢其视觉风格时补充，不建议作为科普信息组件主库 |

## 1. Mister Horse Animation Composer for Premiere

### 名称、版本与兼容性

- 官方当前页面名称为 **Animation Composer for Premiere**，并注明它在 2026-06-10 由 Premiere Composer 更名而来。产品定位是直接在 Premiere 中工作的免费扩展，当前要求 **Premiere 2025 及以上**：<https://misterhorse.com/animation-composer-for-premiere>
- 官方更新记录显示当前插件版本为 **2.1.12（2026-08-12）**，支持 macOS、Windows 和 Windows on Arm，并再次写明 Premiere 2025+：<https://misterhorse.com/changelog/premiere-composer/3>
- Premiere 版本的当前最低要求与更新记录都没有把 After Effects 列为依赖。因此就官网证据而言，安装和使用 Premiere 版不需要单独打开 AE；但购买某个具体素材包前仍应看该包自己的软件要求。

### 适合科普口播的组件

- 免费内置内容已经覆盖 **titles & typography、text boxes、counters、text presets、social-media graphics、shapes、overlays、backgrounds** 等，并可调文字、颜色、尺寸、位置等参数：<https://misterhorse.com/animation-composer-for-premiere>
- Premiere 全部产品目录可见 Scale Titles、Text Presets、Essential Typography、Timers & Counters、Cinematic Titles、Shape Elements、Icons 等分类，基本覆盖“章节标题—重点数字—概念框—箭头标注—图标辅助”的科普信息层：<https://misterhorse.com/products-for-premiere>
- **Essential Typography** 当前含 799 项，涵盖 Text Box、Text & Line、纯文字、圆角填充 / 描边等模块；官方称其可配合任何字体，并可在 Premiere 保存自定义预设：<https://misterhorse.com/products/essential-typography/3285>
- **Text Presets for Premiere** 有 500+ 文字动画，官方明确写着 “Any text. Any font. You can use any font, spacing or size.”：<https://misterhorse.com/products/text-presets-for-premiere/3308>
- **Timers & Counters** 有 84 项（34 timers + 50 counters），可改颜色、填充和描边，适合倒计时、比例、年份、实验数据等数字强调：<https://misterhorse.com/products/timers-and-counters/20004>
- 官方 Icons 分类包括 Charts、Financials、Office、Symbols、UI、Devices 等，适合为抽象知识点添加简单图形语义：<https://misterhorse.com/category/icons>
- 官方 2026 更新页还列出 Scale Titles 的长文本 / Callouts 等标题，以及 Hand Drawn 的箭头、线条、涂画、形状、符号和文本框：<https://misterhorse.com/what-s-new>

### 中文、Unicode 与字体判断

- **已核实**：Text Presets 官方承诺任意文字、任意字体；Essential Typography 官方承诺适配任意字体；Premiere 插件更新记录有 font picker 的维护记录。Premiere 自身又支持本机已安装字体。
- **没有核实到**：Mister Horse 官方没有在这些产品页直接写出 “Unicode / CJK / Chinese / 中文支持”。因此“可选择支持中文的系统字体”是基于上述官方功能的合理推断，不应包装成厂商的 CJK 保证。
- 官方 Starter Pack 更新记录曾修复非英语版本 Premiere / AE 中的 Scale Titles，Text Presets 更新记录也维护过 RTL 语言；这说明厂商会处理非英语问题，但仍不能等同于中文完整兼容证明：<https://misterhorse.com/changelog/starter-pack/3300>、<https://misterhorse.com/changelog/text-presets-for-premiere/3308>
- 不建议把其 **Animated Fonts** 类素材作为中文主方案，因为这类逐字形动画字体是否包含中文字形没有官方证据。优先选择可套用任意字体的 Text Presets / Essential Typography。

### 价格与授权

- 官方价格页当前为：免费 $0；年付 $198/年（标示 $16.50/月）；月付 $19.90/月。免费层含插件、1,000+ 素材与 4 个工具；付费层含 6,000+ 素材、无限用户库。单用户最多可在 2 台电脑使用：<https://misterhorse.com/pricing/>
- 官网注明旧的单包购买模式已转向统一订阅；旧的 Editor’s Bundle 页面已标为 discontinued：<https://misterhorse.com/products/editor-s-bundle/3313>

### 建议的购买前中文实测

用免费层做一个 30 秒测试片，至少包含：

- “量子纠缠：不是超光速通信”这类中英数混排；
- `2026 / 37.5% / ± / ×10⁻³ / （）《》` 等数字、符号与中文标点；
- 思源黑体或 Noto Sans CJK 的 Regular / Bold；
- 单行、两行、长段落、文本框自动缩放、计数器、Callout；
- 导出成片，并在另一台没有插件的电脑打开项目检查可编辑性与缺字。

## 2. MotionVFX mTutorial Pr

### 能力、兼容性与价格

- 官方定位直接面向 tutorials、training、remote lessons、video courses、thematic channels 等内容；可用预设高亮、指向、放大重点，加入鼠标 / 键盘提示，制作对比并标注技术细节：<https://www.motionvfx.com/store%2Cmtutorial-pr%2Cp3799.html>
- Premiere 版本共 **107 个预设：72 Titles + 28 Effects + 7 Transitions**。本结论只看前 100 个标题 / 效果，不评价其中转场。
- 官网当前规格：macOS 或 Windows、Premiere Pro 2022+、**After Effects 2022+**、仅横屏；售价 **$119，一次性购买**。这比纯 Premiere 插件多一个 AE 前置条件，也不适合竖屏短视频直接套用。
- 一次性购买内容通过免费 **mInstaller** 安装；Premiere 内容会出现在 Adobe 的 Essential Graphics / Graphics Templates 体系中：<https://support.motionvfx.com/en/articles/9099828-how-to-install-motionvfx-products>

### 中文与字体风险

- 产品页只给出 “fully customizable”，没有列出字体选择范围，也没有写 Unicode、CJK、Chinese 或可调用任意系统字体。
- MotionVFX 官方的“字体缺失 / 随机字符”帮助条目主要讲 macOS / Motion / FCP 的字体损坏与重复问题，不能拿来证明 Premiere 版中文兼容：<https://support.motionvfx.com/en/articles/5496498-text-in-my-product-shows-missing-or-random-characters>
- 因此购买前应向官方支持一次性确认：① Premiere 版所有 72 个标题是否能输入中文；②是否能选本机安装的思源黑体；③替换字体后自动布局 / 字框是否仍正常；④为什么技术规格要求 AE，以及仅编辑现成模板是否也必须安装 AE。

## 3. Adobe Premiere 原生标题 / 信息组件（中文保底）

- Adobe 当前文档明确：项目字体可替换为**电脑已经安装**或通过 Adobe Fonts 激活的字体：<https://helpx.adobe.com/premiere/desktop/add-text-images/stylize-text/replace-fonts.html>
- Adobe 官方 Premiere 参考手册明确列出 Titler 支持 Chinese、Japanese、Korean（CJK）文字排版。该文档较旧，因此更适合作为“Premiere 文字引擎具备 CJK 基础能力”的证据，而不是当前第三方模板的兼容担保：<https://helpx.adobe.com/archive/en/premiere-pro/cc/2015/premiere_pro_reference.pdf>
- 当前 Premiere 可直接建立标题并调字体、颜色、描边、对齐等：<https://helpx.adobe.com/premiere/desktop/add-text-images/stylize-text/create-titles.html>
- 原生形状支持 Pen、Rectangle、Ellipse、Polygon，可设填充、描边、阴影、遮罩和响应式位置：<https://helpx.adobe.com/premiere/desktop/add-text-images/draw-objects/create-a-shape.html>
- Premiere 自建的文字、形状、效果与关键帧可直接导出为 MOGRT 复用：<https://helpx.adobe.com/premiere/desktop/add-text-images/insert-images-and-graphics/export-graphic-as-a-motion-graphics-template.html>
- Premiere 25.0 起，原 Essential Graphics 已改为 **Graphics Templates**；MOGRT 可以包含可编辑文字、颜色、媒体占位等：<https://helpx.adobe.com/premiere/desktop/add-text-images/use-motion-graphics-templates/where-do-i-get-motion-graphics-templates.html>
- 数据驱动 MOGRT 可使用文本、颜色、数字，并可制作柱状图、折线图等，适合需要重复更新数据的科普栏目；作者阶段通常需要 AE，但使用现成模板不要求编辑者理解复杂动效：<https://helpx.adobe.com/premiere/desktop/add-text-images/use-motion-graphics-templates/use-data-driven-motion-graphics-templates.html>
- 关于 AE：Premiere 原生制作的图形不需要 AE；但 Adobe 官方 FAQ 说明，一些由 AE 制作的 MOGRT 会要求电脑安装 AE。若产品页明确列 AE（如 mTutorial Pr），应按要求准备：<https://helpx.adobe.com/premiere/desktop/get-started/tour-the-workspace/adobe-premiere-faq.html>

## 4. MotionVFX mLowers Simple Pr（窄范围备选）

- 官方页面提供 30 个极简下三分之一标题，售价 **$89，一次性购买**，列出 Premiere Pro CC 2018+，并说明可在 Premiere 内自定义：<https://www.motionvfx.com/store%2Cmlowers-simple-pr%2Cp2284.html>
- 它适合姓名、身份、章节与短定义，不包含 mTutorial 那种高亮、鼠标提示、教程标注体系，也没有 Mister Horse 的计数器、图标与广泛形状组件。
- 官网未明确 Unicode / CJK / 中文支持。页面还提示 CC2018 存在不能更改字体和文本格式等限制，说明其兼容叙述偏旧；购买前必须用当前 Premiere 版本实测。

## 最终购买顺序

1. **零成本起步**：先装 Animation Composer 免费版，同时在 Premiere 原生 Graphics 中做一套中文品牌模板。
2. **中文通过再订阅**：如果 Text Presets、Essential Typography、Counters、Callouts 在思源黑体下均正常，再选 Mister Horse 年付；科普栏目长期更新时年付比月付更合适。
3. **只有大量录屏教程才买 mTutorial Pr**：先确认中文字体与 AE 依赖，再决定是否一次性花 $119。
4. **mLowers Simple Pr 不优先**：除非特别喜欢其视觉风格，且只缺人物 / 章节下三分之一。


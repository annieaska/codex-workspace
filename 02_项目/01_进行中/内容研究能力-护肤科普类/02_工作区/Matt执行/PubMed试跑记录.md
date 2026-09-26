# PubMed MCP 小范围试跑

时间：2026-09-26（CEST）。范围：用户授权试用 PubMed MCP；仅核验两篇项目已有文献，不启动新一轮主题检索。YouTube 待协作推进，Instagram 暂缓。本记录是证据报告，项目状态仍以 PROJECT.md 为准。

## 结论

**公共 MCP 调用及开放论文主体获取已跑通，可作为科学材料获取入口；尚未接入正式研究包。** 两个文献身份中，一个返回论文主体，一个返回未找到开放全文。成功样本原已在项目中深读，因此本次新增文献数与新增合格深读数均为 0，不能据此关闭阶段 3 的科学质量和覆盖缺口。

连接成功、返回正文、完整深读和科学质量合格是不同判断。本次返回缺少资助及利益冲突声明；补充材料只有指针。研究流程仍需核对这些部分。

## 实测输入与结果

| 原来源 | 标识与论文 | 实测结果 | 对项目的意义 |
| --- | --- | --- | --- |
| RES-S03 | DOI `10.1038/s41598-022-09231-8`；乳液、皮肤屏障和微生物组研究 | 返回 PMID `35340018`、PMCID `PMC8957616`、摘要、正文、2 张数据表、6 个图／附件指针；结构化响应 `source=pmc`、`viaSource=pmc` | 开放论文主体可获取，且能提取方法与局限；重复已有来源，不增加证据数量 |
| SK-BEH-001-S004 | DOI `10.1111/ced.12455`；Does poor sleep quality affect skin ageing? | `no-oa`：PMC 无对应全文、Europe PMC 无 PMC 对应记录、Unpaywall 未索引到开放副本 | 原研究包继续保持 abstract_only；本次路线未补齐全文，不能推断全球不存在可访问副本 |

开放论文可定位的研究边界：方法部分列出单中心、5 周、女性小腿研究；本论文只报告设计中的乳液一组，样本 37 人，脂质分析子集 18 人。不能直接外推为所有人群、所有部位、所有保湿产品的独立验证。正文将完整纳排、部分检测方法与统计细节指向补充材料，本次没有读取补充文件内容。

期刊原页的 Funding 段列有 Unilever 资助及部分作者薪酬支持；Competing interests 段同时声明无利益冲突。两类信息应分别保留，不能因声明无冲突就省略资助背景。本次 MCP 正文和结构化结果没有返回这些声明；作者机构也未出现在结构化结果中。核对来源：[期刊原文](https://www.nature.com/articles/s41598-022-09231-8)。

结构化结果没有 `truncation` 或 `deferred` 字段，即服务没有报告本次预算截断／延后；这不代表文章所有部分均已提取。对所查源码的定向检查显示，正文 sections 从 JATS body 提取，未在文章返回对象中加入资助／利益声明字段，与本次观察一致。公共服务部署版本未知，不能把所查 main 源码当成已验证的部署版本。

## 调用方式、计数与证据

- 工具来源：[cyanheads/pubmed-mcp-server](https://github.com/cyanheads/pubmed-mcp-server)，Apache-2.0；读取时 main 的 package.json 版本为 2.10.18。
- 使用仓库公开的 HTTP MCP 端点 `https://pubmed.caseyjhand.com/mcp`，通过本机既有 mcporter 调用。没有安装新包、持久化修改 MCP 配置或提供用户账号／密钥，仅提交公开论文标识。
- 工具发现返回 11 个工具；本次只验证 `pubmed_fetch_fulltext`，未验证主题搜索、MeSH、引文工具或长期服务稳定性。
- 调用账：1 次工具发现；3 次全文工具调用，共 4 个输入项、2 个去重文献身份。首次 DOI 批量 2 篇；随后同一开放论文按 PMCID 调用 2 次，用于排查并修复本机导出格式。受限论文没有重复抓取。主题发现查询为 0；未回写旧研究预算账本。
- 本机 mcporter 的 CLI `raw` 和 `json` 模式均把嵌套结构显示为 `[Object]`，不能当作 JSON 入库。已定位到现有 CLI 的结果包装逻辑，使用其既有 runtime API 直接保存原始响应，得到可解析 JSON；未修改 mcporter 安装文件。两份原始失败格式输出保留，避免掩盖重取次数。
- 定向检查：两篇身份对应正确；成功项具有方法／结果正文、2 表及 6 指针；失败项有访问链原因；最后一次原始响应可解析且无 `isError`。不运行项目全量测试。

证据均保存在临时目录，需保留以便接入时复核：

`/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类/02_工作区/99_临时/2026-09-26_PubMed试跑/`

| 文件 | 性质 |
| --- | --- |
| `tools.json` | 工具发现与输入输出 schema |
| `fulltext.raw.txt` | 首次双 DOI 批量的 CLI 原始输出，含未开放原因 |
| `fulltext.md` | 从首次输出安全解码的可读正文，未补写缺失声明 |
| `fulltext-repeat.raw.txt` | CLI json 模式仍折叠嵌套对象的原始输出 |
| `fulltext-response.json` | 直接保存的 MCP 原始响应，含完整 structuredContent；仅成功开放论文 |
| `repo-tree.json`、`pmc-article-parser.ts` | 源码定向检查依据；仓库提交 `620f5cc575c774027582baf1b91b77bcad98f2c0` |

源码定位：[parsePmcArticle](https://github.com/cyanheads/pubmed-mcp-server/blob/620f5cc575c774027582baf1b91b77bcad98f2c0/src/services/ncbi/parsing/pmc-article-parser.ts#L1388)。

## 接下来怎么用

1. 将此 MCP 定位为论文检索／取文工具；正式接入时保留 DOI、PMID、PMCID、实际获取渠道、抓取日期和不可访问原因，并按 DOI 去重。
2. 抓取后检查方法、结果、补充材料、资助和利益声明是否足够；缺项继续补查或标记缺口，再做现有质量评分与分支覆盖审核。不能只见全文成功就自动判深读合格。
3. YouTube 下一步从项目已有公开链接 `https://www.youtube.com/watch?v=biIzSPOEQgQ` 做小样核验，目标为账号、发布日期、观察日期、可见指标和字幕可得性；确需页面协作时给用户具体操作。Instagram 暂缓，不以其他平台数据冒充其结果。

本次不更改两份已冻结研究 JSON、run-config、页面或知识库，不宣称正式候选合格。

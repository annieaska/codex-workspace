from pathlib import Path
import json,re
P=Path('/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类')
D=P/'03_交付物/护肤科普研究首版'
T=P/'02_工作区/99_临时/2026-09-26_UI正式接入'
html=(D/'UI设计原型.html').read_text()
html=re.sub(r'<script[\s\S]*?</script>','',html)
html=html.replace('UI 设计候选 · r2','正式研究工作台').replace('真实材料 · 演示操作<br>草稿仅本页有效，刷新即清除','真实材料 · 来源可追溯<br>修改后请保存或导出')
html=html.replace('<div class="side-bottom">','<div class="side-bottom"><button data-action="files">保存 / 导入 / 导出</button>')
html=re.sub(r'<span class="prototype-note">.*?</span></span>','<span class="prototype-note" id="save-state">已载入 · 本地文件</span>',html)
html=html.replace('</body>', '<script id="boot-data" type="application/json">__BOOT_DATA__</script>\n<script>__CORE_JS__</script>\n<script>__APP_JS__</script>\n</body>')
html=html.replace('</style>', '''
.tabs{overflow-x:auto;flex-shrink:0}.tabs button{white-space:nowrap}
.data-row .meta{flex-wrap:wrap}.provenance{display:flex;flex-wrap:wrap;gap:6px;margin-top:9px}
.provenance .tag{font-size:10px}.modal-body{overflow-wrap:anywhere}
.error-banner{padding:14px;border:1px solid #bc5e39;background:#fff4ed;color:#883f24;white-space:pre-wrap}
.reader{line-height:1.85;white-space:pre-wrap;font-size:14px}.reader-table{overflow-x:auto;margin-top:16px}
.reader-table table{border-collapse:collapse;min-width:500px;width:100%;font-size:12px}.reader-table td,.reader-table th{border:1px solid var(--line);padding:9px;text-align:left}
.modal-body details{margin-top:16px}.modal-body summary{cursor:pointer;font-size:12px;color:var(--muted)}
.modal-body pre{white-space:pre-wrap;font-size:11px;max-height:320px;overflow:auto;background:var(--paper);padding:14px}
.field input,.field textarea,.field select{width:100%;box-sizing:border-box}.field label{display:block;margin-bottom:7px}.field textarea{min-height:90px}
.inline-check{display:flex;align-items:flex-start;gap:8px;margin:10px 0}.inline-check input{width:auto}
.operation-bar{display:flex;gap:8px;flex-wrap:wrap;margin-top:15px}.operation-bar button{font-size:12px}
#save-state{max-width:190px;white-space:normal;text-align:right}.table-wrap>.note{margin:12px}
@media(max-width:600px){.page-heading-actions{max-width:145px}.page-heading-actions>.operation-bar{justify-content:flex-end}.page-heading-actions>.small{display:none}.page-heading h1{font-size:21px}#task-switch{max-width:200px}.toolbar select{max-width:100%}.detail-foot .btn-row{flex-wrap:wrap}.candidate-layout .detail-foot{max-height:145px;overflow:auto}}
</style>''')
(D/'workbench.template.html').write_text(html)
a=json.loads((P/'02_工作区/99_临时/2026-09-26_PubMed试跑/fulltext-response.json').read_text())['structuredContent']['articles'][0]
acq={'schema_version':'1.0','batch_id':'PUBMED-PILOT-20260926','acquired_on':'2026-09-26','tool':'pubmed_fetch_fulltext','provider':'cyanheads/pubmed-mcp-server','endpoint':'https://pubmed.caseyjhand.com/mcp','report':'../../02_工作区/Matt执行/PubMed试跑记录.md','counts':{'unique_papers':2,'fulltext_success':1,'no_open_fulltext':1,'new_sources':0,'new_qualified_reads':0,'topic_queries':0,'fulltext_calls':3,'input_items':4},'note':'两篇均为已有文献的补取试跑；不是主题搜索，不增加来源或合格深读。取得正文不等于完成质量审核。','items':[{'id':'PM-PILOT-RES-S03','run_id':'SK-RES-001','source_id':'RES-S03','doi':a['doi'],'title':a['title'],'status':'retrieved','channel':'PubMed MCP → PMC','result_summary':'取得摘要、5 个正文章节、2 张数据表、6 个图／附件指针。','limits':['返回内容缺少作者机构、资助与利益声明，需另行核对原文。','图及补充文件只有指针，本次没有下载或读取附件。','该来源原已取得全文；本次不增加来源数或合格深读数。'],'raw_evidence':'../../02_工作区/99_临时/2026-09-26_PubMed试跑/fulltext-response.json','article':a},{'id':'PM-PILOT-BEH-S004','run_id':'SK-BEH-001','source_id':'SK-BEH-001-S004','doi':'10.1111/ced.12455','title':'Does poor sleep quality affect skin ageing?','status':'no-oa','channel':'PubMed MCP → PMC / Europe PMC / Unpaywall','result_summary':'本次公开获取路线未取得开放全文，原资料仍为仅摘要。','limits':['PMC 无对应全文；Europe PMC 无 PMC 对应记录；Unpaywall 未索引到开放副本。','仅说明本次路线未成功，不能推断所有渠道均无全文。','未增加来源或合格深读。'],'raw_evidence':'../../02_工作区/99_临时/2026-09-26_PubMed试跑/fulltext.raw.txt'}]}
(D/'acquisition-results.json').write_text(json.dumps(acq,ensure_ascii=False,indent=2)+'\n')
js=(T/'approved-app.js').read_text()
js=js.replace("const DATA=JSON.parse(document.querySelector('#research-data').textContent);", "const boot=JSON.parse(document.querySelector('#boot-data').textContent), C=WorkbenchCore, policy=boot.policy, DATA=boot.runs, ACQ=boot.acquisitions||{items:[],counts:{}};")
js=js.replace("full_text:'已读全文'","full_text:'已取得全文',revise:'修正',exclude:'排除'")
js=js.replace("note:'当前原型展示已有设定；新建任务仅演示填写和预览。'", "note:'新建任务会校验必填范围；创建成功后仍需导出任务交给 Codex 取证。'")
js=js.replace("note:'当前原型的审阅意见是演示草稿，刷新页面后清除。'", "note:'先逐支填写待提交意见，再点“提交全部审阅”登记身份。提交后可冻结本版审阅；刷新前请保存或导出。'")
js=js.replace('每次选 1–2 项预览补查要求','每次选 1–2 项查看要求，按预算逐目标导出补证请求').replace('补证预览不会启动研究，也不会关闭缺口。','请求导出前检查原任务剩余额度；导出不代表执行，也不会关闭缺口。')
js=js.replace('按标签找材料，打开详情核对原文、适用人群和局限；有疑问就带到“分支审阅”。','在“科学来源”查原有证据，在“获取成果”读工具实际取回的内容；打开详情核对来源、适用人群和局限。')
start=js.index('let active=0;');end=js.index('const tabs=',start)
js=js[:start]+'''let active=0,busy=false,initialized=false;
const freshState=d=>({view:'home',branch:d.branches[0]?.id,branchTab:'overview',evidenceTab:'sources',directionTab:'candidates',candidate:d.candidates[0]?.id,deliveryTab:'summary',query:'',sourceFilter:'all',page:1,gapPage:1,gapQuery:'',gapFilter:'all',versionPage:1,selected:new Set(),drafts:{},dirty:false});
const states=DATA.map(freshState), D=()=>DATA[active], S=()=>states[active], T=()=>C.taskFor(D(),policy), gaps=()=>D().gaps.filter(g=>g.status!=='closed'),byId=(key,id)=>(D()[key]||[]).find(x=>x.id===id);
const taskShort=d=>C.taskFor(d,policy)?.topic||d.run_id;
''' +js[end:]
# A replacement owns a whole function up to the next named declaration.
def replace_fn(name,nextname,body):
 global js
 start=js.index('function '+name+'(');end=js.index('function '+nextname+'(',start)
 js=js[:start]+body.strip()+'\n'+js[end:]
# Replacements are separately authored, leaving the approved layout helpers intact.
for name,nextname in [('home','scope'),('evidence','branchChoices'),('review','branchContent'),('directions','gapFiltered'),('delivery','showDialog'),('reviewForm','closeMenu')]:
 body=(T/(name+'.js')).read_text()
 if name=='delivery':
  # The modal navigation variables sit between these functions.
  body+='\nlet dialogReturn=null,dialogTrail=[];\n'
 replace_fn(name,nextname,body)
js=js.replace('d.task.', 'T().').replace('D().task.', 'T().')
js=js.replace('UI 原型','工作台').replace('本页展示当前任务范围；新建任务可以先体验填写与范围预览。','本页展示任务范围；绑定策略和剩余额度可在下方查看。')
js=js.replace("${goButton('evidence','下一步：查阅证据',true)}", "${goButton('evidence','下一步：查阅证据',true)}<button data-action=\"policy\">策略与预算记录</button>")
js=js.replace("if(tab&&view==='delivery')S().deliveryTab=tab;", "if(tab&&view==='delivery')S().deliveryTab=tab;if(tab&&view==='evidence'){S().evidenceTab=tab;S().page=1;S().query=''}")
js=js.replace("s.drafts[b.id]?'已有演示草稿':'保留待补证'", "s.drafts[b.id]?'意见待提交':C.review(d,b.id)?L(C.review(d,b.id).action):'等待审阅'")
js=js.replace('本页演示草稿 · 不是真实审核','意见待提交 · 尚未写入研究记录')
js=js.replace('以下为研究包已有的代理审阅记录；不代表用户亲自或临床专家确认。','下列记录保留实际登记的决定者身份；代理意见不代表用户或临床专家确认。')
js=js.replace("${esc(x.actor_label||'主控代理')} ·", "${esc(x.actor_label||'未记录')}（${esc(x.actor_type||'未记录身份')}）${x.invalidated?' · 已失效':''} ·")
js=js.replace('仅生成交接预览','查看要求后按预算导出').replace('预览补证要求','补证要求与请求')
# Add provenance and complete record access without crowding the reading surface.
js=js.replace("function detail(key,id){", "function detail(key,id){if(key==='acquisitions'){acquisitionDetail(id);return;}")
js=js.replace("showDialog(title,body,'',nested)}", "if(key==='sources')body=provenanceDetails(x)+body;body+=`<details><summary>完整原始记录</summary><pre>${esc(JSON.stringify(x,null,2))}</pre></details>`;showDialog(title,body,'',nested)}")
js=js.replace('完整审计载荷保留在原始研究包中。','完整审计载荷保留在下方原始记录及导出文件中。')
js=js.replace("function render(){const d=D(),s=S();", "function render(){const d=D(),s=S();if(!d)return;$('#save-state').textContent=s.dirty?'有改动 · 请保存或导出':'已载入 · 本地文件';")
js=js.replace("const b=e.target.closest('button,a');if(!b)return;", "const b=e.target.closest('button,a');if(!b||!initialized)return;")
js=js.replace("else if(a==='new-preview')newPreview();", "else if(a==='new-preview')newPreview();else if(a)handleAction(a,b);")
# Keep later clear-* branches reachable (unknown actions are ignored by handleAction).
js=js.replace("else if(a)handleAction(a,b);else if(a==='clear-search')", "else if(a==='clear-search')")
js=js.replace("else if(a==='clear-selection'){S().selected.clear();render()}});", "else if(a==='clear-selection'){S().selected.clear();render()}else if(a)handleAction(a,b);});")
js=js.replace("已切换研究任务；各任务的浏览位置和演示草稿分别保留。", "已切换研究任务；各任务的浏览位置和待提交意见分别保留。")
js=js.replace("else if(e.target.id==='gap-filter')", "else if(e.target.id==='source-filter'){S().sourceFilter=e.target.value;S().page=1;render()}else if(e.target.id==='article-part'){articlePart(e.target.dataset.id,e.target.value)}else if(e.target.id==='import-file'){run(async()=>{const file=e.target.files[0];if(file)await load(JSON.parse(await file.text()));})}else if(e.target.id==='gap-filter')")
js=js.replace("if(e.target.id==='new-task-form')newPreview()", "if(e.target.id==='new-task-form')newPreview();if(e.target.dataset.operation)handleSubmit(e.target)")
js=js.replace("S().query='';S().page=1;render();$('#material-search').focus()", "S().query='';S().sourceFilter='all';S().page=1;render();$('#material-search').focus()")
js=js.replace("window.addEventListener('resize',syncMenu);render();syncMenu();", "window.addEventListener('resize',syncMenu);\n"+(T/'operations.js').read_text()+'''\ntry {if(!await C.verifyPolicy(policy))throw Error('绑定策略校验失败');for(const d of DATA){const a=await C.audit(d,policy);if(a.errors.length)throw Error(d.run_id+'：'+a.errors.join('；'));}initialized=true;render();syncMenu();document.body.dataset.ready='true';}catch(e){$('#content').innerHTML='<div class="error-banner" role="alert">'+esc(e.message)+'</div>';}
''')
(D/'workbench-app.js').write_text('(async()=>{\n'+js+'\n})();\n')
build=(T/'before-build_workbench.py').read_text()
build=build.replace("def render(selected, files):", "acquisitions=json.loads((ROOT/'acquisition-results.json').read_text())\ndef render(selected, files):")
build=build.replace("'app_version':'SK-WORKBENCH-20260925-r1'", "'app_version':'SK-WORKBENCH-20260926-r2','acquisitions':acquisitions")
(D/'build_workbench.py').write_text(build)
print('Integrated approved template, application, and separate acquisition data.')

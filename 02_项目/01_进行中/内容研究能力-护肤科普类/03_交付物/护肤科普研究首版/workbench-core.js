/* 同一 v0.1 契约；浏览器与定向验证共用，无网络操作。 */
(function(root){
'use strict';
const collections=['sources','claims','branches','signals','decisions','candidates','snapshots','search_log','gaps'];
const actors=['controller_delegate','user','qualified_reviewer'];
const copy=x=>JSON.parse(JSON.stringify(x));
const text=x=>typeof x==='string'&&x.trim().length>0;
const present=x=>x!==undefined&&x!==null&&(typeof x!=='string'||text(x))&&(!Array.isArray(x)||x.length>0);
const canonical=x=>JSON.stringify(sort(x));
function sort(x){if(Array.isArray(x))return x.map(sort);if(x&&typeof x==='object')return Object.fromEntries(Object.keys(x).sort().map(k=>[k,sort(x[k])]));return x;}
async function sha(x){const bytes=new TextEncoder().encode(typeof x==='string'?x:canonical(x));if(!globalThis.crypto?.subtle)throw Error('当前浏览器不支持本地 SHA-256，请使用新版浏览器。');return [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');}
async function verifyPolicy(c){const v=copy(c);delete v.content_hash;return (await sha(v))===c.content_hash;}
function taskFor(d,c){const bound=c.runs.find(r=>r.id===d.run_id);return bound?{...bound,...(d.task||{})}:d.task;}
function s0(c,t){return (c.s0_required||[]).filter(k=>{const bits=k.split('.');let value=bits[0]==='run'?t:c;if(bits[0]==='run')bits.shift();for(const key of bits)value=value?.[key];return !present(value);}).concat(t&&!['behavior','result'].includes(t.mode)?['run.mode（无效）']:[]);}
function material(d){const v=copy(d);for(const k of ['decisions','candidates','snapshots','status'])delete v[k];return v;}
const fingerprint=d=>sha(material(d));
function activeDecisions(d,stage){return d.decisions.filter(x=>x.stage===stage&&!x.invalidated&&x.input_revision===d.revision);}
function review(d,id){return activeDecisions(d,'review').filter(x=>x.branch_id===id).at(-1);}
function allReviewed(d){return d.branches.length>0&&d.branches.every(b=>{const a=review(d,b.id);return a&&['keep','revise','exclude','gap'].includes(a.action)&&text(a.reason);});}
function latest(d,kind){return d.snapshots.filter(s=>s.audit_origin!=='external_history'&&s.kind===kind&&s.status==='frozen'&&s.input_revision===d.revision).at(-1);}
function critical(d){return d.gaps.filter(g=>g.critical&&g.status!=='closed');}
function originalKey(value){return String(value).replace(/#.*$/,'').replace(/^(?:https?:\/\/(?:dx\.)?doi\.org\/|doi:)/i,'').toLowerCase();}
function original(record){return originalKey(record.original_id||record.doi||(record.pmid?'pmid:'+record.pmid:null)||record.url||record.id);}
function budget(d,c){
 const b=c.budget_per_run, categories=Object.keys(c.accounting.s1_categories), q=Object.fromEntries(categories.map(k=>[k,0])), reads=new Set(), allReads=new Set(), targets={}, routes=new Set(),errors=[],screening=[],seenQueries=new Set();
 const rows=[...d.sources,...d.signals],records=new Map(rows.map(x=>[x.id,x])),originals=new Map(rows.map(x=>[original(x),x]));
 const resolve=id=>records.get(id)||originals.get(originalKey(id));
 for(const e of d.search_log){const level=e.stage||e.level;if(level==='S0')continue;if(!['S1','S2'].includes(level)){errors.push(e.id+'：阶段只允许 S0/S1/S2');continue;}
 const query=e.query??e.query_text, category=e.source_category??e.category_or_target_id, target=e.category_or_target_id||(typeof e.target==='object'?e.target?.id:e.target);
 const issued=text(query)&&e.status!=='planned'&&e.status!=='not_executed';
 if(issued){const key=level+'|'+(level==='S1'?category:target)+'|'+query.trim();if(seenQueries.has(key))errors.push(e.id+'：重复查询不能当作免费重试');seenQueries.add(key);}
 if(e.status==='access_blocked'||e.access_result==='access_blocked'||/ENOTFOUND|DNS.*fail|访问受阻|需要登录/.test(String(e.access_result)))routes.add(e.route);
 let ids=e.qualified_read_ids||e.consumption?.qualified_read_ids;
 if(!ids&&Array.isArray(e.qualified_reads))ids=e.qualified_reads;
 if(!ids&&Number(e.qualified_reads)>0){ids=e.source_ids||[];if(ids.length!==Number(e.qualified_reads))errors.push(e.id+'：合格深读数量须有相同数量的记录 ID');}
 ids=ids||[];
 for(const id of ids)if(!resolve(id))errors.push(e.id+'：合格深读引用不存在 '+id);
 const known=ids.map(resolve).filter(Boolean).map(original);
 if(level==='S1'){if(!(category in q))errors.push(e.id+'：未归属五类 S1 查询类别');else if(issued)q[category]++;known.filter(x=>!allReads.has(x)).forEach(x=>reads.add(x));}
 else{if(!text(target)){errors.push(e.id+'：S2 缺稳定目标');continue;}if(!targets[target])targets[target]={queries:0,reads:new Set()};if(issued)targets[target].queries++;known.filter(x=>!allReads.has(x)).forEach(x=>targets[target].reads.add(x));}
 known.forEach(x=>allReads.add(x));
 if(issued){const screened=typeof e.screened_hits==='number'&&Number.isFinite(e.screened_hits)?e.screened_hits:null;screening.push({id:e.id,returned_hits:e.returned_hits??e.hits??null,screened_hits:screened});if(screened!==null&&(screened<0||screened>b.hits_per_query))errors.push(e.id+'：实际筛读条数超配置上限');}
 }
 for(const [k,n] of Object.entries(q))if(n>b.s1_query_variants_per_source_category)errors.push(k+'：查询预算超限');
 if(reads.size>b.s1_qualified_deep_reads_total)errors.push('S1 共享合格深读预算超限');
 if(Object.keys(targets).length>b.s2_max_targets)errors.push('S2 目标数超限');
 for(const [k,v] of Object.entries(targets)){if(v.queries>b.s2_query_variants_per_target)errors.push(k+'：S2 查询超限');if(v.reads.size>b.s2_deep_reads_per_target)errors.push(k+'：S2 深读超限');}
 return {s1_queries:q,s1_qualified_reads:reads.size,s2_targets:Object.fromEntries(Object.entries(targets).map(([k,v])=>[k,{queries:v.queries,qualified_reads:v.reads.size}])),blocked_routes:[...routes],screening_observations:screening,screening_note:screening.some(x=>x.screened_hits===null)?'部分查询的实际筛读数量未知；预算算术未超限不能证明全部执行守约，须保留执行偏差。':'筛读数按原始记录核算；仍须结合执行偏差与访问停止记录判断。',errors};
}
function canRequest(d,c,request){const a=budget(d,c),b=c.budget_per_run, reasons=[...a.errors];if(a.blocked_routes.includes(request.route))reasons.push('此路线已访问受阻，必须停止');if(request.stage==='S1'){if(!(request.category in a.s1_queries))reasons.push('请选择已配置来源类别');else if(a.s1_queries[request.category]>=b.s1_query_variants_per_source_category)reasons.push('此类别查询预算已耗尽');if(a.s1_qualified_reads>=b.s1_qualified_deep_reads_total)reasons.push('共享深读预算已耗尽');}else if(request.stage==='S2'){if(!latest(d,'review')||!latest(d,'direction'))reasons.push('S2 必须先完成当前输入的审阅与方向冻结');const g=d.gaps.find(x=>x.id===request.gap_id&&x.status==='open');if(!g)reasons.push('S2 必须绑定仍开放的明确缺口');if(!text(request.target))reasons.push('S2 必须指定稳定目标');const t=a.s2_targets[request.target];if(!t&&Object.keys(a.s2_targets).length>=b.s2_max_targets)reasons.push('S2 目标数已耗尽');if(t?.queries>=b.s2_query_variants_per_target)reasons.push('目标查询预算已耗尽');if(t?.qualified_reads>=b.s2_deep_reads_per_target)reasons.push('目标深读预算已耗尽');}else reasons.push('不允许 S3 或未定义阶段');return {allowed:reasons.length===0,reasons};}
function sourceEligible(s,c){
 const q=s.quality;if(!['full_text','official_record'].includes(s.read_level)||!text(s.url)||!present(s.locator)||!q||q.fatal_flaw||s.fatal_flaw||!text(q.status)||/(unknown|unassessed|unscored|未评|未知|待评)/i.test(q.status))return false;
 const known=x=>present(x)&&!/(unknown|unassessed|unscored|未评|未知|待评)/i.test(JSON.stringify(x));
 if(q.status==='guidance_assessed')return [q.publisher_identity,q.development_method_and_evidence_basis||q.method_basis,q.population_and_scope||q.population_limits,q.limitations||s.limitations].every(known);
 const paper=c?.evidence?.paper;if(!paper)return false;
 const values={method:q.method,independence:q.independence,source_quality:q.source_quality??q.source,author_fit:q.author_fit??q.author};
 if(!Object.entries(paper.weights).every(([key,max])=>typeof values[key]==='number'&&Number.isFinite(values[key])&&values[key]>=0&&values[key]<=max))return false;
 return typeof q.total==='number'&&Number.isFinite(q.total)&&q.total===Object.values(values).reduce((sum,n)=>sum+n,0)&&q.total>=paper.thresholds.medium_min&&q.total<=paper.thresholds.maximum;
}
function gates(d,a,c){const science=[],interest=[];const branches=(a.branch_ids||[]).map(id=>d.branches.find(b=>b.id===id));if(!allReviewed(d)||!latest(d,'review'))science.push('逐支审阅尚未冻结');if(a.invalidated||!branches.length||branches.some(b=>!b||b.coverage!=='covered'||review(d,b.id)?.action!=='keep'))science.push('所选分支未完整覆盖并保留');if(critical(d).length){science.push('仍有关键缺口');interest.push('仍有关键缺口');}
 if(a.science_gate?.strength!=='strong'||!present(a.science_gate?.reasons))science.push('缺少有依据的强科学评估');
 const claims=(a.claim_ids||[]).map(id=>d.claims.find(x=>x.id===id));if(!claims.length||claims.some(cl=>!cl||!(cl.source_refs||[]).some(r=>r.role==='support'&&sourceEligible(d.sources.find(s=>s.id===r.source_id)||{},c))))science.push('关键主张缺可评估的直接来源');
 const signals=(a.signal_ids||[]).map(id=>d.signals.find(x=>x.id===id));if(!['high','medium'].includes(a.interest_gate?.level)||!present(a.interest_gate?.reasons)||!text(a.interest_gate?.comparison_basis))interest.push('缺少中/高兴趣的可比材料与理由');if(!signals.length||signals.some(s=>!s||s.verification_level!=='platform_page'||s.status!=='available'||!text(s.url)||!present(s.account)||!present(s.published_at)||!present(s.observed_at)||!Object.values(s.metrics||{}).some(n=>typeof n==='number'&&n>=0)))interest.push('缺少可核验平台原页及实际观测');
 if(d.demo||d.test_fixture){science.push('演示/验收数据不能正式合格');interest.push('演示/验收数据不能正式合格');}
 return {science:{pass:!science.length,reasons:science},interest:{pass:!interest.length,reasons:interest},formal:!science.length&&!interest.length};}
function validate(d,c,structureOnly=false){const errors=[],add=(ok,m)=>{if(!ok)errors.push(m);};
 add(d&&typeof d==='object'&&!Array.isArray(d),'研究记录必须是对象');if(errors.length)return errors;
 for(const k of ['schema_version','revision','run_id','mode','config_ref','generated_at','status','demo','knowledge_base'])add(k in d,'缺少顶层字段 '+k);
 add(d.schema_version==='0.1','仅支持唯一契约 v0.1');add(text(d.revision)&&text(d.run_id),'运行 ID/版本不能为空');add(typeof d.demo==='boolean','demo 必须明确为布尔值');add(['behavior','result'].includes(d.mode),'无效模式');
 add(d.config_ref?.sha256===c.content_hash&&d.config_ref?.revision===c.revision,'策略版本或 canonical 哈希不匹配');
 for(const k of collections)add(Array.isArray(d[k]),k+' 必须为数组');if(collections.some(k=>!Array.isArray(d[k])))return errors;
 const t=taskFor(d,c);add(!!t,'任务不在策略中且缺少本次 task');if(t){s0(c,t).forEach(k=>errors.push('S0 缺项 '+k));add(t.id===d.run_id&&t.mode===d.mode,'task 与研究运行 ID/模式不一致');}
 if(collections.some(k=>d[k].some(row=>!row||typeof row!=='object'||Array.isArray(row)))){errors.push('集合含非对象记录');return errors;}
 const ids=new Map();for(const k of collections)for(const row of d[k]){if(!row||typeof row!=='object'){errors.push(k+' 包含无效记录');continue;}add(text(row.id),k+' 缺记录 ID');add(!ids.has(row.id),'重复 ID '+row.id);ids.set(row.id,k);add(row.run_id===d.run_id,row.id+' 缺少/错误 run_id');add(text(row.revision),row.id+' 缺 revision');add(typeof row.demo==='boolean',row.id+' 缺 demo');}
 const history=d.historical_decisions||[];add(Array.isArray(history),'historical_decisions 必须为数组');const historicalIds=new Set();if(Array.isArray(history))for(const row of history){add(row&&text(row.id)&&row.run_id===d.run_id,'历史决定身份无效');if(row){add(!ids.has(row.id)&&!historicalIds.has(row.id),'历史决定 ID 重复 '+row.id);historicalIds.add(row.id);}}
 const refTargets={source_ids:'sources',support_source_ids:'sources',counter_source_ids:'sources',closure_source_ids:'sources',claim_ids:'claims',branch_ids:'branches',parent_ids:'branches',related_ids:'branches',related_branch_ids:'branches',signal_ids:'signals',review_decision_ids:'decisions',decision_ids:'decisions',candidate_ids:'candidates',gap_ids:'gaps'};
 for(const k of collections)for(const row of d[k]){for(const [field,kind] of Object.entries(refTargets)){if(row[field]!==undefined){add(Array.isArray(row[field]),row.id+' 的 '+field+' 必须为数组');if(Array.isArray(row[field]))for(const id of row[field])add(ids.get(id)===kind||(k==='snapshots'&&row.audit_origin==='external_history'&&kind==='decisions'&&historicalIds.has(id)),row.id+' 引用失效 '+field+': '+id);}}
 for(const g of ['science_gate','interest_gate'])for(const id of row[g]?.gap_ids||[])add(ids.get(id)==='gaps',row.id+' 门槛缺口引用失效 '+id);
 if(row.url!==undefined&&row.url!==null)add(/^https?:\/\//i.test(row.url),row.id+' 原始链接必须为 http(s)');}
 for(const s of d.sources){for(const k of ['title','url','authors','published_at','accessed_at','source_type','language','geography','access_status','read_level','locator','excerpt_or_summary','quality','limitations','missing_reason'])add(k in s,s.id+' 缺 '+k);if([s.title,s.url,s.authors,s.published_at,s.locator].some(x=>x===null))add(present(s.missing_reason),s.id+' 未知字段缺原因');}
 for(const cl of d.claims){add(text(cl.text),cl.id+' 缺主张正文');add(Array.isArray(cl.source_refs),cl.id+' 缺来源引用数组');for(const r of Array.isArray(cl.source_refs)?cl.source_refs:[]){add(ids.get(r.source_id)==='sources',cl.id+' 来源引用失效 '+r.source_id);add(['support','counter','limit'].includes(r.role),cl.id+' 来源角色无效');add(r&&'locator' in r,cl.id+' 引用缺定位字段');}}
 for(const b of d.branches){for(const k of ['title','definition','chain_position','upstream','downstream','time_scale','population','modifiers','exclusions','claim_ids','source_ids','coverage','preliminary_judgment','priority_rationale','gaps'])add(k in b,b.id+' 缺 '+k);}
 for(const g of d.gaps){add(['open','closed'].includes(g.status),g.id+' 缺口状态无效');if(g.status==='closed')add((g.closure_source_ids||[]).length>0||text(g.closure_note),g.id+' 关闭缺少证据或范围排除理由');}
 for(const a of d.decisions){add(actors.includes(a.actor_type)&&text(a.actor_label),a.id+' 决定者身份未明确');add(text(a.reason)&&text(a.input_revision)&&text(a.decided_at),a.id+' 决定缺理由/输入版本/时间');if(a.branch_id)add(ids.get(a.branch_id)==='branches',a.id+' 分支不存在');if(a.candidate_id)add(ids.get(a.candidate_id)==='candidates',a.id+' 方向不存在');}
 errors.push(...budget(d,c).errors);
 for(const a of d.candidates){for(const k of ['branch_ids','claim_ids','signal_ids','review_decision_ids'])add(Array.isArray(a[k]),a.id+' 缺数组 '+k);add(a.science_gate&&typeof a.science_gate==='object'&&a.interest_gate&&typeof a.interest_gate==='object',a.id+' 缺独立双门槛记录');if(!structureOnly&&a.status==='formal')add(gates(d,a,c).formal,a.id+' 越过正式双门槛');}
 if(!structureOnly&&d.status==='frozen')add(!!latest(d,'package'),'状态声称已冻结但没有有效最终包');
 return errors;
}
function invalidate(d,from,reason){const kinds=from==='review'?['review','direction','package']:['direction','package'];for(const s of d.snapshots)if(kinds.includes(s.kind)&&s.status==='frozen'){s.status='invalidated';s.invalidation_reason=reason;}for(const a of d.decisions)if(a.stage==='direction')a.invalidated=true;for(const a of d.candidates)if(a.status==='formal')a.status='draft';d.status=from==='review'?'research_draft':'reviewed';}
function id(d,letter){const used=new Set([...collections.flatMap(k=>d[k].map(x=>x.id)),...(d.historical_decisions||[]).map(x=>x.id)]);let n=1;while(used.has(d.run_id+'-'+letter+String(n).padStart(3,'0')))n++;return d.run_id+'-'+letter+String(n).padStart(3,'0');}
function base(d,letter){return {id:id(d,letter),run_id:d.run_id,revision:d.revision,demo:d.demo};}
function actorCheck(a){if(!actors.includes(a.actor_type)||!text(a.actor_label))throw Error('请选择决定者身份并填写姓名/标识。');}
async function saveReview(d,c,rows,a){actorCheck(a);if(rows.some(x=>!text(x.reason)||!['keep','revise','gap','exclude'].includes(x.action)))throw Error('每个分支必须有处理方式和理由。');if(rows.length!==d.branches.length||new Set(rows.map(x=>x.branch_id)).size!==d.branches.length||rows.some(x=>!d.branches.some(b=>b.id===x.branch_id)))throw Error('须逐一覆盖本次全部分支。');invalidate(d,'review','分支审阅已修改，后续决定须重审');const hash=await fingerprint(d);for(const row of rows)d.decisions.push({...base(d,'D'),...a,qualification:a.qualification||null,stage:'review',decided_at:new Date().toISOString(),input_revision:d.revision,input_content_sha256:hash,...row});return d;}
function makeCandidates(d){if(!latest(d,'review')||!allReviewed(d))throw Error('先完成并冻结逐支审阅。');invalidate(d,'direction','方向评估需重新确认');for(const b of d.branches){if(review(d,b.id).action==='exclude')continue;if(d.candidates.some(a=>a.branch_ids?.length===1&&a.branch_ids[0]===b.id&&a.input_revision===d.revision&&!a.invalidated))continue;d.candidates.push({...base(d,'A'),input_revision:d.revision,title:b.title,branch_ids:[b.id],claim_ids:b.claim_ids||[],signal_ids:[],review_decision_ids:[review(d,b.id).id],science_gate:{status:'unknown',strength:'unknown',reasons:[],gap_ids:critical(d).map(g=>g.id)},interest_gate:{status:'unknown',level:'unknown',reasons:[],comparison_basis:null,gap_ids:critical(d).map(g=>g.id)},allowed_expression:b.allowed_expression||null,forbidden_expression:b.forbidden_expression||null,status:'draft'});}return d;}
async function snapshot(d,c,kind,a,selection=null){actorCheck(a);const errors=validate(d,c);if(errors.length)throw Error(errors.join('\n'));const mh=await fingerprint(d);if(!allReviewed(d))throw Error('逐支审阅尚未完成。');if(kind==='review'){invalidate(d,'review','新审阅冻结替代旧审阅');}
 else if(!latest(d,'review'))throw Error('需要有效的审阅冻结。');
 if(kind==='direction'){if(!selection||!text(selection.reason))throw Error('方向选择须有理由。');const ca=d.candidates.find(x=>x.id===selection.candidate_id);if(!ca)throw Error('方向不存在');if(selection.classification==='formal'&&!gates(d,ca,c).formal)throw Error('正式双门槛未通过，只可明确冻结含缺口试运行。');if(!['formal','trial_with_gaps'].includes(selection.classification))throw Error('须明确正式或含缺口试运行');invalidate(d,'direction','新方向冻结替代旧方向');ca.status=selection.classification==='formal'?'formal':'draft';d.decisions.push({...base(d,'D'),...a,qualification:a.qualification||null,stage:'direction',action:'confirm',candidate_id:ca.id,reason:selection.reason,classification:selection.classification,required_changes:null,decided_at:new Date().toISOString(),input_revision:d.revision,input_content_sha256:mh});}
 const parent=kind==='direction'?latest(d,'review'):kind==='package'?latest(d,'direction'):null;if(kind==='package'&&!parent)throw Error('需要有效的方向冻结。');if(kind==='package'){for(const old of d.snapshots)if(old.kind==='package'&&old.status==='frozen'){old.status='invalidated';old.invalidation_reason='新最终包替代旧包';}selection=copy(parent.content.selection);const ca=d.candidates.find(x=>x.id===selection.candidate_id);if(selection.classification==='formal'&&!gates(d,ca,c).formal)throw Error('正式门槛已失效');}
 const body={kind,material:material(d),decisions:copy(d.decisions.filter(x=>!x.invalidated)),candidates:copy(d.candidates),selection:copy(selection),budget:budget(d,c),stop_reasons:d.search_log.filter(x=>x.stop_reason).map(x=>({id:x.id,reason:x.stop_reason})),parent_snapshot_id:parent?.id||null,parent_content_sha256:parent?.content_sha256||null,knowledge_base_attachment:kind==='package'?{status:'candidate_only_not_ingested',claim_ids:d.claims.map(x=>x.id),knowledge_base:copy(d.knowledge_base)}:null};
 const s={...base(d,'F'),kind,created_at:new Date().toISOString(),...a,input_revision:d.revision,input_content_sha256:mh,config_sha256:c.content_hash,content_sha256:await sha(body),decision_ids:d.decisions.filter(x=>!x.invalidated).map(x=>x.id),candidate_ids:d.candidates.map(x=>x.id),status:'frozen',invalidation_reason:null,classification:selection?.classification||'review_record',content:body};d.snapshots.push(s);d.status=kind==='review'?'reviewed':kind==='direction'?'directions_confirmed':'frozen';return s;}
async function audit(d,c){
 const errors=validate(d,c,true),stale=[];if(!(await verifyPolicy(c)))errors.push('内嵌策略 canonical 哈希校验失败');if(errors.length)return {errors,stale,fingerprint:null};
 const mh=await fingerprint(d);let staleReview=false,staleDirection=false,changedMaterial=false;
 const currentReview=activeDecisions(d,'review'),currentDirection=activeDecisions(d,'direction');
 for(const s of d.snapshots){
  if(s.audit_origin==='external_history'){if(!s.audit_payload_json||await sha(s.audit_payload_json)!==s.content_sha256)errors.push(s.id+' 外部审计内容哈希不一致');else {const old=JSON.parse(s.audit_payload_json);if(old.run_id!==d.run_id||old.config_ref?.sha256!==c.content_hash)errors.push(s.id+' 外部审计绑定不一致');}continue;}
  if(!s.content||await sha(s.content)!==s.content_sha256){errors.push(s.id+' 快照内容哈希不一致');continue;}
  if(s.status!=='frozen')continue;
  const inputChanged=s.config_sha256!==c.content_hash||s.input_revision!==d.revision||s.input_content_sha256!==mh;
  const reviewChanged=s.kind==='review'&&canonical(s.content.decisions.filter(x=>x.stage==='review'))!==canonical(currentReview);
  const directionChanged=s.kind==='direction'&&(canonical(s.content.decisions.filter(x=>x.stage==='direction'))!==canonical(currentDirection)||canonical(s.content.candidates)!==canonical(d.candidates));
  const parent=s.kind==='review'?null:d.snapshots.find(x=>x.id===s.content.parent_snapshot_id);
  const parentChanged=s.kind!=='review'&&(!parent||parent.status!=='frozen'||parent.content_sha256!==s.content.parent_content_sha256);
  if(inputChanged||reviewChanged||directionChanged||parentChanged){stale.push(s.id);if(inputChanged||reviewChanged)staleReview=true;else staleDirection=true;if(inputChanged)changedMaterial=true;}
 }
 for(const a of d.decisions)if(a.input_revision!==d.revision||(a.input_content_sha256&&a.input_content_sha256!==mh)||(changedMaterial&&a.stage==='review'))a.invalidated=true;
 if(staleReview||staleDirection)invalidate(d,staleReview?'review':'direction','材料、决定或前序冻结已变化，必须重新审阅确认');
 if(changedMaterial)for(const a of d.candidates)a.invalidated=true;
 for(const s of d.snapshots)if(stale.includes(s.id)){s.status='invalidated';s.invalidation_reason='输入、决定或父快照已失效';}
 return {errors:[...new Set([...errors,...validate(d,c)])],stale:[...new Set(stale)],fingerprint:mh};
}
function create(c,t,path){const missing=s0(c,t);if(missing.length)throw Error('S0 缺项：'+missing.join('、'));return {schema_version:'0.1',revision:t.id+'-r1',run_id:t.id,mode:t.mode,task:copy(t),demo:false,config_ref:{path,revision:c.revision,sha256:c.content_hash},generated_at:new Date().toISOString(),status:'research_draft',...Object.fromEntries(collections.map(k=>[k,[]])),knowledge_base:{status:'not_researched',interface:null,version:null,queried_at:null,queries:null,matched_ids:null,missing_reason:'尚未执行知识库对照'},stage_notes:{research:'S0 已校验，尚未研究',decisions:'尚未进入审阅',candidates:'尚未进入方向',snapshots:'尚未冻结'}};}
const api={collections,actors,copy,canonical,sha,verifyPolicy,taskFor,s0,material,fingerprint,review,allReviewed,latest,critical,budget,canRequest,gates,validate,invalidate,base,saveReview,makeCandidates,snapshot,audit,create};root.WorkbenchCore=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);

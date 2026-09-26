const {chromium}=require('/Users/chengyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),crypto=require('crypto'),{pathToFileURL}=require('url');
const P='/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类',W=path.join(P,'02_工作区/Matt执行'),D=path.join(P,'03_交付物/护肤科普研究首版'),T=path.join(P,'02_工作区/99_临时/2026-09-26_UI正式接入');
const C=require(path.join(D,'workbench-core.js')),read=p=>JSON.parse(fs.readFileSync(p)),sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const report={scope:'仅BEH r2修正表达、受影响引用/冻结及可见内容和同版导出；RES及既有历史/预算/UI证据复用。',started:new Date().toISOString(),checks:[],exports:[],manifest:{},freeze_binding:[],errors:[],network:[]};
const check=x=>{report.checks.push(x);console.log('PASS '+x)};
(async()=>{
 let browser;
 try{
  const base=read(path.join(T,'closedloop-beh-r2-baseline.json')),src=path.join(W,'research-SK-BEH-001.json'),d=read(src),old=read(base.backups[src]),out=read(path.join(D,'SK-BEH-001.json')),policy=read(path.join(W,'run-config.json'));
  for(const [p,h] of Object.entries(base.protected))assert.equal(sha(p),h,p);
  for(const [p,b] of Object.entries(base.backups))assert.equal(sha(b),base.baseline[p],b);
  check('RES字节、获取成果、全部BEH既有物理冻结不变；r1四份备份与修正前相符');
  for(const k of ['sources','claims','signals','budget','search_log','knowledge_base'])assert.deepEqual(d[k],old[k],k);
  for(const b of d.branches){const prev=old.branches.find(x=>x.id===b.id);for(const k of ['claim_ids','source_ids','definition','preliminary_judgment','priority_rationale'])assert.deepEqual(b[k],prev[k]);assert.deepEqual(b.allowed_expression,[b.solution_path]);}
  const expressions=d.branches.map(b=>b.solution_path);assert.equal(new Set(expressions).size,4);
  for(const a of d.candidates){assert.deepEqual(a.allowed_expression,a.branch_ids.map(i=>d.branches.find(b=>b.id===i).solution_path));assert.equal(new Set(a.allowed_expression).size,a.allowed_expression.length);assert.equal(a.formal_admission,false);}
  assert.deepEqual(d.package.expression_boundaries.allowed,d.package.knowledge_chain.map(x=>d.branches.find(b=>b.id===x.branch_id).solution_path));assert.equal(new Set(d.package.expression_boundaries.allowed).size,4);
  for(const x of d.package.knowledge_chain)assert.equal(x.solution_path,d.branches.find(b=>b.id===x.branch_id).solution_path);
  check('四类有限表达各不相同，分支→候选→包一致；来源/主张/引用/预算/兴趣及准入未提级');
  for(const decision of d.decisions){assert.equal(decision.input_revision,d.revision);assert.equal(decision.actor_type,'controller_delegate');assert.ok(decision.id.includes('-CL2-D-'));}
  for(const decision of old.decisions)assert.ok(d.historical_decisions.some(x=>C.canonical(x)===C.canonical(decision)));
  for(const k of ['branches','decisions','candidates','package'])assert.deepEqual(out[k],d[k],k);
  let parent=null;
  for(const s of d.snapshots.slice(-3)){
   const wrapper=read(s.audit_path),p=wrapper.payload;assert.equal(await C.sha(p),s.content_sha256);assert.equal(wrapper.payload_sha256,s.content_sha256);assert.equal(p.revision,d.revision);assert.equal(p.freeze_stage.parent_snapshot_id,parent);assert.equal(s.parent_snapshot_id,parent);assert.deepEqual(p.branches,d.branches);
   if(s.kind==='review'){assert.deepEqual(p.candidates,[]);assert.equal(p.package,undefined);assert.ok(p.decisions.every(x=>x.stage==='review'));}else{assert.deepEqual(p.candidates,d.candidates);assert.deepEqual(p.package,d.package);assert.deepEqual(p.decisions,d.decisions);}
   parent=s.id;report.freeze_binding.push({id:s.id,path:s.audit_path,file_sha256:sha(s.audit_path),payload_sha256:s.content_sha256});
  }
  assert.ok(d.snapshots.slice(-6,-3).every(s=>s.status==='invalidated'&&s.input_revision==='SK-BEH-001-closedloop-r1'));
  assert.deepEqual(C.validate(out,policy),[]);const audit=await C.audit(out,policy);assert.deepEqual(audit.errors,[]);assert.deepEqual(audit.stale,[]);report.core={errors:[],stale:[],fingerprint:audit.fingerprint};
  check('r2审阅/方向/包与当版表达和代理决定绑定，三份新冻结哈希及父链成立；引用审计通过');
  browser=await chromium.launch({headless:true});const context=await browser.newContext({viewport:{width:1365,height:900},offline:true,acceptDownloads:true}),page=await context.newPage();page.setDefaultTimeout(10000);page.on('pageerror',e=>report.errors.push(e.message));page.on('request',r=>{if(/^https?:/.test(r.url()))report.network.push(r.url());});
  await page.goto(pathToFileURL(path.join(D,'index.html')).href);await page.locator('body[data-ready="true"]').waitFor();const boot=await page.evaluate(()=>JSON.parse(document.querySelector('#boot-data').textContent));const run=boot.runs.find(x=>x.run_id==='SK-BEH-001');assert.deepEqual(run,out);await page.locator('#task-switch').selectOption(String(boot.runs.indexOf(run)));
  const nav=async x=>page.locator('#nav [data-go="'+x+'"]').click();await nav('review');
  for(const b of run.branches){await page.locator('[data-branch="'+b.id+'"]').click();await page.getByRole('tab',{name:'适用边界',exact:true}).click();assert.ok((await page.locator('#panel-branchTab').innerText()).includes(b.solution_path));await page.getByRole('tab',{name:'审阅记录',exact:true}).click();const text=await page.locator('#panel-branchTab').innerText();assert.ok(text.includes(b.review_decision_ids[0])&&text.includes(b.solution_path));}
  check('BEH四分支具体表达及r2代理审阅在现有页面可见');
  await nav('directions');for(const a of run.candidates){await page.locator('[data-candidate="'+a.id+'"]').click();const text=await page.locator('#panel-directionTab .detail').innerText();for(const e of a.allowed_expression)assert.ok(text.includes(e));}
  await nav('delivery');const text=await page.locator('#content').innerText();for(const e of run.package.expression_boundaries.allowed)assert.ok(text.includes(e));assert.ok(text.includes('当前输入仍需重新确认'));check('三个候选和研究包显示各自有限表达，保留重新确认门槛');
  const download=async(action,name)=>{const wait=page.waitForEvent('download');await page.locator('[data-action="'+action+'"]').last().click();const dl=await wait,p=path.join(T,name);await dl.saveAs(p);report.exports.push(p);return p;};
  const jp=await download('export-json','closedloop-r2-verify-SK-BEH-001.json');assert.deepEqual(read(jp),run);const hp=await download('export-html','closedloop-r2-verify-SK-BEH-001.html');const other=await context.newPage();await other.goto(pathToFileURL(hp).href);await other.locator('body[data-ready="true"]').waitFor();const eb=await other.evaluate(()=>JSON.parse(document.querySelector('#boot-data').textContent));assert.deepEqual(eb.runs,[run]);assert.ok((await other.locator('#content').innerText()).includes(run.revision));await other.close();
  await page.getByRole('tab',{name:/版本历史/}).click();const hist=await page.locator('.history').innerText();for(const s of run.snapshots.slice(-3))assert.ok(hist.includes(s.id));check('BEH浏览器JSON/HTML同为r2且可重开，三份新冻结在版本历史可见');
  assert.deepEqual(report.errors,[]);assert.deepEqual(report.network,[]);
  for(const p of [src,path.join(D,'SK-BEH-001.json'),path.join(D,'SK-BEH-001.html'),path.join(D,'index.html'),...report.exports])report.manifest[p]=sha(p);
  report.reused_evidence=['closedloop-data-validation.json：RES内容、旧冻结/备份、来源边界、预算','closedloop-ui-validation.json：RES全部及未变BEH来源/缺口/获取详情、中文摘要和UI行为'];report.status='passed';
 }catch(e){report.status='failed';report.failure=e.stack;console.error(e);process.exitCode=1;}finally{report.finished=new Date().toISOString();fs.writeFileSync(path.join(T,'closedloop-beh-r2-validation.json'),JSON.stringify(report,null,2)+'\n');if(browser)await browser.close();}
})();

const {chromium}=require('/Users/chengyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{pathToFileURL}=require('url');
const P='/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类';
const D=path.join(P,'03_交付物/护肤科普研究首版'),T=path.join(P,'02_工作区/99_临时/2026-09-26_UI正式接入');
const report={started:new Date().toISOString(),scope:'仅改写的分支/来源/包、获取中文观点、缺口与同版JSON/HTML；不改业务数据，不提交页面决定，无网络。',runtime_reason:'Playwright连接器无法访问本机file路径（ERR_FILE_NOT_FOUND），使用已有本机Playwright。',checks:[],errors:[],network:[],exports:[]};
const check=x=>{report.checks.push(x);console.log('PASS '+x)};
(async()=>{
 const browser=await chromium.launch({headless:true});const context=await browser.newContext({viewport:{width:1365,height:900},offline:true,acceptDownloads:true});const page=await context.newPage();page.setDefaultTimeout(10000);
 page.on('pageerror',e=>report.errors.push(e.message));page.on('console',m=>{if(m.type()==='error')report.errors.push(m.text())});page.on('request',r=>{if(/^https?:/.test(r.url()))report.network.push(r.url())});
 const nav=async x=>page.locator('#nav [data-go="'+x+'"]').click();
 const close=async()=>{await page.locator('#dialog').getByRole('button',{name:'关闭详情',exact:true}).click()};
 const download=async(action,name)=>{const wait=page.waitForEvent('download');await page.locator('[data-action="'+action+'"]').last().click();const dl=await wait;const p=path.join(T,name);await dl.saveAs(p);report.exports.push(p);return p};
 try{
  await page.goto(pathToFileURL(path.join(D,'index.html')).href);await page.locator('body[data-ready="true"]').waitFor();
  const boot=await page.evaluate(()=>JSON.parse(document.querySelector('#boot-data').textContent));assert.equal(boot.app_version,'SK-WORKBENCH-20260926-r5');assert.equal(boot.runs.length,2);
  const acq=JSON.parse(fs.readFileSync(path.join(D,'acquisition-results.json')));check('当前r5入口加载两份closedloop-r1研究');
  for(const id of ['SK-RES-001','SK-BEH-001']){
   const run=boot.runs.find(x=>x.run_id===id);assert.equal(run.revision,id+'-closedloop-r1');await page.locator('#task-switch').selectOption(String(boot.runs.indexOf(run)));await nav('review');
   assert.equal(await page.locator('[data-branch]').count(),run.branches.length);
   for(const b of run.branches){
    await page.locator('[data-branch="'+b.id+'"]').click();await page.getByRole('tab',{name:'判断概览',exact:true}).click();const body=await page.locator('#panel-branchTab').innerText();
    for(const k of ['preliminary_judgment','definition','priority_rationale','chain_position'])assert.ok(body.includes(b[k]),b.id+' '+k+'未在概览完整显示');
    await page.getByRole('tab',{name:'审阅记录',exact:true}).click();const rec=await page.locator('#panel-branchTab').innerText();assert.ok(rec.includes(b.review_decision_ids[0])&&rec.includes('controller_delegate'));
   }check(id+' 所有分支的地图、判断、优先级及当版代理审阅可见');
   const sourceId=id==='SK-RES-001'?'RES-S03':'SK-BEH-001-S006';const branch=run.branches.find(b=>b.source_ids.includes(sourceId));await page.locator('[data-branch="'+branch.id+'"]').click();await page.getByRole('tab',{name:'主张与证据',exact:true}).click();await page.locator('[data-detail="sources"][data-id="'+sourceId+'"]').first().click();
   const source=run.sources.find(s=>s.id===sourceId),detail=await page.locator('#dialog').innerText();
   for(const v of (Array.isArray(source.excerpt_or_summary)?source.excerpt_or_summary:[source.excerpt_or_summary]))assert.ok(detail.includes(v));
   if(id==='SK-RES-001'){assert.ok(detail.includes('≤1')&&detail.includes('≥1')&&detail.includes('仍null'));}await close();check(id+' 方法摘要/来源定位和局限在详情可读');
   await nav('directions');assert.equal(await page.locator('[data-candidate]').count(),run.candidates.length);await page.getByRole('tab',{name:/待补证/}).click();const gap=id==='SK-RES-001'?'RES-G07':'SK-BEH-001-G011';await page.getByLabel('搜索待补证项',{exact:true}).fill(gap);await page.locator('[data-detail="gaps"][data-id="'+gap+'"]').click();const gd=await page.locator('#dialog').innerText();assert.ok(gd.includes(id==='SK-RES-001'?'归账未核实':'旧G010'));await close();check(id+' 新关键缺口可查询并查看完整要求');
   await nav('delivery');const content=await page.locator('#content').innerText();assert.ok(content.includes(run.package.synthesis));for(const x of run.package.knowledge_chain)assert.ok(content.includes(x.title)&&content.includes(x.content));assert.ok(content.includes('当前输入仍需重新确认'));check(id+' 当前包显示改写解释顺序，保留重确认门槛');
   const j=await download('export-json','closedloop-verify-'+id+'.json');const exported=JSON.parse(fs.readFileSync(j));assert.deepEqual(exported,run);
   const h=await download('export-html','closedloop-verify-'+id+'.html');const other=await context.newPage();other.on('pageerror',e=>report.errors.push(e.message));await other.goto(pathToFileURL(h).href);await other.locator('body[data-ready="true"]').waitFor();const eb=await other.evaluate(()=>JSON.parse(document.querySelector('#boot-data').textContent));assert.deepEqual(eb.runs,[exported]);assert.ok((await other.locator('#content').innerText()).includes(run.revision));await other.close();check(id+' 浏览器导出JSON与HTML保持同版，导出HTML可直接重开');
   await page.getByRole('tab',{name:/版本历史/}).click();const hist=await page.locator('.history').innerText();for(const s of run.snapshots.slice(-3))assert.ok(hist.includes(s.id));check(id+' 六阶段新留档中的三份在版本历史可见');
   await nav('evidence');await page.getByRole('tab',{name:/获取成果/}).click();
   if(id==='SK-RES-001'){
    const video=acq.items.find(x=>x.kind==='video').video,summary=page.getByRole('region',{name:'视频中文摘要',exact:true});assert.ok(await summary.isVisible());assert.equal(await summary.locator('p').textContent(),video.content_analysis.overview);
    await page.getByRole('button',{name:'查看观点与字幕 ↗',exact:true}).click();assert.equal(await page.getByLabel('选择查看内容').inputValue(),'summary');assert.ok((await page.locator('#video-content').innerText()).includes(video.content_analysis.overview));await page.getByLabel('选择查看内容').selectOption('analysis');assert.ok((await page.locator('#video-content').innerText()).includes('本轮已作为同源传播材料'));await page.getByLabel('选择查看内容').selectOption('transcript');assert.ok((await page.locator('#video-content').innerText()).length>100);await close();check('结果型中文摘要、作者观点与AI分析分开显示，字幕可读');
   }else{await page.getByRole('button',{name:'查看详情 ↗',exact:true}).click();assert.ok((await page.locator('#dialog').innerText()).includes('不能推断所有渠道'));await close();check('行为型无OA获取限制保留');}
  }
  assert.deepEqual(report.errors,[]);assert.deepEqual(report.network,[]);check('无页面错误和自动网络请求');report.status='passed';
 }catch(e){report.status='failed';report.failure=e.stack;console.error(e);process.exitCode=1;}finally{report.finished=new Date().toISOString();fs.writeFileSync(path.join(T,'closedloop-ui-validation.json'),JSON.stringify(report,null,2)+'\n');await browser.close();}
})();

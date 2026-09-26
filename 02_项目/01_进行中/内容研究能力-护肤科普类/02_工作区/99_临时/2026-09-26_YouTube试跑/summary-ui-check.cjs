const {chromium}=require('/Users/chengyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{pathToFileURL}=require('url');
const T=__dirname,P=path.resolve(T,'../../..'),D=path.join(P,'03_交付物/护肤科普研究首版');
const source=JSON.parse(fs.readFileSync(path.join(D,'acquisition-results.json'))),video=source.items.find(x=>x.kind==='video'),analysis=video.video.content_analysis;
const result={started:new Date().toISOString(),version:'SK-WORKBENCH-20260926-r4',fallback:'Browser plugin unavailable; existing Playwright runtime used.',scope:'Chinese summary and analysis defaults, original subtitle switching, metadata access, associated signal, JSON/HTML exports, desktop/390px; prior unaffected r3 results reused.',checks:[],errors:[],requests:[]};
const check=name=>{result.checks.push(name);console.log('PASS '+name)};
(async()=>{
 const browser=await chromium.launch({headless:true});
 const context=await browser.newContext({viewport:{width:1365,height:900},acceptDownloads:true});
 context.on('page',p=>{p.setDefaultTimeout(8000);p.on('pageerror',e=>result.errors.push(e.message));p.on('console',m=>{if(m.type()==='error')result.errors.push(m.text())});p.on('request',r=>{if(/^https?:/.test(r.url()))result.requests.push(r.url())})});
 const page=await context.newPage();
 const close=async p=>p.getByRole('button',{name:'关闭详情',exact:true}).click();
 const evidence=async p=>{await p.locator('#nav [data-go="evidence"]').click();await p.getByRole('tab',{name:/获取成果/}).click()};
 const open=async p=>p.getByRole('button',{name:video.title,exact:true}).click();
 const ready=async(p,file)=>{await p.goto(pathToFileURL(file).href);await p.locator('body[data-ready="true"]').waitFor()};
 const summary=async p=>{
  assert.equal(await p.getByLabel('选择查看内容').inputValue(),'summary');
  const region=p.getByRole('region',{name:'中文概要与核心观点',exact:true});
  const text=await region.textContent();assert.ok(text.includes(analysis.overview));assert.ok(text.includes(analysis.interpretation));assert.ok(text.includes(analysis.care_boundary));
  for(const item of analysis.key_points){assert.ok(text.includes(item.title));assert.ok(text.includes(item.text));assert.equal(await region.getByRole('link',{name:`在原视频核对：${item.title}（${item.source_label}）`}).getAttribute('href'),video.video.url+'&t='+item.start_seconds+'s')}
  assert.match(text,/核心观点 · 原视频/);assert.match(text,/内容解读 · AI 分析/);
  const box=await region.evaluate(e=>({height:e.clientHeight,scroll:e.scrollHeight,overflow:getComputedStyle(e).overflowY}));assert.ok(box.height<=360&&box.scroll>box.height&&box.overflow==='auto');
 };
 const download=async(name,button)=>{const event=page.waitForEvent('download');await page.getByRole('button',{name:button,exact:true}).click();const file=await event;const target=path.join(T,'summary-roundtrip-'+name);await file.saveAs(target);return target};
 try{
  await ready(page,path.join(D,'index.html'));await page.locator('#task-switch').selectOption('1');await evidence(page);
  const row=page.locator('.data-row').filter({hasText:video.id});assert.match(await row.innerText(),/含中文概要与分析/);assert.match(await row.innerText(),/这条视频讲如何/);await open(page);await summary(page);
  await page.screenshot({path:path.join(T,'summary-desktop.png')});
  check('结果型视频默认呈现中文全片概要、四组原视频观点及 AI 解读，原视频时间入口正确');
  await page.getByLabel('选择查看内容').selectOption('analysis');const analysisText=await page.getByRole('region',{name:'内容分析与研究用途'}).textContent();for(const item of analysis.analysis_sections)assert.ok(analysisText.includes(item.text));assert.match(await page.locator('#video-content').innerText(),/以下为 AI 内容分析，区别于原视频观点/);
  await page.getByLabel('选择查看内容').selectOption('overview');assert.match(await page.locator('#video-content').innerText(),/American Academy of Dermatology/);assert.match(await page.locator('#video-content').innerText(),/播放 17,127 · 点赞 48 · 评论数 2/);assert.equal(await page.getByRole('link',{name:'打开原视频 ↗'}).getAttribute('href'),video.video.url);
  for(const [part,label,content] of [['transcript','字幕阅读内容',video.video.subtitles.text],['vtt','字幕原始时间片',video.video.subtitles.vtt]]){await page.getByLabel('选择查看内容').selectOption(part);assert.equal(await page.getByRole('region',{name:label,exact:true}).textContent(),content)}
  check('内容分析独立标注，切换资料与英文 TXT/VTT 均正确，字幕原文未变');
  await close(page);await page.getByRole('tab',{name:/平台线索/}).click();await page.locator('.data-row').filter({hasText:'RES-I01'}).getByRole('button',{name:'查看详情 ↗'}).click();await page.getByRole('button',{name:'查看内容分析与字幕 →'}).click();await summary(page);await page.getByRole('button',{name:'← 返回上一条详情'}).click();assert.equal(await page.getByRole('button',{name:'查看内容分析与字幕 →'}).count(),1);await close(page);
  check('原平台线索入口进入同一中文概要，并保留返回操作');
  await page.locator('#sidebar [data-action="files"]').click();const json=await download('acquisitions.json','导出获取成果 JSON');const payload=JSON.parse(fs.readFileSync(json));assert.ok(payload.items.every(x=>x.run_id==='SK-RES-001'));assert.deepEqual(payload.items.find(x=>x.kind==='video'),video);
  const html=await download('workbench.html','导出完整 HTML');await context.setOffline(true);const roundtrip=await context.newPage();await ready(roundtrip,html);await evidence(roundtrip);await open(roundtrip);await summary(roundtrip);await roundtrip.close();
  check('当前任务 JSON 和离线 HTML 导出保留中文分析与完整英文字幕');
  const mobile=await context.newPage();await mobile.setViewportSize({width:390,height:844});await ready(mobile,path.join(D,'index.html'));await mobile.addStyleTag({content:'*,*::before,*::after{transition:none!important;animation:none!important}'});await mobile.locator('#task-switch').selectOption('1');await mobile.getByRole('button',{name:'打开导航'}).click();await evidence(mobile);await open(mobile);await summary(mobile);
  for(const part of ['summary','analysis']){await mobile.getByLabel('选择查看内容').selectOption(part);const bounds=await mobile.evaluate(()=>{const d=document.querySelector('#dialog'),r=d.getBoundingClientRect(),s=document.querySelector('#video-content [role="region"]');return {vw:innerWidth,sw:document.documentElement.scrollWidth,left:r.left,right:r.right,dw:d.clientWidth,dsw:d.scrollWidth,rw:s.clientWidth,rsw:s.scrollWidth}});assert.ok(bounds.sw<=bounds.vw+1&&bounds.left>=0&&bounds.right<=bounds.vw&&bounds.dsw<=bounds.dw+1&&bounds.rsw<=bounds.rw+1,JSON.stringify(bounds))}
  await mobile.getByLabel('选择查看内容').selectOption('summary');await mobile.screenshot({path:path.join(T,'summary-mobile.png')});
  check('390px 中文概要与分析无横向溢出，内容区域高度受限');
  assert.deepEqual(result.errors,[]);assert.deepEqual(result.requests,[]);check('无脚本/控制台错误，无页面自动联网请求');result.status='passed';
 }catch(e){result.status='failed';result.failure=e.stack;await page.screenshot({path:path.join(T,'summary-failure.png')});process.exitCode=1;console.error(e)}finally{result.finished=new Date().toISOString();fs.writeFileSync(path.join(T,'summary-ui-validation.json'),JSON.stringify(result,null,2)+'\n');await browser.close()}
})();

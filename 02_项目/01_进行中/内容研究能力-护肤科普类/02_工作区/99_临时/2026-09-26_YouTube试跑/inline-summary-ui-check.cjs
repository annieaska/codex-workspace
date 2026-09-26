const {chromium}=require('/Users/chengyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict'),{pathToFileURL}=require('url');
const T=__dirname,P=path.resolve(T,'../../..'),D=path.join(P,'03_交付物/护肤科普研究首版');
const source=JSON.parse(fs.readFileSync(path.join(D,'acquisition-results.json'))),video=source.items.find(x=>x.kind==='video');
const result={version:'SK-WORKBENCH-20260926-r5',started:new Date().toISOString(),scope:'Only inline video summary visibility, full text, detail entry and desktop/390px layout. Unchanged r4 detail and data checks reused.',fallback:'Browser plugin unavailable; existing Playwright runtime used.',checks:[],errors:[],requests:[]};
const check=name=>{result.checks.push(name);console.log('PASS '+name)};
(async()=>{
 const browser=await chromium.launch({headless:true});
 const context=await browser.newContext({viewport:{width:1365,height:900},offline:true});
 const page=await context.newPage();page.setDefaultTimeout(8000);
 page.on('pageerror',e=>result.errors.push(e.message));page.on('console',m=>{if(m.type()==='error')result.errors.push(m.text())});page.on('request',r=>{if(/^https?:/.test(r.url()))result.requests.push(r.url())});
 try{
  await page.goto(pathToFileURL(path.join(D,'index.html')).href);await page.locator('body[data-ready="true"]').waitFor();
  await page.locator('#task-switch').selectOption('1');await page.locator('#nav [data-go="evidence"]').click();await page.getByRole('tab',{name:/获取成果/}).click();
  const summary=page.getByRole('region',{name:'视频中文摘要',exact:true});
  await page.addStyleTag({content:'*,*::before,*::after{transition:none!important;animation:none!important}'});
  for(const [name,width,height] of [['desktop',1365,900],['mobile',390,844]]){
   await page.setViewportSize({width,height});
   if(name==='mobile'){
    await page.reload();await page.locator('body[data-ready="true"]').waitFor();await page.addStyleTag({content:'*,*::before,*::after{transition:none!important;animation:none!important}'});
    await page.locator('#task-switch').selectOption('1');await page.getByRole('button',{name:'打开导航'}).click();await page.locator('#nav [data-go="evidence"]').click();await page.getByRole('tab',{name:/获取成果/}).click();
   }
   await page.locator('#toast').waitFor({state:'hidden'});
   assert.ok(await summary.isVisible());assert.equal(await summary.locator('p').textContent(),video.video.content_analysis.overview);assert.equal(await page.locator('#dialog').isVisible(),false);
   const bounds=await summary.evaluate(e=>{const p=e.querySelector('p'),r=e.getBoundingClientRect(),style=getComputedStyle(p);return{top:r.top,left:r.left,right:r.right,vw:innerWidth,vh:innerHeight,sw:document.documentElement.scrollWidth,clamp:style.webkitLineClamp,textHeight:p.clientHeight,textScroll:p.scrollHeight}});
   assert.ok(bounds.top>=0&&bounds.top<bounds.vh&&bounds.left>=0&&bounds.right<=bounds.vw&&bounds.sw<=bounds.vw+1,JSON.stringify(bounds));assert.equal(bounds.clamp,'none');assert.ok(bounds.textScroll<=bounds.textHeight+1,JSON.stringify(bounds));
   await page.screenshot({path:path.join(T,`inline-summary-${name}.png`)});check(`${name}: 获取成果直接显示完整中文摘要，无需打开详情；无截断或横向溢出`);
  }
  await page.getByRole('button',{name:'查看观点与字幕 ↗',exact:true}).click();assert.equal(await page.getByLabel('选择查看内容').inputValue(),'summary');assert.ok((await page.getByRole('region',{name:'中文概要与核心观点',exact:true}).textContent()).includes(video.video.content_analysis.overview));check('查看观点与字幕继续进入原中文概要与核心观点详情');
  assert.deepEqual(result.errors,[]);assert.deepEqual(result.requests,[]);check('无脚本或控制台错误，无自动联网请求');result.status='passed';
 }catch(e){result.status='failed';result.failure=e.stack;process.exitCode=1;console.error(e)}finally{result.finished=new Date().toISOString();fs.writeFileSync(path.join(T,'inline-summary-ui-validation.json'),JSON.stringify(result,null,2)+'\n');await browser.close()}
})();

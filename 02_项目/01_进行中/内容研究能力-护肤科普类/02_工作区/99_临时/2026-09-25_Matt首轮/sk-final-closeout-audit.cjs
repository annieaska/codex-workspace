const fs=require('fs'),path=require('path'),assert=require('assert/strict'),crypto=require('crypto');
globalThis.crypto=crypto.webcrypto;
const project='/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类';
const dir=path.join(project,'03_交付物/护肤科普研究首版'),src=path.join(project,'02_工作区/Matt执行');
const C=require(path.join(dir,'workbench-core.js'));
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const boot=p=>JSON.parse(fs.readFileSync(p,'utf8').match(/<script id="boot-data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
(async()=>{
 const prior=read(path.join(__dirname,'sk-final-r4-input-audit.json'));
 const index=boot(path.join(dir,'index.html')),report={checked_at:new Date().toISOString(),scope:'I1 integration and BEH G010 state closure only; unchanged evidence reused',files:[],runs:[]};
 assert.equal(index.runs.length,2);assert.equal(index.delivery_files.length,2);
 const embeddedCore=fs.readFileSync(path.join(dir,'workbench-core.js'),'utf8').replaceAll('</script','<\\/script');
 for(const name of ['index.html','SK-BEH-001.html','SK-RES-001.html'])assert(fs.readFileSync(path.join(dir,name),'utf8').includes(embeddedCore),name+' final core');
 for(const name of ['workbench-app.js','workbench.template.html','build_workbench.py','README.md'])assert.equal(hash(path.join(dir,name)),prior.files.find(f=>f.name===name).sha256,'unchanged '+name);
 for(const rid of ['SK-BEH-001','SK-RES-001']){
  const originalPath=path.join(src,rid==='SK-BEH-001'?'research-SK-BEH-001.json':'SK-RES-001.json');
  const original=read(originalPath),doc=read(path.join(dir,rid+'.json')),single=boot(path.join(dir,rid+'.html'));
  assert.deepEqual(single.runs,[doc]);assert.deepEqual(index.runs.find(d=>d.run_id===rid),doc);assert.deepEqual(single.policy,index.policy);
  assert.equal(doc.import_context.artifact_sha256,hash(originalPath));
  for(const [key,value] of Object.entries(original))if(!['snapshots','status','import_context'].includes(key))assert.deepEqual(doc[key],value,rid+' original '+key);
  assert.equal(doc.snapshots.length,original.snapshots.length);
  for(let i=0;i<original.snapshots.length;i++)for(const [key,value] of Object.entries(original.snapshots[i]))assert.deepEqual(doc.snapshots[i][key],value,rid+' snapshot '+key);
  assert.equal(doc.package.type,'trial_with_gaps');assert.equal(doc.package.formal_release,false);assert.equal(doc.package.candidate_import_attachment.auto_import,false);
  assert.equal(doc.demo,false);assert(!doc.test_fixture);assert(doc.candidates.every(c=>c.status==='draft'&&C.gates(doc,c,index.policy).formal===false));
  let audited,budget;
  if(rid==='SK-BEH-001'){
   assert.equal(doc.revision,'SK-BEH-001-package-r3');assert.equal(doc.gaps.find(g=>g.id.endsWith('G010')).status,'closed');
   assert.equal(doc.gaps.find(g=>g.id.endsWith('G009')).status,'open');
   assert.deepEqual([...doc.package.open_gap_ids].sort(),doc.gaps.filter(g=>g.status==='open').map(g=>g.id).sort());
   audited=await C.audit(C.copy(doc),index.policy);budget=C.budget(doc,index.policy);
  }else{
   assert.equal(hash(path.join(dir,rid+'.json')),prior.files.find(f=>f.name===rid+'.json').sha256,'RES unchanged material');
   const reused=prior.runs.find(r=>r.run_id===rid);audited=reused.audit;budget=reused.budget;
  }
  assert.deepEqual(audited.errors,[]);assert.deepEqual(audited.stale,[]);assert.deepEqual(budget.errors,[]);
  report.runs.push({run_id:rid,revision:doc.revision,source_sha256:hash(originalPath),audit:audited,budget,evidence:rid==='SK-BEH-001'?'G010 state delta audit':'unchanged RES material; prior audit reused'});
 }
 for(const name of ['index.html','SK-BEH-001.html','SK-BEH-001.json','SK-RES-001.html','SK-RES-001.json','demo.html','static-fixtures.json','workbench-core.js','workbench-app.js','workbench.template.html','build_workbench.py','README.md','verify_workbench.cjs','verify_historical_ids.cjs'])report.files.push({name,bytes:fs.statSync(path.join(dir,name)).size,sha256:hash(path.join(dir,name))});
 console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e);process.exit(1);});

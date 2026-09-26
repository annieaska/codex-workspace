const fs=require('fs'),path=require('path'),assert=require('assert/strict'),crypto=require('crypto');
globalThis.crypto=crypto.webcrypto;
const project='/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类';
const dir=path.join(project,'03_交付物/护肤科普研究首版'),src=path.join(project,'02_工作区/Matt执行');
const C=require(path.join(dir,'workbench-core.js'));
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const boot=p=>JSON.parse(fs.readFileSync(p,'utf8').match(/<script id="boot-data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
(async()=>{
 const index=boot(path.join(dir,'index.html')),report={config:index.policy.content_hash,files:[],runs:[]};
 assert.equal(index.runs.length,2);assert.equal(index.delivery_files.length,2);
 for(const rid of ['SK-BEH-001','SK-RES-001']){
  const originalPath=path.join(src,rid==='SK-BEH-001'?'research-SK-BEH-001.json':'SK-RES-001.json');
  const original=read(originalPath),doc=read(path.join(dir,rid+'.json')),single=boot(path.join(dir,rid+'.html'));
  assert.deepEqual(single.runs,[doc]);assert.deepEqual(index.runs.find(d=>d.run_id===rid),doc);
  assert.deepEqual(single.policy,index.policy);assert.equal(doc.import_context.artifact_sha256,hash(originalPath));
  assert.equal(doc.package.type,'trial_with_gaps');assert(!doc.test_fixture);assert.equal(doc.demo,false);
  for(const [key,value] of Object.entries(original))if(!['snapshots','status','import_context'].includes(key))assert.deepEqual(doc[key],value,rid+' original '+key);
  assert.equal(doc.snapshots.length,original.snapshots.length);
  for(let i=0;i<original.snapshots.length;i++)for(const [key,value] of Object.entries(original.snapshots[i]))assert.deepEqual(doc.snapshots[i][key],value,rid+' snapshot '+key);
  const audited=await C.audit(C.copy(doc),index.policy);assert.deepEqual(audited.errors,[],rid+' audit');assert.deepEqual(audited.stale,[],rid+' stale');
  const budget=C.budget(doc,index.policy);assert.deepEqual(budget.errors,[]);
  report.runs.push({run_id:rid,revision:doc.revision,source_sha256:hash(originalPath),counts:Object.fromEntries(C.collections.map(k=>[k,doc[k].length])),historical_decisions:(doc.historical_decisions||[]).length,package_type:doc.package.type,audit:audited,budget});
 }
 for(const name of ['index.html','SK-BEH-001.html','SK-BEH-001.json','SK-RES-001.html','SK-RES-001.json','demo.html','static-fixtures.json','workbench-core.js','workbench-app.js','workbench.template.html','build_workbench.py','README.md'])report.files.push({name,bytes:fs.statSync(path.join(dir,name)).size,sha256:hash(path.join(dir,name))});
 console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e);process.exit(1);});

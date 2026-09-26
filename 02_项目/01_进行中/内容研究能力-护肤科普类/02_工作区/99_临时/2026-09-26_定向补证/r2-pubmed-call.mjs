import { createRuntime } from '/opt/homebrew/lib/node_modules/mcporter/dist/index.js';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const dir = path.dirname(fileURLToPath(import.meta.url));
const [id, tool, argsText] = process.argv.slice(2);
if (!/^r2-c-[a-z0-9-]+$/.test(id)) throw Error('Invalid output name');
const args = JSON.parse(argsText);
const policy = JSON.parse(await readFile(path.join(dir,'../../Matt执行/run-config.json'),'utf8'));
const snapshot = JSON.parse(await readFile(path.join(dir,'../../Matt执行/SK-SUPPLEMENT-20260926-r2-policy.json'),'utf8'));
if (JSON.stringify(policy)!==JSON.stringify(snapshot.policy)) throw Error('Policy snapshot mismatch');
const request={id,started_at:new Date().toISOString(),policy_revision:policy.revision,policy_hash:policy.content_hash,tool,args};
await writeFile(path.join(dir,id+'-request.json'),JSON.stringify(request,null,2)+'\n',{flag:'wx'});
const runtime=await createRuntime({servers:[{name:'pubmed',command:{kind:'http',url:new URL('https://pubmed.caseyjhand.com/mcp')},lifecycle:{mode:'ephemeral'}}],rootDir:dir});
try {
 const response=await runtime.callTool('pubmed',tool,{args,timeoutMs:60000});
 await writeFile(path.join(dir,id+'-response.json'),JSON.stringify({completed_at:new Date().toISOString(),response},null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({id,saved:true,isError:response?.isError??false}));
} catch(e) {
 await writeFile(path.join(dir,id+'-error.json'),JSON.stringify({completed_at:new Date().toISOString(),error:String(e)},null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({id,error:String(e)}));process.exitCode=1;
} finally {await runtime.close();}


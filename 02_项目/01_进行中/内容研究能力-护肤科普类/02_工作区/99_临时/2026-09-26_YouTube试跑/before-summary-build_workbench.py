#!/usr/bin/env python3
"""从唯一 run-config 与 v0.1 研究记录构建自包含离线入口。无网络、无依赖。"""
from pathlib import Path
import argparse, hashlib, json
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--config',type=Path,default=ROOT.parent.parent/'02_工作区/Matt执行/run-config.json')
parser.add_argument('--data',type=Path,action='append',default=[])
parser.add_argument('--output',type=Path,default=ROOT/'index.html')
parser.add_argument('--split',action='store_true',help='同时输出各主题自包含HTML与同版可导入JSON')
args=parser.parse_args()
config=json.loads(args.config.read_text())
payload={k:v for k,v in config.items() if k!='content_hash'}
actual=hashlib.sha256(json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
if actual!=config['content_hash']: raise SystemExit('run-config canonical 哈希不一致，拒绝构建')
runs=[json.loads(path.read_text()) for path in args.data]
for run in runs:
 if run.get('schema_version')!='0.1' or run.get('config_ref',{}).get('sha256')!=actual: raise SystemExit('研究契约或绑定策略不匹配：'+run.get('run_id','unknown'))
 if run.get('test_fixture'): raise SystemExit('禁止将验收夹具打包到正式入口')
# 只读主控审计原件；在成果副本嵌入精确 canonical 字节，不重写历史时间。
for path,run in zip(args.data,runs):
 external=False
 for snap in run.get('snapshots',[]):
  if snap.get('audit_path') and not snap.get('content'):
   audit_path=Path(snap['audit_path']).resolve()
   if audit_path.parent!=path.resolve().parent: raise SystemExit('审计文件须位于研究记录的同一已授权目录')
   audit=json.loads(audit_path.read_text())
   payload=audit['payload']
   encoded=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(',',':'))
   digest=hashlib.sha256(encoded.encode()).hexdigest()
   if digest!=snap['content_sha256'] or digest!=audit['payload_sha256']: raise SystemExit('外部审计哈希不一致：'+str(audit_path))
   if payload['run_id']!=run['run_id'] or payload['config_ref']['sha256']!=actual: raise SystemExit('外部审计绑定错误')
   snap['audit_origin']='external_history'
   snap['audit_payload_json']=encoded
   external=True
 if external:
  run['import_context']={'source_path':str(path.resolve()),'artifact_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'original_status':run['status'],'note':'主控历史审计保留原时间与哈希；当前工作台输入须重新确认，未冒充S2前决定。'}
  run['status']='research_draft'
acquisitions=json.loads((ROOT/'acquisition-results.json').read_text())
def render(selected, files):
 boot=json.dumps({'app_version':'SK-WORKBENCH-20260926-r3','acquisitions':acquisitions,'config_path':str(args.config.resolve()),'policy':config,'runs':selected,'delivery_files':files},ensure_ascii=False).replace('<','\\u003c')
 result=(ROOT/'workbench.template.html').read_text()
 for token,value in [('__BOOT_DATA__',boot),('__CORE_JS__',(ROOT/'workbench-core.js').read_text()),('__APP_JS__',(ROOT/'workbench-app.js').read_text())]:
  if result.count(token)!=1: raise SystemExit('模板占位数量错误：'+token)
  result=result.replace(token,value.replace('</script','<\\/script'))
 return result
files=[]
if args.split:
 for run in runs:
  rid=run['run_id']
  if not rid or any(ch not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-' for ch in rid): raise SystemExit('运行ID不能用于安全文件名')
  files.append({'run_id':rid,'html':rid+'.html','json':rid+'.json'})
 for run,entry in zip(runs,files):
  (args.output.parent/entry['html']).write_text(render([run],[]))
  (args.output.parent/entry['json']).write_text(json.dumps(run,ensure_ascii=False,indent=2)+'\n')
result=render(runs,files)
args.output.write_text(result)
print(json.dumps({'output':str(args.output.resolve()),'runs':[d['run_id'] for d in runs],'artifact_sha256':hashlib.sha256(result.encode()).hexdigest(),'separate_files':files},ensure_ascii=False))

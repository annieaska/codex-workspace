from pathlib import Path
import json, hashlib, re, datetime
P=Path('/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类')
W=P/'02_工作区/Matt执行';D=P/'03_交付物/护肤科普研究首版';T=P/'02_工作区/99_临时/2026-09-26_UI正式接入'
read=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
canonical=lambda x:json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
base=read(T/'closedloop-baseline.json');checks=[];manifest={}
def check(ok,text):
 assert ok,text
 checks.append(text)
for p,h in base['protected'].items():check(sha(Path(p))==h,'保护文件字节不变：'+Path(p).name)
for p,b in base['backups'].items():check(sha(Path(b))==base['baseline'][p],'原件备份字节一致：'+Path(b).name)
check(sorted(p.name for p in P.iterdir())==base['root_entries'],'项目根目录未增加输出')
for name in ['SK-RES-001.json','research-SK-BEH-001.json']:
 src=W/name;d=read(src);old=read(Path(base['backups'][str(src)]));out=read(D/(d['run_id']+'.json'))
 check(d['search_log']==old['search_log'],d['run_id']+' 原查询日志完整未改')
 check(d['knowledge_base']==old['knowledge_base'],d['run_id']+' 知识库对照记录完整未改')
 check([s['id'] for s in d['sources']]==[s['id'] for s in old['sources']],d['run_id']+' 来源集合未增加/丢失')
 check(d['revision']==out['revision'] and d['branches']==out['branches'] and d['candidates']==out['candidates'] and d['decisions']==out['decisions'],d['run_id']+' 过程与交付研究内容同版')
 check(all(x in d['historical_decisions'] for x in old['decisions']),d['run_id']+' 旧当前决定转为历史保留')
 check(all(x['input_revision']==d['revision'] and x['actor_type']=='controller_delegate' for x in d['decisions']),d['run_id']+' 新决定绑定当版/代理身份')
 check(all(x['status'] in ['invalidated','historical'] for x in d['snapshots'][:-3]),d['run_id']+' 旧冻结索引为失效或历史')
 parent=None
 for s in d['snapshots'][-3:]:
  w=read(Path(s['audit_path']));payload=w['payload'];h=hashlib.sha256(canonical(payload).encode()).hexdigest()
  check(h==w['payload_sha256']==s['content_sha256'],d['run_id']+' 新冻结哈希 '+s['kind'])
  check(payload['revision']==d['revision'] and s['parent_snapshot_id']==parent and payload['freeze_stage']['parent_snapshot_id']==parent,d['run_id']+' 新冻结阶段/版本 '+s['kind'])
  if s['kind']=='review':check(not payload['candidates'] and all(x['stage']=='review' for x in payload['decisions']),d['run_id']+' 审阅冻结先于草案')
  parent=s['id'];manifest[s['audit_path']]=sha(Path(s['audit_path']))
 for key in ['branches','claims','decisions','candidates']:
  check(all(x['revision']==d['revision'] for x in d[key]) if key in ['branches','decisions','candidates'] else True,d['run_id']+' 当前 '+key+' 版本')
 check(all(x['coverage']=='partial' for x in d['branches']) and not d['package']['formal_release'] and all(not a['formal_admission'] for a in d['candidates']),d['run_id']+' 含缺口状态未提级')
 manifest[str(src)]=sha(src);manifest[str(D/(d['run_id']+'.json'))]=sha(D/(d['run_id']+'.json'));manifest[str(D/(d['run_id']+'.html'))]=sha(D/(d['run_id']+'.html'))
a=read(D/'acquisition-results.json');oa=read(Path(base['backups'][str(D/'acquisition-results.json')]))
check(a['items'][0]['article']==oa['items'][0]['article'],'取得论文正文未改写')
v=a['items'][2]['video'];ov=oa['items'][2]['video']
check(v['subtitles']==ov['subtitles'] and v['metrics']==ov['metrics'],'字幕原件和观察指标未改写')
for k in ['overview','title_zh','key_points']:
 check(v['content_analysis'][k]==ov['content_analysis'][k],'中文作者观点保留：'+k)
doc=json.dumps(a['items'][0]['article'],ensure_ascii=False)
for term in ['37','18','55','48','15','944','569','22.6','44.0','2.3','0.2','33%']:
 check(term in doc,'RES-S03 本地获取正文包含方法/终点 '+term)
sub=a['items'][0]['article']['sections'][3]['subsections']
parts={s['title']:s['text'] for s in sub}
check('≤ 1' in parts['Study participants'] or '≤1' in parts['Study participants'],'RES-S03 纳入阈值≤1原文')
check('≥ 1' in parts['Skin dryness assessment'] or '≥1' in parts['Skin dryness assessment'],'RES-S03 评估阈值≥1原文')
res=read(W/'SK-RES-001.json');beh=read(W/'research-SK-BEH-001.json')
ledger=res['budget']['platform_read_reconciliation'];yb=next(x for x in a['batches'] if x['batch_id']=='YOUTUBE-PILOT-20260926')
check(ledger['status']=='unverified' and ledger['platform_qualified_deep_reads'] is None and ledger['stage_assignment'] is None and yb['counts']['new_qualified_reads'] is None,'平台共享深读未知，不把科学新增0代入')
check(any(g['id']=='RES-G07' and g['critical'] and g['status']=='open' for g in res['gaps']),'平台归账作为关键开放缺口')
check(all('RES-I01' not in x['signal_ids'] for x in beh['candidates']),'干燥视频未移作行为型兴趣')
check(beh['audit_provenance']['independent_review']['applies_to_current_revision'] is False,'旧独立审核不覆盖新版')
for name in ['index.html','acquisition-results.json']:manifest[str(D/name)]=sha(D/name)
report={'status':'passed','completed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'本轮数据、来源关键改写、本地原件/冻结/预算/同版；非临床审核','checks':checks,'core_results_reused':{'source':'本轮生成后第一次 node 调用；C.validate、C.audit、C.gates、C.budget','SK-RES-001':{'errors':[],'stale':[],'fingerprint':'0747a057e5e35acaaf7d0acbefa71b87469f8cba41d7ef20dbd16f242964e8e2','all_formal':False,'queries':19,'science_reads':5},'SK-BEH-001':{'errors':[],'stale':[],'fingerprint':'41de5a38afc9e51bf3a80c2a9ad15bffffbbda0869fc7d012308a2c484828664','all_formal':False,'queries':13,'science_reads':5}},'manifest':manifest}
(T/'closedloop-data-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'passed','checks':len(checks),'protected_files':len(base['protected']),'backups':len(base['backups']),'report':str(T/'closedloop-data-validation.json')},ensure_ascii=False))

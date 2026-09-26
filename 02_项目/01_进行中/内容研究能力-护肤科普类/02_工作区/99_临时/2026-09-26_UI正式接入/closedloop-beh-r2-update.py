from pathlib import Path
import json, hashlib, copy, datetime, shutil

P=Path('/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类')
W=P/'02_工作区/Matt执行'; D=P/'03_交付物/护肤科普研究首版'; T=P/'02_工作区/99_临时/2026-09-26_UI正式接入'
read=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
canon=lambda x:json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def dump(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
src=W/'research-SK-BEH-001.json'; d=read(src)
assert d['revision']=='SK-BEH-001-closedloop-r1'
assert not (T/'closedloop-beh-r2-baseline.json').exists()
old=copy.deepcopy(d);now=datetime.datetime.now(datetime.timezone.utc).isoformat();rev='SK-BEH-001-closedloop-r2'
changed=[src,D/'index.html',D/'SK-BEH-001.html',D/'SK-BEH-001.json']
protected=[W/'SK-RES-001.json',D/'SK-RES-001.json',D/'SK-RES-001.html',D/'acquisition-results.json']
protected += [Path(s['audit_path']) for s in d['snapshots']]
base={'revision':old['revision'],'baseline':{str(p):sha(p) for p in changed},'protected':{str(p):sha(p) for p in protected},'backups':{}}
for p in changed:
    dest=T/('closedloop-r1-before-beh-r2-'+('process-' if p==src else 'delivery-')+p.name)
    assert not dest.exists();shutil.copy2(p,dest);base['backups'][str(p)]=str(dest)
dump(T/'closedloop-beh-r2-baseline.json',base)

expressions={
'SK-BEH-001-B01':'在S006的两晚限制卧床实验中，部分照片外观与社交意愿评分发生变化，可信赖性未显著变化；S007为不同设计的反向摘要线索。只描述各实验的照片评分，不推出生理损伤、长期老化或真实社交行为，也不把未显著结果写成等效。',
'SK-BEH-001-B02':'分别说明节律机制线索、S005单夜剥夺的前臂局部测量与S004睡眠质量的观察关联；S005指标并非一致变差。短期读数、分子信号与相关性不能合并为长期皮肤损伤的因果结论，也不能给出恢复剂量或期限。',
'SK-BEH-001-B03':'优先调整可改变的睡眠机会与规律性；CDC对18–60岁的一般至少7小时建议属于睡眠健康指导。清洁保湿按实际干燥等需求与耐受处理，持续睡眠问题寻求专业帮助；不把护理当作缺觉补偿，也不把一般建议当作皮肤恢复剂量。',
'SK-BEH-001-B04':'先把短睡、主观睡眠质量差、节律不规律与急性整夜剥夺分开，再按人群、实验时长和终点选用对应证据；晚睡但睡够不直接等同两晚限制卧床，不设统一伤肤时刻或睡眠损伤阈值。'
}
d.update(revision=rev,updated_at=now,status='research_draft')
d['closedloop_revision'].update(input_revision=rev,prior_input_sha256=sha(src),expression_correction={'prior_revision':old['revision'],'reason':'主控验收发现四分支solution_path重复并传入候选和包；本次只恢复各分支已有证据支持的有限表达。','scope':'BEH表达及其决定/候选/包/冻结与正式页面；来源、主张、预算、兴趣和准入不变。'})
d['historical_decisions'].extend(copy.deepcopy(d['decisions']))
idmap={x['id']:x['id'].replace('-CL-D-','-CL2-D-') for x in d['decisions']}
branches={b['id']:b for b in d['branches']}
for b in d['branches']:
    b.update(revision=rev,solution_path=expressions[b['id']],allowed_expression=[expressions[b['id']]],review_decision_ids=[idmap[x] for x in b['review_decision_ids']])
    b['review_decision']=b['review_decision_ids'][0]
for a in d['candidates']:
    a.update(revision=rev,input_revision=rev,allowed_expression=[expressions[i] for i in a['branch_ids']],review_decision_ids=[idmap[i] for i in a['review_decision_ids']])
    a['selection_reason']={'SK-BEH-001-A001':'A001先区分睡眠暴露，再优先处理可改变的睡眠与按需护理；一般健康建议不等于皮肤恢复剂量，护理不补偿缺觉。作为含缺口试运行主方向。','SK-BEH-001-A002':'A002承担机制、短期局部测量与观察关联的分层解释；不能把不同终点合并为长期因果，只作含缺口补充。','SK-BEH-001-A003':'A003仅保留具体实验的照片评分及不一致线索；不推出生理损伤、长期老化或真实社交行为，只作受限背景。'}[a['id']]
for x in d['decisions']:
    x.update(id=idmap[x['id']],revision=rev,input_revision=rev,decided_at=now)
    if x['stage']=='review':x['reason']+=' 本轮表达修正：'+expressions[x['branch_id']]
    else:x['reason']=next(a['selection_reason'] for a in d['candidates'] if a['id']==x['candidate_id'])
pkg=d['package'];pkg.update(input_revision=rev,controller_decision_recorded_at=now)
for row in pkg['knowledge_chain']:row['solution_path']=expressions[row['branch_id']]
pkg['expression_boundaries']['allowed']=[expressions[row['branch_id']] for row in pkg['knowledge_chain']]
for row in pkg['candidate_import_attachment']['draft_candidate_refs']:row['review_decision_ids']=[idmap[x] for x in row['review_decision_ids']]
d['stage_report']['input_revision']=rev
d['audit_provenance']['current_revision_scope']='本对象记录均为历史版本审计来源，不覆盖closedloop-r2；本轮代理决定见decisions，本轮独立专业审核未完成。'
g=next(g for g in d['gaps'] if g['id']=='SK-BEH-001-G011');g.update(revision=rev,description='本轮closedloop-r2在r1材料/分支基础上修正了具体允许表达及候选/包；旧G010关闭只覆盖历史版本，本轮尚待主控核验及所需独立专业审核。')
for s in d['snapshots']:
    if s['input_revision']==old['revision']:
        s.update(status='invalidated',invalidation_reason='BEH允许表达已修正为closedloop-r2；r1代理决定仅适用于旧输入，物理原件保持。')
parent=None
for kind in ['review','direction','package']:
    payload=copy.deepcopy(d)
    if kind=='review':payload['decisions']=[x for x in payload['decisions'] if x['stage']=='review'];payload['candidates']=[];payload.pop('package',None)
    payload['status']={'review':'reviewed','direction':'directions_confirmed','package':'frozen'}[kind]
    payload['freeze_stage']={'kind':kind,'parent_snapshot_id':parent,'input_revision':rev,'actor_type':'controller_delegate','qualification':'非用户或临床确认；含缺口试运行。'}
    bodyhash=hashlib.sha256(canon(payload).encode()).hexdigest();path=W/(rev+'-'+kind+'-freeze.json');assert not path.exists()
    dump(path,{'schema_version':'sk-research-audit-snapshot/1.0','kind':kind,'created_at':now,'actor_type':'controller_delegate','payload_sha256':bodyhash,'payload':payload})
    sid='SK-BEH-001-CL2-F-'+kind
    d['snapshots'].append({'id':sid,'run_id':d['run_id'],'revision':rev,'demo':False,'kind':kind,'created_at':now,'actor_type':'controller_delegate','actor_label':'主控授权施工代理','qualification':'非用户、临床或独立专业确认','input_revision':rev,'config_sha256':d['config_ref']['sha256'],'content_sha256':bodyhash,'decision_ids':[x['id'] for x in payload['decisions']],'candidate_ids':[x['id'] for x in payload.get('candidates',[])],'status':'frozen','invalidation_reason':None,'audit_path':str(path),'audit_origin':'external_history','classification':'review_record' if kind=='review' else 'trial_with_gaps','delivery_class':'trial_with_gaps','parent_snapshot_id':parent})
    parent=sid
d['status']='frozen';dump(src,d)
shutil.copy2(__file__,T/'closedloop-beh-r2-update.py')
print(json.dumps({'revision':rev,'expressions':4,'new_freezes':3,'status':'candidate_ready'},ensure_ascii=False))

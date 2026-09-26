from pathlib import Path
import json, hashlib, copy
from datetime import datetime, timezone
p=Path(__file__).parent
f=p/'SK-RES-001.json'
d=json.loads(f.read_text())
assert d['revision']=='direction-r1', '仅执行一次，避免覆盖已完成记录'
now=lambda:datetime.now(timezone.utc).isoformat()
base=lambda i:dict(id=i,run_id=d['run_id'],revision='s2-r1',demo=False)
s=d['sources'][5]
s.update(doi='10.1007/s00403-024-03003-2',published_at='2024-06-03',url='https://link.springer.com/article/10.1007/s00403-024-03003-2',authors=['Parikesit Muhammad','Endi Novianto','Mirawati Setyorini','Lili Legiawati','Shannaz Nadia Yusharyahya','Sri Linuwih Menaldi','Windy Keumala Budianti'],revision='s2-r1',access_status='partial',read_level='abstract_only',locator='Publisher abstract / Funding / Competing interests / Author information',missing_reason='原刊摘要、作者与基金可读；正文付费，未购买或登录。')
s['quality']['funding']='University of Indonesia Hibah PUTI 2023；Paragon Technology and Innovation 提供试验材料。'
s['quality']['conflict_of_interest']='作者声明无利益冲突；材料支持另列，不据此推定独立重复。'
s['limitations'].append('S2核对原刊身份与披露，仍未阅读全文，不能据摘要完成方法评分。')
s7=base('RES-S07')
s7.update(title='Sensory neuron activation from topical treatments modulates the sensorial perception of human skin',url='https://academic.oup.com/pnasnexus/article/2/9/pgad292/7278834',doi='10.1093/pnasnexus/pgad292',authors=['Ross Bennett-Kennett','Joseph Pace','Barbara Lynch','Yegor Domanov','Gustavo S Luengo','Anne Potter','Reinhold H Dauskardt'],published_at='2023-09-26',accessed_at='2026-09-25',access_time_precision='day',recorded_at=now(),source_type='mechanism_with_human_perception',language='en',geography='Stanford/法国研发机构；法国保湿剂与中国清洁剂消费者调查',access_status='available',read_level='full_text',locator='Abstract; Materials and methods: Human sensorial perception assessment; Conclusion; Funding; Competing interest',excerpt_or_summary='离体角质层力学、神经刺激模型与人体自报体验联合研究，支持紧绷感的力学解释；不等于客观屏障损伤的诊断准确性研究。',quality={'status':'unscored','method':None,'independence':None,'source':None,'author':None,'total':None,'missing_reason':'未完成独立重复与全部量化评分依据核验','funding':'L’Oréal 资助 Stanford 工作，多名作者为该公司员工或受资助者。','independent_replication_checks':{k:None for k in ['team','data','funding','experiment','population','intervention','outcome','method']}},limitations=['调查评价的是一周使用后的感受，实验和模型不能替代人体直接神经测量；未验证紧绷作为屏障损伤诊断指标。','含中国消费者调查，不代表独立中国团队重复或当代平台市场需求。'],missing_reason=None)
d['sources'].append(s7)
d['claims'][0]['source_refs'].append({'source_id':'RES-S07','role':'limit','locator':s7['locator']})
d['claims'][0]['revision']='s2-r1'
b=d['branches'][0]
b['source_ids'].append('RES-S07');b['support_source_ids'].append('RES-S07')
b['revision']='s2-r1'
for g in d['gaps']:
 if g['id']=='RES-G02':
  g.update(description='已补到紧绷体验的机制全文，但未取得在本任务人群中以屏障损伤为参照的诊断效度研究。',closure_note='RES-S07 部分补证，不关闭诊断边界缺口。',partial_source_ids=['RES-S07'])
 if g['id']=='RES-G03':g['closure_note']='原刊摘要补齐RES-S06身份/资助披露，全文付费；RES-S07无独立重复核验。科学高强度门槛未通过。'
 if g['id']=='RES-G04':g.update(description='一项机制论文含中国清洁剂感受调查；仍不足以完成中国日常护理外推与市场兴趣验证。',partial_source_ids=['RES-S07'])
 if g['id']=='RES-G05':g.update(description='3年窗口新增2023-09-26机制全文；1年窗口与其他时间窗的合格人体证据仍不足，不能声称最新证据覆盖充分。',partial_source_ids=['RES-S07'])
queries=[
 ('RES-Q16','RES-T01','"Sensorial perception" "skin" "Berkey" "2023" PNAS Nexus',[],0,'发现PNAS原文标识；PMC访问受限，继续核对原刊入口。'),
 ('RES-Q17','RES-T02','"Effectiveness of topical hyaluronic acid of different molecular weights" "2024" full text',['RES-S06'],0,'原刊摘要及身份/基金可读，正文付费；注册页仅壳页，无新增合格深读。'),
 ('RES-Q18','RES-T01','site.academic.oup.com/pnasnexus "pgad292"',['RES-S07'],1,'准确原刊入口可读，完成方法、结论、基金与利益披露阅读；不具有诊断准确性结论。'),
 ('RES-Q19','RES-T02','"10.1007/s00403-024-03003-2" "full" university',[],0,'机构仓储只提供摘要/原刊DOI线索，未得到允许访问的全文。')]
for qid,target,q,src,n,result in queries:
 r=base(qid)
 r.update(stage='S2',level='S2',policy_revision='SK-MATT-20260925-r2',policy_hash=d['config_ref'].get('content_hash',d['snapshots'][0]['config_sha256']),source_category='targeted_evidence',category_or_target_id=target,target=target,query_id=qid,query=q,query_text=q,issued_at='2026-09-25',executed_at='2026-09-25',time_precision='day; 实际发生于第一次审阅与方向冻结之后，未补造秒级查询时间',route='web/primary-source',returned_hits=None,hits=None,screening_limit=10,hit_count_missing_reason='混合检索返回未保留可靠逐查询总量；只筛选前最多10项',qualified_reads=n,qualified_read_ids=['doi:10.1093/pnasnexus/pgad292'] if n else [],source_ids=src,new_qualified_items=n,duplicate_original_ids=[],new_claim_ids=[],new_conflicts=[],consumption={'queries':1,'deep_reads':n},status='completed' if n else 'partial',access_result=result,stop_reason='目标补证已取得可用部分或遭遇付费访问边界；非检索饱和')
 d['search_log'].append(r)
d['budget']['S2'].update(queries_total=4,deep_reads=1,original_dedup_keys=['doi:10.1093/pnasnexus/pgad292'],stopped='两个目标各2次查询；T01取得机制全文但无诊断证据，T02全文付费；不扩大全景或冒称饱和。')
for t in d['budget']['S2']['targets']:
 t.update(queries_used=2,deep_reads_used=1 if t['id']=='RES-T01' else 0,status='partial',stop_reason='有限补证结束；保留关键缺口。')
d['revision']='s2-r1'
d['status']='s2_complete_with_gaps'
# 旧物理冻结保持原样；当前数组标明其针对旧材料。
for s in d['snapshots']:
 s['status']='historical'
 s['invalidation_reason']='S2补证改变当前材料；原审计文件仍保留，当前版需重新审阅/确认。'
d['historical_decisions']=copy.deepcopy(d['decisions'])
d['decisions']=[]
for i,b in enumerate(d['branches'],1):
 did=f'RES-D-R2-{i:02}'
 dec=base(did);dec.update(revision='review-r2',stage='review',actor_type='controller_delegate',actor_label='主控代理',qualification=None,decided_at=now(),input_revision='s2-r1',branch_id=b['id'],candidate_id=None,action='gap',reason='已复核S2新增机制原文与原刊摘要；新增材料不足以关闭诊断、独立性、时间窗或平台兴趣缺口。仅保留限定研究分支，不批准正式候选。',required_changes=['保留全部关键缺口','禁止诊断与疗效外推','不得冒称临床专家或用户亲自审核'])
 d['decisions'].append(dec);b['review_decision_ids']=[did]
for c in d['candidates']:
 b=next(b for b in d['branches'] if b['id']==c['branch_ids'][0])
 c['review_decision_ids']=b['review_decision_ids'];c['revision']='review-r2'
d['revision']='review-r2'
def freeze(kind,rev):
 payload=copy.deepcopy(d)
 # 包含此前冻结的引用，不递归携带物理审计全文。
 raw=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
 sha=hashlib.sha256(raw).hexdigest();ts=now()
 path=p/f"SK-RES-001-{kind}-r2-freeze.json"
 assert not path.exists()
 wrapper={'schema':'sk-research-audit-snapshot/1.0','kind':kind,'created_at':ts,'actor_type':'controller_delegate','payload_sha256':sha,'payload':payload}
 path.write_text(json.dumps(wrapper,ensure_ascii=False,indent=2)+'\n');path.chmod(0o444)
 d['snapshots'].append(dict(id=f'RES-F-{kind}-r2',run_id=d['run_id'],revision=rev,demo=False,kind=kind,created_at=ts,actor_type='controller_delegate',input_revision=d['revision'],config_sha256=d['snapshots'][0]['config_sha256'],content_sha256=sha,decision_ids=[x['id'] for x in d['decisions']],candidate_ids=[x['id'] for x in d['candidates']],status='frozen',invalidation_reason=None,audit_path=str(path),qualification='主控代理决定；非用户亲自确认或临床资质审核',delivery_class='含关键缺口的试运行包'))
freeze('review','review-r2')
for i,c in enumerate(d['candidates'][:2],1):
 dec=base(f'RES-D-D2-{i:02}');dec.update(revision='direction-r2',stage='direction',actor_type='controller_delegate',actor_label='主控代理',qualification=None,decided_at=now(),input_revision='review-r2',branch_id=c['branch_ids'][0],candidate_id=c['id'],action='confirm',decision_scope='trial_direction_only',reason='主方向表象与诊断边界，辅方向配方/人群/终点限定；仅供含关键缺口试运行，科学及兴趣门禁未通过。',required_changes=['保持草案和关键缺口标记'])
 d['decisions'].append(dec)
d['revision']='direction-r2';freeze('direction','direction-r2')
d['revision']='package-r2';d['status']='trial_complete_with_critical_gaps'
d['delivery_class']='含关键缺口的试运行包'
d['package']={'type':'trial_with_gaps','primary_candidate_id':'RES-K01','supplemental_candidate_ids':['RES-K02'],'formal_release':False,'synthesis':'先区分干燥/紧绷的表象与诊断，再讨论证据支持范围内的护理优先级；保湿研究须保留人群、部位、配方与测量终点限制。','selected_direction_reason':'降低把体验直接诊断成屏障损伤的表达风险；不将其包装为已验证的市场选题。','other_branches':'环境清洁与持续症状处理作为背景/边界，尚未独立达到正式候选门槛。','next_action':'在既定可公开访问范围获得可核验平台信号，并补足分支质量/反证/时间窗覆盖后再申请正式准入。','frozen_by':'controller_delegate'}
freeze('package','package-r2')
d['updated_at']=now()
f.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
ids={x['id'] for x in d['sources']}
assert all(r['source_id'] in ids for c in d['claims'] for r in c['source_refs'])
assert len(d['search_log'])==19 and sum(x['consumption']['deep_reads'] for x in d['search_log'])==5
assert all(c['status']=='draft' for c in d['candidates'])
print(json.dumps({'run_id':d['run_id'],'revision':d['revision'],'sources':len(d['sources']),'queries':len(d['search_log']),'qualified_deep_reads':5,'snapshots':len(d['snapshots']),'formal_release':False,'file':str(f)},ensure_ascii=False))


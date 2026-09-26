from pathlib import Path
import json, hashlib, copy, datetime, shutil

P=Path('/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类')
W=P/'02_工作区/Matt执行'; D=P/'03_交付物/护肤科普研究首版'; T=P/'02_工作区/99_临时/2026-09-26_UI正式接入'
NOW=datetime.datetime.now(datetime.timezone.utc).isoformat()
BASE=json.loads((T/'closedloop-baseline.json').read_text())
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def canon(a): return json.dumps(a,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def dump(p,a): p.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for p,h in BASE['baseline'].items():
    if digest(Path(p))!=h: raise RuntimeError('输入已变化，停止 '+p)
for p,h in BASE['protected'].items():
    if digest(Path(p))!=h: raise RuntimeError('保护文件已变化，停止 '+p)
res=json.loads((W/'SK-RES-001.json').read_text()); beh=json.loads((W/'research-SK-BEH-001.json').read_text()); acq=json.loads((D/'acquisition-results.json').read_text())
def find(d,k,i): return next(x for x in d[k] if x['id']==i)
def extend_value(old,new): return (old if isinstance(old,list) else [old])+new
def init(d):
    rev=d['run_id']+'-closedloop-r1'; d['revision']=rev; d['updated_at']=NOW; d['delivery_class']='trial_with_gaps'; d['status']='research_draft'
    d.setdefault('historical_decisions',[]).extend(copy.deepcopy(d['decisions'])); d['decisions']=[]
    for s in d['snapshots']:
        if s['status']=='frozen': s.update(status='invalidated',invalidation_reason='闭环 r1 材料与分支已变化；旧决定只适用于旧输入，物理原件保留。')
        s['audit_origin']='external_history'
    d['closedloop_revision']={'spec_revision':'SK-CLOSELOOP-20260926-v1','input_revision':rev,'material_scope':'仅已有本地材料；本轮新增网络查询 0、来源 0、知识库写入 0。','prior_input_sha256':BASE['baseline'][str(W/('SK-RES-001.json' if d['mode']=='result' else 'research-SK-BEH-001.json'))],'authority':'controller_delegate；施工代理审阅与方向决定，非用户确认、临床审核或独立审计。','external_evidence_order':'既有外部来源及获取附件 → 已有知识库导出对照 → 分支审阅 → 草案 → 既有兴趣材料与方向重判 → 本地材料定向补充 → 含缺口包。','quality_scoring':'方法补足不自动转化为数值评分；缺少独立性、完整附件等依据时保持未评分。','independent_review_status':'本轮实现候选待主控核验；历史独立审核不自动覆盖新版本。'}
    for s in d['sources']:
        s['evidence_provenance']={'revision':rev,'local_record':str(W/('SK-RES-001.json' if d['mode']=='result' else 'research-SK-BEH-001.json')),'read_scope':'复用已存来源记录及其原文定位；除单列取得的附件外，本轮未重新读取网络原页。'}
        s['limitations']=extend_value(s.get('limitations',[]),['本轮离线复用历史来源记录；当前全文或方法缺口以本来源逐项说明为准，不把历史摘要视为新阅读全文。'])
    return rev
rr=init(res); br=init(beh)

# WP1–3: result evidence, map, knowledge-base boundary.
s=find(res,'sources','RES-S03'); s['revision']=rr; s['accessed_at']='2026-09-26'; s['access_status']='full_text_retrieved_supplement_not_verified'
s['locator']=extend_value(s['locator'],['本地 acquisition-results.json → items[id=PM-PILOT-RES-S03].article.sections[3] Materials and methods：Study participants、Treatment regime、Skin dryness assessment、Skin hydration assessment、Stratum corneum cohesivity；Results 和 Supplementary Information。','原始获取附件：'+str(P/'02_工作区/99_临时/2026-09-26_PubMed试跑/fulltext-response.json')])
s['excerpt_or_summary']='作者结果：37名18–55岁女性小腿单中心研究，所报告润肤乳组每日两次、持续5周；角质层含水读数22.6→44.0、视觉干燥评分2.3→0.2，胶带蛋白量944→569µg，神经酰胺半定量增加33%。这些是该组的前后观察，不等于成分或全部产品的对照因果效应。方法补足：三组平衡不完全区组设计仅报告其中润肤乳组；评估前48小时停用产品、20°C/50%相对湿度适应15分钟，含水每时点5次读数，脂质子样本18人。AI判断：含水、外观、角质层黏聚性与脂质终点分别解释；本次返回正文未见可直接引用的TEWL结果，不把含水改善写成屏障完全修复。'
s['limitations']=extend_value(s['limitations'],['本地正文内部不一致：Study participants 纳入红斑≤1，Skin dryness assessment 写红斑≥1；未核原版/补充材料，不能任选阈值。','三组设计仅报告一个处理组，本次正文没有该组可用的同期未处理比较；完整排除条件、统计细节、脂质及微生物方法指向未读补充材料。','多样性与总体网络结果不显著，个体网络变化不证明因果机制；正文讨论中7天86%改善为data not shown，不采用作效果承诺。','5周为研究观察期，非普遍恢复时间；不外推面部、老年人、疾病或每种配方。','本次返回正文未含完整单位、资金和利益冲突栏目；既有Unilever资助/雇佣记录保留其历史来源，不宣称本次获取已复核披露。'])
s['quality']['method_evidence']='已补入对象、单中心设计、使用和评估条件及部分测量程序；阈值冲突、完整统计/补充附件未核，method/total仍null。'
s['quality']['funding_provenance']='沿用旧来源记录的正文披露定位；本次MCP正文未返回完整资金/利益冲突栏目。'
s['evidence_provenance'].update(acquisition_id='PM-PILOT-RES-S03',raw_evidence=str(P/'02_工作区/99_临时/2026-09-26_PubMed试跑/fulltext-response.json'),read_scope='本轮实际读取已存获取正文的Methods、Results、Discussion；未补读外链或附件。')
for i in ['RES-S01','RES-S02']:
    x=find(res,'sources',i);x['limitations']=extend_value(x['limitations'],['与RES-I01视频同为AAD机构内容，属于同源专业传播，不能计为额外独立科学证据。'])
c=find(res,'claims','RES-C01');c['text']='干燥、脱屑及紧绷是待描述的表象；主观紧绷、角质层含水、失水通量和疾病诊断不能互换。现有机制及感受研究未建立可用于个体诊断的敏感度/特异度。';c['revision']=rr
c=find(res,'claims','RES-C04');c['text']='角质层含水、TEWL、视觉干燥评分及临床体验测量不同问题。RES-S03的5周含水/外观改善与RES-S06摘要中不同终点结果不能合并成“所有保湿均修复屏障”。';c['revision']=rr
c=copy.deepcopy(find(res,'claims','RES-C03'));c.update(id='RES-C06',revision=rr,text='RES-S03中37名女性小腿在5周润肤乳使用后含水和视觉干燥改善；所返回正文只报告该处理组，支持限定人群/部位/配方的前后观察，不足以归因单一成分或确定普遍恢复时限。',source_refs=[{'source_id':'RES-S03','role':'support','locator':'本地PM-PILOT-RES-S03.article：Materials and methods/Study participants、Treatment regime；Results/Skin hydration and dryness；正文阈值冲突见来源局限。'}],certainty='受限单组前后观察；完整质量未评分',population='37名18–55岁女性、小腿；脂质子样本18人',context='所报告润肤乳组、每日两次；非面部或疾病试验',time_scale='5周观察；评估前停用48小时。不能定义起效、持续或恢复曲线。',allowed_expression='这项特定人群和部位的研究在5周时观察到含水及外观改善。',forbidden_expression='5周一定修复屏障；7天86%恢复；该成分或所有保湿产品等效。',gaps=['RES-G03','RES-G04']);res['claims'].append(c)

maps={
'RES-B01':dict(title='先描述表象，不能凭紧绷诊断屏障损伤',definition='表象包括紧绷、干燥感和可见脱屑；先记录部位、洗后或环境变化时机、持续性及伴随不适。鉴别线索用于整理问题，不能据此确诊；主观感受、含水测量和临床诊断分层。',chain_position='表象记录 → 外部触发与人群背景 → 测量/机制解释 → 护理与就诊边界；各箭头是解释次序，非已证实的连续因果链。',preliminary_judgment='RES-S07（mechanical/神经模型与人群感受调查）使紧绷的物理解释更具体，但不是诊断试验；RES-S01为公众指导。可以说“先辨明何种体验”，不能说“紧绷就是屏障坏了”。',priority_rationale='优先级1：除持续不缓解等需评估的情形外，先纠正表象与诊断混同，避免直接把产品当治疗。',claim_ids=['RES-C01'],source_ids=['RES-S01','RES-S04','RES-S07'],solution_path='记录体验、部位、触发与持续性；持续不缓解转B04，日常外部因素转B02。'),
'RES-B02':dict(title='先排查环境、洗浴和接触刺激',definition='可能原因线索：低湿度、热源、热水或较长洗浴、清洁产品及湿作业/摩擦暴露。按发生前后、身体部位和接触场景核对，而非给单一病因标签。适用一般日常干燥护理；持续问题仍须评估。',chain_position='低湿/热水/清洁或接触暴露 → 干燥体验的可能触发 → 减少刺激并及时保湿 → 观察耐受与持续性。',preliminary_judgment='RES-S01/S02支持温和护理顺序；AAD视频00:19–00:43、01:03–片尾给出同源动作表达。可以建议逐项核对可调整因素，不能声称改一项必然治愈或给出各因素效应排序。',priority_rationale='优先级2：先处理可调整的上游暴露。顺序依据低复杂度和专业日常建议，不是效果大小比较；同机构视频不增加科学独立性。',claim_ids=['RES-C02'],source_ids=['RES-S01','RES-S02'],solution_path='短时温水洗浴、温和无香精产品、轻拍干后及时保湿；核对衣物/湿作业和热源等接触，按耐受观察。'),
'RES-B03':dict(title='保湿承担什么作用，证据落在哪个终点',definition='保湿是日常护理措施；分清配方、使用频率、部位和比较条件，再解释含水、视觉干燥、黏聚性与脂质变化。RES-S03补入方法后支持具体的前后观察；摘要反向线索只提示配方和终点差异。',chain_position='减少可调整刺激 → 按需要/耐受使用基础保湿 → 按相同终点与人群解读结果 → 无改善时回到原因和评估边界。',preliminary_judgment='RES-S03（Methods/Results）37名女性小腿5周：含水22.6→44.0、视觉干燥2.3→0.2；但只报告处理组，红斑阈值两处冲突、补充统计未核。可作有限案例，不能推出单成分疗效、所有产品等效或恢复期限。RES-S05/S06仍为摘要级边界线索。',priority_rationale='优先级4：先解释原因与测量，再讨论护理。获取了正文使方法更可查，但不足以替代对照、质量与独立复核；不依产品卖点提级。',claim_ids=['RES-C03','RES-C04','RES-C06'],source_ids=['RES-S02','RES-S03','RES-S05','RES-S06'],solution_path='说明基础保湿角色与该研究观察条件；不选品牌，不设统一恢复时间。'),
'RES-B04':dict(title='持续不缓解时，自我护理在何处停止',definition='区分可先调整的日常干燥与持续或令人困扰、调整后仍不缓解的情况；后者可能需要皮肤科进一步评估。不能从脱屑、紧绷或刺痛直接判定湿疹、过敏或感染，也不能把研究护理作为疾病治疗。',chain_position='持续症状/护理后未改善 → 专业评估可能原因 → 是否需要进一步处理；这一边界贯穿所有分支。',preliminary_judgment='RES-S01/S02的就诊边界及AAD视频片尾支持“调整后不缓解需寻求评估”。这是行动边界，不是诊断规则；视频字幕未人工逐秒校对，不能独立支撑疾病或处方主张。',priority_rationale='优先级0（条件触发）：持续不缓解者先评估，优先于继续更换产品；其余一般干燥再按B01→B02→B05→B03阅读。',claim_ids=['RES-C05'],source_ids=['RES-S01','RES-S02'],solution_path='持续不缓解先寻求皮肤科评估；不替代诊断、不推荐处方或治疗方案。'),
'RES-B05':dict(title='含水、失水与紧绷机制不能互相代替',definition='角质层含水表示一个含水状态读数；TEWL涉及经皮水分散失；视觉评分描述可见干燥；紧绷是主观体验。离体结构与力学模型帮助提出可能机制，不能据一个读数诊断整体屏障或疾病。',chain_position='水分/结构/力学的可能机制 → 各自测量终点 → 与体验关联尚需核实 → 不跨层级推出诊断或疗效。',preliminary_judgment='RES-S04为离体猪角质层结构证据，RES-S07含离体材料、神经模型与人群感受调查；都未给出本任务个体诊断效度。RES-S06摘要终点差异是边界线索，不能与RES-S03不同设计合并量化。',priority_rationale='优先级3：在谈“修复”之前交代测量含义，防止把含水改善、机制推测和临床恢复混用。',claim_ids=['RES-C01','RES-C04'],source_ids=['RES-S03','RES-S04','RES-S06','RES-S07'],solution_path='每次陈述先写清测了什么、在哪个部位和人群测、没测什么。'),
'RES-B06':dict(title='年龄、部位和研究人群决定适用边界',definition='同样称干燥，日常成人护理、18–55岁女性小腿研究、60–80岁老年人小腿研究和离体猪角质层属于不同对象。年龄/部位提供适用性检查，不能仅凭年龄诊断病因，不能将老年或腿部数据直接用于面部与疾病。',chain_position='人群/部位/场景 → 可用研究的适用性 → 限定表达与护理边界；此检查横贯原因、机制和措施各支。',preliminary_judgment='RES-S03本地方法补足了37名女性小腿范围；RES-S06仍仅36名雅加达老年人的摘要，全文受限；RES-S07中国感受调查不是独立临床复现，也不是中国平台兴趣。',priority_rationale='横向优先检查：每个主张都过人群/部位这一关；独立内容候选优先级5，当前没有足够材料做分年龄治疗或中国受众结论。',claim_ids=['RES-C03','RES-C04','RES-C06'],source_ids=['RES-S03','RES-S04','RES-S06','RES-S07'],solution_path='逐条写出研究对象与排除范围；人口/临床外推不足时留白，不生成年龄化或疾病化推荐。')}
template=copy.deepcopy(res['branches'][0])
for i,v in maps.items():
    b=next((b for b in res['branches'] if b['id']==i),None)
    if b is None: b=copy.deepcopy(template);b['id']=i;res['branches'].append(b)
    b.update(v,revision=rr,coverage='partial',review_decision_ids=[],parent_ids=[],related_ids=[x for x in maps if x!=i])
    b['support_source_ids']=v['source_ids'];b['counter_source_ids']=[x for x in v['source_ids'] if x in ['RES-S05','RES-S06']]
    b['upstream']=[v['chain_position'].split(' → ')[0]];b['downstream']=[v['solution_path']]
    b['gaps']=list(dict.fromkeys(['RES-G02'] if i=='RES-B01' else ['RES-G03'] if i in ['RES-B03','RES-B05'] else ['RES-G04'] if i=='RES-B06' else ['RES-G03','RES-G04']))
    b['allowed_expression']=[v['solution_path']];b['forbidden_expression']=['从紧绷或单一读数诊断屏障损伤；保证护理治愈；承诺固定恢复天数。']
    b['context']='一般日常干燥的非诊断解释；人体/离体、年龄与部位按来源分列。'
    b['coverage_matrix']={k:'partial' for k in template['coverage_matrix']};b['coverage_matrix']['review_decision']='covered'
    b['priority_order']={'RES-B04':0,'RES-B01':1,'RES-B02':2,'RES-B05':3,'RES-B03':4,'RES-B06':5}[i]
    b['population']=v['definition'] if i=='RES-B06' else '一般成人日常护理；研究实证不超出各来源的人群与部位。'

g=find(res,'gaps','RES-G01');g.update(description='RES-I01已补到AAD公开视频元数据、互动快照及自动字幕；中国受众、可比基线、评论含义、当前/基线期趋势仍未知，Instagram未重启。单条机构视频不能关闭兴趣门槛。',closure_note='获取进展不等于兴趣通过：17127播放、48赞、2评论为单时点观察；未读取评论正文，未核实受众地区。',revision=rr)
g=find(res,'gaps','RES-G03');g.update(description='RES-S03已补具体方法与结果，但正文红斑阈值≤1/≥1冲突、补充统计和完整方法未核，本次正文未返回完整披露；RES-S06全文仍受限，质量数值评分和独立复核未完成。',closure_note='不能以取得正文或补入方法当作质量合格；5周观察不构成统一恢复期限。',revision=rr)
g=find(res,'gaps','RES-G06');g['closure_note']='已有导出在Claim.statement及关联Source.title上做字面OR匹配、limit=100，零匹配只说明本查询未命中；不能写成知识库无相关知识或已全面检索。'

# WP4: observed platform material remains separate from scientific independence and demand.
video=acq['items'][2]['video']; sig=find(res,'signals','RES-I01')
sig.update(revision=rr,status='metadata_and_subtitles_observed',verification_level='platform_metadata_and_auto_subtitles',published_at=video['published_on'],observed_at=acq['items'][2]['observed_at'],account=video['channel'],metrics=video['metrics'],audience_region=None,missing_reason='受众地区、可比基线及评论正文未知；自动字幕未对照音轨核验。现有视频用于内容结构参考，不能确定兴趣强度。',content_summary='AAD作者观点：短时温水洗浴、清洁后及时保湿、温和无香精产品、减少接触/环境刺激，持续不缓解寻求评估。AI解读：适合行动清单表达；同源指导不能新增独立科学佐证或证明市场需求。',related_branch_ids=['RES-B02','RES-B04'],source_dependency='与RES-S01/RES-S02同为AAD，非独立科学印证。')
ledger={'status':'unverified','material_id':'RES-I01','original_dedup_key':'youtube:biIzSPOEQgQ','science_new_qualified_reads':0,'platform_qualified_deep_reads':None,'stage_assignment':None,'shared_budget_impact':'已取得并读取视频字幕，是否达到平台合格深读及应归S1还是既有S2目标未核实；共享余额不可据科学新增0推成平台新增0。无授权执行新查询，未知归账关闭前不能据账面余额继续扩展。','known_science_reads':{'S1':4,'S2':1},'current_offline_reuse_new_queries':0}
res['budget']['platform_read_reconciliation']=ledger
res['gaps'].append({'id':'RES-G07','run_id':res['run_id'],'revision':rr,'demo':False,'scope_id':'RES-I01','category':'execution_budget','description':'已补取YouTube字幕的合格深读及S1/S2共享预算归账未核实；不能把科学新增深读0等同平台深读0。','critical':True,'status':'open','closure_source_ids':[],'closure_note':ledger['shared_budget_impact']})
yb=next(x for x in acq['batches'] if x['batch_id']=='YOUTUBE-PILOT-20260926');yb['counts']['new_qualified_reads']=None;yb['counts']['new_scientific_qualified_reads']=0;yb['counts']['platform_qualified_deep_reads']=None;yb['read_accounting']=ledger;yb['note']+=' 本轮离线复核澄清：旧new_qualified_reads=0仅能说明未新增科学深读，不能证明平台共享合格深读为0；平台资格和阶段归账未核实。'
ca=video['content_analysis']
for row in ca.get('analysis_sections',[]):
    if row['title']=='对当前研究有什么用':row['text']='本轮已作为同源传播材料补入RES-B02/B04和候选表达判断，提取清洁后保湿、无香味/无香精及持续不缓解的边界。属于AI代理整理，未完成独立专业审核；不追加科学独立样本，不判定主题热度。'
ca['review_status']='本轮AI代理已用于研究闭环；未对照音轨人工校对，未完成独立专业审核。'
acq['items'][2]['limits'].append('与AAD科学指导同机构；共享平台深读资格与S1/S2阶段归账未核实，科学新增0不等于平台深读0。')
acq['items'][0]['limits'].append('本轮已据本地正文补入研究；红斑阈值两处不一致、补充方法/统计及本次未返回的披露仍未核实，不等于质量评分完成。')

# Behavior mode: distinct exposure/response/action map; no transfer of RES interest.
s=find(beh,'sources','SK-BEH-001-S004');s['revision']=br;s['limitations']=extend_value(s['limitations'],['2026-09-26已有PubMed补取记录仍未取得开放全文，不能把获取尝试变成完成方法核验；60名健康白人女性的观察关联不证明睡眠造成长期老化。']);s['evidence_provenance']['acquisition_id']='PM-PILOT-BEH-S004'
s=find(beh,'sources','SK-BEH-001-S006');s['excerpt_or_summary']=extend_value(s['excerpt_or_summary'],['本轮依据已存S2方法复用：25名被摄者、两晚8h/4h卧床条件，实际睡眠约7h35/4h15，间隔至少1周；122名评分者，各终点排除不完全相同。交叉混合模型、标准照片及拍摄/选片盲法限制了若干混杂，但不能从照片感知推出生理损伤、实际社交行为或恢复时间。'])
s=find(beh,'sources','SK-BEH-001-S005');s['limitations']=extend_value(s['limitations'],['本轮保持2025年40名韩国女性、单夜急性剥夺/前臂测量范围；同一前臂不同区域并非独立睡眠对照，分子变化与临床屏障终点不可互代。'])
c=copy.deepcopy(find(beh,'claims','SK-BEH-001-C001'));c.update(id='SK-BEH-001-C008',revision=br,text='睡眠时长不足、主观睡眠质量差、急性整夜剥夺与节律偏移是不同暴露；须分别描述，现有材料不支持统一“几点以后算熬夜伤肤”的临床阈值。',source_refs=[{'source_id':'SK-BEH-001-S003','role':'support','locator':'CDC About Sleep：睡眠时长、质量及规律性的一般健康指导。'},{'source_id':'SK-BEH-001-S001','role':'limit','locator':'The circadian clock and diseases of the skin：叙述综述中的昼夜节律机制，不是特定入睡时间临床试验。'},{'source_id':'SK-BEH-001-S006','role':'limit','locator':'Methods：8h/4h卧床交叉条件、两晚；只代表此实验暴露。'},{'source_id':'SK-BEH-001-S004','role':'limit','locator':'摘要：以睡眠质量分组的观察关联，完整方法未获得。'}],allowed_expression='先区分时长、质量与规律性，再解释对应研究测了什么。',forbidden_expression='过某个时刻皮肤必然受损；所有少睡暴露等效。',time_scale='无统一皮肤损伤阈值或恢复时限。',gaps=['SK-BEH-001-G002','SK-BEH-001-G006']);beh['claims'].append(c)
bm={
'SK-BEH-001-B01':dict(title='短期外观感知，不等于生理损伤',definition='外观感知是照片评分中的疲态、健康感、吸引力或社交意愿；区别于屏障指标、个人主观感受、真实社交行为与长期老化。记录实验暴露和评分对象，不能给日常个人作外观诊断。',chain_position='特定短期睡眠限制 → 标准照片 → 他人评分；与生理损伤/长期老化没有已验证的连续因果桥。',preliminary_judgment='S006中25名健康被摄者两晚8h/4h卧床，实际睡眠约7h35/4h15；122名评分者部分评分变化，可信赖性未显著变化。S007为不同设计的2019反向摘要线索，全文未核，不能合并效应或称等效。',priority_rationale='优先级3：可作为受限解释背景；没有由此成立的额外护肤收益，不因“显老”吸引注意而超越睡眠行为建议。'),
'SK-BEH-001-B02':dict(title='节律机制、屏障测量与长期关联分层',definition='分别研究节律机制的可能性、急性睡眠剥夺的局部生理读数、长期睡眠质量的观察关联。机制来自混合模型、人群和实验；“有机制线索”不等于已经证明长期因果。',chain_position='不同睡眠暴露 → 可能生物过程 → 局部测量或观察关联；临床损伤、长期老化和恢复过程尚缺直接证据。',preliminary_judgment='S005（2025，40名韩国女性、单夜剥夺、前臂）指标并非一致变差，分子信号不能替代临床屏障结论；S004为60名健康白人女性的观察摘要，本次补取仍无全文。S001综述不能独立给出皮肤恢复剂量。',priority_rationale='优先级2：用分层证据纠正“熬夜必然伤屏障”，为行动边界提供依据；质量评分、长期因果及独立复现缺口使其不能独立成为正式强科学候选。'),
'SK-BEH-001-B03':dict(title='优先保障睡眠，护理按实际需求处理',definition='可改变因素是睡眠机会和规律性，以及与当前干燥等实际需求相匹配的日常清洁保湿。CDC对18–60岁一般建议至少7小时，属于公共健康指导，不是每个人的皮肤恢复剂量；持续睡眠问题应寻求专业帮助。',chain_position='识别时长/质量/规律性 → 调整可改变的睡眠行为 → 按实际皮肤需求温和护理；护理与睡眠作用分别判断，不能视作补偿。',preliminary_judgment='S003支持一般睡眠健康建议，S002支持日常干燥护理；没有护肤抵消睡眠不足的比较试验。能给出行动顺序，不能保证恢复容貌、逆转老化、补回缺觉或某天数见效。',priority_rationale='优先级1（行动主方向）：可改变性和一般健康依据最直接；实际收益限于相应指导范围，不能把潜在皮肤收益或恐惧叙事作为排序理由。'),
'SK-BEH-001-B04':dict(title='先说清熬夜指的是哪一种睡眠暴露',definition='把短睡、主观睡眠质量差、节律不规律与整夜急性剥夺分开记录；既有研究用不同人群、实验时长和终点回答不同问题。晚睡但时长足够与实验中两晚限制卧床不能直接等同。',chain_position='行为定义（时长/质量/规律性/急性剥夺） → 对应证据选择 → 外观或生理层面的限定判断 → 可调整行为。',preliminary_judgment='S003公共健康指导与S001节律综述用于建立问题框架；S004睡眠质量关联、S005急性剥夺、S006两晚限制并非同一暴露。没有证据支持本任务统一的伤肤时间点或剂量。',priority_rationale='解释顺序第1，行动排序与B03相连：先明确可改变的暴露，才谈实证结果；不能套用结果型“症状→诊断”的排序。')}
template=copy.deepcopy(beh['branches'][0])
for i,v in bm.items():
    b=next((b for b in beh['branches'] if b['id']==i),None)
    if b is None:
        b=copy.deepcopy(template);b.update(id=i,claim_ids=['SK-BEH-001-C008'],source_ids=['SK-BEH-001-S001','SK-BEH-001-S003','SK-BEH-001-S004','SK-BEH-001-S006'],gaps=['SK-BEH-001-G002','SK-BEH-001-G006','SK-BEH-001-G009']);beh['branches'].append(b)
    b.update(v,revision=br,coverage='partial',review_decision_ids=[],related_ids=[x for x in bm if x!=i])
    b.pop('review_decision',None);b['review_status']='controller_reviewed_with_gaps'
    b['upstream']=v['chain_position'].split(' → ')[0];b['downstream']=v['chain_position'].split(' → ')[-1]
    b['allowed_expression']=[v['definition']];b['forbidden_expression']=['少睡必然损伤屏障或不可逆老化；护肤抵消缺觉；固定伤肤时刻或恢复期限。']
    if i.endswith('B04'):
        b['population']='一般睡眠健康与各来源特定实验人群分别说明；不把国外小样本外推中国全部人群。';b['time_scale']={'onset':None,'duration':None,'recovery':None,'missing_reason':'暴露设计各异，不存在本任务已验证的统一损伤或恢复时间。'};b['support']='CDC指导和既有研究的暴露定义；不是新的临床因果发现。';b['counterevidence']='不同暴露/终点不宜直接合并，不能把未显著差异视作无害或等效。';b['modifiers']={'amplifiers':None,'mitigators':None,'missing_reason':'日常调节因素对皮肤终点的效应未核实。'}
    b['solution_path']= '先区分暴露，再把一般睡眠行动与对应皮肤需求分别处理；不承诺补偿作用。'
    b['priority_order']={'SK-BEH-001-B03':1,'SK-BEH-001-B04':1,'SK-BEH-001-B02':2,'SK-BEH-001-B01':3}[i]
beh['closedloop_revision']['interest_boundary']='RES-I01属于干燥主题，未移作睡眠/熬夜主题的兴趣证据；行为型平台信号仍未核实。'
beh['closedloop_revision']['budget_boundary']='沿用历史13次查询/5项科学合格深读；本轮离线复用不增加查询。G008未知筛读数及历史禁用路线重试偏差仍保留。'
g=find(beh,'gaps','SK-BEH-001-G009');g['description']+=' 本轮方法重组与S004无OA记录不构成质量评分或独立专业审核完成。';g['revision']=br
beh['gaps'].append({'id':'SK-BEH-001-G011','run_id':beh['run_id'],'revision':br,'demo':False,'scope_id':beh['run_id'],'category':'current_revision_review','description':'本轮closedloop-r1已重组材料、分支及候选；旧G010关闭只覆盖历史版本，本轮尚待主控核验及所需独立专业审核。','critical':True,'status':'open','closure_source_ids':[],'closure_note':'不能以历史独立AI审计、生成新包或定向结构验证代替本轮专业证据审核。'})

def decisions_and_candidates(d):
    rev=d['revision']; prefix='RES' if d['mode']=='result' else 'SK-BEH-001';mapping={}
    for n,b in enumerate(d['branches'],1):
        i=f'{prefix}-CL-D-R{n:02d}';mapping[b['id']]=i
        d['decisions'].append({'id':i,'run_id':d['run_id'],'revision':rev,'demo':False,'stage':'review','actor_type':'controller_delegate','actor_label':'主控授权施工代理','qualification':None,'decided_at':NOW,'input_revision':rev,'branch_id':b['id'],'candidate_id':None,'action':'gap','reason':b['preliminary_judgment']+' '+b['priority_rationale']+' 代理决定：保留有限表达并继续补证，coverage仍partial，不准入正式候选。','required_changes':['保留具体人群、终点及时间限制','未核质量与兴趣不得提级','独立专业审核未完成；当前记录非用户确认']})
        b['review_decision_ids']=[i]
        if d['mode']=='behavior':b['review_decision']=i
    if d['mode']=='result':
        specs=[('RES-K01','干燥紧绷先怎么判断：描述体验、核对触发、守住评估边界',['RES-B04','RES-B01','RES-B02'],'primary'),('RES-K02','保湿改善了什么：读懂含水、外观与修复的距离',['RES-B05','RES-B03'],'supporting'),('RES-K03','环境与清洁行动并入主方向',['RES-B02'],'merged_into_RES-K01'),('RES-K04','自我护理停止边界并入主方向',['RES-B04'],'merged_into_RES-K01'),('RES-K05','年龄和部位作为全包适用性检查',['RES-B06'],'limited_background')]
    else: specs=[('SK-BEH-001-A001','先说清睡眠暴露，再安排睡眠与日常护理',['SK-BEH-001-B04','SK-BEH-001-B03'],'primary'),('SK-BEH-001-A002','熬夜研究分别测到了什么',['SK-BEH-001-B02'],'supporting'),('SK-BEH-001-A003','短期照片感知的有限发现',['SK-BEH-001-B01'],'limited_background')]
    for i,title,bs,selection in specs:
        a=next((x for x in d['candidates'] if x['id']==i),None)
        if a is None:a={'id':i,'run_id':d['run_id'],'demo':False};d['candidates'].append(a)
        branches=[find(d,'branches',b) for b in bs];claims=list(dict.fromkeys(x for b in branches for x in b['claim_ids']))
        sci=list(dict.fromkeys(x for b in branches for x in b['gaps']));interest=['RES-G01','RES-G07'] if d['mode']=='result' else ['SK-BEH-001-G003','SK-BEH-001-G004']
        why='结果型先处理评估边界与上游触发，再解释护理；同源视频仅改善表达素材，不证明需求。' if d['mode']=='result' else '行为型先定义可改变的睡眠暴露和行动，机制与外观只作有限解释；不移用干燥视频的兴趣。'
        a.update(revision=rev,input_revision=rev,title=title,branch_ids=bs,claim_ids=claims,review_decision_ids=[mapping[b] for b in bs],signal_ids=[s['id'] for s in d['signals']],science_gate={'status':'blocked','strength':'unknown','reasons':['来源完整性、质量/独立性及外推仍有缺口；代理审阅不等于强科学准入。',why],'gap_ids':sci},interest_gate={'status':'unknown','level':'unknown','reasons':['缺少可比样本、目标受众和基线；单条内容或受限索引不能确定需求。'],'comparison_basis':None,'gap_ids':interest},allowed_expression=[b['solution_path'] for b in branches],forbidden_expression=['将含缺口草案当正式合格选题。','给出普遍诊断、疗效或恢复时间。'],status='draft',selection=selection,selection_class='trial_with_gaps',formal_admission=False,current_review_status='controller_reviewed_with_gaps',selection_reason=why+' '+('合并入主方向，避免重复单列。' if selection.startswith('merged') else '仅内部试运行解释优先级。'))
    for n,a in enumerate(d['candidates'],1):
        d['decisions'].append({'id':f'{prefix}-CL-D-D{n:02d}','run_id':d['run_id'],'revision':rev,'demo':False,'stage':'direction','actor_type':'controller_delegate','actor_label':'主控授权施工代理','qualification':None,'decided_at':NOW,'input_revision':rev,'branch_id':None,'candidate_id':a['id'],'action':'merge' if a['selection'].startswith('merged') else 'select_trial' if a['selection']=='primary' else 'retain_limited','reason':a['selection_reason'],'classification':'trial_with_gaps','required_changes':['科学门槛blocked、兴趣unknown、正式准入false；保持缺口。']})
    pkg=d['package'];pkg.pop('independent_audit_closeout',None);pkg.pop('process_state_correction',None);pkg.pop('packaging_correction',None)
    pkg.update(type='trial_with_gaps',formal_release=False,frozen_by='controller_delegate',controller_decision_recorded_at=NOW,authority_note='本轮主控授权施工代理依据本地材料重新记录；旧决定只作历史。非用户确认、临床审核或独立专业审核。',input_revision=rev,primary_candidate_id=specs[0][0],supplemental_candidate_ids=[specs[1][0]],open_gap_ids=[g['id'] for g in d['gaps'] if g['status']=='open'],next_action='主控核验本轮材料/可见内容及代理决定；未核方法、质量、目标受众和预算归账保持开放。当前授权不包含新网络检索、发布或入库。')
    if d['mode']=='result':
        order=['RES-B04','RES-B01','RES-B02','RES-B05','RES-B03','RES-B06'];pkg['synthesis']='结果型：先守住持续不缓解时的评估边界，再描述干燥/紧绷表象、核对环境与清洁触发，分清测量和机制后解释基础保湿。RES-S03本地方法使5周女性小腿观察更具体，但对照、阈值冲突、补充方法与外推仍有限；AAD视频只作同源行动表达。';pkg['selected_direction_reason']='K01合并症状定义、触发因素与停止边界；K02承担终点/配方解释；K03/K04并入K01，K05仅横向适用检查。无正式合格赢家。';pkg['other_branches']='B03/B05为证据解释，B06为全包适用性检查；没有独立市场准入。';pkg['limited_background_candidate_ids']=['RES-K05'];pkg['merged_candidate_ids']=['RES-K03','RES-K04']
    else:
        order=['SK-BEH-001-B04','SK-BEH-001-B03','SK-BEH-001-B02','SK-BEH-001-B01'];pkg['synthesis']='行为型：先分清睡眠时长、质量、规律性与急性剥夺，再优先处理可改变的睡眠行为；按实际皮肤需要安排基础护理。节律机制、局部测量、观察关联与照片评分分层，护理补偿、长期老化和恢复时间均无可泛化结论。';pkg['selected_direction_reason']='A001依可改变性和一般健康指导作为试运行主方向；A002补证据层级，A003仅受限背景，不用外观恐惧推高优先级。干燥主题AAD视频不转作睡眠兴趣。';pkg['other_branches']='B02/B01不能推出临床损伤、长期老化、真实社交结果或固定恢复时间。'
    pkg['knowledge_chain']=[{'order':n,'branch_id':i,'title':find(d,'branches',i)['title'],'content':find(d,'branches',i)['preliminary_judgment'],'claim_ids':find(d,'branches',i)['claim_ids'],'source_ids':find(d,'branches',i)['source_ids'],'solution_path':find(d,'branches',i)['solution_path'],'priority_rationale':find(d,'branches',i)['priority_rationale'],'coverage':'partial'} for n,i in enumerate(order,1)]
    pkg['chain_note']='上述为解释和行动优先顺序；不同研究间没有自动成立的连续因果关系。代理冻结属于当前输入的留档，不等于用户或临床确认；工作台导入后仍须按既有机制重新确认。'
    pkg['candidate_import_attachment'].update(status='not_submitted',auto_import=False,formal_candidates=[],draft_candidate_refs=[{'candidate_id':a['id'],'branch_ids':a['branch_ids'],'claim_ids':a['claim_ids'],'review_decision_ids':a['review_decision_ids'],'proposed_record_state':'draft_pending_current_revision_review','formal_admission':False,'selection':a['selection']} for a in d['candidates']],reason='本轮仅提供可追溯草案附件；当前科学blocked、兴趣unknown，禁止自动入库。历史独立AI审核不覆盖本轮改写。')
    pkg['expression_boundaries']={'allowed':[b['solution_path'] for b in d['branches']],'forbidden':['把感受、单项指标、机制或相关性写成普遍疾病诊断/疗效。','给出固定恢复期限、护肤补偿缺觉或泛化产品承诺。','把机构同源传播计作独立科学复核，把单视频互动当主题需求。'],'timing':'仅保留各研究观察时点；发生、持续、恢复曲线未核实。'}
    return prefix

def freeze(d,prefix):
    rev=d['revision']; parent=None
    for kind in ['review','direction','package']:
        payload=copy.deepcopy(d)
        # Each physical freeze contains the actual stage state; previous decisions cannot count as this review.
        if kind=='review':payload['decisions']=[x for x in payload['decisions'] if x['stage']=='review'];payload['candidates']=[];payload.pop('package',None)
        payload['status']={'review':'reviewed','direction':'directions_confirmed','package':'frozen'}[kind]
        payload['freeze_stage']={'kind':kind,'parent_snapshot_id':parent,'input_revision':rev,'actor_type':'controller_delegate','qualification':'非用户或临床确认；含缺口试运行。'}
        bodyhash=hashlib.sha256(canon(payload).encode()).hexdigest(); path=W/(d['run_id']+'-closedloop-r1-'+kind+'-freeze.json')
        if path.exists():raise RuntimeError('禁止覆盖新冻结 '+str(path))
        dump(path,{'schema_version':'sk-research-audit-snapshot/1.0','kind':kind,'created_at':NOW,'actor_type':'controller_delegate','payload_sha256':bodyhash,'payload':payload})
        sid=prefix+'-CL-F-'+kind
        d['snapshots'].append({'id':sid,'run_id':d['run_id'],'revision':rev,'demo':False,'kind':kind,'created_at':NOW,'actor_type':'controller_delegate','actor_label':'主控授权施工代理','qualification':'非用户、临床或独立专业确认','input_revision':rev,'config_sha256':d['config_ref']['sha256'],'content_sha256':bodyhash,'decision_ids':[x['id'] for x in payload['decisions']],'candidate_ids':[x['id'] for x in payload.get('candidates',[])],'status':'frozen','invalidation_reason':None,'audit_path':str(path),'audit_origin':'external_history','classification':'review_record' if kind=='review' else 'trial_with_gaps','delivery_class':'trial_with_gaps','parent_snapshot_id':parent})
        parent=sid
    d['status']='frozen'

for d in [res,beh]:
    prefix=decisions_and_candidates(d)
    if 'stage_report' in d:
        d['closedloop_revision']['historical_stage_report']=copy.deepcopy(d['stage_report'])
    d['stage_report']={'stage':'package','state':'controller_delegate_frozen_trial_with_gaps','input_revision':d['revision'],'review_gate':'controller_delegate_reviewed_with_gaps','direction_gate':'controller_delegate_trial_with_gaps','saturation_reached':False,'saturation_reason':'离线有界修订不等于证据饱和；方法、独立性、兴趣和归账缺口仍开放。','priority_order':[x['branch_id'] for x in d['package']['knowledge_chain']],'priority_basis':d['package']['selected_direction_reason'],'completion_limit':'本轮仅完成代理材料重组与冻结；当前版本尚待主控核验，未完成独立专业审核或正式准入。','next_action':d['package']['next_action']}
    if d.get('audit_provenance'):
        d['audit_provenance']['current_revision_scope']='本对象记录均为历史版本审计来源，不覆盖closedloop-r1；本轮代理决定见decisions，本轮独立专业审核未完成。'
        d['audit_provenance']['independent_review']['applies_to_current_revision']=False
    if d.get('coverage_audit'):
        d['coverage_audit']['scope_note']='沿用原运行配置时间窗和历史获取证据；本轮离线重组，不表示新增外部检索或审核。'
    d['limitations']=extend_value(d.get('limitations',[]),['本轮为已授权离线闭环：本地来源记录/附件、已有知识库导出和平台内容的代理整理；未知项保持开放。所有科学质量与兴趣门槛未通过，没有正式合格选题。'])
    freeze(d,prefix)
dump(W/'SK-RES-001.json',res);dump(W/'research-SK-BEH-001.json',beh);dump(D/'acquisition-results.json',acq)
shutil.copy2(__file__,T/'closedloop-update.py')
with (W/'闭环施工记录.md').open('a') as f:
    f.write('\n实现候选已写入（'+NOW+'）：结果型6分支/6主张/5草案、行为型4分支/8主张/3草案；两份process JSON、acquisition-results.json及6份closedloop-r1新冻结。旧决定移入historical_decisions，旧冻结索引标失效，物理原件保持。备份/基线在既有2026-09-26_UI正式接入目录的closedloop-before-*与closedloop-baseline.json。下一步构建页面并进行一次定向验证；当前尚未验证。\n')
print(json.dumps({'revisions':[res['revision'],beh['revision']],'new_freezes':6,'data_files':3,'status':'implementation_candidate_ready'},ensure_ascii=False))

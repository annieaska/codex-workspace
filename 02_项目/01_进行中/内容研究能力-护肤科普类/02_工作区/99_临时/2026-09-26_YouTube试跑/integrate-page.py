from pathlib import Path
import json, re, shutil
P=Path('/Users/chengyu/12_打工人程宇/02_项目/01_进行中/内容研究能力-护肤科普类')
D=P/'03_交付物/护肤科普研究首版'
T=P/'02_工作区/99_临时/2026-09-26_YouTube试跑'
for name in ['workbench-app.js','workbench.template.html','build_workbench.py','acquisition-results.json','README.md']:
    dest=T/('before-'+name)
    if not dest.exists():shutil.copy2(D/name,dest)
shutil.copy2(P/'PROJECT.md',T/'before-PROJECT.md')
old=json.loads((D/'acquisition-results.json').read_text())
assert old['schema_version']=='1.0'
items=old.pop('items')
old.pop('schema_version')
for item in items:
    item['kind']='article'
    item['batch_id']=old['batch_id']
attempt=json.loads((T/'yt-dlp-attempt.json').read_text())
v=attempt['metadata']
vtt=(T/'biIzSPOEQgQ.en.vtt').read_text()
txt=(T/'biIzSPOEQgQ.en.txt').read_text()
batch_id='YOUTUBE-PILOT-20260926'
raw='../../02_工作区/99_临时/2026-09-26_YouTube试跑/'
video={
    'id':'YT-PILOT-RES-I01','kind':'video','run_id':'SK-RES-001','signal_id':'RES-I01','batch_id':batch_id,
    'title':v['title'],'status':'retrieved','channel':'YouTube → yt-dlp',
    'observed_at':attempt['observed_at'],
    'result_summary':'已取得 AAD 公开视频的账号、发布日期、播放／点赞／评论数，以及英文自动字幕。',
    'limits':['自动字幕未经人工校对；未对照音轨逐秒核验完整性。','互动数字是获取时的快照；未取得评论正文或受众地区，也缺少可比样本，兴趣门槛仍待核验。','这是已有线索补取，不是新增检索或合格科学深读。'],
    'raw_evidence':raw+'yt-dlp-attempt.json',
    'video':{'id':v['id'],'url':v['webpage_url'],'channel':v['channel'],'channel_id':v['channel_id'],'channel_url':v['channel_url'],
        'published_on':f"{v['upload_date'][:4]}-{v['upload_date'][4:6]}-{v['upload_date'][6:]}",
        'duration_seconds':v['duration'],'description':v['description'],
        'metrics':{'views':v['view_count'],'likes':v['like_count'],'comments':v['comment_count']},
        'subtitles':{'language':'en','kind':'automatic','manually_reviewed':False,'completeness_verified':False,
            'cue_count':len(re.findall(r'^\d{2}:\d{2}:\d{2}\.\d{3} -->',vtt,re.M)),
            'text_line_count':len(txt.strip().splitlines()),'text':txt,'vtt':vtt,
            'processing':'纯文本移除 VTT 标签并仅去掉相邻重复行；原始时间片保留在 VTT。',
            'raw_evidence':raw+'biIzSPOEQgQ.en.vtt'}}}
items.append(video)
acq={'schema_version':'2.0','note':'按研究任务展示真实补取成果。补取不改变原研究记录、预算或准入结论。',
    'batches':[old,{'batch_id':batch_id,'acquired_on':attempt['observed_at'][:10],'tool':attempt['tool'],'tool_version':attempt['tool_version'],
        'provider':'YouTube 公开页面（yt-dlp 提取）','counts':{'existing_videos':1,'subtitle_success':1,'new_sources':0,'topic_queries':0,'new_qualified_reads':0},
        'note':'沿用 RES-I01 已有链接；无新关键词搜索、登录、音视频下载或评论正文读取。'}], 'items':items}
(D/'acquisition-results.json').write_text(json.dumps(acq,ensure_ascii=False,indent=2)+'\n')
p=D/'workbench-app.js';s=p.read_text()
def replace(old,new):
    global s
    assert s.count(old)==1,(old[:110],s.count(old))
    s=s.replace(old,new)
replace("ACQ=boot.acquisitions||{items:[],counts:{}}", "ACQ=boot.acquisitions||{items:[],batches:[]}")
replace("查看 PubMed 获取成果 · ${acq.filter(x=>x.status==='retrieved').length} 份正文取得 / ${acq.length} 篇尝试 →", "查看获取成果 · ${esc(acquisitionSummary(acq))} →")
replace('PubMed 小样共尝试 2 篇已有文献：1 篇取得正文，1 篇未取得开放全文。新增来源 0，新增合格深读 0。本页只显示当前任务的 ${acq.length} 条。', '${esc(acquisitionSummary(acq))}。均为已有资料补取；获取成功不等于质量审核或兴趣门槛通过。')
start=s.index('function materialRow(');end=s.index('function branchChoices(',start)
s=s[:start]+'''function materialRow(x,key){
 const acquisition=key==='acquisitions',latest=key==='signals'?signalAcquisition(x):null,title=x.title||x.text||x.indexed_title||`${x.platform} 平台线索`,summary=acquisition?x.result_summary:latest?latest.result_summary:x.excerpt_or_summary||x.allowed_expression||x.missing_reason||'',status=acquisition?acquisitionStatus(x):key==='sources'?L(x.read_level):key==='signals'?latest?'已补取 · 兴趣待核验':'兴趣待核验':'需限定表达';
 return `<article class="data-row"><div class="grow"><div class="meta"><span class="mono muted">${esc(x.id)}</span>${tag(status,acquisition||key==='signals'?'blue':'')}</div><h3><button class="linkbtn" data-detail="${key}" data-id="${esc(x.id)}">${esc(title)}</button></h3><p class="description clamp">${esc(arr(summary).join('；'))}</p>${key==='sources'?sourceBadges(x):acquisition?`<div class="provenance">${tag(x.channel)}${tag('已有资料补取')}${tag(acquisitionBatch(x).acquired_on)}</div>`:latest?`<div class="provenance">${tag('YouTube · 英文自动字幕')}${tag(acquisitionBatch(latest).acquired_on)}</div>`:''}</div><div class="trailing"><button class="linkbtn small" data-detail="${key}" data-id="${esc(x.id)}">${acquisition&&x.status==='retrieved'?'阅读获取内容':'查看详情'} ↗</button></div></article>`;
}
''' + s[end:]
# Keep historical signal facts in a clearly labeled section; attach the separate acquisition.
start=s.index("else if(key==='signals'){",s.index('function detail('));end=s.index("else if(key==='snapshots')",start)
s=s[:start]+'''else if(key==='signals'){const latest=signalAcquisition(x);title=x.indexed_title||`${x.platform} 平台线索`;const historical=`<dl class="details-list"><div><dt>原记录未核验原因</dt><dd>${textValue(x.missing_reason)}</dd></div><div><dt>日期与账号</dt><dd>发布时间：${esc(x.published_at||'未知')}<br>账号：${esc(x.account||'未知')}</dd></div><div><dt>互动指标</dt><dd>${textValue(x.metrics?Object.fromEntries(Object.entries(x.metrics).map(([k,v])=>[({views:'播放量',likes:'点赞数',comments:'评论数'})[k]||k,v])):'未知')}</dd></div><div><dt>受众地区</dt><dd>${textValue(x.audience_region)}</dd></div></dl>`;body=`<div class="row wrap">${tag(x.platform)}${tag('兴趣待核验','warn')}</div>${latest?`<div class="note mt"><strong>已补取视频资料与自动字幕</strong><p>${esc(latest.result_summary)}</p><p class="small muted">获取时间：${esc(observedLabel(latest.observed_at))}。新成果单独保存，原研究记录保留。</p></div>${videoFacts(latest)}<button class="primary mt" data-detail="acquisitions" data-id="${esc(latest.id)}">查看视频与字幕 →</button><details><summary>查看原研究记录 · ${esc(x.observed_at||'日期未记录')}</summary>${historical}</details>`:`<div class="note warn mt">目前仅为索引或受限访问线索，不能用来判定内容热度。</div>${historical}`}<p class="small muted mt">缺少受众地区与可比依据，单条视频不能证明主题热度。</p><p class="mt">${/^https?:\\/\\//.test(x.url||'')?`<a href="${esc(x.url)}" target="_blank" rel="noopener noreferrer">查看平台原页 ↗</a>`:'未记录线索链接'}</p>`}
''' + s[end:]
replace("else if(e.target.id==='article-part'){articlePart(e.target.dataset.id,e.target.value)}", "else if(e.target.id==='article-part'){articlePart(e.target.dataset.id,e.target.value)}else if(e.target.id==='video-part'){videoPart(e.target.dataset.id,e.target.value)}")
replace("function acquisitions(){return (ACQ.items||[]).filter(a=>a.run_id===D().run_id&&D().sources.some(s=>s.id===a.source_id))}", '''function acquisitions(){return (ACQ.items||[]).filter(a=>a.run_id===D().run_id&&(a.kind==='video'?D().signals.some(s=>s.id===a.signal_id):D().sources.some(s=>s.id===a.source_id)))}
function acquisitionBatch(a){return ACQ.batches.find(b=>b.batch_id===a.batch_id)||{}}
function acquisitionExport(){const items=acquisitions();return {...ACQ,run_id:D().run_id,items,batches:ACQ.batches.filter(b=>items.some(a=>a.batch_id===b.batch_id))}}
function signalAcquisition(s){return acquisitions().find(a=>a.kind==='video'&&a.signal_id===s.id)}
function acquisitionStatus(a){return a.kind==='video'?'视频资料与自动字幕已取得':a.status==='retrieved'?'正文已取得 · 待质量核验':'未取得开放全文'}
function acquisitionSummary(items){const papers=items.filter(a=>a.kind==='article'),videos=items.filter(a=>a.kind==='video');return [papers.length?`论文 ${papers.length} 篇（正文取得 ${papers.filter(a=>a.status==='retrieved').length} 篇）`:'',videos.length?`YouTube ${videos.length} 条（含自动字幕）`:''].filter(Boolean).join('；')||'当前任务暂无补取成果'}
function observedLabel(value){return value?new Date(value).toISOString().slice(0,19).replace('T',' ')+' UTC':'未记录'}
function videoFacts(a){const v=a.video,n=x=>x==null?'未取得':Number(x).toLocaleString('en-US');return `<dl class="details-list"><div><dt>发布账号</dt><dd>${esc(v.channel)}</dd></div><div><dt>发布时间 / 时长</dt><dd>${esc(v.published_on)} · ${Math.floor(v.duration_seconds/60)} 分 ${v.duration_seconds%60} 秒</dd></div><div><dt>互动数据快照</dt><dd>播放 ${n(v.metrics.views)} · 点赞 ${n(v.metrics.likes)} · 评论数 ${n(v.metrics.comments)}<p class="small muted">采集于 ${esc(observedLabel(a.observed_at))}；评论数不代表已取得评论正文。</p></dd></div></dl>`}
function videoDetail(a){const v=a.video;showDialog('YouTube 获取成果',`<div class="row wrap">${tag('YouTube','blue')}${tag('英文自动字幕')}${tag('已有线索补取')}</div><h3 class="mt">${esc(a.title)}</h3><p class="small muted mt">关联平台线索 ${esc(a.signal_id)} · 获取于 ${esc(observedLabel(a.observed_at))}</p><div class="operation-bar"><a href="${esc(v.url)}" target="_blank" rel="noopener noreferrer">打开原视频 ↗</a><a href="${esc(v.channel_url)}" target="_blank" rel="noopener noreferrer">查看发布账号 ↗</a></div><div class="field mt"><label for="video-part">选择查看内容</label><select id="video-part" data-id="${esc(a.id)}"><option value="overview">视频资料与互动快照</option><option value="transcript">英文自动字幕 · 阅读版</option><option value="vtt">英文自动字幕 · 原始时间片</option></select></div><div id="video-content" class="mt"></div><details><summary>获取来源与使用限制</summary><p class="small">获取渠道 ${esc(a.channel)} · ${esc(acquisitionBatch(a).tool_version)}<br>批次 ${esc(a.batch_id)}<br>原始证据 ${esc(a.raw_evidence)}<br>字幕证据 ${esc(v.subtitles.raw_evidence)}</p>${a.limits.map(x=>`<p class="small mt">${esc(x)}</p>`).join('')}</details>`,'',$('#dialog').open);videoPart(a.id,'overview')}
function videoPart(id,part){const a=acquisitions().find(x=>x.id===id),el=$('#video-content');if(!a?.video||!el)return;const v=a.video,sub=v.subtitles;if(part==='overview'){el.innerHTML=`${videoFacts(a)}<p class="note">已取得 ${sub.cue_count} 条字幕时间片，整理为 ${sub.text_line_count} 行英文。自动字幕尚未经人工校对，兴趣门槛仍待核验。</p><details><summary>视频简介（原文）</summary><div class="reader video-reader mt" role="region" aria-label="视频简介原文" tabindex="0">${esc(v.description)}</div></details>`}else{const raw=part==='vtt';el.innerHTML=`<p class="note">英文自动字幕，未经人工校对。${raw?'原始 VTT 保留时间戳及滚动字幕的重复文本。':esc(sub.processing)}</p><div class="reader video-reader mt" role="region" aria-label="${raw?'字幕原始时间片':'字幕阅读内容'}" tabindex="0">${esc(raw?sub.vtt:sub.text)}</div><div class="operation-bar"><button data-action="export-subtitle-text" data-id="${esc(id)}">下载字幕 TXT ↓</button><button data-action="export-subtitle-vtt" data-id="${esc(id)}">下载原始 VTT ↓</button></div>`}}
''')
# Article provenance now uses its own batch rather than an incorrect global provider.
replace('${esc(ACQ.acquired_on)}','${esc(acquisitionBatch(a).acquired_on)}') if s.count('${esc(ACQ.acquired_on)}')==1 else None
# Same substitution occurs once in provenanceDetails and once in acquisitionDetail.
s=s.replace('${esc(ACQ.acquired_on)}','${esc(acquisitionBatch(a).acquired_on)}')
replace("if(!a)return;const v=a.article;", "if(!a)return;if(a.kind==='video'){videoDetail(a);return;}const batch=acquisitionBatch(a),v=a.article;")
replace('${esc(ACQ.tool)} · ${esc(ACQ.provider)}<br>批次 ${esc(ACQ.batch_id)}<br>证据位置 ${esc(a.raw_evidence)}<br>${esc(ACQ.note)}','${esc(batch.tool)} · ${esc(batch.provider)}<br>批次 ${esc(batch.batch_id)}<br>证据位置 ${esc(a.raw_evidence)}<br>${esc(batch.note)}')
replace('acquisitions:{...ACQ,items:acquisitions()}', 'acquisitions:acquisitionExport()')
replace('function handleAction(a){', 'function handleAction(a,b){')
replace("else if(a==='export-acquisitions')download(ACQ,'PubMed-实际获取成果.json')", "else if(a==='export-acquisitions')download(acquisitionExport(),D().run_id+'-实际获取成果.json');else if(a==='export-subtitle-text'||a==='export-subtitle-vtt'){const v=acquisitions().find(x=>x.id===b.dataset.id)?.video;if(v){const raw=a==='export-subtitle-vtt';download(raw?v.subtitles.vtt:v.subtitles.text,v.id+'.en.'+(raw?'vtt':'txt'),raw?'text/vtt':'text/plain')}}")
replace('在“科学来源”查原有证据，在“获取成果”读工具实际取回的内容；打开详情核对来源、适用人群和局限。','在“获取成果”阅读论文正文或视频字幕；在“平台线索”看补取进展。打开详情核对来源、获取时间和局限。')
p.write_text(s)
p=D/'workbench.template.html';s=p.read_text();s=s.replace('.reader-table table{','.video-reader{max-height:300px;overflow:auto;overscroll-behavior:contain;padding:14px;border:1px solid var(--line);background:#fff;overflow-wrap:anywhere}\n.reader-table table{');p.write_text(s)
p=D/'build_workbench.py';s=p.read_text();assert 'SK-WORKBENCH-20260926-r2' in s;s=s.replace('SK-WORKBENCH-20260926-r2','SK-WORKBENCH-20260926-r3');p.write_text(s)
print('Acquisition schema and workbench candidate updated; 2 articles + 1 YouTube video.')

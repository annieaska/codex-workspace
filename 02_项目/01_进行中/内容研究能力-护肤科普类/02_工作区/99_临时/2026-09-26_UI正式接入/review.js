function review(){
 const b=byId('branches',S().branch)||D().branches[0],s=S();
 let h=heading('分支审阅','逐支填写意见，提交全部后可冻结本版审阅。',`<div class="operation-bar"><button data-action="submit-reviews" ${D().branches.length?'':'disabled'}>提交全部审阅</button><button data-action="freeze-review" ${C.allReviewed(D())&&!Object.keys(s.drafts).length?'':'disabled'}>冻结审阅</button></div>`);
 if(!b)return h+'<div class="empty"><strong>尚无研究分支</strong><p>先取得材料并导入研究记录，再进行审阅。</p></div>';
 s.branch=b.id;
 return h+`<div class="split">${branchChoices()}<article class="detail"><div class="detail-head"><div class="row between"><span class="mono muted">${esc(b.id)}</span>${tag(L(b.coverage),'warn')}</div><h2>${esc(b.title)}</h2>${tabs('branchTab',[['overview','判断概览'],['claims','主张与证据'],['bounds','适用边界'],['records','审阅记录']],s.branchTab)}</div><div class="detail-scroll" role="tabpanel" id="panel-branchTab" aria-labelledby="tab-branchTab-${s.branchTab}">${branchContent(b)}</div><footer class="detail-foot"><span class="muted small">${s.drafts[b.id]?'有待提交意见 · 刷新前请提交并保存':C.latest(D(),'review')?'本版审阅已冻结':C.review(D(),b.id)?'本支意见已记录':'本支等待本版审阅'}</span><button class="primary" data-action="review-form">填写审阅意见 ${icon('arrow')}</button></footer></article></div>`;
}

// Shared review-only interactions. Uses the synthetic preview model.
const tokens = JSON.parse(document.getElementById('design-tokens').textContent);
let entries = structuredClone(demoEntries), policy = structuredClone(demoPolicy), lastKnown = new Map(entries.map(entry=>[entry.id,structuredClone(entry)])), revision = 0, route = 'library', filter = 'all', selected = entries[0].id, selectedProfile = 'app', selectedGroup = '앱 개발', planState = null, history = [];
const $ = id => document.getElementById(id);
const escapeHTML = value => String(value).replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
const demoVaultPath = entry => '~/Library/Application Support/AgentSkillManager/Disabled/'+entry.rootId+'/'+entry.id+'/payload/'+entry.path.split('/').at(-1);
const icon = name => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${document.getElementById('i-'+name).innerHTML}</svg>`;
const stateLabel = state => ({on:'발견 위치에 있음',off:'보관됨',unknown:'파일 상태 미확인'}[state]??'파일 상태 미확인');
function setTheme(dark) {
 document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
 for (const [name,value] of Object.entries(tokens.primitive.color[dark?'dark':'light'])) document.documentElement.style.setProperty('--c-'+name,value);
 for (const [name,value] of Object.entries(tokens.primitive.radius)) document.documentElement.style.setProperty('--radius-'+name,value+'px');
 for (const [name,value] of Object.entries(tokens.primitive.fontSize)) document.documentElement.style.setProperty('--font-'+name,value+'px');
 for (const [name,value] of Object.entries(tokens.primitive.motion)) document.documentElement.style.setProperty('--motion-'+name,value+'ms');
 const resolve = path => path.split('.').reduce((object,key)=>object[key],tokens);
 for (const [name,path] of Object.entries(tokens.semantic.radius)) document.documentElement.style.setProperty('--radius-'+name,resolve(path)+'px');
 for (const [variable,path] of Object.entries({'tile-radius':tokens.component.tile.radius,'finding-radius':tokens.component.finding.radius,'finding-padding':tokens.component.finding.padding,'sheet-padding':tokens.component.sheet.padding})) {
  let value=resolve(path);if(typeof value==='string')value=resolve(value);document.documentElement.style.setProperty('--'+variable,value+'px');
 }
 for (const [variable,value] of Object.entries({'sidebar-width':tokens.component.layout.sidebarWidth,'list-width':tokens.component.layout.listWidth,'tile-min-height':tokens.component.tile.minHeight,'row-min-height':tokens.component.row.minHeight,'sheet-width':tokens.component.sheet.width})) document.documentElement.style.setProperty('--'+variable,value+'px');
 $('theme').setAttribute('aria-pressed',String(dark));$('theme').textContent=dark?'밝은 모드':'어두운 모드';
}
function message(text) {$('status').textContent=text;}
function inScope(entry) {return $('scope').value==='all'||entry.agent===$('scope').value;}
function inOriginScope(entry) {const origin=$('origin-filter')?.value||'all';return origin==='all'||(repositoryFor(entry)?.id??'unknown')===origin;}
function provenanceHTML(entry) {
 const provenance=demoProvenance[entry.id],repository=repositoryFor(entry);
 return `<h3>출처 저장소</h3><div class="card">${repository?`<h3>${escapeHTML(repository.name)}</h3><dl class="kv"><dt>출처 근거</dt><dd>${escapeHTML(provenance.evidence)}</dd><dt>내부 위치</dt><dd class="path">${escapeHTML(provenance.relativePath)}</dd><dt>설치 방식</dt><dd>${escapeHTML(provenance.method)}</dd><dt>설치 버전</dt><dd>미확인</dd></dl><p>출처 연결은 관리 권한을 바꾸지 않습니다. 이 기록은 화면 검토용 예시입니다.</p>`:'<h3>출처 미확인</h3><p>이름만으로 저장소를 추정하지 않습니다. 실제 앱에서는 설치 근거를 확인하거나 사용자가 출처를 연결합니다.</p>'}</div>`;
}
function matches(text) {return text.toLowerCase().includes($('search').value.toLowerCase().trim());}
function statusHTML(entry) {return `<span class="status ${entry.state==='on'?'':entry.state}"><span class="dot ${entry.state==='on'?'':entry.state}"></span>${stateLabel(entry.state)}</span>`;}
function rowHTML(entry) {return `<button class="entry ${entry.id===selected?'selected':''}" data-entry="${entry.id}" aria-pressed="${entry.id===selected}" aria-label="${escapeHTML(entry.name+' · '+entry.agent+' · '+entry.location+' · '+stateLabel(entry.state))}"><span class="entry-icon">${icon(entry.kind==='link'?'link':entry.writable?'document':'lock')}</span><span class="entry-text"><span class="entry-name">${escapeHTML(entry.name)}</span><span class="entry-description">${escapeHTML(entry.description)}</span><span class="entry-location" style="display:block;font-size:11px;overflow-wrap:anywhere" title="${escapeHTML(entry.location)}">${escapeHTML(entry.location)}</span><span class="entry-meta"><span>${entry.agent}</span><span>·</span><span>${entry.state==='on'?'발견됨':entry.state==='off'?'보관됨':'미확인'}</span>${entry.writable?'':`<span>· 읽기 전용</span>`}${entry.findings?`<span>· 확인 ${entry.findings}</span>`:''}</span></span></button>`;}
function drawTiles() {
 const scopeEntries=entries.filter(inScope).filter(e=>route!=='library'||inOriginScope(e)), counts={all:scopeEntries.length,on:scopeEntries.filter(e=>e.state==='on').length,off:scopeEntries.filter(e=>e.state==='off').length,attention:scopeEntries.filter(e=>e.findings||e.state==='unknown').length,readonly:scopeEntries.filter(e=>!e.writable).length,favourite:scopeEntries.filter(e=>e.favourite).length};
 document.querySelector('[data-route="findings"] .count').textContent=String(entries.filter(inScope).reduce((sum,entry)=>sum+entry.findings,0));
 const tileDefs=[['all','전체','layers',''],['on','발견됨','power','success'],['off','보관됨','box','neutral'],['attention','확인 필요','warning','warning'],['readonly','읽기 전용','lock','purple'],['favourite','즐겨찾기','star','warning']];
 $('tiles').innerHTML=tileDefs.map(([id,label,symbol,color])=>`<button class="tile ${color} ${route==='library'&&filter===id?'selected':''}" data-filter="${id}" aria-pressed="${route==='library'&&filter===id}"><span class="tile-top">${icon(symbol)}<strong>${counts[id]}</strong></span><span class="tile-label">${label}</span></button>`).join('');
}
function detailHTML(entry) {
 if(!entry)return '<div class="empty"><strong>선택한 항목이 없습니다</strong>검색어나 조회 범위를 바꿔보세요.</div>';
 const counterparts=entries.filter(e=>sourceEntryId(e,policy)===entry.id||e.id===sourceEntryId(entry,policy));
 return `<div class="detail-title"><span class="large-icon">${icon(entry.kind==='link'?'link':entry.writable?'layers':'lock')}</span><div><h2>${escapeHTML(entry.name)}</h2><div class="row" style="margin-top:5px">${statusHTML(entry)}${!entry.writable?'<span class="pill">읽기 전용</span>':''}</div></div></div><p>${escapeHTML(entry.description)}</p><div class="actions inline-actions">${entry.writable&&['on','off'].includes(entry.state)?`<button class="button primary" data-action="entry-plan" data-id="${entry.id}">${icon(entry.state==='off'?'power':'box')}${entry.state==='off'?'원래 위치로 복원':'보관하기'}</button>`:'<button class="button" disabled>파일 변경 불가</button>'}<button class="button" data-action="favourite" data-id="${entry.id}" aria-pressed="${entry.favourite}">${icon('star')}${entry.favourite?'즐겨찾기 해제':'즐겨찾기'}</button></div>${!entry.writable?`<div class="card"><h3>${entry.owner}이 관리하는 항목</h3><p>본문과 설치 위치를 확인할 수 있습니다. 제공 주체의 파일은 여기서 옮기거나 편집하지 않습니다.</p></div>`:''}${provenanceHTML(entry)}<h3>설치 위치</h3><div class="card"><div class="row">${icon(entry.kind==='link'?'link':'box')}<strong>${entry.agent} · ${entry.kind==='link'?'심볼릭 링크':entry.writable?'사용자 스킬':entry.owner+' 카탈로그'}</strong></div><dl class="kv"><dt>원래 위치</dt><dd class="path">${escapeHTML(entry.location)}</dd><dt>파일 상태</dt><dd>${stateLabel(entry.state)}</dd><dt>관리 가능</dt><dd>${entry.writable?'보관 · 복원 가능':'조회 · 검사 가능'}</dd></dl></div>${counterparts.length?`<h3>공유 원본 관계</h3><div class="card">${counterparts.map(e=>`<div class="member-row"><div><div class="entry-name">${escapeHTML(e.name)}</div><div class="subtle" style="font-size:12px">${e.agent} · ${e.kind==='link'?'이 원본의 참조':'참조하는 공유 원본'}</div></div><button class="button small" data-action="select-related" data-id="${e.id}">보기</button></div>`).join('')}<p>링크만 보관하면 공유 원본은 유지됩니다. 원본을 보관할 때에는 알려진 참조를 함께 처리해야 합니다.</p></div>`:''}<h3>앱 전체 고정</h3><button class="button" data-action="pin" data-id="${entry.id}" aria-pressed="${policy.pinnedIds.includes(entry.id)}" ${!entry.writable&&!policy.pinnedIds.includes(entry.id)?'disabled':''}>${policy.pinnedIds.includes(entry.id)?'고정 해제':'항상 유지로 고정'}</button>${policy.pinnedIds.includes(entry.id)?'<p>앱 전체 보호 · '+(entry.state==='off'?'고정됨 · 현재 보관됨. ':'')+'고정 자체는 파일을 옮기지 않습니다.</p>':''}<h3>검사 결과</h3>${entry.findings?`<div class="card warning"><h3>${icon('warning')} 설명과 참조를 확인해 주세요</h3><p>예시 검사 결과입니다. 실제 검사에서는 대상 에이전트와 근거 위치를 표시합니다.</p></div>`:'<p>예시 기본 검사에서 확인할 문제는 없습니다.</p>'}<h3>지침 미리보기 <span class="pill">예시</span></h3><pre>${escapeHTML('---\nname: '+entry.name+'\ndescription: '+entry.description+'\n---\n\n이 본문은 화면 검토용 예시입니다.\n실제 설치된 지침을 읽은 결과가 아닙니다.')}</pre><h3>대화 반영</h3><p>현재 대화의 반영 상태는 미확인입니다. 파일을 변경한 뒤 새 대화에서 스킬 목록을 확인하세요.</p>`;
}
function syncEntrySelection(visible,reason) {
 if((reason==='filter'||selected===undefined)&&!visible.some(entry=>entry.id===selected))selected=visible[0]?.id;
 for(const entry of entries)lastKnown.set(entry.id,structuredClone(entry));
 return Boolean(selected&&!entries.some(entry=>entry.id===selected));
}
function missingEntryDetail() {
 const previous=lastKnown.get(selected);
 return `<div class="card error"><h2>선택한 설치 항목을 찾을 수 없습니다</h2><p>${escapeHTML(previous?.name??selected)}</p><div class="path">마지막 위치: ${escapeHTML(previous?.location??'미확인')}</div><p>다른 항목으로 자동 선택하지 않았습니다. 다시 검사하거나 목록에서 항목을 선택하세요.</p></div>`;
}
function drawLibrary(reason='observe') {
 const sourceEntries=entries.filter(inScope).filter(inOriginScope), visible=sourceEntries.filter(e=>matches(e.name+' '+e.description+' '+e.agent+' '+e.location+' '+(repositoryFor(e)?.name??''))).filter(e=>filter==='all'||filter==='on'&&e.state==='on'||filter==='off'&&e.state==='off'||filter==='attention'&&(e.findings||e.state==='unknown')||filter==='readonly'&&!e.writable||filter==='favourite'&&e.favourite);
 const missing=syncEntrySelection(visible,reason);
 $('list-head').innerHTML=`<div class="row"><h2>설치 항목</h2><span class="pill">${visible.length}개</span></div><p>이름이 같아도 설치 위치는 별도로 관리합니다.</p>`;
 $('list-body').innerHTML=visible.length?visible.map(rowHTML).join(''):!sourceEntries.length&&demoRepositories.some(repository=>repository.id===$('origin-filter')?.value)?'<div class="empty"><strong>현재 등록 위치에서 발견된 항목이 없습니다</strong>이 출처로 연결된 설치 항목이 없습니다. 원격 저장소의 스킬 목록은 조회하지 않았습니다.</div>':'<div class="empty"><strong>일치하는 항목이 없습니다</strong>검색어 또는 조회 범위를 바꿔보세요.</div>';
 $('detail').innerHTML=missing?missingEntryDetail():detailHTML(entries.find(entry=>entry.id===selected));
 return visible.length;
}
function drawGroups() {
 const groups=[...new Set(entries.map(e=>e.group))].filter(name=>matches(name));
 if(!groups.includes(selectedGroup))selectedGroup=groups[0];
 $('list-head').innerHTML='<h2>그룹</h2><p>분류를 바꿔도 파일 상태는 그대로입니다.</p>';
 $('list-body').innerHTML=groups.map(name=>`<button class="entry ${name===selectedGroup?'selected':''}" data-group="${name}" aria-pressed="${name===selectedGroup}"><span class="entry-icon">${icon('grid')}</span><span class="entry-text"><span class="entry-name">${name}</span><span class="entry-description">${entries.filter(e=>e.group===name&&inScope(e)).length}개 설치 항목 · 현재 조회 범위</span></span></button>`).join('')||'<div class="empty">일치하는 그룹이 없습니다.</div>';
 const members=entries.filter(e=>e.group===selectedGroup&&inScope(e));
 $('detail').innerHTML=selectedGroup?`<div class="detail-title"><span class="large-icon">${icon('grid')}</span><div><h2>${selectedGroup}</h2><p>관련 설치 항목을 모아둔 그룹</p></div></div><div class="card"><h3>그룹에 스위치를 두지 않습니다</h3><p>여기에 항목을 넣는 행동은 분류만 바꿉니다. 실제 작업 구성을 바꾸려면 관리 범위를 지정한 프로필을 적용하세요.</p></div><h3>그룹의 설치 항목</h3>${members.map(e=>`<div class="member-row"><div><div class="entry-name">${e.name}</div><span class="subtle">${e.agent}</span></div>${statusHTML(e)}</div>`).join('')||'<p>현재 조회 범위에 항목이 없습니다.</p>'}<div class="actions"><button class="button primary" data-action="go-profiles">작업 프로필 보기</button></div>`:'<div class="empty">그룹을 선택하세요.</div>';
}
function drawProfiles() {
 const profiles=demoProfiles.filter(p=>matches(p.name+' '+p.description));
 if(!profiles.some(p=>p.id===selectedProfile))selectedProfile=profiles[0]?.id;
 $('list-head').innerHTML='<h2>작업 프로필</h2><p>프로필의 관리 범위는 조회 필터와 별개입니다.</p>';
 $('list-body').innerHTML=profiles.map(p=>{const plan=planChanges(entries,p,policy);return `<button class="entry ${p.id===selectedProfile?'selected':''}" data-profile="${p.id}" aria-pressed="${p.id===selectedProfile}"><span class="entry-icon">${icon('profile')}</span><span class="entry-text"><span class="entry-name">${p.name}</span><span class="entry-description">${p.description}</span><span class="entry-meta">${plan.blocked.length?'적용 불가':plan.changes.length?plan.changes.length+'개 변경 필요':'구성 일치'} · 관리 ${p.managedIds.length}개</span></span></button>`;}).join('')||'<div class="empty">일치하는 프로필이 없습니다.</div>';
 const p=demoProfiles.find(p=>p.id===selectedProfile);if(!p){$('detail').innerHTML='<div class="empty">프로필을 선택하세요.</div>';return;}
 const plan=planChanges(entries,p,policy), wanted=new Set([...p.desiredIds,...policy.pinnedIds.filter(id=>p.managedIds.includes(id))]);
 $('detail').innerHTML=`<div class="detail-title"><span class="large-icon">${icon('profile')}</span><div><h2>${p.name}</h2><p>${p.description}</p></div></div><div class="actions"><button class="button primary" data-action="profile-plan" data-id="${p.id}">적용 미리보기</button></div><div class="split-summary"><div class="summary-card"><strong>${p.managedIds.length}</strong><span>프로필의 관리 항목</span></div><div class="summary-card"><strong>${wanted.size}</strong><span>유지할 항목 · 고정 포함</span></div></div><div class="card"><h3>${plan.blocked.length?'적용할 수 없는 구성입니다':plan.matched?'예시 구성이 일치합니다':'현재 구성과 '+plan.changes.length+'개 다릅니다'}</h3><p>관리 범위 밖 ${plan.untouched.length}개는 그대로 유지합니다. 조회 범위가 달라도 프로필의 지정 범위는 바뀌지 않습니다.</p></div><h3>목표 구성</h3>${entries.filter(e=>p.managedIds.includes(e.id)).map(e=>`<div class="member-row"><div><div class="entry-name">${e.name}</div><span class="subtle" style="font-size:12px">${e.agent}${policy.pinnedIds.includes(e.id)?' · 앱 전체 고정':''}</span></div><span class="pill">${wanted.has(e.id)?'발견 위치에 유지':'보관'}</span></div>`).join('')}<h3>항상 유지와 즐겨찾기</h3><p>고정 항목은 모든 프로필과 단일 변경에서 보호합니다. 즐겨찾기는 빠르게 찾기 위한 표시이며 전환 규칙을 바꾸지 않습니다.</p>`;
}
function drawFindings(reason='observe') {
 const visible=entries.filter(inScope).filter(e=>e.findings&&matches(e.name+' '+e.description));
 const missing=syncEntrySelection(visible,reason);
 $('list-head').innerHTML='<h2>검사 결과</h2><p>기본 검사 · 로컬 · 예시 결과</p>';
 $('list-body').innerHTML=visible.map(rowHTML).join('')||'<div class="empty">현재 범위에 검사 결과가 없습니다.</div>';
 const entry=entries.find(e=>e.id===selected);
 $('detail').innerHTML=missing?missingEntryDetail():entry?.findings?`<div class="card warning"><h3>${icon('warning')} 설명과 참조를 확인해 주세요</h3><p>${entry.name} · 기본 검사 예시</p></div><h3>검사 근거</h3><pre>${escapeHTML('대상 에이전트: '+entry.agent+'\n검사 규칙: 예시 메타데이터 점검\n근거 위치: SKILL.md frontmatter\n실제 파일을 검사한 결과가 아닙니다.')}</pre><h3>권장 행동</h3><p>에이전트별 허용 형식과 Agent Skills 표준을 구별해서 확인합니다. 검사 결과만으로 파일을 자동 수정하지 않습니다.</p><button class="button" data-action="select-related" data-id="${entry.id}">설치 항목 보기</button>`:entry?`<h2>${escapeHTML(entry.name)}</h2><p>선택한 항목의 현재 검사 결과가 없습니다.</p><div class="path">${escapeHTML(entry.location)}</div>`:'<div class="empty">검사 결과를 선택하세요.</div>';
}
function drawHistory() {
 $('list-head').innerHTML='<h2>변경 기록</h2><p>시안에서 적용한 예시 변경만 기록합니다.</p>';
 const visibleHistory=history.map((record,index)=>({...record,index})).filter(record=>matches(record.title)).reverse();
 $('list-body').innerHTML=visibleHistory.length?visibleHistory.map(record=>`<div class="card"><h3>${record.title}</h3><p>${record.changes.length}개 변경 · ${record.restored?'되돌림':'파일 변경 완료 예시'}</p>${!record.restored?`<button class="button small" data-action="undo" data-id="${record.index}">되돌리기 미리보기</button>`:''}</div>`).join(''):`<div class="empty"><strong>${history.length?'일치하는 기록이 없습니다':'아직 변경한 항목이 없습니다'}</strong>${history.length?'검색어를 바꿔보세요.':'프로필을 예시 데이터에 적용하면 여기에 기록됩니다.'}</div>`;
 $('detail').innerHTML=`<h2>변경 기록과 복구</h2><p>현재 대화 반영과 파일 변경 결과를 구별해서 기록합니다.</p><div class="card"><h3>원래 위치에 다른 파일이 있다면</h3><p>보관 항목을 자동으로 덮어쓰거나 기존 항목을 지우지 않습니다. 두 위치를 함께 보여주고 복구를 멈춥니다.</p><button class="button" data-action="recovery-example">복구 충돌 예시 보기</button></div><h3>중단된 변경</h3><p>앱이 다시 시작되면 이동별 기록과 실제 위치를 비교합니다. 확인한 이동만 되돌리며, 해결되지 않은 복구가 있으면 새 쓰기를 막습니다.</p>`;
}
function render(reason='observe') {
 const focusedButton=document.activeElement;
 const focusKey=['entry','profile','group','filter','action'].find(key=>focusedButton?.dataset[key]);
 const focusValue=focusKey?focusedButton.dataset[focusKey]:null;
 $('search').placeholder=({library:'스킬 검색',groups:'그룹 검색',profiles:'프로필 검색',findings:'검사 결과 검색',history:'기록 검색'}[route]);
 document.querySelectorAll('[data-route]').forEach(button=>{if(button.dataset.route===route)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');});
 drawTiles();({library:drawLibrary,groups:drawGroups,profiles:drawProfiles,findings:drawFindings,history:drawHistory}[route])(reason);
 if(focusKey)document.querySelector(`[data-${focusKey}="${CSS.escape(focusValue)}"]${focusKey==='action'&&focusedButton.dataset.id?`[data-id="${CSS.escape(focusedButton.dataset.id)}"]`:''}`)?.focus();
}
function openPlan(profile,title,undoIndex=null) {
 const plan=undoIndex===null?planChanges(entries,profile,policy):planUndo(entries,history,undoIndex,policy);planState={profile:structuredClone(profile),title,plan,revision,undoIndex,used:false};
 $('plan-title').textContent=title;$('refresh-plan').hidden=true;$('apply-plan').hidden=false;$('apply-plan').disabled=Boolean(plan.blocked.length)||!plan.changes.length;
 const on=plan.changes.filter(e=>e.target==='on').length,off=plan.changes.length-on;
 $('plan-body').innerHTML=`<p>예시 데이터의 변경 계획입니다. 실제 파일은 변경하지 않습니다.</p><div class="row"><span class="pill">${on}개 복원</span><span class="pill">${off}개 보관</span><span class="pill">${plan.retained.length}개 유지</span></div>${plan.blocked.map(b=>`<div class="card error"><h3>적용할 수 없습니다</h3><p>${escapeHTML(b.reason)}</p></div>`).join('')}${plan.changes.map(e=>`<div class="change-row"><span class="change-label ${e.target==='off'?'off':''}">${e.target==='on'?'복원':'보관'}</span><div><strong>${escapeHTML(e.name)}</strong><div class="subtle" style="font-size:12px">${e.agent} · ${e.kind==='link'?'링크 자체':'스킬 폴더'}</div><div class="path">출발: ${escapeHTML(e.target==='off'?e.location:demoVaultPath(e))}<br>도착: ${escapeHTML(e.target==='off'?demoVaultPath(e):e.location)}</div></div></div>`).join('')}<p>${plan.blocked.length?'이 계획은 차단되어 적용할 수 없습니다. 파일 상태는 바뀌지 않습니다.':'관리 범위 밖 '+plan.untouched.length+'개는 유지합니다. '+plan.retained.filter(e=>e.pinned).length+'개 고정 항목도 유지합니다.'}</p>${plan.changes.some(e=>e.sourceId||entries.some(other=>sourceEntryId(other,policy)===e.id))?'<div class="card"><h3>공유 원본과 참조가 포함돼 있습니다</h3><p>링크만 보관할 때에는 원본이 유지됩니다. 원본과 참조를 함께 변경할 때에는 이동 순서를 조정합니다.</p></div>':''}<div class="card"><h3>관계 확인</h3><p>관련 설치 항목의 관계는 상세 화면에서 확인하세요. 관계 보기로 현재 변경 목표를 바꾸지 않습니다.</p></div><div class="sheet-status">파일 변경 후 현재 대화의 반영 상태는 미확인입니다.</div><div class="actions"><button class="button small" data-action="stale-example">미리보기 중 외부 변경 재현</button></div>`;
 if(!$('plan-dialog').open)$('plan-dialog').showModal();
}
function showPlanBlocked(reasons) {
 planState.plan={...planState.plan,blocked:reasons,valid:false,matched:false};
 $('apply-plan').disabled=true;$('refresh-plan').hidden=false;
 $('plan-body').innerHTML=`<p>현재 조건에서 적용할 수 없습니다. 파일 상태와 변경 기록은 그대로입니다.</p>${reasons.map(reason=>`<div class="card error" role="alert" data-reason-code="${escapeHTML(reason.code)}"><h3>적용할 수 없습니다</h3><p>${escapeHTML(reason.reason)}</p>${reason.relatedIds.length?`<p>관련 항목: ${reason.relatedIds.map(escapeHTML).join(', ')}</p>`:''}</div>`).join('')}<p>최초 변경 목표는 그대로입니다. 다시 확인해 새 미리보기를 검토하세요.</p>`;
}
function applyPlan() {
 if(!planState||planState.used)return 'Unavailable';
 if(planState.undoIndex!==null){const freshUndo=planUndo(entries,history,planState.undoIndex,policy);if(freshUndo.blocked.length){showPlanBlocked(freshUndo.blocked);return 'Blocked';}}
 const outcome=applyPreview(entries,planState.plan,policy,revision,planState.revision);
 if(outcome.status==='Blocked'){const fresh=planChanges(entries,planState.plan.intent,policy);showPlanBlocked(fresh.blocked.length?fresh.blocked:[blockedReason('InvalidPlan',null,'미리보기의 이동 목록과 현재 계획이 다릅니다.')]);return 'Blocked';}
 if(outcome.status==='Stale'){$('apply-plan').disabled=true;$('refresh-plan').hidden=false;$('plan-body').insertAdjacentHTML('afterbegin','<div class="card error" role="alert"><h3>미리보기 이후 항목이 변경되었습니다</h3><p>계획을 다시 확인한 뒤 적용해 주세요.</p></div>');return 'Stale';}
 if(outcome.status==='NoChanges'){message('변경할 항목이 없습니다.');return 'NoChanges';}
 const before=entries;
 entries=outcome.entries;revision++;planState.used=true;
 const record={id:revision,title:planState.title,changes:planState.plan.changes.map(change=>({id:change.id,previous:change.state,target:change.target,beforeFingerprint:entryFingerprint(before.find(entry=>entry.id===change.id)),afterFingerprint:entryFingerprint(entries.find(entry=>entry.id===change.id))})),restored:false};
 if(planState.undoIndex!==null){history[planState.undoIndex].restored=true;record.undoOf=history[planState.undoIndex].id;}
 history.push(record);
 $('plan-dialog').close();render();
 const focusSelector=route==='profiles'?`[data-action="profile-plan"][data-id="${CSS.escape(selectedProfile)}"]`:route==='library'?`[data-entry="${CSS.escape(selected??'')}"]`:`[data-route="${CSS.escape(route)}"]`;
 document.querySelector(focusSelector)?.focus();
 message(`${record.changes.length}개 예시 항목을 변경했습니다. 실제 스킬 파일은 변경하지 않았습니다.`);
 return 'Applied';
}
function navigateTo(nextRoute) {
 if(route!==nextRoute)$('search').value='';
 route=nextRoute;render('filter');
 if($('detail-dialog')?.open)$('detail-dialog').close();
}
document.addEventListener('click',event=>{
 const button=event.target.closest('button');if(!button)return;
 if(button.dataset.route){navigateTo(button.dataset.route);return;}
 if(button.dataset.filter){route='library';filter=button.dataset.filter;render('filter');return;}
 if(button.dataset.entry){selected=button.dataset.entry;render();return;}
 if(button.dataset.profile){selectedProfile=button.dataset.profile;render();return;}
 if(button.dataset.group){selectedGroup=button.dataset.group;render();return;}
 const id=button.dataset.id,entry=entries.find(e=>e.id===id);
 switch(button.dataset.action){
  case 'entry-plan':if(!entry){message('설치 항목을 찾을 수 없습니다.');break;}openPlan({kind:'single',managedIds:[id],desiredIds:entry.state==='off'?[id]:[]},entry.state==='off'?'설치 항목 복원':'설치 항목 보관');break;
  case 'profile-plan':openPlan(demoProfiles.find(p=>p.id===id),demoProfiles.find(p=>p.id===id).name+' 프로필 적용');break;
  case 'favourite':entry.favourite=!entry.favourite;render();message(entry.name+(entry.favourite?' 즐겨찾기에 추가했습니다.':' 즐겨찾기를 해제했습니다.'));break;
  case 'select-related':route='library';filter='all';$('search').value='';$('scope').value='all';if($('origin-filter'))$('origin-filter').value='all';selected=id;render('filter');break;
  case 'inspect-entry':if(entry){selected=id;$('detail').innerHTML=detailHTML(entry);}break;
  case 'go-profiles':navigateTo('profiles');break;
  case 'pin':if(entry&&(entry.writable||policy.pinnedIds.includes(id))){policy.pinnedIds=policy.pinnedIds.includes(id)?policy.pinnedIds.filter(item=>item!==id):[...policy.pinnedIds,id];render();message('고정 설정을 바꿨습니다. 파일 상태는 그대로입니다.');}break;
  case 'stale-example':revision++;message('외부 변경을 예시로 재현했습니다. 열린 계획은 다시 확인해야 합니다.');break;
  case 'undo':{const index=Number(id);openPlan(planUndo(entries,history,index,policy).intent,'완료 기록 되돌리기',index);break;}
  case 'recovery-example':{const result=classifyRecovery('expected','expected');$('detail').innerHTML=`<h2>복구 충돌 예시</h2><div class="card error"><h3>두 위치에 항목이 있습니다</h3><p>원래 위치의 새 항목과 보관된 항목을 모두 보존했습니다. 자동 복구를 진행하지 않습니다.</p></div><dl class="kv"><dt>원래 위치</dt><dd class="path">~/.agents/skills/writing · 새 항목 있음</dd><dt>보관 위치</dt><dd class="path">앱 보관 위치 · 기존 항목 있음</dd><dt>판단</dt><dd>${result==='conflict'?'충돌 · 쓰기 차단':'예시 오류'}</dd></dl><p>실제 앱에서는 두 위치를 열어 사용자가 확인할 수 있습니다.</p><button class="button" data-action="history-back">변경 기록으로 돌아가기</button>`;break;}
  case 'history-back':render();break;
 }
});
$('theme').addEventListener('click',()=>setTheme($('theme').getAttribute('aria-pressed')!=='true'));
$('scope').addEventListener('change',()=>render('filter'));$('search').addEventListener('input',()=>render('filter'));
$('origin-filter')?.addEventListener('change',()=>{render('filter');message('출처별로 목록을 좁혔습니다. 작업 구성과 파일 상태는 그대로입니다.');});
$('rescan').addEventListener('click',()=>{render();message('예시 데이터의 상태를 다시 확인했습니다. 실제 파일은 검사하지 않았습니다.');});
$('sidebar-toggle').addEventListener('click',()=>{const open=$('app-window').classList.toggle('sidebar-open');$('sidebar-toggle').setAttribute('aria-expanded',String(open));$('sidebar-toggle').setAttribute('aria-label',open?'사이드바 닫기':'사이드바 열기');});
$('cancel-plan').addEventListener('click',()=>$('plan-dialog').close());$('apply-plan').addEventListener('click',applyPlan);
$('refresh-plan').addEventListener('click',()=>openPlan(planState.profile,planState.title,planState.undoIndex));
document.addEventListener('keydown',event=>{if($('plan-dialog').open||$('detail-dialog')?.open)return;if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='f'){event.preventDefault();$('search').focus();}});
setTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);render();

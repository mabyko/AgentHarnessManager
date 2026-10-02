import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const context = vm.createContext({});
vm.runInContext(readFileSync(resolve(root, 'docs/design/preview-model.js'), 'utf8'), context);
const {demoEntries: entries,demoProfiles: profiles,demoPolicy: policy,planChanges,planUndo,applyPreview,classifyRecovery,entryFingerprint} = vm.runInContext('({demoEntries,demoProfiles,demoPolicy,planChanges,planUndo,applyPreview,classifyRecovery,entryFingerprint})',context);
const copy=value=>JSON.parse(JSON.stringify(value));
const initial=copy(entries), initialPolicy=copy(policy), initialProfiles=copy(profiles);
const plan=planChanges(entries,profiles[1],policy);
assert.equal(plan.blocked.length,0);assert.equal(plan.changes.length,5);
assert.equal(plan.changes.some(entry=>entry.id==='git'),false,'전역 고정 항목 보관 0건');
assert.equal(plan.untouched.map(entry=>entry.id).join(','),'system,plugin','관리 범위 밖 유지');
assert.ok(plan.changes.findIndex(entry=>entry.id==='swiftui-claude')<plan.changes.findIndex(entry=>entry.id==='swiftui-shared'),'참조부터 보관');
assert.deepEqual(copy(entries),initial);assert.deepEqual(copy(policy),initialPolicy);assert.deepEqual(copy(profiles),initialProfiles);
const result=applyPreview(entries,plan,policy,0,0),after=result.entries;
assert.equal(result.status,'Applied');
assert.deepEqual(after.filter((entry,index)=>entry.state!==entries[index].state).map(entry=>entry.id).sort(),plan.changes.map(entry=>entry.id).sort(),'미리보기 대상과 모의 적용 대상 일치');
const matched=planChanges(after,profiles[1],policy);
assert.equal(matched.matched,true);assert.equal(applyPreview(after,matched,policy,1,1).status,'NoChanges');
const restore=planChanges(after,profiles[0],policy);
assert.equal(restore.valid,true);assert.ok(restore.changes.findIndex(entry=>entry.id==='swiftui-shared')<restore.changes.findIndex(entry=>entry.id==='swiftui-claude'),'원본 먼저 복원');
assert.equal(applyPreview(entries,plan,{...policy,pinnedIds:[...policy.pinnedIds,'debug']},0,0).status,'Stale','고정 정책 변경은 계획 만료');
assert.equal(applyPreview(entries.map(entry=>({...entry,favourite:!entry.favourite})),plan,policy,0,0).status,'Applied','즐겨찾기는 파일 계획 전제가 아님');
assert.equal(applyPreview(entries,plan,policy,1,0).status,'Stale');

const item=(id,overrides={})=>({id,name:id,agent:'Codex',location:'/skills/'+id,path:'/skills/'+id,rootId:'r',owner:'user',kind:'folder',state:'on',writable:true,contentFingerprint:'bytes-'+id,entryRevision:0,...overrides});
const basePolicy={pinnedIds:[],roots:[{id:'r',path:'/skills',owner:'user',approved:true,accessible:true,complete:true}],sources:[],protectedPaths:[]};
const intent=(ids,desired=[],kind='profile')=>({kind,managedIds:ids,desiredIds:desired});
const source=(id,entryId,overrides={})=>({id,entryId,path:'/skills/'+entryId,approved:true,accessible:true,status:'present',depth:1,...overrides});
const blocked=(items,request,configuration=basePolicy)=>{const planned=planChanges(items,request,configuration);assert.equal(planned.valid,false);assert.equal(planned.matched,false);assert.ok(planned.blocked.length);assert.ok(planned.blocked.every(reason=>typeof reason.code==='string'&&Array.isArray(reason.relatedIds)),'구조화된 차단 이유');assert.equal(applyPreview(items,planned,configuration,0,0).status,'Blocked');return planned;};
blocked([item('x'),item('x',{path:'/skills/y'})],intent(['x']));
blocked([item('x'),item('y',{path:'/skills/x'})],intent(['x']));
for(const invalid of [{owner:undefined},{owner:'unknown'},{writable:'true'},{writable:false},{owner:'plugin'},{state:'unknown'},{state:'missing'},{path:'/skills/../escape'},{path:'/other/x'}])blocked([item('x',invalid)],intent(['x'],['x']));
blocked([],intent(['missing']));
for(const malformed of [null,[null],[{id:'../escape'}]])assert.equal(planChanges(malformed,intent(['x']),basePolicy).valid,false,'잘못된 Snapshot은 계획 차단');
assert.equal(planChanges([item('x')],{},basePolicy).valid,false);
blocked([item('x')],intent(['x'],['x']),{...basePolicy,roots:[{...basePolicy.roots[0],owner:'plugin'}]});blocked([item('x')],intent(['x'],['outside']));
const pins={...basePolicy,pinnedIds:['x']};
blocked([item('x')],intent(['x'],[],'single'),pins);
blocked([item('x',{state:'off'})],intent(['x'],[],'single'),pins);
assert.equal(planChanges([item('x',{state:'off'})],intent(['x']),pins).changes[0].target,'on','프로필은 범위 안 전역 고정 항목 복원');
assert.equal(planChanges([item('x',{state:'off'}),item('y')],intent(['y'],['y']),pins).changes.length,0,'범위 밖 고정 항목 자동 복원 0건');
assert.equal(planChanges([item('x'),item('new')],intent(['x'],['x']),basePolicy).untouched[0].id,'new');
assert.equal(planChanges([item('x')],intent(['x'],['x','x']),basePolicy).matched,true,'목표 목록 중복 제거');

const linked=[item('folder'),item('ref',{kind:'link',sourceId:'source'})];
const linkedPolicy={...basePolicy,sources:[source('source','folder')]};
blocked(linked,intent(['folder']),linkedPolicy);
blocked(linked.map(entry=>({...entry,state:'off'})),intent(['ref'],['ref']),linkedPolicy);
blocked([linked[0],{...linked[1],state:'off'}],intent(['folder','ref'],['ref']),linkedPolicy);
blocked([linked[0],{...linked[1],writable:false}],intent(['folder']),linkedPolicy);
assert.equal(planChanges([linked[0],{...linked[1],state:'off'}],intent(['folder']),linkedPolicy).valid,true,'기존 보관된 참조는 유지');
assert.equal(planChanges(linked.map(entry=>({...entry,state:'off'})),intent(['ref','folder'],['ref','folder']),linkedPolicy).valid,true,'원본 현재 off여도 선행 복원 계획이면 링크 복원 가능');
for(const status of ['missing','unknown']) {
  const subPolicy={...basePolicy,sources:[source('source','folder',{path:'/skills/folder/missing-child',status})]};
  assert.ok(blocked([{...linked[0]},{...linked[1],state:'off'}],intent(['ref'],['ref']),subPolicy).blocked.some(reason=>reason.code==='SourceUnavailable'));
  blocked(linked.map(entry=>({...entry,state:'off'})),intent(['ref','folder'],['ref','folder']),subPolicy);
  const verified={...subPolicy,sources:subPolicy.sources.map(source=>({...source,expectedWhenRestored:true}))};
  assert.equal(planChanges(linked.map(entry=>({...entry,state:'off'})),intent(['ref','folder'],['ref','folder']),verified).valid,true,'보관 payload의 해당 하위 목표 존재가 검증된 경우만 함께 복원');
}
assert.deepEqual(copy(blocked(linked,intent(['folder']),linkedPolicy).blocked.find(reason=>reason.code==='ActiveReference').relatedIds),['ref']);
assert.equal(blocked([item('x')],intent(['x'],[],'single'),pins).blocked[0].code,'PinnedEntry');
const chain=[item('folder'),item('middle',{kind:'link',sourceId:'s1'}),item('leaf',{kind:'link',sourceId:'s2'})];
const chainPolicy={...basePolicy,sources:[source('s1','folder'),source('s2','middle')]};
for(const id of ['folder','middle','leaf'])blocked(chain,intent([id]),chainPolicy);
blocked(chain.map(entry=>({...entry,state:'off'})),intent(['leaf','middle','folder'],['leaf','middle','folder']),chainPolicy);
blocked([item('a',{kind:'link',sourceId:'a-source',state:'off'}),item('b',{kind:'link',sourceId:'b-source',state:'off'})],intent(['a','b'],['a','b']),{...basePolicy,sources:[source('a-source','b'),source('b-source','a')]});
for(const changes of [{status:'missing'},{status:'unknown'},{approved:false},{accessible:false},{depth:2},{cyclic:true}])blocked([item('external',{kind:'link',sourceId:'ext',state:'off'})],intent(['external'],['external']),{...basePolicy,sources:[source('ext',undefined,{path:'/shared/source',...changes})]});
assert.equal(planChanges([item('external',{kind:'link',sourceId:'ext',state:'off'})],intent(['external'],['external']),{...basePolicy,sources:[source('ext',undefined,{path:'/shared/source'})]}).valid,true,'외부 승인 원본은 설치 ID 없이 검증');
blocked([item('outer'),item('inner',{path:'/skills/outer/inner'})],intent(['outer']));
blocked([item('outer')],intent(['outer']),{...basePolicy,roots:[...basePolicy.roots,{id:'nested',path:'/skills/outer/nested',owner:'user',approved:true,accessible:true,complete:true}]});
blocked([item('outer')],intent(['outer']),{...basePolicy,protectedPaths:['/skills/outer/protected']});
blocked([item('protected')],intent(['protected'],['protected']),{...basePolicy,protectedPaths:['/skills/protected']});
blocked([item('x')],intent(['x']),{...basePolicy,roots:[{...basePolicy.roots[0],complete:false}]});
blocked([item('outer'),item('ref',{kind:'link',sourceId:'sub'})],intent(['outer']),{...basePolicy,sources:[source('sub',undefined,{path:'/skills/outer/data'})]});
const newRefPlan=planChanges([linked[0]],intent(['folder']),linkedPolicy);
assert.equal(applyPreview(linked,newRefPlan,linkedPolicy,0,0).status,'Stale','새 참조도 재검증 전제 변경');
for(const [from,to,expected] of [['expected','missing','before-move'],['missing','expected','after-move'],['expected','expected','conflict'],['missing','missing','missing'],['changed','expected','external-change']])assert.equal(classifyRecovery(from,to),expected);
assert.equal(classifyRecovery('missing','expected'),'after-move','복원 의도는 보관위치(from)→원래위치(to)로 분류');
assert.throws(()=>classifyRecovery('invalid','changed'));

const tokens = JSON.parse(readFileSync(resolve(root,'docs/design/tokens.json'),'utf8'));
function resolveToken(path, seen = new Set()) {
  assert.ok(!seen.has(path), '토큰 순환 참조: '+path); seen.add(path);
  const value = path.split('.').reduce((object,key) => object?.[key], tokens);
  assert.notEqual(value, undefined, '없는 토큰: '+path);
  return typeof value === 'string' && /^(primitive|semantic)\./.test(value) ? resolveToken(value,seen) : value;
}
for (const theme of ['light','dark']) for (const token of Object.values(tokens.semantic.color)) resolveToken(token.reference.replace('$theme',theme));
for (const values of [tokens.semantic.space,tokens.semantic.radius,...Object.values(tokens.component)]) for (const value of Object.values(values)) if(typeof value === 'string' && /^(primitive|semantic)\./.test(value)) resolveToken(value);
const luminance = hex => {
  const linear = hex.match(/[\da-f]{2}/gi).map(value => parseInt(value,16)/255).map(value => value<=.04045 ? value/12.92 : ((value+.055)/1.055)**2.4);
  return linear[0]*.2126+linear[1]*.7152+linear[2]*.0722;
};
for(const [theme,palette] of Object.entries(tokens.primitive.color)) {
  for(const [foreground,background] of [['text','surface'],['muted','surface'],['muted','raised'],['accent','onAccent'],['accent','selection'],['success','successSurface'],['warning','warningSurface'],['danger','dangerSurface'],['purple','purpleSurface']]) {
    const values=[luminance(palette[foreground]),luminance(palette[background])].sort((a,b)=>b-a);
    const contrast=(values[0]+.05)/(values[1]+.05);
    assert.ok(contrast>=4.5,`${theme} ${foreground}/${background}: ${contrast.toFixed(2)} 대비`);
  }
}
const html = readFileSync(resolve(root,'docs/design/preview.html'),'utf8');
// Memory DOM only: execute the real review UI handlers, never a filesystem model.
const nodes=new Map(),listeners=new Map();
const document={activeElement:null,getElementById(id){if(!nodes.has(id))nodes.set(id,{innerHTML:'',textContent:'',value:id==='scope'?'all':'',open:false,dataset:{},style:{setProperty(){}},attributes:new Map(),addEventListener(type,fn){listeners.set(id+':'+type,fn)},setAttribute(key,value){this.attributes.set(key,value)},getAttribute(key){return this.attributes.get(key)},querySelectorAll(){return []},showModal(){this.open=true},close(){this.open=false},insertAdjacentHTML(_,value){this.innerHTML=value+this.innerHTML},focus(){document.activeElement=this}});return nodes.get(id)},querySelectorAll(){return []},querySelector(){return this.getElementById('selector')},addEventListener(type,fn){listeners.set('document:'+type,fn)},documentElement:{style:{setProperty(){}}}};
document.getElementById('design-tokens').textContent=html.match(/<script id="design-tokens" type="application\/json">([\s\S]*?)<\/script>/)[1];
const ui=vm.createContext({document,structuredClone,CSS:{escape:value=>value},window:{matchMedia:()=>({matches:false})}});
vm.runInContext(readFileSync(resolve(root,'docs/design/preview-model.js'),'utf8'),ui);
vm.runInContext(readFileSync(resolve(root,'docs/design/preview-controller.js'),'utf8'),ui);
const run=source=>vm.runInContext(source,ui);
const click=(action,id)=>listeners.get('document:click')({target:{closest:()=>({dataset:{action,id}})}});
for(const basename of ['manifest.json','payload','state.json','.hidden']) {
  ui.bucketEntry=item('bucket-id',{path:'/skills/'+basename,name:'different-metadata-name'});
  const path=run('demoVaultPath(bucketEntry)');
  assert.ok(path.endsWith('/bucket-id/payload/'+basename),'보관 파일 이름은 내부 metadata와 분리');
  assert.ok(!path.endsWith('/bucket-id/manifest.json'),'manifest와 실제 파일은 같은 디렉터리를 사용하지 않음');
}
const stateBeforePin=run('JSON.stringify({entries,revision,history})');click('pin','writing');
assert.equal(run('JSON.stringify({entries,revision,history})'),stateBeforePin,'보관된 항목 고정은 파일·기록·revision 변경 0건');
assert.ok(run('policy.pinnedIds.includes("writing")'));
run('policy=structuredClone(demoPolicy)');
click('entry-plan','git');assert.equal(run('planState.plan.valid'),false,'단일 클릭도 전역 고정 보호');assert.equal(run('applyPlan()'),'Blocked');
assert.ok(document.getElementById('plan-body').innerHTML.includes('data-reason-code="PinnedEntry"'));assert.ok(!document.getElementById('plan-body').innerHTML.includes('고정 항목도 유지합니다'),'차단 계획은 유지 성공을 단정하지 않음');
run('entries.push({...structuredClone(entries[0]),id:"same-name-different-location",path:"/Users/demo/.agents/skills/another-copy",location:"~/.agents/skills/another-copy"});render()');
const duplicateRows=document.getElementById('list-body').innerHTML.match(/<button[^>]+aria-label="[^"]*swiftui-ui-patterns · Codex[^"]*"/g);
assert.equal(duplicateRows.length,2);assert.notEqual(duplicateRows[0],duplicateRows[1],'같은 이름·에이전트 목록도 전체 위치 접근성 이름으로 구별');assert.ok(document.getElementById('list-body').innerHTML.includes('~/.agents/skills/another-copy'),'목록에 위치 표시');run('entries=structuredClone(demoEntries)');
run('openPlan(demoProfiles[1],"글쓰기")');const wanted=run('JSON.stringify(planState.plan.intent)');
assert.ok(!document.getElementById('plan-body').innerHTML.includes('include-related'),'의도 변경 자동 확장 버튼 제거');
click('include-related');assert.equal(run('JSON.stringify(planState.plan.intent)'),wanted,'과거 자동 확장 동작도 의도 변경 0건');
assert.equal(run('applyPlan()'),'Applied');assert.equal(run('applyPlan()'),'Unavailable','한 번 사용한 계획 재적용 차단');
assert.equal(run('entries.filter(entry=>entry.state==="on").map(entry=>entry.id).sort().join(",")'),'git,system,writing');
const noChangeBefore=run('JSON.stringify({revision,history,entries})');run('openPlan(demoProfiles[1],"일치")');assert.equal(run('applyPlan()'),'NoChanges');assert.equal(run('JSON.stringify({revision,history,entries})'),noChangeBefore,'NoChanges는 모의 기록·revision·파일 상태 변경 0건');
run('openPlan(demoProfiles[0],"앱 개발")');assert.equal(run('applyPlan()'),'Applied');
click('undo','0');assert.ok(run('planState.plan.blocked.length')>0,'후속 작업이 있는 예전 기록 Undo 차단');assert.equal(run('applyPlan()'),'Blocked');
click('undo','1');assert.equal(run('planState.plan.valid'),true);assert.equal(run('applyPlan()'),'Applied');assert.equal(run('history.length'),3,'Undo 자체도 새 작업 기록');
assert.equal(run('history[1].restored'),true);assert.equal(run('history[2].undoOf'),run('history[1].id'));
click('undo','2');run('entries=entries.map(entry=>entry.id==="writing"?{...entry,contentFingerprint:"external-edit"}:entry)');assert.equal(run('applyPlan()'),'Blocked','Undo 이후 내용 지문 변경 차단');
assert.equal(document.getElementById('apply-plan').disabled,true);assert.equal(document.getElementById('refresh-plan').hidden,false);assert.ok(document.getElementById('plan-body').innerHTML.includes('data-reason-code="UndoStateChanged"'),'실행 직전 새 차단 근거를 열린 미리보기에 표시');
run('entries=structuredClone(demoEntries);policy=structuredClone(demoPolicy);history=[];revision=0;planState=null;selected="swiftui-shared";route="library";filter="all";render()');
run('entries=entries.filter(entry=>entry.id!==selected);render()');assert.equal(run('selected'),'swiftui-shared');assert.ok(document.getElementById('detail').innerHTML.includes('마지막 위치'),'외부 누락은 마지막 상세 유지');
document.getElementById('scope').value='Claude Code';listeners.get('scope:change')();assert.equal(run('selected'),'swiftui-claude','사용자 조회 필터 변경은 가시 항목 선택');
run('entries=structuredClone(demoEntries);selected="debug";route="library";filter="on"');document.getElementById('scope').value='all';run('render();entries=entries.map(entry=>entry.id===selected?{...entry,state:"off"}:entry);render()');
assert.equal(run('selected'),'debug','외부 상태 변경으로 목록 필터에서 제외돼도 선택 유지');assert.ok(document.getElementById('detail').innerHTML.includes('diagnosing-bugs'));
run('entries=structuredClone(demoEntries);selected="debug";route="findings";render();entries=entries.map(entry=>entry.id===selected?{...entry,findings:0}:entry);render()');
assert.equal(run('selected'),'debug','외부 검사 결과 변화로 목록에서 제외돼도 선택 유지');assert.ok(document.getElementById('detail').innerHTML.includes('현재 검사 결과가 없습니다'));
run('entries=entries.filter(entry=>entry.id!==selected);render()');assert.equal(run('selected'),'debug');assert.ok(document.getElementById('detail').innerHTML.includes('마지막 위치: ~/.agents/skills/diagnosing-bugs'),'검사 결과 화면도 외부 누락 마지막 위치 유지');
document.getElementById('scope').value='Claude Code';listeners.get('scope:change')();assert.equal(run('selected'),'plugin','검사 결과 사용자 필터 변경은 가시 항목 선택');
run('entries=structuredClone(demoEntries).map(entry=>entry.id==="domain"?{...entry,state:"off"}:entry.id==="git"?{...entry,writable:false}:entry);selectedProfile="app";drawProfiles()');assert.ok(!document.getElementById('detail').innerHTML.includes('예시 구성이 일치합니다'),'차단 항목을 0개 변경으로 일치 표시하지 않음');
run('entries=structuredClone(demoEntries);policy=structuredClone(demoPolicy);openPlan(demoProfiles[1],"고정 변경")');click('pin','debug');assert.equal(run('applyPlan()'),'Stale','열린 계획은 전역 고정 변경 후 재검증');
run('policy=structuredClone(demoPolicy);openPlan(demoProfiles[1],"즐겨찾기")');click('favourite','debug');assert.equal(run('applyPlan()'),'Applied');
run('openPlan({kind:"single",managedIds:["swiftui-claude"],desiredIds:["swiftui-claude"]},"원본 없는 복원")');assert.equal(run('planState.plan.valid'),false);
const savedIntent=run('JSON.stringify(planState.plan.intent)');click('include-related');assert.equal(run('JSON.stringify(planState.plan.intent)'),savedIntent);

assert.ok(!html.includes('__DESIGN_TOKENS__'), '시안 토큰 삽입 누락');
const embedded = html.match(/<script id="design-tokens" type="application\/json">([\s\S]*?)<\/script>/);
assert.deepEqual(JSON.parse(embedded[1]),tokens,'시안과 토큰 원본 일치');
assert.ok(!/<(?:script|link)[^>]+(?:src|href)="https?:\/\//.test(html),'시안은 외부 의존성 없이 열림');
for (const match of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
  if(match[0].includes('application/json'))continue;
  new vm.Script(match[1]);
}
new vm.Script(readFileSync(resolve(root,'docs/design/preview-controller.js'),'utf8'));
for(const file of ['README.md','README.ko.md','CONTRIBUTING.md','SECURITY.md','THIRD_PARTY_NOTICES.md','docs/README.md','GLOSSARY.md','docs/product-scenarios.md','docs/design-system.md','docs/architecture.md','docs/design/final-candidate.md']) {
  const text=readFileSync(resolve(root,file),'utf8');
  for(const match of text.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    const target=match[1].split('#')[0];
    if(!target||/^[a-z]+:\/\//i.test(target))continue;
    assert.ok(existsSync(resolve(root,dirname(file),target)),`${file}: 링크 대상 없음 ${target}`);
  }
}
const candidateHTML=readFileSync(resolve(root,'docs/design/final-preview.html'),'utf8');
const candidateTokens=JSON.parse(candidateHTML.match(/<script id="design-tokens" type="application\/json">([\s\S]*?)<\/script>/)[1]);
for(const palette of Object.values(candidateTokens.primitive.color))for(const [fg,bg]of [['text','surface'],['muted','surface'],['muted','raised'],['muted','sidebar'],['accent','onAccent'],['accent','selection'],['success','successSurface'],['warning','warningSurface'],['danger','dangerSurface']]){
 const values=[luminance(palette[fg]),luminance(palette[bg])].sort((a,b)=>b-a);
 assert.ok((values[0]+.05)/(values[1]+.05)>=4.5,`최종 후보 ${fg}/${bg} 대비`);
}
// The new presentation uses the same executable handlers and plan rules.
run('entries=structuredClone(demoEntries);policy=structuredClone(demoPolicy);history=[];revision=0;planState=null;selectedProfile="app"');
document.getElementById('scope').value='all';document.getElementById('search').value='';
vm.runInContext(candidateHTML.match(/<script>\n([\s\S]*?)<\/script>/)[1],ui);
assert.equal(run('route'),'profiles');
assert.ok(document.getElementById('list-body').innerHTML.includes('앱 전체 고정'));
assert.ok(document.getElementById('list-body').innerHTML.includes('~/.claude/skills/swiftui-ui-patterns'));
run('selectedProfile="writing";render();openPlan(demoProfiles[1],"글쓰기 프로필 적용")');
assert.ok(document.getElementById('plan-body').innerHTML.includes('다른 프로젝트에도 영향'));
assert.equal(run('applyPlan()'),'Applied');assert.equal(run('planChanges(entries,demoProfiles[1],policy).matched'),true);
assert.equal(document.activeElement,document.getElementById('selector'),'적용 뒤 키보드 포커스 복원');
run('openPlan(demoProfiles[0],"앱 개발 프로필 적용");revision++');assert.equal(run('applyPlan()'),'Stale');assert.equal(document.getElementById('apply-plan').disabled,true);
run('openPlan({kind:"single",managedIds:["git"],desiredIds:[]},"고정 보관")');assert.equal(run('applyPlan()'),'Blocked');assert.ok(document.getElementById('plan-body').innerHTML.includes('PinnedEntry'));
// Source classification is presentation metadata, never a write authority or profile scope.
run('entries=structuredClone(demoEntries);policy=structuredClone(demoPolicy);history=[];revision=0;route="library";filter="all";planState=null');
document.getElementById('search').value='';document.getElementById('scope').value='all';
const beforeOrigin=run('JSON.stringify({entries,policy,profiles:demoProfiles,history,revision,plan:planChanges(entries,demoProfiles[0],policy)})');
document.getElementById('origin-filter').value='matt';listeners.get('origin-filter:change')();
assert.ok(document.getElementById('list-body').innerHTML.includes('data-entry="debug"'));
assert.ok(document.getElementById('list-body').innerHTML.includes('data-entry="domain"'));
assert.ok(document.getElementById('list-body').innerHTML.includes('data-entry="plugin"'));
assert.ok(!document.getElementById('list-body').innerHTML.includes('data-entry="swiftui-shared"'));
assert.equal(run('JSON.stringify({entries,policy,profiles:demoProfiles,history,revision,plan:planChanges(entries,demoProfiles[0],policy)})'),beforeOrigin,'출처 필터는 파일·권한·목표·관리 범위·안전 계획 변경 0건');
assert.equal(run('planChanges(entries,{kind:"single",managedIds:["plugin"],desiredIds:[]},policy).valid'),false,'같은 출처의 플러그인도 파일 변경 불가');
run('route="profiles";selectedProfile="app";render()');
assert.ok(document.getElementById('list-body').innerHTML.includes('~/.claude/skills/swiftui-ui-patterns'),'출처 필터와 무관한 전체 프로필 관리 대상');
run('route="library"');document.getElementById('origin-filter').value='mabyko';listeners.get('origin-filter:change')();
assert.ok(!document.getElementById('list-body').innerHTML.includes('data-entry='),'등록 출처의 로컬 항목 0개를 원격 스킬로 채우지 않음');
assert.ok(document.getElementById('list-body').innerHTML.includes('원격 저장소의 스킬 목록은 조회하지 않았습니다.'));
document.getElementById('origin-filter').value='unknown';listeners.get('origin-filter:change')();
assert.ok(document.getElementById('list-body').innerHTML.includes('data-entry="swiftui-shared"'));
click('select-related','domain');assert.equal(document.getElementById('origin-filter').value,'all');assert.equal(run('selected'),'domain','관련 항목 이동 시 출처 필터 초기화');
assert.ok(document.getElementById('detail').innerHTML.includes('사용자 지정 · 예시'));
assert.ok(document.getElementById('detail').innerHTML.includes('skills/domain-modeling'));
// Navigation regressions found in the single parallel review round.
run('route="groups";render();$("detail-dialog").showModal();$("search").value="앱"');
click('go-profiles');
assert.equal(run('route'),'profiles');assert.equal(document.getElementById('detail-dialog').open,false,'명시적 화면 전환은 상세 모달 닫기');
assert.equal(document.getElementById('search').value,'','화면 전환은 다른 대상의 검색어 초기화');
assert.equal(document.getElementById('scope').disabled,true,'전체 구성을 보여주는 화면은 에이전트 조회 필터 비활성화');
document.getElementById('search').value='앱';document.getElementById('origin-filter').value='matt';
run('selectedProfile="app";render()');
const profileContext=run('JSON.stringify({route,selectedProfile,search:$("search").value,scope:$("scope").value,origin:$("origin-filter").value})');
listeners.get('list-body:click')({target:{closest:()=>({dataset:{action:'inspect-entry',id:'debug'}})}});click('inspect-entry','debug');
assert.equal(document.getElementById('detail-dialog').open,true);
assert.ok(document.getElementById('detail').innerHTML.includes('diagnosing-bugs'));
click('favourite','debug');
assert.ok(document.getElementById('detail').innerHTML.includes('diagnosing-bugs'),'구성 내부 상세의 설정 변경 후에도 본문 보존');
assert.equal(run('JSON.stringify({route,selectedProfile,search:$("search").value,scope:$("scope").value,origin:$("origin-filter").value})'),profileContext,'구성 항목 확인은 원래 화면·검색·필터 보존');
let prevented=false;
listeners.get('document:keydown')({metaKey:true,key:'f',preventDefault(){prevented=true}});
assert.equal(prevented,false,'모달 중 배경 검색 단축키를 가로채지 않음');
document.getElementById('detail-dialog').close();
run('route="library";filter="readonly";$("search").value="";$("origin-filter").value="matt";render("filter")');
assert.ok(document.getElementById('list-head').innerHTML.includes('표시 1개 / 출처 범위 3개'),'실제 결과 수와 출처 범위 총수 구분');
run('filter="all";$("origin-filter").value="all";$("search").value="~/.claude/skills";render("filter")');
assert.ok(document.getElementById('list-head').innerHTML.includes('표시 1개 / 출처 범위 8개'),'설치 위치로 동일 이름의 항목 찾기');
assert.equal(document.getElementById('search').value,'~/.claude/skills','관찰 갱신은 검색 보존');
run('navigateTo("profiles")');assert.equal(document.getElementById('search').value,'');
assert.ok(document.getElementById('list-body').innerHTML.includes('발견됨 → 보관'),'변경 전후를 본문에서 명시');
console.log('통과: 전역 고정·참조/경로 영향·NoChanges·Undo·복구 분류·실제 시안 클릭·최종 후보 적용/차단·포커스 요청·모달/탐색 맥락·결과 수/경로 검색·출처 필터 상태/권한 보존·양쪽 테마 대비·문서 링크·문법 (파일 이동/네이티브 검증 아님)');

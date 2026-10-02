// Review-only rules and synthetic paths. No filesystem or agent integration.
const demoEntries = [
  {id:'swiftui-shared',name:'swiftui-ui-patterns',description:'SwiftUI 화면, 탐색과 상태 구성',agent:'Codex',location:'~/.agents/skills/swiftui-ui-patterns',kind:'folder',state:'on',writable:true,favourite:true,findings:0,group:'앱 개발'},
  {id:'swiftui-claude',name:'swiftui-ui-patterns',description:'공유 원본을 참조하는 Claude 설치 항목',agent:'Claude Code',location:'~/.claude/skills/swiftui-ui-patterns',kind:'link',sourceId:'swiftui-source',state:'on',writable:true,favourite:false,findings:0,group:'앱 개발'},
  {id:'debug',name:'diagnosing-bugs',description:'증거를 확인하며 원인과 재현 조건 찾기',agent:'Codex',location:'~/.agents/skills/diagnosing-bugs',kind:'folder',state:'on',writable:true,favourite:false,findings:1,group:'앱 개발'},
  {id:'writing',name:'writing',description:'문서의 구조와 문장을 다듬는 작업',agent:'Codex',location:'~/.agents/skills/writing',kind:'folder',state:'off',writable:true,favourite:false,findings:0,group:'글쓰기'},
  {id:'git',name:'git-workflow',description:'브랜치와 커밋 작업 흐름',agent:'Codex',location:'~/.agents/skills/git-workflow',kind:'folder',state:'on',writable:true,favourite:true,findings:0,group:'공통'},
  {id:'system',name:'openai-docs',description:'시스템이 제공하는 공식 문서 확인 지침',agent:'Codex',location:'시스템 제공 카탈로그',kind:'folder',state:'on',writable:false,owner:'시스템',favourite:false,findings:0,group:'공통'},
  {id:'plugin',name:'code-review',description:'플러그인 카탈로그의 리뷰 지침',agent:'Claude Code',location:'플러그인 제공 카탈로그',kind:'folder',state:'unknown',writable:false,owner:'플러그인',favourite:false,findings:1,group:'앱 개발'},
  {id:'domain',name:'domain-modeling',description:'프로젝트의 용어와 관계 정리',agent:'Codex',location:'~/.agents/skills/domain-modeling',kind:'folder',state:'on',writable:true,favourite:false,findings:0,group:'설계'}
].map(entry=>({...entry,owner:entry.owner??'user',rootId:entry.agent==='Codex'?'codex':'claude',path:entry.location.replace('~','/Users/demo'),contentFingerprint:'demo-'+entry.id,entryRevision:0}));
const demoPolicy = {
  pinnedIds:['git'],
  roots:[{id:'codex',path:'/Users/demo/.agents/skills',owner:'user',approved:true,accessible:true,complete:true},{id:'claude',path:'/Users/demo/.claude/skills',owner:'user',approved:true,accessible:true,complete:true}],
  protectedPaths:['/Users/demo/.claude/skills/synced'],
  sources:[{id:'swiftui-source',entryId:'swiftui-shared',path:'/Users/demo/.agents/skills/swiftui-ui-patterns',approved:true,accessible:true,status:'present',depth:1}]
};
const demoProfiles = [
  {id:'app',name:'앱 개발',description:'SwiftUI와 디버깅에 집중',managedIds:['swiftui-shared','swiftui-claude','debug','writing','git','domain'],desiredIds:['swiftui-shared','swiftui-claude','debug']},
  {id:'writing',name:'글쓰기',description:'문서 작성으로 작업 전환',managedIds:['swiftui-shared','swiftui-claude','debug','writing','git','domain'],desiredIds:['writing']},
  {id:'design',name:'설계',description:'프로젝트의 용어와 구조 정리',managedIds:['swiftui-shared','swiftui-claude','debug','writing','git','domain'],desiredIds:['domain']}
];

// Synthetic, manually assigned provenance; never evidence about this Mac's skills.
// Physical link originals remain in demoPolicy.sources.
const demoRepositories = [
  {id:'matt',name:'mattpocock/skills',url:'https://github.com/mattpocock/skills'},
  {id:'mabyko',name:'mabyko/mabyko-kit',url:'https://github.com/mabyko/mabyko-kit'}
];
const demoProvenance = {
  debug:{repositoryId:'matt',relativePath:'skills/diagnosing-bugs',method:'사용자 복사본',evidence:'사용자 지정 · 예시'},
  domain:{repositoryId:'matt',relativePath:'skills/domain-modeling',method:'사용자 복사본',evidence:'사용자 지정 · 예시'},
  plugin:{repositoryId:'matt',relativePath:'skills/code-review',method:'플러그인 묶음',evidence:'사용자 지정 · 예시'}
};
const repositoryFor = entry => demoRepositories.find(repository=>repository.id===demoProvenance[entry.id]?.repositoryId);

const insidePath = (path,parent) => typeof path==='string' && typeof parent==='string' && (path===parent || path.startsWith(parent+'/'));
const validPath = path => typeof path==='string' && path.startsWith('/') && !path.includes('\0') && !path.split('/').some(part=>part==='.'||part==='..') && !path.includes('//') && !path.endsWith('/');
const sourceFor = (entry,policy) => policy.sources.find(source=>source.id===entry.sourceId);
const sourceEntryId = (entry,policy) => sourceFor(entry,policy)?.entryId;
const entryFingerprint = entry => JSON.stringify([entry.id,entry.path,entry.rootId,entry.kind,entry.state,entry.writable,entry.owner??'user',entry.sourceId??null,entry.contentFingerprint,entry.entryRevision]);
function snapshotSignature(entries,policy) {
  // ponytail: one catalog signature; unrelated file changes also require a new preview.
  return JSON.stringify([entries.map(entryFingerprint).sort(),[...policy.pinnedIds].sort(),policy.roots,policy.protectedPaths,policy.sources]);
}

const blockedReason=(code,id,reason,relatedIds=[])=>({code,id,reason,relatedIds});
function planChanges(entries,intent,policy) {
  if(!Array.isArray(entries)||entries.some(entry=>!entry||typeof entry!=='object')||!intent||!Array.isArray(intent.managedIds)||!Array.isArray(intent.desiredIds)||!policy||!['pinnedIds','roots','protectedPaths','sources'].every(key=>Array.isArray(policy[key]))||policy.roots.some(root=>!root||typeof root!=='object')||policy.sources.some(source=>!source||typeof source!=='object')||![undefined,'profile','single','undo'].includes(intent.kind)) {
    return {intent:null,changes:[],retained:[],blocked:[blockedReason('InvalidInput',null,'계획 입력 형식이 유효하지 않습니다.')],untouched:[],valid:false,matched:false,signature:null};
  }
  const managed=new Set(intent.managedIds), pinned=new Set(policy.pinnedIds), desired=new Set(intent.desiredIds);
  const byId=new Map(entries.map(entry=>[entry.id,entry])), changes=[], retained=[], blocked=[];
  const block=(code,id,reason,relatedIds=[])=>blocked.push(blockedReason(code,id,reason,relatedIds));
  const finish=()=>({intent:{kind:intent.kind??'profile',managedIds:[...managed],desiredIds:[...intent.desiredIds]},changes,retained,blocked,untouched:entries.filter(entry=>!managed.has(entry.id)),valid:!blocked.length,matched:!blocked.length&&!changes.length,signature:snapshotSignature(entries,policy)});
  if(byId.size!==entries.length || entries.some(entry=>typeof entry.id!=='string'||!entry.id||entry.id==='.'||entry.id==='..'||/[\\/]/.test(entry.id))) {
    block('InvalidEntryIdentity',null,'설치 ID가 중복되거나 유효하지 않습니다.');return finish();
  }
  const paths=entries.filter(entry=>validPath(entry.path)).map(entry=>entry.path);
  if(new Set(paths).size!==paths.length){block('DuplicateEntryPath',null,'동일한 실제 설치 위치가 중복 등록됐습니다.');return finish();}
  if(new Set(policy.sources.map(source=>source.id)).size!==policy.sources.length || new Set(policy.roots.map(root=>root.id)).size!==policy.roots.length) {
    block('DuplicateRegistryIdentity',null,'원본 또는 발견 위치 ID가 중복됩니다.');return finish();
  }
  for(const id of desired)if(!managed.has(id))block('TargetOutsideScope',id,'목표 항목이 관리 범위 밖에 있습니다.');
  if((intent.kind??'profile')==='profile')for(const id of pinned)if(managed.has(id))desired.add(id);
  for(const id of managed) {
    const entry=byId.get(id), root=policy.roots.find(root=>root.id===entry?.rootId);
    if(!entry){block('MissingEntry',id,'설치 항목을 찾을 수 없습니다.');continue;}
    if(entry.writable!==true||entry.owner!=='user'||root?.owner!=='user'){block('ReadOnlyOwnership',id,'제공 주체가 관리하는 읽기 전용 항목입니다.');continue;}
    if(!['on','off'].includes(entry.state)){block('UnknownFileState',id,'현재 파일 상태를 확인할 수 없습니다.');continue;}
    if(!['folder','link'].includes(entry.kind)||!validPath(entry.path)||root?.approved!==true||root.accessible!==true||!validPath(root.path)||entry.path===root.path||!insidePath(entry.path,root.path)) {
      block('UnapprovedLocation',id,'승인된 발견 위치 안의 설치 항목을 확인할 수 없습니다.');continue;
    }
    if(policy.protectedPaths.some(path=>insidePath(entry.path,path))){block('ProtectedLocation',id,'보호 위치의 항목은 관리 범위에 포함할 수 없습니다.');continue;}
    const target=desired.has(id)?'on':'off';
    if(target==='off'&&pinned.has(id)){block('PinnedEntry',id,'앱 전체 고정 항목입니다. 보관하려면 먼저 고정을 해제하세요.');continue;}
    if(target===entry.state)retained.push({...entry,pinned:pinned.has(id)});
    else changes.push({...entry,target,pinned:pinned.has(id)});
  }
  const stateAfter=id=>changes.find(entry=>entry.id===id)?.target??byId.get(id)?.state;
  const referencesTo=target=>entries.filter(entry=>entry.kind==='link'&&(sourceEntryId(entry,policy)===target.id||target.kind==='folder'&&insidePath(sourceFor(entry,policy)?.path,target.path)));
  const neighbours=id=>referencesTo(byId.get(id)??{id}).map(entry=>entry.id).concat(sourceEntryId(byId.get(id)??{},policy)??[]);
  for(const change of changes) {
    const connected=new Set(),pending=[change.id];
    while(pending.length){const id=pending.pop();if(connected.has(id))continue;connected.add(id);pending.push(...neighbours(id));}
    if([...connected].some(id=>{const entry=byId.get(id);return entry?.kind==='link'&&(byId.get(sourceEntryId(entry,policy))?.kind==='link'||(sourceFor(entry,policy)?.depth??1)>1||sourceFor(entry,policy)?.cyclic);})) {
      block('UnsupportedLinkGraph',change.id,'다단계 또는 순환 링크 관계의 변경은 첫 버전에서 지원하지 않습니다.',[...connected].filter(id=>id!==change.id));
    }
    if(policy.protectedPaths.some(path=>insidePath(change.path,path)||change.kind==='folder'&&insidePath(path,change.path)))block('ProtectedLocation',change.id,'보호 위치에 영향을 주는 이동입니다.');
    if(change.kind==='folder' && (entries.some(entry=>entry.id!==change.id&&insidePath(entry.path,change.path))||policy.roots.some(root=>insidePath(root.path,change.path))))block('NestedEntries',change.id,'이동 폴더 안에 다른 설치 항목이나 등록 위치가 있습니다.',entries.filter(entry=>entry.id!==change.id&&insidePath(entry.path,change.path)).map(entry=>entry.id));
    if(change.target==='off') {
      if(policy.roots.some(root=>root.complete!==true))block('IncompleteDiscovery',change.id,'등록 위치의 참조 검사가 완료되지 않았습니다.');
      const references=referencesTo(change);
      if(references.some(entry=>stateAfter(entry.id)!=='off'))block('ActiveReference',change.id,'공유 원본을 사용하는 다른 설치 항목을 함께 보관해야 합니다.',references.filter(entry=>stateAfter(entry.id)!=='off').map(entry=>entry.id));
    }
    if(change.target==='on'&&change.kind==='link') {
      const source=sourceFor(change,policy), sourceEntry=byId.get(source?.entryId);
      // expectedWhenRestored verifies this exact target inside the parked payload,
      // including child paths; a containing folder alone does not prove existence.
      const targetVerified=source?.status==='present'||sourceEntry?.state==='off'&&stateAfter(sourceEntry.id)==='on'&&source?.expectedWhenRestored===true;
      const available=source?.approved===true&&source.accessible===true&&validPath(source.path)&&(source.entryId?sourceEntry?.kind==='folder'&&insidePath(source.path,sourceEntry.path)&&stateAfter(source.entryId)==='on'&&targetVerified:source.status==='present');
      if(!available)block('SourceUnavailable',change.id,'복원 시점의 공유 원본 존재·승인·접근을 확인할 수 없습니다.',source?.entryId?[source.entryId]:[]);
    }
  }
  const order=entry=>entry.target==='off'?(entry.kind==='link'?0:1):(entry.kind==='folder'?2:3);
  changes.sort((a,b)=>order(a)-order(b));
  return finish();
}

function planUndo(entries,history,index,policy) {
  const record=history[index];
  const intent={kind:'undo',managedIds:record?.changes.map(change=>change.id)??[],desiredIds:record?.changes.filter(change=>change.previous==='on').map(change=>change.id)??[]};
  const plan=planChanges(entries,intent,policy), ids=new Set(intent.managedIds);
  if(!record||record.restored||history.slice(index+1).some(later=>later.changes.some(change=>ids.has(change.id))))plan.blocked.push(blockedReason('UndoHasSuccessor',null,'이 기록 이후 같은 항목을 변경했거나 이미 되돌렸습니다.',[...ids]));
  if(record?.changes.some(change=>{const entry=entries.find(entry=>entry.id===change.id);return !entry||entryFingerprint(entry)!==change.afterFingerprint;}))plan.blocked.push(blockedReason('UndoStateChanged',null,'기록한 변경 후 상태와 현재 항목이 다릅니다.',[...ids]));
  plan.valid=!plan.blocked.length;plan.matched=plan.valid&&!plan.changes.length;return plan;
}

function applyPreview(entries,plan,policy,currentRevision,expectedRevision) {
  if(!plan||!Array.isArray(plan.blocked)||!Array.isArray(plan.changes)||plan.blocked.length)return {status:'Blocked',entries};
  const fresh=planChanges(entries,plan.intent,policy);
  if(fresh.signature===null)return {status:'Blocked',entries};
  if(currentRevision!==expectedRevision||plan.signature!==fresh.signature)return {status:'Stale',entries};
  const moves=changes=>JSON.stringify(changes.map(change=>[entryFingerprint(change),change.target]));
  if(fresh.blocked.length||moves(fresh.changes)!==moves(plan.changes))return {status:'Blocked',entries};
  if(!plan.changes.length)return {status:'NoChanges',entries};
  return {status:'Applied',entries:entries.map(entry=>{const change=plan.changes.find(change=>change.id===entry.id);return change?{...entry,state:change.target,entryRevision:entry.entryRevision+1}:entry;})};
}

// Only classifies the recorded move's physical endpoints, never user pin/source policy.
// A real rollback also validates paths, content, and newly changed external references.
function classifyRecovery(from,to) {
  if(![from,to].every(state=>['expected','missing','changed'].includes(state)))throw new Error('알 수 없는 복구 상태');
  if(from==='changed'||to==='changed')return 'external-change';
  if(from==='expected'&&to==='expected')return 'conflict';
  if(from==='missing'&&to==='missing')return 'missing';
  return from==='expected'?'before-move':'after-move';
}

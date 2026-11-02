const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const express = require('express');
const http = require('node:http');
const { createServerBookRecapStorage } = require('../src/services/bookRecapStorage.service');
const { createBookRecapExecutor } = require('../src/services/bookRecapExecutor');
const { createBookRecapAuthorization } = require('../src/services/bookRecapAuthorization');
const { createBookRecapDisplayService } = require('../src/services/bookRecapDisplay.service');
const { createBookRecapDisplayHttpAdapter } = require('../src/routes/bookRecapDisplayHttpAdapter');
const legacy = require('../src/services/bookRecapHttpContract');
const fixture = require('../../tool/book_recap_eval/fixture.v1.json');
const gate = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };

module.exports = async function scenarios(t, { db, pool, repo, user, generate, probe }) {
  const entries = require('../src/repositories/entry.repository');
  const origin = 'https://synthetic.invalid', authorize = createBookRecapAuthorization(1);
  const storage = createServerBookRecapStorage({ repository: repo, origin, macKey: Buffer.alloc(32, 41) });
  let now = new Date();
  const options = { repository: repo, authorize, origin, cursorKey: Buffer.alloc(32, 42),
    cursorLifetimeMs: 60000, displayPolicy: { version:'test-only',windowMs:2000 }, clock:() => now };
  const service = createBookRecapDisplayService(options);
  const principal = f => ({ userId: f.userId, tokenVersion: 0 });
  const row = async f => (await db.query('SELECT * FROM reading_recaps WHERE id=$1', [f.id])).rows[0];
  const version = f => ({ book_id:f.bookId,expected_revision:f.scope.revision,expected_source_fingerprint:f.scope.source_fingerprint });
  async function setup({ userId, saved = false, follows = false } = {}) {
    now = new Date(); userId ||= await user();
    await db.query('UPDATE users SET ai_consent_version=1 WHERE id=$1', [userId]);
    const f = { userId, id:randomUUID(), bookId:randomUUID() };
    const e = await entries.createEntry(userId, { source:'ai_question',book_id:f.bookId,book_title:'Same title',
      chapter_index:'7',chapter_title:'Synthetic chapter',original_text:fixture.excerpt,
      user_input:fixture.question,ai_explanation:fixture.answer,
      metadata_json:{origin:'reader',reading_ai_context:{scope:'selection',selectedText:fixture.excerpt}} });
    f.entryId = e.id;
    if (follows) f.follow = await entries.createFollowUp(userId,e.id,'Synthetic follow-up','Historical answer');
    const prepared = await storage.prepare(userId,{recap_id:f.id,request_id:randomUUID(),book_id:f.bookId,selected_sources:[{entry_id:e.id}]});
    const executor = createBookRecapExecutor({storage,authorize,model:'synthetic',transport:async req => {
      const s = JSON.parse(req.messages[1].content);
      return {completed:true,finishReason:'stop',text:JSON.stringify({schemaVersion:1,snapshotFingerprint:s.snapshotFingerprint,
        knowledge:[{id:'k1',kind:'argument',title:'Condition',summary:'Necessary, not sufficient.',basis:'source_supported',
          evidenceRefs:[s.evidence.find(v=>v.kind==='book_excerpt').id],quotes:[]}],relations:[],myThinking:[],openQuestions:[],nextQuestions:[]})};
    }});
    await executor.generate(principal(f),f.id,generate(prepared));
    if (saved) await storage.save(userId,f.id,{request_id:randomUUID(),expected_revision:(await row(f)).revision});
    f.scope = await service.scope(principal(f),f.id); return f;
  }
  const view = f => service.view(principal(f),f.id,version(f));
  const evidence = (f, ids=f.scope.evidence_catalog.map(e=>e.id)) => service.evidence(principal(f),f.id,{...version(f),evidence_ids:ids});
  const fails = (promise, code) => assert.rejects(promise,{error_code:code});

  await t.test('B24b1 stable microsecond keyset pagination, private metadata only and foreign cursor refusal', async () => {
    const a=await setup(), b=await setup({userId:a.userId}), c=await setup({userId:a.userId}), outsider=await setup();
    await db.query("UPDATE reading_recaps SET created_at='2025-01-01T00:00:00.123456Z' WHERE user_id=$1",[a.userId]);
    const expected=[a.id,b.id,c.id].sort().reverse();
    const first=await service.history(principal(a),{limit:1});
    assert.equal(first.items[0].id,expected[0]); assert(first.items[0].created_at.endsWith('123456Z'));
    assert.equal(first.items[0].availability,'requires_online_verification');
    const encoded=JSON.stringify(first);
    for(const secret of [fixture.excerpt,fixture.answer,'result_json','selected_sources','source_fingerprint',a.userId]) assert(!encoded.includes(secret));
    assert(!first.items.some(v=>v.id===outsider.id));
    await fails(service.history(principal(outsider),{limit:1,cursor:first.next_cursor}),'RECAP_CURSOR_INVALID');
    await fails(service.history(principal(a),{limit:2,cursor:first.next_cursor}),'RECAP_CURSOR_INVALID');
    await fails(service.history(principal(a),{limit:1,cursor:first.next_cursor+'x'}),'RECAP_CURSOR_INVALID');
    await storage.remove(a.userId,expected[1]);
    const second=await service.history(principal(a),{limit:1,cursor:first.next_cursor});
    assert.equal(second.items[0].id,expected[1]); assert.equal(second.items[0].state,'deleted');assert.equal(second.items[0].book_id,null);
    const third=await service.history(principal(a),{limit:1,cursor:second.next_cursor});
    assert.equal(third.items[0].id,expected[2]);assert.equal(third.next_cursor,null);
    now=new Date(now.getTime()+60001);
    await fails(service.history(principal(a),{limit:1,cursor:first.next_cursor}),'RECAP_CURSOR_INVALID');
  });
  await t.test('B24b1 saved/preview/expired distinguish properties without claiming source validity', async () => {
    const a=await setup({saved:true}),b=await setup({userId:a.userId});
    const saved=await service.history(principal(a),{filter:'saved'});assert.deepEqual(saved.items.map(v=>v.id),[a.id]);
    await db.query("UPDATE reading_recaps SET expires_at=now()-interval '1 hour' WHERE id=$1",[b.id]);
    const preview=await service.history(principal(a),{filter:'preview'});assert.equal(preview.items[0].state,'expired');
    assert.equal(preview.items[0].availability,'unavailable');await fails(view(b),'RECAP_EXPIRED');assert((await view(a)).recap.is_saved);
  });
  await t.test('B24b1 restore scope contains no body; new envelope preserves exact B24a legacy DTO', async () => {
    const f=await setup();const serialized=JSON.stringify(f.scope);
    for(const body of [fixture.excerpt,fixture.question,fixture.answer,'Necessary, not sufficient.']) assert(!serialized.includes(body));
    assert.equal(f.scope.requires_local_confirmation,true);assert.equal(f.scope.local_pending_verified,false);
    const result=await view(f);assert.deepEqual(legacy.response.parse(result.recap),result.recap);
    assert.equal(result.recap.state,'ready');assert.equal(result.display.revision,f.scope.revision);
    assert(!legacy.response.safeParse(result).success,'old strict client must not accidentally accept the new envelope');
    assert.equal((await service.validate(principal(f),f.id,version(f))).display.requires_online_on_open,true);
  });
  await t.test('B24b1 evidence preserves reader context, historical AI, questions and fragment-only locations', async () => {
    const f=await setup({follows:true}),result=await evidence(f);
    const excerpt=result.evidence.find(e=>e.kind==='book_excerpt');assert.equal(excerpt.provenance,'reader_context');assert.equal(excerpt.text,fixture.excerpt);
    assert.deepEqual(excerpt.location,{status:'fragment_only',exact:false,chapter_index:'7',chapter_title:'Synthetic chapter'});
    assert(result.evidence.some(e=>e.provenance==='follow_up'&&e.kind==='historical_ai'));
    assert(result.evidence.some(e=>e.kind==='user_question'));
    for(const e of result.evidence) { assert(!('metadata_json' in e));assert(!('sourceField' in e));assert(!('user_id' in e)); }
  });
  await t.test('B24b1 cross-account, wrong book/revision/fingerprint and foreign evidence rejected', async () => {
    const a=await setup(),b=await setup({userId:a.userId}),other=await setup();
    await fails(service.view(principal(other),a.id,version(a)),'RECAP_NOT_FOUND');
    for(const v of [{...version(a),book_id:b.bookId},{...version(a),expected_revision:'999'},{...version(a),expected_source_fingerprint:'0'.repeat(64)}]) {
      await fails(service.view(principal(a),a.id,v),'RECAP_REVISION_CONFLICT');
    }
    await fails(evidence(a,[b.scope.evidence_catalog[0].id]),'RECAP_EVIDENCE_NOT_FOUND');
    await fails(evidence(a,['e-'+'0'.repeat(64)]),'RECAP_EVIDENCE_NOT_FOUND');
  });
  for(const mutation of ['edit','delete','remove']) await t.test(`B24b1 ${mutation} withdraws view, evidence and validation without resurrecting content`,async()=>{
    const f=await setup();await view(f);
    if(mutation==='edit') await entries.updateEntryImportance(f.userId,f.entryId,true);
    else if(mutation==='delete') await entries.deleteEntry(f.userId,f.entryId);
    else await storage.remove(f.userId,f.id);
    const error=mutation==='edit'?'RECAP_SOURCE_CHANGED':'RECAP_UNAVAILABLE';
    await fails(view(f),error);await fails(evidence(f),error);await fails(service.validate(principal(f),f.id,version(f)),error);
    assert.equal((await row(f)).result_json,null);
  });
  await t.test('B24b1 source changes without hook, chapters and follow-up sets fail resolver verification',async()=>{
    for(const mode of ['chapter','content','follow']) {
      const f=await setup();
      if(mode==='follow') await entries.createFollowUp(f.userId,f.entryId,'New question','New answer');
      else await db.query(`UPDATE user_entries SET ${mode==='chapter'?'chapter_title':'user_input'}=$2 WHERE id=$1`,[f.entryId,'Changed synthetic material']);
      await assert.rejects(view(f),e=>e.error_code==='RECAP_SOURCE_CHANGED');
    }
  });
  await t.test('B24b1 missing dependencies, old resolver and schema versions fail closed',async()=>{
    for(const mode of ['dependency','resolver','schema']) {
      const f=await setup();
      if(mode==='dependency') await db.query('DELETE FROM reading_recap_sources WHERE recap_id=$1',[f.id]);
      if(mode==='resolver') await db.query(`UPDATE reading_recaps SET coverage_json=jsonb_set(coverage_json,'{sourceCompleteness}','"local_and_supplied_cache"') WHERE id=$1`,[f.id]);
      if(mode==='schema') await db.query('UPDATE reading_recaps SET schema_version=2 WHERE id=$1',[f.id]);
      await assert.rejects(view(f));
    }
  });
  for(const change of ['consent','ban','token','expired']) await t.test(`B24b1 ${change} denies history, scope and body`,async()=>{
    const f=await setup();let p=principal(f);
    if(change==='consent') await db.query('UPDATE users SET ai_consent_version=0 WHERE id=$1',[f.userId]);
    if(change==='ban') await db.query("UPDATE users SET account_status='banned' WHERE id=$1",[f.userId]);
    if(change==='token') await db.query('UPDATE users SET token_version=1 WHERE id=$1',[f.userId]);
    if(change==='expired') p={...p,expiresAt:1};
    const error=change==='consent'?'AI_CONSENT_REQUIRED':'RECAP_AUTH_REQUIRED';
    await fails(service.history(p,{}),error);await fails(service.scope(p,f.id),error);await fails(service.view(p,f.id,version(f)),error);
  });
  await t.test('B24b1 last authorization check rejects consent revocation during source read',async()=>{
    const f=await setup();let changed=false;
    await assert.rejects(probe.run({async after(sql){if(!changed&&sql.includes('reading_recap_sources')&&sql.includes('ORDER BY evidence_id')){
      changed=true;await pool.query('UPDATE users SET ai_consent_version=0 WHERE id=$1',[f.userId]);
    }}},()=>view(f)),{error_code:'AI_CONSENT_REQUIRED'});assert(changed);
  });
  await t.test('B24b1 explicit display policy, JWT/preview deadline caps and no perpetual permit',async()=>{
    const f=await setup();
    const noPolicy=createBookRecapDisplayService({...options,displayPolicy:undefined});
    await fails(noPolicy.view(principal(f),f.id,version(f)),'RECAP_DISPLAY_POLICY_REQUIRED');
    assert.equal((await noPolicy.history(principal(f),{})).items.length,1);
    const p={...principal(f),expiresAt:Math.floor(Date.now()/1000)+1};
    const g=(await service.view(p,f.id,version(f))).display;assert(Date.parse(g.expires_at)<=p.expiresAt*1000);
    await db.query('UPDATE reading_recaps SET expires_at=$2 WHERE id=$1',[f.id,new Date(now.getTime()+400)]);
    assert.equal((await view(f)).display.max_age_ms,400);
    let moved=false;await fails(probe.run({after(sql){if(!moved&&sql.includes('ORDER BY evidence_id')){moved=true;now=new Date(now.getTime()+2001);}}},()=>view(f)),'RECAP_DISPLAY_EXPIRED');
  });
  await t.test('B24b1 library header/file absence does not invent location or require full book recovery',async()=>{
    const f=await setup();assert.equal((await db.query('SELECT count(*) FROM user_library_books WHERE user_id=$1',[f.userId])).rows[0].count,'0');
    assert((await view(f)).recap.result);assert.equal((await evidence(f)).evidence[0].location.exact,false);
    assert.equal(f.scope.book_id,f.bookId);
  });
  await t.test('B24b1 all non-ready states remain metadata-only and unavailable',async()=>{
    for(const state of ['prepared','generating','failed','cancelled','stale','invalidated','deleted','expired']) {
      const f=await setup();
      if(state==='deleted') await storage.remove(f.userId,f.id);
      else if(state==='invalidated') await entries.deleteEntry(f.userId,f.entryId);
      else await db.query('UPDATE reading_recaps SET state=$2,result_json=NULL WHERE id=$1',[f.id,state]);
      const list=await service.history(principal(f),{});
      assert.equal(list.items[0].state,state);assert.equal(list.items[0].availability,'unavailable');
      await assert.rejects(service.scope(principal(f),f.id));await assert.rejects(view(f));
    }
  });
  await t.test('B24b1 unselected traces, private notes and ordinary chat never enter display',async()=>{
    const f=await setup();
    await entries.createEntry(f.userId,{source:'manual',book_id:f.bookId,original_text:'Not selected excerpt',user_input:'Unselected private note',metadata_json:{origin:'reader'}});
    const conversations=require('../src/repositories/xiaouConversation.repository');
    const chat=await conversations.createConversation(f.userId,{kind:'chat'});
    await conversations.appendMessage(f.userId,chat.id,{role:'user',content:'Ordinary chat private text'});
    const sql=[];
    const response=await probe.run({after(query){sql.push(query);}},()=>evidence(f));
    assert(!JSON.stringify(response).includes('Unselected private note'));assert(!JSON.stringify(response).includes('Ordinary chat private text'));
    assert(!sql.some(s=>/FROM (free_notes|xiaou_messages|ai_messages|user_library_books)/u.test(s)));
    await db.query(`UPDATE user_entries SET metadata_json='{"origin":"free_note"}' WHERE id=$1`,[f.entryId]);
    await assert.rejects(evidence(f));
  });
  await t.test('B24b1 new records after pagination ceiling and updated_at changes do not reorder pages',async()=>{
    const a=await setup(),b=await setup({userId:a.userId});
    await db.query("UPDATE reading_recaps SET created_at='2025-02-01T00:00:00Z' WHERE user_id=$1",[a.userId]);
    const first=await service.history(principal(a),{limit:1});
    const added=await setup({userId:a.userId});
    await db.query("UPDATE reading_recaps SET created_at=now()+interval '1 hour' WHERE id=$1",[added.id]);
    await db.query("UPDATE reading_recaps SET updated_at=now()+interval '1 day' WHERE user_id=$1",[a.userId]);
    const second=await service.history(principal(a),{limit:1,cursor:first.next_cursor});
    assert.notEqual(second.items[0].id,first.items[0].id);assert.notEqual(second.items[0].id,added.id);assert.equal(second.next_cursor,null);
    assert.deepEqual([first.items[0].id,second.items[0].id].sort(),[a.id,b.id].sort());
  });
  await t.test('B24b1 display does not advance existing upload sequence or edit original data',async()=>{
    const f=await setup();
    const before=await db.query('SELECT * FROM user_entries WHERE id=$1',[f.entryId]);
    const seq=(await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1',[f.userId])).rows;
    await view(f);await evidence(f);await service.validate(principal(f),f.id,version(f));await service.history(principal(f),{});
    assert.deepEqual((await db.query('SELECT * FROM user_entries WHERE id=$1',[f.entryId])).rows,before.rows);
    assert.deepEqual((await db.query('SELECT last_sequence FROM sync_user_cursors WHERE user_id=$1',[f.userId])).rows,seq);
  });
  await t.test('B24b1 bounded display query costs measured without a model or background polling',async()=>{
    const f=await setup();const counts={};
    for(const [name,action] of Object.entries({history:()=>service.history(principal(f),{}),
      scope:()=>service.scope(principal(f),f.id),view:()=>view(f),evidence:()=>evidence(f),
      validate:()=>service.validate(principal(f),f.id,version(f))})) {
      let queries=0;const start=performance.now();
      await probe.run({after(){queries++;}},action);
      counts[name]={queries,elapsed_ms:Math.round((performance.now()-start)*100)/100};
      assert(queries>0&&queries<100);
    }
    assert(counts.history.queries<counts.view.queries);
    assert.equal(counts.validate.queries,counts.view.queries,'validation still verifies actual sources, not just a row hash');
    t.diagnostic('B24b1 one-source synthetic-only query sample: '+JSON.stringify(counts));
  });
  for(const firstAction of ['view','delete']) await t.test(`B24b1 deterministic ${firstAction}-first source-delete race`,async()=>{
    const f=await setup(),entered=gate(),release=gate(),pidGate=gate();let firstPid,held=false,b;
    const remove=()=>entries.deleteEntry(f.userId,f.entryId),settle=p=>p.then(value=>({value}),error=>({error}));
    const a=settle(probe.run({connected:pid=>firstPid=pid,async after(sql){
      if(!held&&sql.includes('INSERT INTO sync_user_cursors')){held=true;entered.resolve();await release.promise;}
    }},firstAction==='view'?()=>view(f):remove));
    try{
      await entered.promise;b=settle(probe.run({connected:pid=>pidGate.resolve(pid)},firstAction==='view'?remove:()=>view(f)));
      const pid=await pidGate.promise;let blocked=false;
      for(const until=Date.now()+2000;Date.now()<until;){
        if((await pool.query('SELECT $1::int=ANY(pg_blocking_pids($2)) blocked',[firstPid,pid])).rows[0].blocked){blocked=true;break;}
        await new Promise(r=>setTimeout(r,5));
      }assert(blocked);
    }finally{release.resolve();await Promise.all([a,b]);}
    const [one,two]=await Promise.all([a,b]);assert(!one.error,one.error?.stack);
    if(firstAction==='delete') assert.equal(two.error?.error_code,'RECAP_UNAVAILABLE');
    else {assert(!two.error);assert(one.value.display.max_age_ms<=2000);}
    await fails(view(f),'RECAP_UNAVAILABLE');
  });
  await t.test('B24b1 loopback HTTP auth, DTO, private headers, recovery, evidence and error redaction',async()=>{
    const f=await setup();const app=express();
    app.use('/display',createBookRecapDisplayHttpAdapter({service,requireAiConsent:(_q,_s,n)=>n(),auth:(req,_res,next)=>{
      if(req.headers.authorization!=='Bearer synthetic'){return next(Object.assign(Error('ignored'),{statusCode:401,error_code:'RECAP_AUTH_REQUIRED'}));}
      req.user={id:f.userId,tokenVersion:0};req.authUser={id:f.userId};next();
    }}));
    const server=http.createServer(app);await new Promise(r=>server.listen(0,'127.0.0.1',r));
    const request=async(path,body,authorized=true)=>{
      const res=await fetch(`http://127.0.0.1:${server.address().port}/display${path}`,{method:'POST',headers:{'Content-Type':'application/json',...(authorized?{Authorization:'Bearer synthetic'}:{})},body:JSON.stringify(body)});
      assert.equal(res.headers.get('cache-control'),'no-store, private');return {status:res.status,body:await res.json()};
    };
    try{
      assert.equal((await request('/history',{},false)).status,401);
      assert.equal((await request('/history',{user_id:f.userId})).status,400);
      assert.equal((await request('/history?limit=1',{})).status,400);
      assert.equal((await request('/history',{})).body.items.length,1);
      assert.equal((await request(`/${f.id}/scope`,{})).body.requires_local_confirmation,true);
      const v=await request(`/${f.id}/view`,version(f));assert.equal(v.status,200);legacy.response.parse(v.body.recap);
      assert.equal((await request(`/${f.id}/validate`,version(f))).status,200);
      assert.equal((await request(`/${f.id}/evidence`,{...version(f),evidence_ids:[f.scope.evidence_catalog[0].id]})).status,200);
      const invalid=await request(`/${f.id}/view`,{...version(f),snapshot:{private:'body'}});assert.equal(invalid.status,400);assert.deepEqual(Object.keys(invalid.body),['error_code']);
      await db.query('UPDATE users SET ai_consent_version=0 WHERE id=$1',[f.userId]);
      assert.equal((await request(`/${f.id}/view`,version(f))).status,428);
    }finally{await new Promise(r=>server.close(r));}
  });
};

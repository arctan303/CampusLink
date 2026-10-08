const assert=require('node:assert/strict'),fs=require('node:fs');
const model=new Function('baseclass',fs.readFileSync('packages/luci-app-campuslink/htdocs/luci-static/resources/campuslink/config.js','utf8'))({extend:x=>x});
const provider=JSON.parse(fs.readFileSync('packages/campuslink/files/usr/share/campuslink/providers/drcom-http.json'));
const mock=JSON.parse(fs.readFileSync('packages/campuslink/files/usr/share/campuslink/providers/mock.json'));
const school=JSON.parse(fs.readFileSync('packages/campuslink/files/usr/share/campuslink/schools/local-campus.json'));
const data={providers:[provider,mock],schools:[school],interfaces:[{interface:'wan1'},{interface:'wan2'}]};
const old={schema_version:1,generation:4,accounts:[{id:'a',label:'A',credential_type:'username_password',values:{username:'fake'},password_set:true}],connections:['pc','mobile'].map((mode,i)=>({id:'c'+i,label:'WAN'+i,interface:'wan'+(i+1),provider:'drcom-http',school:'local-campus',account:'a',params:{terminal_mode:mode},enabled:true,auto_login:true,check_interval:60,retry_interval:30,retry_max:600}))};
const baseline=model.copy(old),draft=model.settingsDraft(old,data);
draft.params.auth_server='2.2.2.2';draft.check_interval=120;
const saved=model.saveSettings(old,draft,data);
assert.deepEqual(old,baseline);assert.deepEqual(saved.accounts,old.accounts);assert.equal(saved.generation,4);
for(let i=0;i<2;i++){
 assert.equal(saved.connections[i].account,'a');assert.equal(saved.connections[i].interface,old.connections[i].interface);assert.equal(saved.connections[i].params.terminal_mode,old.connections[i].params.terminal_mode);
 for(const k of ['provider','school','check_interval','retry_interval','retry_max'])assert.equal(k in saved.connections[i],false);
 const effective=model.effective(saved.connections[i],saved);assert.equal(effective.params.auth_server,'2.2.2.2');assert.equal(effective.check_interval,120);
}
const mockDraft={...model.copy(saved.settings),provider:'mock',school:'',params:{}};
const switched=model.saveSettings(saved,mockDraft,data);assert.deepEqual(switched.accounts,saved.accounts);assert.deepEqual(switched.connections.map(c=>c.params),[{},{}]);
assert.equal(model.params(switched.connections[0],data,switched).scenario,'portal');
const exampleProvider=JSON.parse(fs.readFileSync('docs/contracts/examples/drcom-http.provider.json'));
const exampleSchool=JSON.parse(fs.readFileSync('docs/contracts/examples/local-campus.school.json'));
const exampleData={...data,providers:[exampleProvider],schools:[exampleSchool]};
const exampleSaved=model.saveSettings(old,model.settingsDraft(old,exampleData),exampleData);
assert.deepEqual(exampleSaved.connections.map(c=>c.params.terminal_mode),['pc','mobile'],'public extension example must retain per-WAN modes');
assert.deepEqual(exampleSaved.accounts,old.accounts);
const fresh=model.newLine(saved,data,'new');assert.equal('provider' in fresh,false);assert.equal('check_interval' in fresh,false);assert.equal(fresh.enabled,false);
console.log('PASS: shared setting fan-out, local modes/bindings, immutable draft, provider switch and schema2 new line');

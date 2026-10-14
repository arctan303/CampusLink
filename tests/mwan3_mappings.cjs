const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const base='packages/campuslink-mwan3/files/usr/share/campuslink-mwan3/';
const globals={type:v=>v===null || v===undefined?'null':Array.isArray(v)?'array':typeof v==='boolean'?'bool':typeof v==='number'?(Number.isInteger(v)?'int':'double'):typeof v==='string'?'string':'object',length:v=>v==null?0:typeof v==='object'&&!Array.isArray(v)?Object.keys(v).length:v.length,keys:Object.keys,index:(a,v)=>a.indexOf(v),match:(s,r)=>s.match(r),push:(a,v)=>a.push(v),filter:(a,f)=>a.filter(f),max:Math.max,int:v=>Math.trunc(Number(v)),trim:s=>s.trim(),substr:(s,n,l)=>s.substr(n,l),json:JSON.parse,sprintf:(_,v)=>JSON.stringify(v)+'\n',die:m=>{throw new Error(m);},print:()=>{}};
// These modules use the ECMAScript-compatible subset of ucode. The host adapter
// supplies ucode builtins and changes its array-value loop spelling only.
function execute(file,extra,returns){const context={...globals,...extra};const source=fs.readFileSync(base+file,'utf8').replace(/^import .*;\r?\n/gm,'').replace(/export function /g,'function ').replace(/for \(let (\w+) in /g,'for (let $1 of ');return new Function(...Object.keys(context),source+'\nreturn '+returns)(...Object.values(context));}
const rules=execute('mappings.uc',{},'{valid_name,validate_settings,interface_catalog,validate_selection,binding_allowed}');
const {decide}=execute('decision.uc',{},'{decide}');
const row=(source,target,enabled=true)=>({source_interface:source,mwan3_interface:target,enabled});
const settings=(mappings,enabled=true)=>({schema_version:1,generation:0,enabled,mappings});
const values={};for(let i=0;i<6;i++){values['exit_'+i]={'.type':'interface',enabled:'1',family:'ipv4',initial_state:'offline'};values['member_'+i]={'.type':'member',interface:'exit_'+i};}
const catalog=rules.interface_catalog(values),six=rules.validate_settings(settings(catalog.map((t,i)=>row('campus_'+i,t.name))),1);
rules.validate_selection(six,six.mappings.map(m=>m.source_interface),catalog);
assert.equal(six.mappings.length,6);assert.deepEqual(catalog[5].members,['member_5']);
assert.throws(()=>rules.validate_settings(settings([row('a','x'),row('a','y')]),1),/duplicate_source/);
assert.throws(()=>rules.validate_settings(settings([row('a','x'),row('b','x')]),1),/duplicate_mwan3/);
assert.throws(()=>rules.validate_settings(settings([row('a;echo','x')]),1),/invalid_mapping/);
assert.throws(()=>rules.validate_settings(settings([row('a\n','x')]),1),/invalid_mapping/);
assert.throws(()=>rules.validate_settings(settings(Array.from({length:33},(_,i)=>row('a'+i,'b'+i))),1),/invalid_mapping_config/);
for(const [target,code] of [[{...catalog[0],family:'ipv6'},'ipv6'],[{...catalog[0],prepared:false},'tracking_conflict'],[{...catalog[0],tracker_running:true},'tracking_conflict'],[{...catalog[0],enabled:false},'disabled']])assert.throws(()=>rules.validate_selection(settings([row('campus',target.name)]),['campus'],[target]),new RegExp(code));
rules.validate_selection(settings([row('gone','missing',false)]),[],[]);
function harness(persisted){
 const files=new Map(),dirs=new Set(),calls=[],applies=[],uciCalls=[];let clock=1000,failRename=false,handlers;
 const configPath='/test/config.json',runtime='/run/addon';
 if(persisted)files.set(configPath,JSON.stringify(persisted));
 for(const p of ['/lib/mwan3/mwan3.sh','/lib/mwan3/mwan3-skeleton.nft','/etc/hotplug.d/iface/25-mwan3'])files.set(p,'native');
 dirs.add('/var/run/mwan3/iface_state');files.set('/var/run/mwan3/iface_state/edge','offline');
 const net={campus:{up:true,l3_device:'vwan9','ipv4-address':[{address:'10.0.0.2'}]},edge_4:{up:true,l3_device:'vwan9','ipv4-address':[{address:'10.0.0.2'}]}};
 const campus={ok:true,config:{generation:4,connections:[{id:'c',interface:'campus',enabled:true}]},status:[{id:'c',interface:'campus',device:'vwan9',ip:'10.0.0.2',state:'online',reason_code:'already_online',last_check:1000,task_id:''}]};
 const uci={edge:{'.type':'interface',enabled:'1',family:'ipv4',initial_state:'offline'},primary:{'.type':'member',interface:'edge'}};
 const filesystem={mkdir:p=>dirs.add(p),chmod:()=>{},dirname:path.posix.dirname,stat:p=>files.has(p)||dirs.has(p)?{}:null,readfile:p=>files.get(p)??null,unlink:p=>files.delete(p),rename:(a,b)=>{if(failRename&&b===configPath)return false;files.set(b,files.get(a));files.delete(a);return true;},open:p=>({write:s=>{files.set(p,s);return s.length;},flush(){},close(){}}),popen:cmd=>{const args=cmd.split(' ');applies.push(args.slice(1));files.set('/var/run/mwan3/iface_state/'+args[1],args[2]);files.set('/var/run/mwan3track/'+args[1]+'/STATUS',args[2]);return {read:()=>'',close:()=>0};}};
 const bus={call:(object,method,args)=>{calls.push({object,method,args});if(object==='campuslink')return method==='get'?campus:{ok:true};if(object==='uci')return {values:uci};if(object==='service')return {};if(object.startsWith('network.interface.'))return net[object.slice('network.interface.'.length)]||null;return null;},publish:(name,methods)=>{handlers=methods;return {};}};
 const api=execute('controller.uc',{...rules,decide,fs:filesystem,ubus:{connect:()=>bus},uci:{cursor:()=>({get_all:name=>{uciCalls.push(name);return uci;}})},uloop:{init(){},interval(){return {};},run(){}},ARGV:[],getenv:n=>({CAMPUSLINK_MWAN3_CONFIG:configPath,CAMPUSLINK_MWAN3_RUNTIME:runtime})[n],time:()=>clock},'{tick,snapshot}');
 function save(config,expected=api.snapshot().config.generation){let reply;handlers.save.call({args:{config,expected_generation:expected},reply:r=>reply=r});return reply;}
 return {api,files,dirs,calls,applies,net,campus,uci,uciCalls,save,setTime:n=>clock=n,setFailRename:v=>failRename=v};
}
const h=harness();assert.equal(h.api.snapshot().config.enabled,false);assert.equal(h.applies.length,0);
assert.equal(h.save(settings([row('campus','edge')])).ok,true);h.api.tick();
assert.equal(h.applies.at(-1)[0],'edge');assert.equal(h.applies.at(-1)[2],'campus');assert.equal(h.applies.at(-1)[3],'edge_4');assert.equal(h.api.snapshot().status[0].actual,'online');
const coreBefore=JSON.stringify(h.campus.config),uciBefore=JSON.stringify(h.uci);let count=h.applies.length;
assert.equal(h.save(settings([row('campus','edge')])).ok,true);h.api.tick();assert.equal(h.applies.length,count,'saving unchanged active mappings must not interrupt eligible exits');
Object.assign(h.campus.status[0],{state:'backoff',reason_code:'dns_failed',last_check:1010});h.api.tick();assert.equal(h.applies.length,count);assert.equal(h.api.snapshot().status[0].desired,'online');
Object.assign(h.campus.status[0],{state:'action_required',reason_code:'portal_detected',last_check:1020});h.api.tick();assert.equal(h.applies.at(-1)[1],'offline');
count=h.applies.length;h.net.edge_4['ipv4-address'][0].address='10.0.0.9';h.api.tick();assert.equal(h.applies.length,count);assert.equal(h.api.snapshot().status[0].reason,'binding_mismatch');
h.net.edge_4['ipv4-address'][0].address='10.0.0.2';Object.assign(h.campus.status[0],{state:'online',reason_code:'already_online',last_check:1030});h.api.tick();assert.equal(h.applies.at(-1)[1],'online');
h.net.campus.up=false;h.api.tick();assert.equal(h.applies.at(-1)[1],'offline','verified different-name source-down may remove its same-bound target');
count=h.applies.length;assert.equal(h.save(settings([row('campus','edge')],false)).ok,true);h.api.tick();assert.equal(h.applies.length,count,'disabled integration must not mutate native state');
assert.equal(JSON.stringify(h.campus.config),coreBefore);assert.equal(JSON.stringify(h.uci),uciBefore);
const before=JSON.stringify(h.api.snapshot().config);assert.equal(h.save(settings([row('campus','edge')]),-1).reason_code,'config_changed');assert.equal(JSON.stringify(h.api.snapshot().config),before);
h.setFailRename(true);assert.equal(h.save(settings([])).ok,false);assert.equal(JSON.stringify(h.api.snapshot().config),before,'failed atomic file replacement must preserve in-memory configuration');h.setFailRename(false);
assert.equal(h.save(settings([row('missing','edge')])).ok,false);assert.equal(h.save(settings([row('campus','unknown')])).ok,false);
assert.ok(h.uciCalls.length>0 && h.uciCalls.every(name=>name==='mwan3'));
assert.equal(h.calls.some(c=>c.object==='uci'),false,'native config inventory must not depend on rpcd UCI session permissions');
const restored=harness(JSON.parse(h.files.get('/test/config.json')));assert.deepEqual(restored.api.snapshot().config,h.api.snapshot().config,'service restart loads independent persisted mapping settings');
const corrupt=harness({...settings([row('campus','edge')]),generation:1,epochs:{edge:'invalid'}});assert.equal(corrupt.api.snapshot().config_error,true);assert.equal(corrupt.api.snapshot().config.enabled,false);assert.equal(corrupt.applies.length,0,'corrupt activation metadata must not leave a partially loaded active config');
const acl=JSON.parse(fs.readFileSync('packages/luci-app-campuslink/root/usr/share/rpcd/acl.d/luci-app-campuslink.json'))['luci-app-campuslink'];
assert.deepEqual(acl.read.ubus['campuslink.mwan3'],['get']);assert.deepEqual(acl.write.ubus['campuslink.mwan3'],['save']);
console.log('PASS: dynamic six-interface mappings, catalog members, validation, controller/RPC persistence, independent config, same-bound aliases, wrong-binding isolation, unknown retention, physical-down and disabled control');

const assert=require('node:assert/strict'),fs=require('node:fs');
const model=new Function('baseclass',fs.readFileSync('packages/luci-app-campuslink/htdocs/luci-static/resources/campuslink/config.js','utf8'))({extend:x=>x});
const source=fs.readFileSync('packages/luci-app-campuslink/htdocs/luci-static/resources/view/campuslink/main.js','utf8');
const provider=JSON.parse(fs.readFileSync('packages/campuslink/files/usr/share/campuslink/providers/drcom-http.json'));
const school=JSON.parse(fs.readFileSync('packages/campuslink/files/usr/share/campuslink/schools/local-campus.json'));
const clone=model.copy;
class Node {
    constructor(tag,attrs={},children=[]) { this.tag=tag;this.attrs=attrs;Object.assign(this,attrs);if(tag==='input')this.required=attrs.required!=null;this.children=[];this.classList={toggle(){}};this.replace(children); }
    replace(children) { this.children=[children].flat(Infinity).filter(x=>x!=null);this.children.forEach(x=>{if(x instanceof Node)x.parent=this;}); }
    setAttribute(k,v) { this.attrs[k]=v;this[k]=v; }
    all() { return [this,...this.children.flatMap(x=>x instanceof Node ? x.all() : [])]; }
    closest(tag) { for(let n=this;n;n=n.parent)if(n.tag===tag)return n;return null; }
    invalid() { return this.tag==='input' && ((this.required && !this.value) || (this.type==='number' && (Number(this.value)<Number(this.min) || Number(this.value)>Number(this.max)))); }
    checkValidity() { return !this.all().some(x=>x.invalid()); }
    reportValidity() { return this.checkValidity(); }
    querySelectorAll(selector) { return selector===':invalid' ? this.all().filter(x=>x.invalid()) : []; }
    focus() {}
}
function E(tag,attrs,children) { if(attrs instanceof Node || Array.isArray(attrs) || typeof attrs==='string')return new Node(tag,{},attrs);return new Node(tag,attrs,children); }
const flush=()=>new Promise(setImmediate);
function fixture(options={}) {
    let config={schema_version:2,generation:7,settings:{provider:'drcom-http',school:'local-campus',params:{},check_interval:60,retry_interval:30,retry_max:600},accounts:[{id:'a',label:'A',credential_type:'username_password',values:{username:'fake-user'},password_set:true}],connections:[]};
    if(options.connections)config.connections=clone(options.connections);
    let mwan=options.mwan?clone(options.mwan):null,mwanSaves=0,mwanFailure=false,diagnostics=options.diagnostics?clone(options.diagnostics):null,ipQueries=0,ipReply=null;
    let snapshot=()=>({config:clone(config),providers:[provider],schools:[school],interfaces:[{interface:'wan1'}],status:[],events:[],mwan3:mwan?clone(mwan):null,diagnostics:diagnostics?clone(diagnostics):null});
    let delayedGet=null,dialog=null,pollCallback=null,saves=0;
    const rpc={declare(o){return (...args)=>{
        if(o.object==='campuslink.diagnostics'){
            if(o.method==='get')return diagnostics?Promise.resolve(clone(diagnostics)):Promise.reject(new Error('unavailable'));
            ipQueries++;return ipReply || Promise.resolve({ok:false,reason_code:'timeout'});
        }
        if(o.object==='campuslink.mwan3'){
            if(o.method==='get')return mwan?Promise.resolve(clone(mwan)):Promise.reject(new Error('unavailable'));
            mwanSaves++;if(mwanFailure || args[1]!==mwan.config.generation)return Promise.resolve({ok:false,reason_code:'config_changed',message:'联动配置已改变'});
            mwan.config=clone(args[0]);mwan.config.generation++;return Promise.resolve({ok:true,generation:mwan.config.generation});
        }
        if(o.method==='get') { if(delayedGet){const pending=delayedGet;delayedGet=null;return pending;} return Promise.resolve(snapshot()); }
        if(o.method==='save') { saves++;if(args[1]!==config.generation)return Promise.resolve({ok:false,reason_code:'config_changed',message:'配置已改变'});config=clone(args[0]);config.generation++;return Promise.resolve({ok:true}); }
        return Promise.resolve({ok:true});
    };}};
    const ui={showModal(title,children){dialog=new Node('dialog',{},children);},hideModal(){dialog=null;},addNotification(){}};
    const page=new Function('view','rpc','ui','poll','dom','model','E','L',source)({extend:x=>x},rpc,ui,{add(fn){pollCallback=fn;}},{content(n,v){n.replace(v);}},model,E,{resource:x=>x,bind:(fn,ctx,...args)=>fn.bind(ctx,...args)});
    page.render(snapshot());
    function input(label) { const root=dialog || page.panel;const accessible=root.all().find(n=>n.attrs['aria-label']===label);if(accessible)return accessible;const l=root.all().find(n=>n.tag==='label' && n.children.join('')===label);assert.ok(l,'missing label '+label);return root.all().find(n=>n.id===l.attrs.for); }
    function change(label,value) { const n=input(label);n.value=value;(n.attrs.input || n.attrs.change)({target:n}); }
    function toggle(label,value){const n=(dialog || page.panel).all().find(n=>n.tag==='label' && n.children.some(c=>c instanceof Node && c.tag==='span' && c.children.join('')===label)).all().find(n=>n.tag==='input');n.checked=value;n.attrs.change({target:n});}
    function button(text){return (dialog || page.panel).all().find(n=>n.tag==='button' && n.children.join('')===text);}
    function save() { page.editor.save.attrs.click(); }
    return {page,input,change,toggle,button,save,flush,snapshot,get saves(){return saves;},get ipQueries(){return ipQueries;},setDiagnostics(value){diagnostics=clone(value);},delayQuery(){let resolve;ipReply=new Promise(r=>resolve=r);return resolve;},get mwanSaves(){return mwanSaves;},setMwan(value){mwan=clone(value);},failMwan(){mwanFailure=true;},get dialog(){return dialog || page.panel;},delayPoll(){let resolve;const pending=new Promise(r=>resolve=r);delayedGet=pending;const promise=pollCallback();return {resolve,promise};},poll(){return pollCallback();}};
}
async function manualUrls() {
    const f=fixture();f.page.showTab('settings');f.change('认证服务器','');
    f.change('自定义登录地址','https://special.example:8443/login');f.change('自定义状态地址','https://special.example/status');
    f.save();await flush();await flush();assert.equal(f.saves,1,'full URLs without host must reach save');
    assert.equal(f.snapshot().config.settings.params.auth_url,'https://special.example:8443/login');
}
async function defaultSave() {
    const f=fixture();f.page.editLine();f.save();await flush();await flush();
    assert.equal(f.saves,1,'basic defaults must save without filling advanced URLs');
    for(const label of ['登录系统','学校预设','认证服务器','检查间隔（秒）','重试间隔（秒）'])assert.throws(()=>f.input(label));
    const g=fixture();g.page.editAccount('a');g.save();await flush();await flush();
    assert.equal(g.saves,1,'blank password must not become a required input');
}
async function delayedPoll() {
    const f=fixture(),old=f.snapshot(),pending=f.delayPoll();
    f.page.editAccount('a');f.change('账号名称','New label');f.save();f.save();await flush();await flush();
    assert.equal(f.saves,1,'double click saves once');assert.equal(f.page.cfg.generation,8);
    pending.resolve(old);await pending.promise;
    assert.equal(f.page.cfg.generation,8,'late poll must not undo accepted generation');
    assert.equal(f.page.cfg.accounts[0].label,'New label');
}
async function hiddenInvalid() {
    const f=fixture();f.page.showTab('settings');f.change('重试间隔（秒）','1');
    const details=f.dialog.all().find(n=>n.tag==='details');details.open=false;
    f.save();assert.equal(f.saves,0);assert.equal(details.open,true,'invalid advanced field must expand before reporting');
}
async function conflictDraft() {
    const f=fixture();f.page.editAccount('a');f.change('账号名称','Draft');
    // Simulate an external save arriving while this form is open.
    const latest=f.snapshot();latest.config.generation=8;
    const pending=f.delayPoll();pending.resolve(latest);await pending.promise;
    assert.equal(f.input('账号名称').value,'Draft','poll must retain open draft');
    f.page.closeEditor();assert.equal(f.page.cfg.generation,8);
}
async function sharedSettings(){
    const f=fixture();f.page.showTab('settings');f.change('认证服务器','2.2.2.2');f.change('检查间隔（秒）','120');
    f.page.showTab('overview');f.page.showTab('settings');assert.equal(f.input('认证服务器').value,'2.2.2.2','tab switching retains global draft');
    f.page.closeEditor();assert.equal(f.input('认证服务器').value,'1.1.1.1','restore discards draft');
    f.change('认证服务器','2.2.2.2');f.change('检查间隔（秒）','120');f.save();f.save();await flush();await flush();
    assert.equal(f.saves,1);assert.equal(f.snapshot().config.settings.params.auth_server,'2.2.2.2');assert.equal(f.snapshot().config.settings.check_interval,120);
}
async function schoollessSettings(){
    const f=fixture();f.page.showTab('settings');assert.equal(f.input('登录系统').children.find(n=>n.attrs.selected).attrs.value,'drcom-http');
    assert.throws(()=>f.input('学校预设'));assert.equal(f.input('认证服务器').value,'1.1.1.1');
    assert.equal(f.snapshot().config.settings.school,'local-campus','opening draft must not persist migration');
    f.save();await flush();await flush();assert.equal(f.saves,1);
    assert.equal(f.snapshot().config.settings.school,'');assert.equal(f.snapshot().config.settings.params.auth_server,'1.1.1.1');
    f.page.showTab('settings');f.change('认证服务器','');f.save();assert.equal(f.saves,1,'empty host without custom URLs must not save');
}
function mwanSnapshot(){return {ok:true,addon_version:'0.2.0',config:{schema_version:1,generation:2,enabled:false,mappings:[]},interfaces:[{name:'balance_a',family:'ipv4',enabled:true,prepared:true,members:['primary_m1_w1'],actual:'online'}],status:[],backend:{available:true,running:true}};}
async function mwanMappings(){
    const f=fixture({mwan:mwanSnapshot(),connections:[{id:'c',interface:'campus_a'}]});f.page.showTab('mwan3');f.button('新增映射').attrs.click();
    f.change('目标 mwan3 接口 1','balance_a');assert.ok(f.dialog.all().some(n=>n.children.includes('primary_m1_w1')),'target selection must show its associated member');
    f.toggle('参与联动 1',true);f.toggle('启用 mwan3 联动',true);f.page.showTab('overview');f.page.showTab('mwan3');
    assert.equal(f.page.mwan3Session.draft.mappings[0].mwan3_interface,'balance_a','tab switching retains mapping draft');
    f.save();f.save();await flush();await flush();assert.equal(f.mwanSaves,1);assert.equal(f.saves,0,'mapping save must not rewrite authentication config');
    assert.equal(f.snapshot().mwan3.config.mappings[0].source_interface,'campus_a');assert.equal(f.snapshot().mwan3.config.enabled,true);
    const old=f.snapshot();old.mwan3.config.generation=2;f.page.acceptSnapshot(old);assert.equal(f.page.data.mwan3.config.generation,3,'stale addon poll cannot undo successful save');
    f.change('目标 mwan3 接口 1','');const live=f.snapshot().mwan3;live.status=[{source_interface:'campus_a',mwan3_interface:'balance_a',actual:'offline',reason:'authentication_required'}];f.setMwan(live);await f.poll();
    assert.equal(f.page.mwan3Session.draft.mappings[0].mwan3_interface,'','status poll retains unsaved input');
    f.page.closeEditor();assert.equal(f.page.mwan3Session.draft.mappings[0].mwan3_interface,'balance_a','restore returns to persisted mapping');
    assert.ok(f.dialog.all().some(n=>n.children.includes('暂停分流')),'runtime status must refresh independently of switches');
    const lost=f.snapshot();lost.mwan3=null;f.page.acceptSnapshot(lost);const stale=f.snapshot();stale.mwan3.config.generation=2;f.page.acceptSnapshot(stale);assert.equal(f.page.data.mwan3,null,'an unavailable addon must not erase the accepted revision floor');f.page.acceptSnapshot(f.snapshot());
    f.failMwan();f.save();await flush();await flush();assert.ok(f.page.editor.error.textContent.includes('已改变'));assert.equal(f.page.mwan3Session.draft.mappings.length,1,'conflict retains draft');
}
async function mwanUnavailable(){const f=fixture();f.page.showTab('mwan3');assert.ok(f.dialog.children.some(n=>n.children && n.children.some(t=>typeof t==='string'&&t.includes('无法连接'))));f.page.showTab('settings');assert.equal(f.input('认证服务器').value,'1.1.1.1');await f.page.load();}
async function publicIP(){
    const connection={id:'c',interface:'wan1',account:'a',enabled:true,auto_login:true};
    const diag={ok:true,instance:'boot-a',revision:0,entries:[{id:'c',interface:'wan1',public_ipv4:null,error:'not_queried',retry_after_s:0}]};
    const f=fixture({connections:[connection],diagnostics:diag}),resolve=f.delayQuery();
    const pending=f.page.queryPublicIP(connection);f.page.queryPublicIP(connection);assert.equal(f.ipQueries,1,'in-flight query deduplicated');assert.equal(f.button('查询中…').disabled,true);
    f.page.showTab('settings');f.change('认证服务器','draft.example');
    const done=clone(diag);done.revision=2;done.entries[0]={id:'c',interface:'wan1',public_ipv4:'8.8.8.8',checked_at:1000,error:'',retry_after_s:60};f.setDiagnostics(done);resolve({ok:true,query_ok:true});await pending;
    assert.equal(f.input('认证服务器').value,'draft.example','query completion preserves an open settings draft');assert.equal(f.saves,0);assert.equal(f.mwanSaves,0);
    f.page.showTab('overview');assert.ok(f.dialog.all().some(n=>n.children.includes('8.8.8.8')));assert.equal(f.button('刷新出口 IP').disabled,true,'backend cooldown disables refresh');
    const old=f.snapshot();old.diagnostics=clone(diag);f.page.acceptSnapshot(old);assert.equal(f.page.data.diagnostics.revision,2,'late local poll cannot erase completed query');
    const lost=f.snapshot();lost.diagnostics=null;f.page.acceptSnapshot(lost);const staleAgain=f.snapshot();staleAgain.diagnostics=clone(diag);f.page.acceptSnapshot(staleAgain);assert.equal(f.page.data.diagnostics,null,'outage retains revision floor');
    const reboot=f.snapshot();reboot.diagnostics={...diag,instance:'boot-b'};f.page.acceptSnapshot(reboot);assert.equal(f.page.data.diagnostics.instance,'boot-b','reboot accepts a new runtime');
    const failed=fixture({connections:[connection],diagnostics:done});await failed.page.queryPublicIP(connection);assert.ok(failed.dialog.all().some(n=>n.children.includes('8.8.8.8')));assert.equal(failed.saves,0,'query failure leaves authentication configuration untouched');
    const absent=fixture({connections:[connection]});assert.equal(absent.button('查询出口 IP').disabled,true,'missing component does not break overview');
}
(async()=>{let failed=false;for(const test of [defaultSave,manualUrls,delayedPoll,hiddenInvalid,conflictDraft,sharedSettings,schoollessSettings,mwanMappings,mwanUnavailable,publicIP]){try{await test();console.log('PASS:',test.name);}catch(e){failed=true;console.error('FAIL:',test.name,e.stack);}}if(failed)process.exitCode=1;})();

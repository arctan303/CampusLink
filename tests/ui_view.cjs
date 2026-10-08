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
function fixture() {
    let config={schema_version:2,generation:7,settings:{provider:'drcom-http',school:'local-campus',params:{},check_interval:60,retry_interval:30,retry_max:600},accounts:[{id:'a',label:'A',credential_type:'username_password',values:{username:'fake-user'},password_set:true}],connections:[]};
    let snapshot=()=>({config:clone(config),providers:[provider],schools:[school],interfaces:[{interface:'wan1'}],status:[],events:[]});
    let delayedGet=null,dialog=null,pollCallback=null,saves=0;
    const rpc={declare(o){return (...args)=>{
        if(o.method==='get') { if(delayedGet){const pending=delayedGet;delayedGet=null;return pending;} return Promise.resolve(snapshot()); }
        if(o.method==='save') { saves++;if(args[1]!==config.generation)return Promise.resolve({ok:false,reason_code:'config_changed',message:'配置已改变'});config=clone(args[0]);config.generation++;return Promise.resolve({ok:true}); }
        return Promise.resolve({ok:true});
    };}};
    const ui={showModal(title,children){dialog=new Node('dialog',{},children);},hideModal(){dialog=null;},addNotification(){}};
    const page=new Function('view','rpc','ui','poll','dom','model','E','L',source)({extend:x=>x},rpc,ui,{add(fn){pollCallback=fn;}},{content(n,v){n.replace(v);}},model,E,{resource:x=>x,bind:(fn,ctx,...args)=>fn.bind(ctx,...args)});
    page.render(snapshot());
    function input(label) { const root=dialog || page.panel;const l=root.all().find(n=>n.tag==='label' && n.children.join('')===label);assert.ok(l,'missing label '+label);return root.all().find(n=>n.id===l.attrs.for); }
    function change(label,value) { const n=input(label);n.value=value;(n.attrs.input || n.attrs.change)({target:n}); }
    function save() { page.editor.save.attrs.click(); }
    return {page,input,change,save,flush,snapshot,get saves(){return saves;},get dialog(){return dialog || page.panel;},delayPoll(){let resolve;const pending=new Promise(r=>resolve=r);delayedGet=pending;const promise=pollCallback();return {resolve,promise};},poll(){return pollCallback();}};
}
async function manualUrls() {
    const f=fixture();f.page.showTab('settings');f.change('学校预设','');
    f.change('自定义登录地址','https://special.example:8443/login');f.change('自定义状态地址','https://special.example/status');
    f.save();await flush();await flush();assert.equal(f.saves,1,'full URLs without host must reach save');
    assert.equal(f.snapshot().config.settings.params.auth_url,'https://special.example:8443/login');
}
async function defaultSave() {
    const f=fixture();f.page.editLine();f.save();await flush();await flush();
    assert.equal(f.saves,1,'basic defaults must save without filling advanced URLs');
    for(const label of ['认证系统','学校预设','认证服务器','检查间隔（秒）','重试间隔（秒）'])assert.throws(()=>f.input(label));
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
(async()=>{let failed=false;for(const test of [defaultSave,manualUrls,delayedPoll,hiddenInvalid,conflictDraft,sharedSettings]){try{await test();console.log('PASS:',test.name);}catch(e){failed=true;console.error('FAIL:',test.name,e.message);}}if(failed)process.exitCode=1;})();

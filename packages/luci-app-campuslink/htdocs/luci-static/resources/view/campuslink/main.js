'use strict';
'require view';
'require rpc';
'require ui';
'require poll';
'require dom';
'require campuslink.config as model';

var getState = rpc.declare({object:'campuslink',method:'get',expect:{'':{}},reject:true});
var saveConfig = rpc.declare({object:'campuslink',method:'save',params:['config','expected_generation'],expect:{'':{}},reject:true});
var action = rpc.declare({object:'campuslink',method:'action',params:['id','operation'],expect:{'':{}},reject:true});
var getMwan3 = rpc.declare({object:'campuslink.mwan3',method:'get',expect:{'':{}},reject:true});
var saveMwan3 = rpc.declare({object:'campuslink.mwan3',method:'save',params:['config','expected_generation'],expect:{'':{}},reject:true});
var getDiagnostics = rpc.declare({object:'campuslink.diagnostics',method:'get',expect:{'':{}},reject:true});
var queryIP = rpc.declare({object:'campuslink.diagnostics',method:'query',params:['id'],expect:{'':{}},reject:true});
function getSnapshot() {
    return Promise.all([getState(),getMwan3().catch(function(){return null;}),getDiagnostics().catch(function(){return null;})]).then(function(values){
        return Object.assign({},values[0],{mwan3:values[1] && values[1].ok && values[1].addon_version ? values[1] : null,diagnostics:values[2] && values[2].ok && Array.isArray(values[2].entries) ? values[2] : null});
    });
}
var labels = {disabled:'已停用',waiting_interface:'等待接口',checking:'检查中',online:'已联网',authenticating:'登录中',verifying:'复查中',logging_out:'退出中',backoff:'等待重试',action_required:'需要处理',invalid_config:'配置错误'};
var tabs = [['overview','总览'],['connections','登录配置'],['accounts','账号'],['settings','插件设置'],['mwan3','mwan3 联动'],['logs','日志']];
var fieldNames = {auth_server:'认证服务器',auth_url:'登录地址',status_url:'状态地址',logout_url:'退出地址',probe_url:'探测地址',username:'校园网账号',password:'密码'};

return view.extend({
    handleSaveApply:null, handleSave:null, handleReset:null,
    load:function() { return getSnapshot(); },
    render:function(data) {
        this.data = data; this.cfg = model.copy(data.config); this.activeTab = 'overview'; this.editor = null; this.settingsSession = null; this.mwan3Session=null; this.mwan3Generation=data.mwan3?data.mwan3.config.generation:0; this.saving = false; this.sequence = 0;
        this.ipPending={};this.diagnosticsInstance=data.diagnostics?data.diagnostics.instance:null;this.diagnosticsRevision=data.diagnostics?data.diagnostics.revision:0;
        this.panel = E('div',{id:'cl-panel',role:'tabpanel'});
        var self = this;
        this.tabButtons = tabs.map(function(t,i) {
            return E('button',{type:'button',role:'tab',class:'cl-tab','aria-controls':'cl-panel',click:function() { self.showTab(t[0]); },keydown:function(ev) {
                var next = ev.key === 'ArrowRight' ? (i+1)%tabs.length : ev.key === 'ArrowLeft' ? (i+tabs.length-1)%tabs.length : ev.key === 'Home' ? 0 : ev.key === 'End' ? tabs.length-1 : -1;
                if (next >= 0) { ev.preventDefault(); self.showTab(tabs[next][0]); self.tabButtons[next].focus(); }
            }},t[1]);
        });
        var root = E('div',{class:'campuslink'},[E('link',{rel:'stylesheet',href:L.resource('campuslink/style.css')}),E('h2',{},'CampusLink'),E('div',{class:'cl-tabs',role:'tablist','aria-label':'CampusLink 页面'},this.tabButtons),this.panel]);
        this.showTab('overview');
        poll.add(L.bind(function() { return getSnapshot().then(L.bind(function(next) {
            var previous = this.data.config.generation;
            if (!this.acceptSnapshot(next)) return;
            if(this.editor && this.editor.kind==='mwan3' && this.mwanStatusRefresh)this.mwanStatusRefresh();
            if (!this.editor && (this.activeTab === 'overview' || this.activeTab === 'logs' || previous !== next.config.generation)) this.drawPanel();
        },this)); },this),3);
        return root;
    },
    acceptSnapshot:function(next) {
        if (this.data && next.config.generation < this.data.config.generation) return false;
        if(next.mwan3 && next.mwan3.config.generation<this.mwan3Generation)next.mwan3=this.data.mwan3 || null;
        if(next.mwan3)this.mwan3Generation=next.mwan3.config.generation;
        if(next.diagnostics){
            if(next.diagnostics.instance===this.diagnosticsInstance && next.diagnostics.revision<this.diagnosticsRevision)next.diagnostics=this.data.diagnostics || null;
            if(next.diagnostics){this.diagnosticsInstance=next.diagnostics.instance;this.diagnosticsRevision=next.diagnostics.revision;}
        }
        this.data = next;
        if (!this.editor && !this.saving) this.cfg = model.copy(next.config);
        return true;
    },
    button:function(text,fn,positive) { return E('button',{type:'button',class:'btn cbi-button '+(positive ? 'cbi-button-positive' : ''),click:fn},text); },
    showTab:function(id) {
        if(this.editor && this.editor.inline){if(this.saving)return;this.editor=null;this.cfg=model.copy(this.data.config);}
        this.activeTab = id;
        this.tabButtons.forEach(function(button,i) { var active = tabs[i][0] === id; button.classList.toggle('active',active); button.setAttribute('aria-selected',String(active)); button.tabIndex = active ? 0 : -1; });
        this.drawPanel();
    },
    provider:function(c) { var id=this.cfg.settings ? this.cfg.settings.provider : c.provider;return this.data.providers.find(function(p) { return p.id === id; }); },
    accountLabel:function(id) { var a = this.cfg.accounts.find(function(x) { return x.id === id; }); return a ? a.label || a.values.username : '未配置'; },
    modeLabel:function(c) { var p = model.params(c,this.data,this.cfg); return this.provider(c).id === 'drcom-http' ? p.terminal_mode === 'mobile' ? '手机' : '电脑' : this.provider(c).label; },
    table:function(headers,rows,empty) {
        return E('div',{class:'cl-table-wrap'},E('table',{class:'table cbi-section-table'},[E('thead',{},E('tr',{},headers.map(function(h) { return E('th',{},h); }))),E('tbody',{},rows.length ? rows : [E('tr',{},E('td',{colspan:headers.length,class:'cl-empty'},empty))])]));
    },
    row:function(values) { return E('tr',{},values.map(function(v) { return E('td',{},v); })); },
    ipError:function(code) { return {not_queried:'未查询',interface_unavailable:'接口尚未就绪',querying:'正在查询',invalid_response:'查询服务响应无效',timeout:'查询超时',dns_failed:'查询服务域名解析失败',connect_failed:'无法连接查询服务',binding_unavailable:'无法绑定当前 WAN',binding_changed:'接口或配置已变化，请重新查询',busy:'其他线路正在查询，请稍后重试',source_unavailable:'无法读取线路',diagnostics_failed:'查询组件暂不可用'}[code] || '查询失败'; },
    ipCell:function(c) {
        var self=this,diag=this.data.diagnostics,entry=diag && diag.entries.find(function(x){return x.id===c.id;}),ip=entry && entry.public_ipv4;
        var pending=!!this.ipPending[c.interface],hint=!diag?'查询组件不可用':entry && entry.error?this.ipError(entry.error):ip?'':'未查询';
        if(ip)hint=(entry.stale || entry.error?'上次查询 ':'查询于 ')+new Date(entry.checked_at*1000).toLocaleTimeString()+(entry.stale?'（已过期）':'')+(entry.error?' · '+this.ipError(entry.error):'');
        var button=this.button(pending?'查询中…':ip?'刷新出口 IP':'查询出口 IP',function(){return self.queryPublicIP(c);});
        button.disabled=pending || !diag || !!(entry && entry.retry_after_s>0);
        if(entry && entry.retry_after_s>0)button.title=entry.retry_after_s+' 秒后可刷新';
        return E('div',{},[E('span',{},ip || '—'),E('div',{class:'cl-secondary'},hint),button]);
    },
    queryPublicIP:function(c) {
        if(this.editor || this.saving || this.ipPending[c.interface])return Promise.resolve();
        var self=this;this.ipPending[c.interface]=true;this.drawPanel();
        return queryIP(c.id).then(function(reply){
            if(!reply.ok || reply.query_ok===false)ui.addNotification(null,E('p',{},self.ipError(reply.reason_code)),'error');
            return getSnapshot().then(function(next){self.acceptSnapshot(next);});
        }).catch(function(){ui.addNotification(null,E('p',{},'出口 IP 查询失败，请稍后重试'),'error');}).finally(function(){
            delete self.ipPending[c.interface];if(!self.editor && self.activeTab==='overview')self.drawPanel();
        });
    },
    drawPanel:function() {
        var self = this,cfg = this.cfg,content;
        if (this.activeTab === 'overview') {
            var rows = cfg.connections.map(function(c) {
                var s = self.data.status.find(function(x) { return x.id === c.id; }) || {state:'disabled'};
                var status = [E('span',{class:'cl-status cl-'+s.state},labels[s.state] || s.state)];
                if (['backoff','action_required','waiting_interface','invalid_config'].indexOf(s.state) >= 0 && s.message) status.push(E('div',{class:'cl-error-reason'},s.message));
                var controls = [self.button('检查',function() { return self.runAction(c.id,'check'); }),self.button('编辑',function() { self.editLine(c.id); })];
                if (c.enabled && s.state !== 'online') controls.splice(1,0,self.button('登录',function() { return self.runAction(c.id,'login'); },true));
                if (self.provider(c).capabilities.logout && s.state === 'online') controls.push(self.button('退出',function() { return self.runAction(c.id,'logout'); }));
                return self.row([E('div',{},[E('strong',{},c.label || c.interface),E('div',{class:'cl-secondary'},c.interface+(s.ip ? ' · 接口 IP '+s.ip : ''))]),self.accountLabel(c.account),self.modeLabel(c),E('div',{},status),self.ipCell(c),c.auto_login ? '开启' : '关闭',E('div',{class:'cl-actions'},controls)]);
            });
            content = [this.table(['WAN','账号','方式','状态','公网 IPv4','自动登录','操作'],rows,'暂无登录配置'),E('p',{class:'cl-secondary'},'公网 IP 为手动直连查询结果；代理或游戏加速器可能使用其他出口。'),this.button('新增登录配置',function() { self.editLine(); },true)];
        } else if (this.activeTab === 'connections') {
            content = [E('div',{class:'cl-toolbar'},this.button('新增登录配置',function() { self.editLine(); },true)),this.table(['WAN','账号','终端方式','状态','操作'],cfg.connections.map(function(c) {
                return self.row([c.label || c.interface,self.accountLabel(c.account),self.modeLabel(c),c.enabled ? '启用' : '停用',E('div',{class:'cl-actions'},[self.button('编辑',function() { self.editLine(c.id); }),self.button(c.enabled ? '停用' : '启用',function() { return self.runAction(c.id,c.enabled ? 'disable' : 'enable'); }),self.button('删除',function() { self.deleteItem('connection',c.id); })])]);
            }),'暂无登录配置')];
        } else if (this.activeTab === 'accounts') {
            content = [E('div',{class:'cl-toolbar'},this.button('新增账号',function() { self.editAccount(); },true)),this.table(['名称','校园网账号','使用线路','操作'],cfg.accounts.map(function(a) {
                var refs = cfg.connections.filter(function(c) { return c.account === a.id; }).map(function(c) { return c.label || c.interface; });
                return self.row([a.label || a.values.username,a.values.username,refs.join('、') || '未使用',E('div',{class:'cl-actions'},[self.button('编辑',function() { self.editAccount(a.id); }),self.button('删除',function() { self.deleteItem('account',a.id); })])]);
            }),'暂无账号')];
        } else if(this.activeTab === 'settings') {
            this.editSettings();return;
        } else if(this.activeTab === 'mwan3') {
            this.editMwan3();return;
        } else {
            content = [this.table(['时间','线路','事件'],(this.data.events || []).slice(-50).reverse().map(function(e) { var c = cfg.connections.find(function(x) { return x.id === e.id; }); return self.row([new Date(e.time*1000).toLocaleTimeString(),c ? c.label || c.interface : '系统',e.message]); }),'暂无日志')];
        }
        dom.content(this.panel,content);
    },
    errorText:function(reply) {
        var message = reply.message || reply.reason_code || '操作失败',match = message.match(/(?:missing_field|invalid_field|invalid_url):([a-z_]+)/);
        var mappingErrors={duplicate_source_interface:'来源接口重复',duplicate_mwan3_interface:'目标 mwan3 接口重复',source_interface_missing:'来源接口已不存在',mwan3_interface_missing:'目标 mwan3 接口已不存在',mwan3_interface_disabled:'目标 mwan3 接口未启用',ipv6_unsupported:'当前仅支持 IPv4',tracking_conflict:'请在 mwan3 关闭目标独立探测，并设初始状态为离线',backend_unavailable:'CampusLink 或 mwan3 联动依赖不可用'};
        var code=message.split(':')[0];if(mappingErrors[code])return mappingErrors[code]+(message.indexOf(':')>=0?'（'+message.slice(code.length+1)+'）':'');
        return match ? '请检查'+(fieldNames[match[1]] || match[1]) : message;
    },
    runAction:function(id,operation) {
        if (this.editor || this.saving) return Promise.resolve();
        return action(id,operation).then(L.bind(function(reply) {
            if (!reply.ok) ui.addNotification(null,E('p',{},this.errorText(reply)),'error');
            return getSnapshot().then(L.bind(function(next) { if (this.acceptSnapshot(next) && !this.editor) this.drawPanel(); },this));
        },this)).catch(function(e) { ui.addNotification(null,E('p',{},e.message),'error'); });
    },
    input:function(value,change,options) {
        options = options || {};
        var attributes = Object.assign({class:'cbi-input-text',type:'text',value:value == null ? '' : String(value),input:function(ev) { change(options.type === 'number' ? Number(ev.target.value) : ev.target.value); }},options);
        // LuCI E serializes attributes: required="false" is still required in HTML.
        Object.keys(attributes).forEach(function(key) { if (attributes[key] === false || attributes[key] == null) delete attributes[key]; });
        return E('input',attributes);
    },
    select:function(value,choices,change) { return E('select',{class:'cbi-input-select',change:function(ev) { change(ev.target.value); }},choices.map(function(c) { return E('option',{value:c.value,selected:c.value === value ? true : null},c.label); })); },
    checkbox:function(label,value,change) { return E('label',{class:'cl-check'},[E('input',{type:'checkbox',checked:value ? true : null,change:function(ev) { change(ev.target.checked); }}),E('span',{},label)]); },
    field:function(label,control,hint) {
        var id = 'cl-field-'+(++this.sequence); control.id = id;
        return E('div',{class:'cbi-value'},[E('label',{class:'cbi-value-title',for:id},label),E('div',{class:'cbi-value-field'},[control,hint ? E('div',{class:'cbi-value-description'},hint) : ''])]);
    },
    newAccount:function() { return {id:'account-'+Date.now()+'-'+(++this.sequence),label:'',credential_type:'username_password',values:{username:'',password:''}}; },
    accountFields:function(draft,existing) {
        return [this.field('校园网账号',this.input(draft.values.username,function(v) { draft.values.username = v; },{required:true,autocomplete:'off'})),this.field('密码',this.input(draft.values.password,function(v) { draft.values.password = v; },{type:'password',required:!existing,autocomplete:'new-password',placeholder:existing ? '留空保留原密码' : ''})),this.field('账号名称',this.input(draft.label,function(v) { draft.label = v; },{placeholder:'可选'}))];
    },
    closeEditor:function() { if (this.saving) return; if(this.editor && this.editor.inline){if(this.editor.kind==='mwan3')this.mwan3Session=null;else this.settingsSession=null;}else ui.hideModal(); this.editor = null; this.cfg = model.copy(this.data.config); this.drawPanel(); },
    openEditor:function(title,form,candidate,actionLabel,inline,kind) {
        var self = this,error = E('p',{class:'cl-form-error',role:'alert',hidden:true});
        this.editor = {form:form,error:error,inline:!!inline,kind:kind || 'campuslink'};
        var save = this.button(actionLabel || '保存',function() {
            if (self.saving) return;
            if (!form.checkValidity()) {
                form.querySelectorAll(':invalid').forEach(function(control) { var details = control.closest('details'); if (details) details.open = true; });
                form.reportValidity(); return;
            }
            try { self.submit(candidate()); } catch (e) { error.textContent = e.message; error.hidden = false; }
        },true);
        this.editor.save = save;
        var content=[form,error,E('div',{class:'right cl-modal-actions'},[this.button(inline ? '恢复已保存' : '取消',function() { self.closeEditor(); }),save])];
        if(inline)dom.content(this.panel,content);else ui.showModal(title,content);
    },
    submit:function(candidate) {
        var self = this,editor = this.editor;
        this.saving = true; editor.save.disabled = true; editor.error.hidden = true;
        var sender=editor.kind==='mwan3'?saveMwan3:saveConfig;
        return sender(candidate,candidate.generation).then(function(reply) {
            if (!reply.ok) throw new Error(self.errorText(reply));
            if(editor.kind==='mwan3'){self.mwan3Generation=reply.generation;self.data.mwan3=Object.assign({},self.data.mwan3,{config:Object.assign({},candidate,{generation:reply.generation})});}
            return getSnapshot().then(function(next) {
                self.acceptSnapshot(next); self.cfg = model.copy(self.data.config); self.editor = null; if(editor.inline){if(editor.kind==='mwan3')self.mwan3Session=null;else self.settingsSession=null;}else ui.hideModal(); self.drawPanel();
                ui.addNotification(null,E('p',{},'已保存'),'info');
            });
        }).catch(function(e) { editor.error.textContent = e.message; editor.error.hidden = false; }).finally(function() { self.saving = false; editor.save.disabled = false; });
    },
    editAccount:function(id) {
        var original = this.cfg.accounts.find(function(a) { return a.id === id; }),draft = original ? model.accountDraft(original) : this.newAccount(),base = model.copy(this.cfg),self = this;
        var form = E('form',{class:'cl-editor',submit:function(ev) { ev.preventDefault(); }},this.accountFields(draft,!!original));
        this.openEditor(original ? '编辑账号' : '新增账号',form,function() { return model.saveAccount(base,draft); });
    },
    editLine:function(id) {
        if(!this.cfg.settings){this.showTab('settings');ui.addNotification(null,E('p',{},'请先在插件设置选择统一的认证配置'),'info');return;}
        var original = this.cfg.connections.find(function(c) { return c.id === id; }),base = model.copy(this.cfg),self = this;
        var draft = original ? model.copy(original) : model.newLine(base,this.data,'line-'+Date.now()+'-'+(++this.sequence));
        var inline = this.newAccount(),advancedOpen = false,form = E('form',{class:'cl-editor',submit:function(ev) { ev.preventDefault(); }});
        function draw() {
            var p = self.provider(draft),values = model.params(draft,self.data,base),fields = [];
            var interfaces = self.data.interfaces.map(function(x) { return {value:x.interface,label:x.interface}; });
            if (!interfaces.some(function(x) { return x.value === draft.interface; })) interfaces.push({value:draft.interface,label:draft.interface});
            fields.push(self.field('WAN 接口',self.select(draft.interface,interfaces,function(v) { draft.interface = v; })));
            fields.push(self.field('账号',self.select(draft.account,base.accounts.map(function(a) { return {value:a.id,label:a.label || a.values.username}; }).concat([{value:'__new__',label:'＋ 新增账号'}]),function(v) { draft.account = v; draw(); })));
            if (draft.account === '__new__') fields.push(E('div',{class:'cl-inline-account'},self.accountFields(inline,false)));
            function visible(f) { return !f.capability || p.capabilities[f.capability]; }
            function providerField(f) {
                var override = Object.prototype.hasOwnProperty.call(draft.params,f.id),value = f.advanced ? override ? draft.params[f.id] : '' : values[f.id];
                function change(v) { if (f.advanced && v === '') delete draft.params[f.id]; else draft.params[f.id] = v; }
                var control = f.type === 'enum' ? self.select(value,f.choices,change) : f.type === 'boolean' ? self.checkbox(f.label,value,change) : self.input(value,change,{type:f.type === 'integer' ? 'number' : 'text',required:!f.advanced && f.required,placeholder:f.advanced ? values[f.id] || '' : '',min:f.min,max:f.max,autocomplete:'off'});
                return self.field(f.label,control);
            }
            p.connection_fields.filter(function(f) { return f.scope==='connection' && !f.advanced && visible(f); }).forEach(function(f) { fields.push(providerField(f)); });
            fields.push(self.field('线路开关',E('div',{class:'cl-switches'},[self.checkbox('启用线路',draft.enabled,function(v) { draft.enabled = v; }),self.checkbox('自动登录',draft.auto_login,function(v) { draft.auto_login = v; })])));
            var advanced = [self.field('线路名称',self.input(draft.label,function(v) { draft.label = v; },{placeholder:'自动生成'}))];
            p.connection_fields.filter(function(f) { return f.scope==='connection' && f.advanced && visible(f); }).forEach(function(f) { advanced.push(providerField(f)); if (draft.params[f.id] != null) advancedOpen = true; });
            fields.push(E('details',{class:'cl-advanced',open:advancedOpen ? true : null,toggle:function(ev) { advancedOpen = ev.target.open; }},[E('summary',{},'高级设置')].concat(advanced)));
            dom.content(form,fields);
        }
        draw();
        this.openEditor(original ? '编辑登录配置' : '新增登录配置',form,function() { return model.saveLine(base,draft,inline); });
    },
    editSettings:function() {
        var self=this;
        if(!this.settingsSession)this.settingsSession={base:model.copy(this.cfg),draft:model.settingsDraft(this.cfg,this.data),advancedOpen:false};
        var session=this.settingsSession,draft=session.draft,form=E('form',{class:'cl-editor',submit:function(ev){ev.preventDefault();}});
        function draw(){
            var p=self.data.providers.find(function(x){return x.id===draft.provider;}),values=model.params(draft,self.data),fields=[],urlInputs={},serverInput;
            if(session.base.schema_version===1 && session.base.connections.length)fields.push(E('p',{},'旧线路的公共配置不同，请选择统一配置后保存。'));
            fields.push(self.field('登录系统',self.select(draft.provider,self.data.providers.map(function(x){return {value:x.id,label:x.label};}),function(v){draft.provider=v;draft.params={};draft.school='';session.advancedOpen=false;draw();})));
            function visible(f){return f.scope!=='connection' && (!f.capability || p.capabilities[f.capability]);}
            function updateRequired(){var effective=model.params(draft,self.data);if(serverInput)serverInput.required=!(effective.auth_url && effective.status_url);}
            function refreshEndpoints(){var effective=model.params(draft,self.data),urls=model.endpoints(effective.auth_server || '');Object.keys(urlInputs).forEach(function(key){urlInputs[key].placeholder=effective[key] || urls[key] || '' ;});}
            function providerField(f){
                var value=f.advanced ? draft.params[f.id] == null ? '' : draft.params[f.id] : values[f.id];
                function change(v){if(f.advanced && v==='')delete draft.params[f.id];else draft.params[f.id]=v;updateRequired();refreshEndpoints();}
                var control=f.type==='enum'?self.select(value,f.choices,change):f.type==='boolean'?self.checkbox(f.label,value,change):self.input(value,change,{type:f.type==='integer'?'number':'text',required:!f.advanced && f.required,placeholder:f.advanced?values[f.id] || '':'',min:f.min,max:f.max,autocomplete:'off'});
                if(f.id==='auth_server'){serverInput=control;control.setAttribute('pattern','[a-zA-Z0-9][a-zA-Z0-9.\\-]*');updateRequired();}
                if(f.advanced)urlInputs[f.id]=control;
                return self.field(f.label,control);
            }
            p.connection_fields.filter(function(f){return visible(f) && !f.advanced;}).forEach(function(f){fields.push(providerField(f));});
            fields.push(self.field('检查间隔（秒）',self.input(draft.check_interval,function(v){draft.check_interval=v;},{type:'number',min:10,max:3600,required:true})));
            var advanced=[];
            p.connection_fields.filter(function(f){return visible(f) && f.advanced;}).forEach(function(f){advanced.push(providerField(f));if(draft.params[f.id]!=null || (['auth_url','status_url'].indexOf(f.id)>=0 && values[f.id]))session.advancedOpen=true;});
            advanced.push(self.field('重试间隔（秒）',self.input(draft.retry_interval,function(v){draft.retry_interval=v;},{type:'number',min:10,max:600,required:true})));
            advanced.push(self.field('最大重试间隔（秒）',self.input(draft.retry_max,function(v){draft.retry_max=v;},{type:'number',min:60,max:3600,required:true})));
            advanced.push(self.button('恢复默认参数',function(){draft.params={};session.advancedOpen=false;draw();}));
            fields.push(E('details',{class:'cl-advanced',open:session.advancedOpen?true:null,toggle:function(ev){session.advancedOpen=ev.target.open;}},[E('summary',{},'高级设置')].concat(advanced)));
            refreshEndpoints();dom.content(form,fields);
        }
        draw();this.openEditor('插件设置',form,function(){return model.saveSettings(session.base,draft,self.data);},'保存到所有 WAN',true);
    },
    mwanState:function(row) {
        var current=this.data.mwan3,interfaces=current?current.interfaces:[],target=interfaces.find(function(t){return t.name===row.mwan3_interface;});
        var runtime=current && current.status.find(function(s){return s.source_interface===row.source_interface && s.mwan3_interface===row.mwan3_interface;});
        var reasons={binding_mismatch:'两端出口不一致或尚未就绪',tracking_conflict:'原生探测冲突',source_removed:'来源接口已删除',target_unavailable:'目标不可用',backend_unavailable:'依赖不可用',source_unknown:'等待 CampusLink',retain_last_decision:'保留上次判定',status_binding_mismatch:'等待当前出口检查',authentication_pending:'等待认证复查',authentication_required:'需要认证',online_verified:'联网已确认',interface_unavailable:'等待接口',default_route_unavailable:'缺少默认路由',apply_deferred:'状态应用待重试'};
        var actual=runtime?runtime.actual:target && target.actual,status=actual==='online'?'参与分流':actual==='offline'?'暂停分流':'状态未知';
        var saved=current && current.config.mappings.find(function(m){return m.source_interface===row.source_interface && m.mwan3_interface===row.mwan3_interface;});
        var details=runtime?reasons[runtime.reason] || runtime.reason:saved && (!current.config.enabled || !saved.enabled)?'未参与联动':'未保存或等待检查';
        if(target && (!target.prepared || target.tracker_running))details='需关闭目标独立探测，并设初始状态为离线';
        return [status,E('div',{class:'cl-secondary'},details)];
    },
    editMwan3:function() {
        var self=this,snapshot=this.data.mwan3;
        if(!snapshot && !this.mwan3Session){dom.content(this.panel,E('p',{},'无法连接 mwan3 联动组件。请安装或启动支持配置的 campuslink-mwan3；校园网登录功能可继续使用。'));return;}
        if(!this.mwan3Session)this.mwan3Session={draft:model.mwanDraft(snapshot)};
        var draft=this.mwan3Session.draft,form=E('form',{class:'cl-editor',submit:function(ev){ev.preventDefault();}});
        function choices(items,value){var list=[{value:'',label:'请选择'}].concat(items);if(value && !list.some(function(x){return x.value===value;}))list.push({value:value,label:value+'（已不存在）'});return list;}
        function draw(){
            var current=self.data.mwan3,interfaces=current?current.interfaces:[],sourceNames=[];
            var stateNodes=[];
            self.data.config.connections.forEach(function(c){if(sourceNames.indexOf(c.interface)<0)sourceNames.push(c.interface);});
            var fields=[self.checkbox('启用 mwan3 联动',draft.enabled,function(v){draft.enabled=v;})];
            if(!current || !current.backend.available)fields.push(E('p',{class:'cl-form-error'},'mwan3-nft 联动依赖不可用，启用前请检查组件。'));
            else if(!current.backend.running)fields.push(E('p',{class:'cl-secondary'},'mwan3 当前未运行，映射保存后等待它启动。'));
            if(current && current.config_error)fields.push(E('p',{class:'cl-form-error'},'联动配置文件无效，当前未接管接口；请重新配置并保存。'));
            var rows=draft.mappings.map(function(row,i){
                var target=interfaces.find(function(t){return t.name===row.mwan3_interface;}),state=E('div',{},self.mwanState(row)),members=E('div',{},target?target.members.join('、') || '无关联成员':'—');
                stateNodes.push({node:state,members:members,row:row});
                var source=self.select(row.source_interface,choices(sourceNames.map(function(n){return {value:n,label:n};}),row.source_interface),function(v){row.source_interface=v;});
                source.setAttribute('aria-label','来源接口 '+(i+1));
                var destination=self.select(row.mwan3_interface,choices(interfaces.map(function(t){return {value:t.name,label:t.name+(t.family!=='ipv4'?'（IPv6）':!t.enabled?'（未启用）':'')};}),row.mwan3_interface),function(v){row.mwan3_interface=v;draw();});
                destination.setAttribute('aria-label','目标 mwan3 接口 '+(i+1));
                return self.row([self.checkbox('参与联动 '+(i+1),row.enabled,function(v){row.enabled=v;}),source,destination,members,state,self.button('删除',function(){draft.mappings.splice(i,1);draw();})]);
            });
            fields.push(self.table(['启用','CampusLink 接口','mwan3 接口','关联成员','当前状态','操作'],rows,'尚未选择联动接口'));
            fields.push(self.button('新增映射',function(){
                if(draft.mappings.length>=32)return;
                var source=sourceNames.find(function(n){return !draft.mappings.some(function(m){return m.source_interface===n;});}) || '';
                var target=interfaces.find(function(t){return t.name===source && !draft.mappings.some(function(m){return m.mwan3_interface===t.name;});});
                draft.mappings.push({source_interface:source,mwan3_interface:target?target.name:'',enabled:false});draw();
            }));
            fields.push(E('p',{class:'cl-secondary'},'停用或删除映射会停止联动控制并保留当前成员状态；恢复原生探测请在 mwan3 设置。成员、权重和策略由 mwan3 管理。'));
            dom.content(form,fields);
            self.mwanStatusRefresh=function(){stateNodes.forEach(function(item){dom.content(item.node,self.mwanState(item.row));var data=self.data.mwan3,target=data && data.interfaces.find(function(t){return t.name===item.row.mwan3_interface;});dom.content(item.members,target?target.members.join('、') || '无关联成员':'—');});};
        }
        draw();this.openEditor('mwan3 联动',form,function(){if(!self.data.mwan3)throw new Error('联动组件不可用，请恢复连接后重试');return model.saveMwan(draft,self.data);},'保存联动设置',true,'mwan3');
    },
    deleteItem:function(kind,id) {
        var cfg = model.copy(this.cfg),account = kind === 'account',list = account ? cfg.accounts : cfg.connections,item = list.find(function(x) { return x.id === id; });
        if (account && cfg.connections.some(function(c) { return c.account === id; })) { ui.addNotification(null,E('p',{},'该账号正在被线路使用，请先更换线路账号'),'error'); return; }
        if (account) cfg.accounts = list.filter(function(x) { return x.id !== id; }); else cfg.connections = list.filter(function(x) { return x.id !== id; });
        var form = E('form',{},E('p',{},'删除“'+(item.label || id)+'”？'));
        this.openEditor('删除'+(account ? '账号' : '登录配置'),form,function() { return cfg; },'删除');
    }
});

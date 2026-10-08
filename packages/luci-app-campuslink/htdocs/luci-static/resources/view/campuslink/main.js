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
var labels = {disabled:'已停用',waiting_interface:'等待接口',checking:'检查中',online:'已联网',authenticating:'登录中',verifying:'复查中',logging_out:'退出中',backoff:'等待重试',action_required:'需要处理',invalid_config:'配置错误'};
var tabs = [['overview','总览'],['connections','登录配置'],['accounts','账号'],['settings','插件设置'],['logs','日志']];
var fieldNames = {auth_server:'认证服务器',auth_url:'登录地址',status_url:'状态地址',logout_url:'退出地址',probe_url:'探测地址',username:'校园网账号',password:'密码'};

return view.extend({
    handleSaveApply:null, handleSave:null, handleReset:null,
    load:function() { return getState(); },
    render:function(data) {
        this.data = data; this.cfg = model.copy(data.config); this.activeTab = 'overview'; this.editor = null; this.settingsSession = null; this.saving = false; this.sequence = 0;
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
        poll.add(L.bind(function() { return getState().then(L.bind(function(next) {
            var previous = this.data.config.generation;
            if (!this.acceptSnapshot(next)) return;
            if (!this.editor && (this.activeTab === 'overview' || this.activeTab === 'logs' || previous !== next.config.generation)) this.drawPanel();
        },this)); },this),3);
        return root;
    },
    acceptSnapshot:function(next) {
        if (this.data && next.config.generation < this.data.config.generation) return false;
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
                return self.row([E('div',{},[E('strong',{},c.label || c.interface),E('div',{class:'cl-secondary'},c.interface+(s.ip ? ' · '+s.ip : ''))]),self.accountLabel(c.account),self.modeLabel(c),E('div',{},status),c.auto_login ? '开启' : '关闭',E('div',{class:'cl-actions'},controls)]);
            });
            content = [this.table(['WAN','账号','方式','状态','自动登录','操作'],rows,'暂无登录配置'),this.button('新增登录配置',function() { self.editLine(); },true)];
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
        } else {
            content = [this.table(['时间','线路','事件'],(this.data.events || []).slice(-50).reverse().map(function(e) { var c = cfg.connections.find(function(x) { return x.id === e.id; }); return self.row([new Date(e.time*1000).toLocaleTimeString(),c ? c.label || c.interface : '系统',e.message]); }),'暂无日志')];
        }
        dom.content(this.panel,content);
    },
    errorText:function(reply) {
        var message = reply.message || reply.reason_code || '操作失败',match = message.match(/(?:missing_field|invalid_field|invalid_url):([a-z_]+)/);
        return match ? '请检查'+(fieldNames[match[1]] || match[1]) : message;
    },
    runAction:function(id,operation) {
        if (this.editor || this.saving) return Promise.resolve();
        return action(id,operation).then(L.bind(function(reply) {
            if (!reply.ok) ui.addNotification(null,E('p',{},this.errorText(reply)),'error');
            return getState().then(L.bind(function(next) { if (this.acceptSnapshot(next) && !this.editor) this.drawPanel(); },this));
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
    closeEditor:function() { if (this.saving) return; if(this.editor && this.editor.inline)this.settingsSession=null;else ui.hideModal(); this.editor = null; this.cfg = model.copy(this.data.config); this.drawPanel(); },
    openEditor:function(title,form,candidate,actionLabel,inline) {
        var self = this,error = E('p',{class:'cl-form-error',role:'alert',hidden:true});
        this.editor = {form:form,error:error,inline:!!inline};
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
        return saveConfig(candidate,candidate.generation).then(function(reply) {
            if (!reply.ok) throw new Error(self.errorText(reply));
            return getState().then(function(next) {
                self.acceptSnapshot(next); self.cfg = model.copy(self.data.config); self.editor = null; if(editor.inline)self.settingsSession=null;else ui.hideModal(); self.drawPanel();
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
            fields.push(self.field('认证系统',self.select(draft.provider,self.data.providers.map(function(x){return {value:x.id,label:x.label};}),function(v){draft.provider=v;draft.params={};var s=self.data.schools.find(function(x){return x.provider===v;});draft.school=s?s.id:'';session.advancedOpen=false;draw();})));
            fields.push(self.field('学校预设',self.select(draft.school,[{value:'',label:'手动配置'}].concat(self.data.schools.filter(function(x){return x.provider===draft.provider;}).map(function(x){return {value:x.id,label:x.label};})),function(v){draft.school=v;draft.params={};session.advancedOpen=false;draw();})));
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
            advanced.push(self.button('恢复预设参数',function(){draft.params={};session.advancedOpen=false;draw();}));
            fields.push(E('details',{class:'cl-advanced',open:session.advancedOpen?true:null,toggle:function(ev){session.advancedOpen=ev.target.open;}},[E('summary',{},'高级设置')].concat(advanced)));
            refreshEndpoints();dom.content(form,fields);
        }
        draw();this.openEditor('插件设置',form,function(){return model.saveSettings(session.base,draft,self.data);},'保存到所有 WAN',true);
    },
    deleteItem:function(kind,id) {
        var cfg = model.copy(this.cfg),account = kind === 'account',list = account ? cfg.accounts : cfg.connections,item = list.find(function(x) { return x.id === id; });
        if (account && cfg.connections.some(function(c) { return c.account === id; })) { ui.addNotification(null,E('p',{},'该账号正在被线路使用，请先更换线路账号'),'error'); return; }
        if (account) cfg.accounts = list.filter(function(x) { return x.id !== id; }); else cfg.connections = list.filter(function(x) { return x.id !== id; });
        var form = E('form',{},E('p',{},'删除“'+(item.label || id)+'”？'));
        this.openEditor('删除'+(account ? '账号' : '登录配置'),form,function() { return cfg; },'删除');
    }
});

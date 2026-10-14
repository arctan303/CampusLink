'use strict';
'require baseclass';

function copy(value) { return JSON.parse(JSON.stringify(value)); }
function defaults(connection, data) {
    var p = data.providers.find(function(x) { return x.id === connection.provider; });
    var s = (data.schools || []).find(function(x) { return x.id === connection.school; });
    var values = {};
    (p ? p.connection_fields : []).forEach(function(f) { if (f.default != null) values[f.id] = f.default; });
    Object.assign(values, s ? s.defaults : {});
    if (p && p.id === 'drcom-http') {
        var match = values.auth_url && values.auth_url.match(/^http:\/\/([a-zA-Z0-9.-]+):801\/eportal\/portal\/login$/);
        if (match) {
            if (values.auth_server == null) values.auth_server = match[1];
            var urls = endpoints(match[1]);
            Object.keys(urls).forEach(function(key) { if (values[key] === urls[key]) delete values[key]; });
        }
    }
    return values;
}
function endpoints(server) {
    return {auth_url:'http://' + server + ':801/eportal/portal/login',status_url:'http://' + server + '/',logout_url:'http://' + server + ':801/eportal/portal/logout'};
}
function effective(connection,config) { return config && config.schema_version === 2 ? Object.assign({},connection,config.settings,{params:Object.assign({},config.settings.params,connection.params)}) : connection; }
function params(connection, data, config) { var c=effective(connection,config);return Object.assign(defaults(c,data),c.params); }
function lineDraft(connection, data) {
    var draft = copy(connection);
    if (draft.provider !== 'drcom-http') return draft;
    var values = params(draft,data), preset = defaults(draft,data);
    // Compact only canonical old URLs. Nonstandard overrides remain untouched.
    var match = values.auth_url && values.auth_url.match(/^http:\/\/([a-zA-Z0-9.-]+):801\/eportal\/portal\/login$/);
    var server = draft.params.auth_server || (match ? match[1] : values.auth_server);
    if (server) {
        if (server !== preset.auth_server || draft.params.auth_server != null) draft.params.auth_server = server;
        var urls = endpoints(server);
        Object.keys(urls).forEach(function(key) { if (draft.params[key] === urls[key]) delete draft.params[key]; });
    }
    if (draft.params.probe_url === preset.probe_url) delete draft.params.probe_url;
    return draft;
}
function accountDraft(account) { var draft = copy(account); draft.values.password = ''; return draft; }
function upsert(list, item) { var i = list.findIndex(function(x) { return x.id === item.id; }); if (i < 0) list.push(item); else list[i] = item; }
function accountValue(draft, existing) {
    var account = copy(draft);
    account.values.username = (account.values.username || '').trim();
    account.label = account.label.trim() || account.values.username;
    if (!account.values.username) throw new Error('请输入校园网账号');
    if (!account.values.password) { if (!existing || !existing.password_set) throw new Error('请输入密码'); delete account.values.password; }
    delete account.password_set;
    return account;
}
function saveAccount(config, draft) {
    var candidate = copy(config);
    upsert(candidate.accounts,accountValue(draft,config.accounts.find(function(a) { return a.id === draft.id; })));
    return candidate;
}
function saveLine(config, draft, inlineAccount) {
    var candidate = copy(config), connection = copy(draft);
    if (connection.account === '__new__') { var account = accountValue(inlineAccount,null); candidate.accounts.push(account); connection.account = account.id; }
    if (!candidate.accounts.some(function(a) { return a.id === connection.account; })) throw new Error('请选择账号');
    var provider=config.settings ? config.settings.provider : connection.provider;
    connection.label = connection.label.trim() || connection.interface + (provider === 'drcom-http' ? connection.params.terminal_mode === 'mobile' ? ' · 手机' : ' · 电脑' : '');
    upsert(candidate.connections,connection);
    return candidate;
}
function newLine(config, data, id) {
    var interfaces = data.interfaces.map(function(x) { return x.interface; });
    var available = interfaces.filter(function(x) { return /^wan[0-9]*$/.test(x); });
    var iface = available.find(function(x) { return !config.connections.some(function(c) { return c.interface === x; }); }) || available[0] || interfaces[0] || 'wan';
    var provider = data.providers.find(function(x) { return x.id === 'drcom-http'; }) || data.providers[0];
    var line={id:id,label:'',interface:iface,account:config.accounts[0] ? config.accounts[0].id : '__new__',params:{},enabled:false,auto_login:false};
    if(config.schema_version !== 2)Object.assign(line,{provider:provider.id,school:'',check_interval:60,retry_interval:30,retry_max:600});
    return line;
}
function manualSettings(settings,data) {
    var draft=copy(settings),values=params(draft,data),provider=data.providers.find(function(p){return p.id===draft.provider;});
    // Materialize inherited public values before detaching the legacy preset.
    draft.params={};
    provider.connection_fields.forEach(function(f){if(f.scope!=='connection' && values[f.id]!=null)draft.params[f.id]=copy(values[f.id]);});
    draft.school='';
    return lineDraft(draft,data);
}
function settingsDraft(config,data) {
    if(config.settings)return manualSettings(config.settings,data);
    var first=config.connections[0],provider=data.providers.find(function(p){return p.id === (first ? first.provider : 'drcom-http');}) || data.providers[0];
    var draft={provider:provider.id,school:first ? first.school : '',params:{},check_interval:first ? first.check_interval : 60,retry_interval:first ? first.retry_interval : 30,retry_max:first ? first.retry_max : 600};
    provider.connection_fields.forEach(function(f){if(f.scope !== 'connection' && first && first.params[f.id]!=null)draft.params[f.id]=first.params[f.id];});
    return manualSettings(draft,data);
}
function saveSettings(config,draft,data) {
    var candidate=copy(config),provider=data.providers.find(function(p){return p.id===draft.provider;});
    if(!provider)throw new Error('请选择登录系统');
    candidate.schema_version=2;candidate.settings=manualSettings(draft,data);
    candidate.connections=config.connections.map(function(c){
        var previousProvider=(config.settings || c).provider,values=previousProvider===provider.id ? params(c,data,config) : c.params;
        var local={};provider.connection_fields.forEach(function(f){
            var value=values[f.id];
            if(f.scope!=='connection' || value==null)return;
            if(f.type==='enum' && !f.choices.some(function(choice){return choice.value===value;}))return;
            local[f.id]=copy(value);
        });
        return {id:c.id,label:c.label,interface:c.interface,account:c.account,params:local,enabled:c.enabled,auto_login:c.auto_login};
    });
    return candidate;
}
function mwanDraft(snapshot) { return copy(snapshot.config); }
function saveMwan(draft,data) {
    var candidate=copy(draft),sources=[],targets=[],interfaces=data.mwan3.interfaces || [];
    if(candidate.mappings.length>32)throw new Error('最多配置 32 条联动映射');
    candidate.mappings.forEach(function(row){
        if(!row.source_interface || !row.mwan3_interface)throw new Error('请选择来源和目标接口');
        if(sources.indexOf(row.source_interface)>=0)throw new Error('同一 CampusLink 接口只能配置一次');
        if(targets.indexOf(row.mwan3_interface)>=0)throw new Error('同一 mwan3 接口只能由一条映射控制');
        sources.push(row.source_interface);targets.push(row.mwan3_interface);
        if(!candidate.enabled || !row.enabled)return;
        if(!data.config.connections.some(function(c){return c.interface===row.source_interface;}))throw new Error('来源接口已不存在，请停用或删除此映射');
        var target=interfaces.find(function(t){return t.name===row.mwan3_interface;});
        if(!target || !target.enabled)throw new Error('目标 mwan3 接口不存在或未启用');
        if(target.family!=='ipv4')throw new Error('当前联动仅支持 IPv4 接口');
        if(!target.prepared || target.tracker_running)throw new Error('请先在 mwan3 关闭该接口的独立探测，并将初始状态设为离线');
    });
    return candidate;
}
return baseclass.extend({copy:copy,defaults:defaults,params:params,effective:effective,endpoints:endpoints,lineDraft:lineDraft,accountDraft:accountDraft,saveAccount:saveAccount,saveLine:saveLine,newLine:newLine,settingsDraft:settingsDraft,saveSettings:saveSettings,mwanDraft:mwanDraft,saveMwan:saveMwan});

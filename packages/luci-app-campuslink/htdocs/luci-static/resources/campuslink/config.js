'use strict';
'require baseclass';

function copy(value) { return JSON.parse(JSON.stringify(value)); }
function defaults(connection, data) {
    var p = data.providers.find(function(x) { return x.id === connection.provider; });
    var s = data.schools.find(function(x) { return x.id === connection.school; });
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
    var school = data.schools.find(function(x) { return x.provider === provider.id; });
    var line={id:id,label:'',interface:iface,account:config.accounts[0] ? config.accounts[0].id : '__new__',params:{},enabled:false,auto_login:false};
    if(config.schema_version !== 2)Object.assign(line,{provider:provider.id,school:school ? school.id : '',check_interval:60,retry_interval:30,retry_max:600});
    return line;
}
function settingsDraft(config,data) {
    if(config.settings)return lineDraft(config.settings,data);
    var first=config.connections[0],provider=data.providers.find(function(p){return p.id === (first ? first.provider : 'drcom-http');}) || data.providers[0];
    var school=data.schools.find(function(s){return s.provider === provider.id;});
    var draft={provider:provider.id,school:first ? first.school : school ? school.id : '',params:{},check_interval:first ? first.check_interval : 60,retry_interval:first ? first.retry_interval : 30,retry_max:first ? first.retry_max : 600};
    provider.connection_fields.forEach(function(f){if(f.scope !== 'connection' && first && first.params[f.id]!=null)draft.params[f.id]=first.params[f.id];});
    return lineDraft(draft,data);
}
function saveSettings(config,draft,data) {
    var candidate=copy(config),provider=data.providers.find(function(p){return p.id===draft.provider;});
    if(!provider)throw new Error('请选择认证系统');
    candidate.schema_version=2;candidate.settings=copy(draft);
    candidate.connections=config.connections.map(function(c){
        var local={};provider.connection_fields.forEach(function(f){
            var value=c.params[f.id];
            if(f.scope!=='connection' || value==null)return;
            if(f.type==='enum' && !f.choices.some(function(choice){return choice.value===value;}))return;
            local[f.id]=copy(value);
        });
        return {id:c.id,label:c.label,interface:c.interface,account:c.account,params:local,enabled:c.enabled,auto_login:c.auto_login};
    });
    return candidate;
}
return baseclass.extend({copy:copy,defaults:defaults,params:params,effective:effective,endpoints:endpoints,lineDraft:lineDraft,accountDraft:accountDraft,saveAccount:saveAccount,saveLine:saveLine,newLine:newLine,settingsDraft:settingsDraft,saveSettings:saveSettings});

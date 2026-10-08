import * as fs from 'fs';

export function read_json(path, fallback) {
    let s = fs.readfile(path, 262145);
    if(s != null && length(s)>262144)die('config_too_large');
    return s == null ? fallback : json(s);
};

export function write_json(path, value) {
    let tmp = path + '.new';
    let f = fs.open(tmp, 'w', 0600);
    if (!f) die('config_write_failed');
    let content = sprintf('%J\n', value);
    if(length(content)>262144){f.close();fs.unlink(tmp);die('config_too_large');}
    if (f.write(content) != length(content)) { f.close(); fs.unlink(tmp); die('config_write_failed'); }
    f.flush(); f.close(); fs.chmod(tmp, 0600);
    if (!fs.rename(tmp, path)) { fs.unlink(tmp); die('config_write_failed'); }
};

export function monotime() {
    return +split(fs.readfile('/proc/uptime'), ' ')[0];
};

export function result(outcome, reason, message, extra) {
    let r = {outcome, reason_code: reason, message};
    for (let k, v in (extra || {})) r[k] = v;
    return r;
};

export function clean_message(message, credentials) {
    let s = type(message) == 'string' ? message : '';
    for (let k, value in (credentials || {}))
        if (type(value) == 'string' && length(value)) s = join('[已隐藏]', split(s, value));
    return substr(replace(s, /[[:cntrl:]<>]/g, ' '), 0, 240);
};

export function field_value(field, value) {
    if (value == null || value === '') {
        if (field.required) die('missing_field:' + field.id);
        return value;
    }
    if (field.type == 'integer') {
        if (type(value) != 'int' || (field.min != null && value < field.min) || (field.max != null && value > field.max)) die('invalid_field:' + field.id);
    }
    else if (field.type == 'boolean') { if (type(value) != 'bool') die('invalid_field:' + field.id); }
    else {
        if (type(value) != 'string' || length(value) > 1024 || match(value, /[[:cntrl:]]/)) die('invalid_field:' + field.id);
        if (field.type == 'enum' && !length(filter(field.choices, (c) => c.value == value))) die('invalid_field:' + field.id);
        if (field.type == 'url' && !match(value, /^https?:\/\/[a-zA-Z0-9._:-]+(\/[^[:space:]]*)?$/)) die('invalid_url:' + field.id);
    }
    return value;
};

export function valid_id(id) { return type(id) == 'string' && !!match(id, /^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/); };

export function merge_params(provider, school, overrides, resolve, global_only) {
    let params = {};
    for (let field in provider.connection_fields) if (field.default != null) params[field.id] = field.default;
    for (let k, v in (school?.defaults || {})) params[k] = v;
    for (let k, v in (overrides || {})) params[k] = v;
    for (let k in params)
        if (!length(filter(provider.connection_fields, (f) => f.id == k))) die('unknown_field:' + k);
    for (let field in provider.connection_fields) if(!global_only || field.scope!='connection')field_value(field, params[field.id]);
    if (resolve) {
        params = resolve(params, {provider,school,overrides:overrides || {}});
        if (type(params) != 'object') die('invalid_resolved_params');
        for (let k in params)
            if (!length(filter(provider.connection_fields, (f) => f.id == k))) die('unknown_field:' + k);
        for (let field in provider.connection_fields) if(!global_only || field.scope!='connection')field_value(field, params[field.id]);
    }
    return params;
};

export function validate_provider(p, handler) {
    if(type(p)!='object' || p.schema_version!==1 || !valid_id(p.id) || type(p.label)!='string' || !length(p.label) || length(p.label)>128 || p.credential_type!='username_password')die('invalid_provider_metadata');
    if(type(p.capabilities)!='object' || p.capabilities.check!==true || p.capabilities.login!==true || type(p.capabilities.logout)!='bool' || p.capabilities.heartbeat!==false)die('invalid_provider_capabilities');
    for(let op in ['check','login'])if(type(handler[op])!='function')die('missing_provider_operation');
    if(handler.resolve_params!=null && type(handler.resolve_params)!='function')die('invalid_provider_resolver');
    if(p.capabilities.logout && type(handler.logout)!='function')die('missing_provider_operation');
    if(type(p.account_fields)!='array' || length(p.account_fields)!=2 || p.account_fields[0].id!='username' || p.account_fields[0].type!='string' || p.account_fields[0].required!==true || p.account_fields[1].id!='password' || p.account_fields[1].type!='secret' || p.account_fields[1].required!==true)die('unsupported_credential_fields');
    if(type(p.connection_fields)!='array' || length(p.connection_fields)>64)die('invalid_provider_fields');
    let seen={};
    for(let field in [...p.account_fields,...p.connection_fields]){
        if(!valid_id(field.id) || seen[field.id] || type(field.label)!='string' || !length(field.label) || length(field.label)>128 || type(field.required)!='bool' || index(['string','secret','enum','integer','boolean','url'],field.type)<0)die('invalid_provider_field');
        seen[field.id]=true;
        if(field.type=='secret' && field.default!=null)die('secret_default');
        if(field.type=='secret' && index(p.connection_fields,field)>=0)die('secret_connection_field');
        if(field.type=='enum'){
            if(type(field.choices)!='array' || !length(field.choices) || length(field.choices)>128)die('invalid_choices');
            let choices={};for(let c in field.choices){if(type(c.value)!='string' || !length(c.value) || length(c.value)>128 || choices[c.value] || type(c.label)!='string' || !length(c.label) || length(c.label)>128)die('invalid_choices');choices[c.value]=true;}
        }else if(field.choices!=null)die('unexpected_choices');
        for(let key in ['min','max'])if(field[key]!=null && (field.type!='integer' || type(field[key])!='int'))die('invalid_range');
        if(field.min!=null && field.max!=null && field.min>field.max)die('invalid_range');
        if(field.default!=null)field_value(field,field.default);
        if(field.advanced!=null && type(field.advanced)!='bool')die('invalid_field_presentation');
        if(field.scope!=null && index(['global','connection'],field.scope)<0)die('invalid_field_scope');
        if(field.capability!=null && index(['logout','heartbeat'],field.capability)<0)die('invalid_field_capability');
    }
    return p;
};

export function validate_school(s,providers){
    if(type(s)!='object' || s.schema_version!==1 || !valid_id(s.id) || type(s.label)!='string' || !length(s.label) || length(s.label)>128 || !providers[s.provider] || type(s.defaults)!='object' || index(['unverified','verified'],s.verification_status)<0)die('invalid_school_metadata');
    if(s.verification_status=='verified' && (!match(s.verification?.date || '',/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) || type(s.verification?.environment)!='string' || !length(s.verification.environment) || type(s.verification?.summary)!='string' || !length(s.verification.summary)))die('missing_verification');
    let p=providers[s.provider];
    for(let k,v in s.defaults){let field=filter(p.connection_fields,(f)=>f.id==k)[0];if(!field)die('unknown_school_field');field_value(field,v);}
    return s;
};

export function validate_result(r, operation, credentials){
    let allowed={check:['online','unauthenticated','indeterminate'],login:['accepted','rejected','rate_limited','indeterminate'],logout:['unauthenticated','rejected','rate_limited','indeterminate']};
    if(type(r)!='object' || !allowed[operation] || index(allowed[operation],r.outcome)<0 || type(r.reason_code)!='string' || !match(r.reason_code,/^[a-z][a-z0-9_]{0,63}$/) || type(r.message)!='string' || (r.retry_after_s!=null && (type(r.retry_after_s)!='int' || r.retry_after_s<0 || r.retry_after_s>86400)))return result('indeterminate','provider_contract_error','提供商返回无效结果');
    return result(r.outcome,r.reason_code,clean_message(r.message,credentials),r.retry_after_s!=null?{retry_after_s:r.retry_after_s}:{});
};

function validate_intervals(value){
    let interval=value.check_interval ?? 60,retry=value.retry_interval ?? 30,cap=value.retry_max ?? 600;
    for(let f in [{min:10,max:3600,value:interval},{min:10,max:600,value:retry},{min:60,max:3600,value:cap}])
        if(type(f.value)!='int' || f.value<f.min || f.value>f.max)die('invalid_interval');
    if(cap<retry)die('invalid_interval');
};

export function effective_connection(config,line){
    if(config.schema_version!==2)return line;
    let g=config.settings;
    return {...line,provider:g.provider,school:g.school,params:{...g.params,...line.params},check_interval:g.check_interval,retry_interval:g.retry_interval,retry_max:g.retry_max};
};

export function validate_config(input, old, providers, schools, handlers) {
    if (type(input) != 'object' || index([1,2],input.schema_version)<0 || type(input.accounts) != 'array' || type(input.connections) != 'array') die('invalid_config');
    if(old.schema_version===2 && input.schema_version!==2)die('unsupported_config_version');
    if (length(input.accounts) > 64 || length(input.connections) > 32) die('config_too_large');
    let cfg = {schema_version: input.schema_version, generation: (old.generation || 0) + 1, accounts: [], connections: []};
    if(input.schema_version===2){
        let g=input.settings,p=providers[g?.provider],school=g?.school?schools[g.school]:null;
        if(type(g)!='object' || !p || (g.school && (!school || school.provider!=g.provider)) || type(g.params)!='object')die('invalid_plugin_settings');
        for(let k in g)if(index(['provider','school','params','check_interval','retry_interval','retry_max'],k)<0)die('unknown_plugin_setting');
        for(let k in g.params){let f=filter(p.connection_fields,x=>x.id==k)[0];if(!f || f.scope=='connection')die('invalid_global_field:'+k);}
        validate_intervals(g);
        // Per-line fields obtain their defaults later, not global overrides.
        merge_params(p,school,g.params,handlers?.[p.id]?.resolve_params,true);
        cfg.settings={provider:g.provider,school:g.school || '',params:g.params,check_interval:g.check_interval ?? 60,retry_interval:g.retry_interval ?? 30,retry_max:g.retry_max ?? 600};
    }
    let accounts = {}, used = {};
    for (let a in input.accounts) {
        if (!valid_id(a.id) || accounts[a.id] || type(a.label) != 'string' || length(a.label) > 128 || a.credential_type != 'username_password') die('invalid_account');
        let previous = filter(old.accounts, (o) => o.id == a.id)[0];
        let values = {username: a.values?.username};
        values.password = a.values?.password ?? previous?.values?.password;
        let credential_fields = [{id:'username', type:'string', required:true}, {id:'password', type:'secret', required:true}];
        for (let f in credential_fields) field_value(f, values[f.id]);
        let account = {id:a.id, label:a.label, credential_type:a.credential_type, values};
        push(cfg.accounts, account); accounts[a.id] = account;
    }
    for (let source in input.connections) {
        if(type(source.params)!='object')die('invalid_connection');
        if(input.schema_version===2){
            for(let k in source)if(index(['id','label','interface','account','params','enabled','auto_login'],k)<0)die('global_setting_on_line:'+k);
            let p=providers[cfg.settings.provider];
            for(let k in source.params){let f=filter(p.connection_fields,x=>x.id==k)[0];if(!f || f.scope!='connection')die('global_parameter_on_line:'+k);}
        }
        let c=effective_connection(cfg,source);
        if (!valid_id(c.id) || used[c.id] || !valid_id(c.interface) || type(c.label) != 'string' || length(c.label) > 128) die('invalid_connection');
        let p = providers[c.provider], school = c.school ? schools[c.school] : null;
        if (!p || (c.school && (!school || school.provider != c.provider))) die('invalid_provider_or_school');
        if (!accounts[c.account] || accounts[c.account].credential_type != p.credential_type) die('account_in_use_or_missing');
        if (type(c.params) != 'object' || type(c.enabled) != 'bool' || type(c.auto_login) != 'bool') die('invalid_connection');
        let interval = c.check_interval ?? 60, retry = c.retry_interval ?? 30, cap = c.retry_max ?? 600;
        validate_intervals(c);
        merge_params(p, school, c.params, handlers?.[p.id]?.resolve_params);
        used[c.id] = true;
        if (c.enabled && used['iface:' + c.interface]) die('interface_in_use');
        if (c.enabled) used['iface:' + c.interface] = true;
        let line={id:c.id,label:c.label,interface:c.interface,account:c.account,params:source.params,enabled:c.enabled,auto_login:c.auto_login};
        if(input.schema_version===1){line.provider=c.provider;line.school=c.school || '';line.check_interval=interval;line.retry_interval=retry;line.retry_max=cap;}
        push(cfg.connections,line);
    }
    if(length(sprintf('%J\n',cfg))>262144)die('config_too_large');
    return cfg;
};

export function upgrade_config(config,providers,schools,handlers){
    if(config.schema_version!==1 || !length(config.connections))return config;
    let first=config.connections[0],p=providers[first.provider];
    let common=merge_params(p,schools[first.school],first.params,handlers?.[p.id]?.resolve_params);
    for(let c in config.connections){
        if(c.provider!=first.provider || c.school!=first.school || c.check_interval!=first.check_interval || c.retry_interval!=first.retry_interval || c.retry_max!=first.retry_max)return config;
        let values=merge_params(p,schools[c.school],c.params,handlers?.[p.id]?.resolve_params);
        for(let f in p.connection_fields)if(f.scope!='connection' && values[f.id]!==common[f.id])return config;
    }
    let next=json(sprintf('%J',config));next.schema_version=2;
    let params={};for(let f in p.connection_fields)if(f.scope!='connection' && first.params[f.id]!=null)params[f.id]=first.params[f.id];
    next.settings={provider:first.provider,school:first.school,params,check_interval:first.check_interval,retry_interval:first.retry_interval,retry_max:first.retry_max};
    for(let c in next.connections){
        let local={};for(let f in p.connection_fields)if(f.scope=='connection' && c.params[f.id]!=null)local[f.id]=c.params[f.id];
        c.params=local;for(let k in ['provider','school','check_interval','retry_interval','retry_max'])delete c[k];
    }
    // Migration stays in memory until the first successful save; preserve generation.
    return {...validate_config(next,{...config,generation:config.generation-1},providers,schools,handlers),generation:config.generation};
};

export function public_config(cfg) {
    let copy = json(sprintf('%J', cfg));
    for (let a in copy.accounts) { a.password_set = !!length(a.values.password || ''); delete a.values.password; }
    return copy;
};

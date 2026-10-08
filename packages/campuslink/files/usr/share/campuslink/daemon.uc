import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import {read_json,write_json,monotime,result,merge_params,validate_config,public_config,validate_provider,validate_school,effective_connection,upgrade_config} from './common.uc';
import * as drcom from './providers/drcom-http.uc';
import * as mock from './providers/mock.uc';

const BASE = getenv('CAMPUSLINK_BASE') || '/usr/share/campuslink';
const CONFIG = getenv('CAMPUSLINK_CONFIG') || '/etc/campuslink/config.json';
const RUNTIME = getenv('CAMPUSLINK_RUNTIME') || '/var/run/campuslink';
const OBJECT = getenv('CAMPUSLINK_OBJECT') || 'campuslink';
const handlers = {'drcom-http':drcom, mock};
let providers = {}, schools = {}, states = {}, jobs = {}, events = [], cooldowns = {}, sequence = 0;
for (let path in (fs.glob(BASE + '/providers/*.json') || [])) { let p=read_json(path); if (handlers[p.id]) {validate_provider(p,handlers[p.id]);if(providers[p.id])die('duplicate_provider');providers[p.id]=p;} }
for (let path in (fs.glob(BASE + '/schools/*.json') || [])) { let s=validate_school(read_json(path),providers);if(schools[s.id])die('duplicate_school');schools[s.id]=s; }
fs.mkdir(fs.dirname(CONFIG),0700); fs.mkdir(RUNTIME,0700); fs.chmod(RUNTIME,0700);
let cfg = read_json(CONFIG,{schema_version:1,generation:0,accounts:[],connections:[]});
if (index([1,2],cfg.schema_version)<0) die('unsupported_config_version\n');
cfg = {...validate_config(cfg,{generation:cfg.generation-1,accounts:cfg.accounts},providers,schools,handlers),generation:cfg.generation};
cfg = upgrade_config(cfg,providers,schools,handlers);
uloop.init();
const bus = ubus.connect(), net = ubus.connect();
const SELF = int(split(fs.readfile('/proc/self/stat'),' ')[0]);
if (!bus || !net) die('ubus_unavailable\n');

function cleanup(dir) {
    for (let name in ['curl.conf','body','headers','cookies','context.json','context.json.new','progress.json','result.json','progress.json.new','result.json.new']) fs.unlink(dir + '/' + name);
    fs.rmdir(dir);
};
function log(id, code, message) {
    push(events,{time:time(),id,reason_code:code,message});
    while (length(events) > 200) shift(events);
};
function connection(id) { let c=filter(cfg.connections,(c)=>c.id == id)[0];return c?effective_connection(cfg,c):null; }
function route(iface) {
    let s=net.call('network.interface.' + iface,'status',{}) || {};
    let ip=s['ipv4-address']?.[0]?.address, device=s.l3_device;
    return s.up && ip && device ? {ip,device} : null;
};
function state(c) {
    if (!states[c.id]) states[c.id]={id:c.id,state:c.enabled?'waiting_interface':'disabled',reason_code:'initial',message:'等待检查',next_due:0,cooldown_until:0,failures:0,paused:false};
    states[c.id].cooldown_until=max(states[c.id].cooldown_until,cooldowns[c.interface] || 0);
    return states[c.id];
};
function stop_job(id) {
    let job=jobs[id];
    if(!job)return;
    let pid=job.task?.pid(), stat=pid?fs.readfile('/proc/'+pid+'/stat'):null;
    let info=stat?match(stat,/^[0-9]+ \(.*\) [A-Za-z] ([0-9]+) ([0-9]+) /):null;
    if(info && int(info[1])==SELF){
        // setsid gives this worker its own process group. Kill the group and
        // its leader, including curl; fixed numeric arguments only.
        let p=fs.popen('kill -TERM -- -'+pid+' 2>/dev/null','r');p?.close();
        p=fs.popen('kill -TERM '+pid+' 2>/dev/null','r');p?.close();
    }
    cleanup(job.dir);delete jobs[id];
};
function finish(id,job,r) {
    let c=connection(id), s=c ? state(c) : null, current=c ? route(c.interface) : null;
    if (!s || !c.enabled || job.generation != cfg.generation || !current || current.ip != job.route.ip || current.device != job.route.device) {
        if (s) { s.state=c.enabled?'waiting_interface':'disabled'; s.next_due=0; s.message='配置或接口已变化，重新检查'; }
        return;
    }
    if (type(r) != 'object' || index(['online','unauthenticated','indeterminate','accepted','rejected','rate_limited'],r.outcome) < 0) r=result('indeterminate','provider_contract_error','提供商返回无效结果');
    s.last_check=time(); s.reason_code=r.reason_code; s.message=r.message; s.device=current.device; s.ip=current.ip; s.identity_verified=false;
    let now=monotime();
    if (r.outcome == 'online') { s.state='online'; s.failures=0; s.cooldown_until=max(0,cooldowns[c.interface] || 0); s.next_due=now+c.check_interval; }
    else if (r.outcome == 'unauthenticated' && now < s.cooldown_until) { s.state='backoff';s.next_due=s.cooldown_until; }
    else if (r.outcome == 'unauthenticated' && (job.operation == 'logout' || !c.auto_login)) { s.state='action_required'; s.next_due=now+c.check_interval; }
    else if (r.outcome == 'rejected') { s.state='action_required'; s.paused=true; s.next_due=now+c.check_interval; }
    else {
        s.failures=min(s.failures+1,16);
        let delay=min(c.retry_interval * (1 << (s.failures-1)),c.retry_max);
        delay=max(delay,min(int(r.retry_after_s || 0),86400),s.cooldown_until-now);
        s.state='backoff'; s.cooldown_until=now+delay; s.next_due=s.cooldown_until;
        if(r.outcome=='rate_limited')cooldowns[c.interface]=max(cooldowns[c.interface] || 0,s.cooldown_until);
    }
    log(id,s.reason_code,s.message);
};
function start(c,operation) {
    let s=state(c), now=monotime();
    if (!c.enabled) return {ok:false,reason_code:'disabled',message:'请先启用线路'};
    if (jobs[c.id]) return {ok:true,task_id:jobs[c.id].id,busy:true};
    if (length(keys(jobs)) >= 2) return {ok:false,reason_code:'busy',message:'后台正在处理其他线路，稍后重试'};
    if (operation != 'check' && now < s.cooldown_until) return {ok:false,reason_code:'cooldown',message:'处于重试冷却，请稍后重试',retry_after_s:int(s.cooldown_until-now)+1};
    let r=route(c.interface);
    if (!r) { s.state='waiting_interface'; s.reason_code='interface_unavailable'; s.message='接口未获得 IPv4 地址'; s.next_due=now+10; return {ok:false,reason_code:s.reason_code,message:s.message}; }
    if (operation == 'logout') {
        if (!providers[c.provider].capabilities.logout) return {ok:false,reason_code:'unsupported',message:'当前提供商未验证退出能力'};
        let next=json(sprintf('%J',cfg));filter(next.connections,(item)=>item.id==c.id)[0].auto_login=false;next.generation++;write_json(CONFIG,next);cfg=next;c=connection(c.id);s.paused=false;
    }
    if (operation == 'login') s.paused=false;
    let task_id='task-' + (++sequence), dir=fs.mkdtemp(RUNTIME + '/job-XXXXXX');
    if (!dir) return {ok:false,reason_code:'local_io_failed'};
    let account=filter(cfg.accounts,(a)=>a.id==c.account)[0];
    let ctx={connection:c,account,route:r,workdir:dir,operation,params:merge_params(providers[c.provider],schools[c.school],c.params,handlers[c.provider].resolve_params),allow_login:c.auto_login && !s.paused && now>=s.cooldown_until};
    let job={id:task_id,dir,route:r,generation:cfg.generation,operation,task:null,deadline:now+45,completed:false};
    jobs[c.id]=job; s.state=operation=='logout'?'logging_out':'checking'; s.task_id=task_id;
    write_json(dir+'/context.json',ctx);
    job.task=uloop.process('/usr/bin/setsid',['/usr/bin/ucode',BASE+'/worker.uc',dir+'/context.json'],null,function(rc) {
        if (jobs[c.id] !== job) return;
        job.completed=true;
        try { let reply=read_json(dir+'/result.json',result('indeterminate','worker_failed','任务未正常完成'));finish(c.id,job,reply); }
        catch(e) { s.state='backoff';s.reason_code='provider_error';s.message='状态处理失败';s.next_due=monotime()+30; }
        cleanup(dir); delete jobs[c.id];
    });
    if (!job.task) { cleanup(dir);delete jobs[c.id];s.state='backoff';s.next_due=now+10;return {ok:false,reason_code:'worker_failed'}; }
    return {ok:true,task_id};
};
function tick() {
    let now=monotime();
    for (let id,job in jobs) {
        if(now>job.deadline) {stop_job(id);let c=connection(id);if(c){let s=state(c);s.state='backoff';s.reason_code='worker_timeout';s.message='任务超时';s.next_due=now+30;}}
        else {let progress=read_json(job.dir+'/progress.json',null);if(progress && states[id])states[id].state=progress.phase;}
    }
    for (let line in cfg.connections) {
        let c=effective_connection(cfg,line);
        let s=state(c);
        if (!c.enabled) { s.state='disabled';continue; }
        let r=route(c.interface);
        if (jobs[c.id] && (!r || r.ip!=jobs[c.id].route.ip || r.device!=jobs[c.id].route.device)) stop_job(c.id);
        if (jobs[c.id]) continue;
        if (!r) {s.state='waiting_interface';s.reason_code='interface_unavailable';s.message='等待接口获得 IPv4';continue;}
        if (s.ip && (s.ip!=r.ip || s.device!=r.device)) {s.next_due=0;s.paused=false;s.cooldown_until=0;}
        s.ip=r.ip;s.device=r.device;
        if (!s.paused && now>=s.next_due) start(c,'check');
    }
};
function snapshot() {
    let status=[];
    for(let line in cfg.connections) {
        let c=effective_connection(cfg,line);
        let s=state(c), a=filter(cfg.accounts,(a)=>a.id==c.account)[0];
        push(status,{id:c.id,interface:c.interface,state:s.state,reason_code:s.reason_code,message:s.message,device:s.device,ip:s.ip,last_check:s.last_check,next_check_s:max(0,int(s.next_due-monotime())),cooldown_s:max(0,int(s.cooldown_until-monotime())),task_id:jobs[c.id]?.id || '',configured_account:a?.label,identity_verified:false,auto_login:c.auto_login});
    }
    return {ok:true,version:'0.3.0',config:public_config(cfg),providers:map(keys(providers),(k)=>providers[k]),schools:map(keys(schools),(k)=>schools[k]),status,events,interfaces:(net.call('network.interface','dump',{})?.interface || [])};
};
const object=bus.publish(OBJECT,{
    get:{args:{ubus_rpc_session:''},call:function(req){req.reply(snapshot());}},
    save:{args:{config:{},expected_generation:0,ubus_rpc_session:''},call:function(req){
        try {
            if(req.args.expected_generation !== cfg.generation) {req.reply({ok:false,reason_code:'config_changed',message:'配置已改变，请重新加载页面'});return;}
            if(type(req.args.config?.accounts)=='array' && type(req.args.config?.connections)=='array'){
                let refs=filter(req.args.config.connections,(c)=>!length(filter(req.args.config.accounts,(a)=>a.id==c.account)));
                if(length(refs)){req.reply({ok:false,reason_code:'account_in_use',message:'线路仍引用未保留的账号，请先删除或更换线路账号',references:map(refs,(c)=>({id:c.id,label:c.label,account:c.account}))});return;}
            }
            let next=validate_config(req.args.config,cfg,providers,schools,handlers);
            write_json(CONFIG,next);
            for(let id in jobs) stop_job(id);
            cfg=next;states={};log('', 'config_saved','配置已保存');req.reply({ok:true,generation:cfg.generation});
        } catch(e) { req.reply({ok:false,reason_code:'invalid_config',message:substr(e.message || '配置无效',0,160)}); }
    }},
    action:{args:{id:'',operation:'',ubus_rpc_session:''},call:function(req){
        let c=connection(req.args.id), op=req.args.operation;
        if(!c || index(['check','login','logout','enable','disable'],op)<0){req.reply({ok:false,reason_code:'invalid_action'});return;}
        if(op=='enable' || op=='disable') {
            try{let candidate=json(sprintf('%J',cfg));filter(candidate.connections,(item)=>item.id==c.id)[0].enabled=op=='enable';let next=validate_config(candidate,cfg,providers,schools,handlers);write_json(CONFIG,next);cfg=next;stop_job(c.id);delete states[c.id];req.reply({ok:true});}
            catch(e){req.reply({ok:false,reason_code:'invalid_config',message:substr(e.message||'配置无效',0,160)});}
            return;
        }
        try{req.reply(start(c,op));}catch(e){req.reply({ok:false,reason_code:'operation_failed',message:'操作未启动，请检查配置'});}
    }}
});
if(!object) die('campuslink_object_unavailable\n');
const timer=uloop.interval(1000,tick);
const sigterm=uloop.signal('SIGTERM',function(){for(let id in jobs)stop_job(id);uloop.end();});
const sigint=uloop.signal('SIGINT',function(){for(let id in jobs)stop_job(id);uloop.end();});
tick();uloop.run();

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uci from 'uci';
import * as uloop from 'uloop';
import {decide} from './decision.uc';
import {valid_name,validate_settings,interface_catalog,validate_selection,binding_allowed} from './mappings.uc';

const ROOT=getenv('CAMPUSLINK_MWAN3_RUNTIME') || '/var/run/campuslink-mwan3';
const CONFIG=getenv('CAMPUSLINK_MWAN3_CONFIG') || '/etc/campuslink-mwan3/config.json';
const OBJECT=getenv('CAMPUSLINK_MWAN3_OBJECT') || 'campuslink.mwan3';
const once=ARGV[0]=='--once',dry=ARGV[0]=='--dry-run';
const fixture=once && ARGV[1] ? ARGV[1] : null;
let bus=ubus.connect(),client=ubus.connect(),cache={},statuses=[];
if (!bus || !client) die('ubus_unavailable\n');
fs.mkdir(ROOT,0700);fs.chmod(ROOT,0700);fs.mkdir(ROOT+'/events',0700);
function read_json(path,fallback) {
    try {let content=fs.readfile(path,65537);return content!=null && length(content)<=65536 ? json(content) : fallback;}
    catch(e){return fallback;}
}
function write_json(path,value) {
    let content=sprintf('%J\n',value);
    if (length(content)>65536) die('config_too_large');
    if (fs.readfile(path)==content) return;
    let f=fs.open(path+'.new','w',0600);
    if (!f || f.write(content)!=length(content)) die('local_write_failed');
    f.flush();f.close();fs.chmod(path+'.new',0600);
    if (!fs.rename(path+'.new',path)) die('local_rename_failed');
}
function call(object,method,args) {try{return client.call(object,method,args || {});}catch(e){return null;}}
let stored=read_json(CONFIG,null),config_error=false;
let cfg={schema_version:1,generation:0,enabled:false,mappings:[],epochs:{}};
if (fs.stat(CONFIG)) {
    try {
        if (!stored || type(stored.generation)!='int' || stored.generation<0 || (stored.epochs!=null && type(stored.epochs)!='object')) die('invalid_config');
        let clean={...stored};delete clean.epochs;
        cfg=validate_settings(clean,stored.generation);cfg.epochs=stored.epochs || {};
        for (let name in keys(cfg.epochs))
            if (!valid_name(name) || type(cfg.epochs[name])!='int' || cfg.epochs[name]<0 || cfg.epochs[name]>cfg.generation) die('invalid_activation_epoch');
    }
    catch(e){cfg={schema_version:1,generation:0,enabled:false,mappings:[],epochs:{}};config_error=true;}
}
function route(iface) {
    let net=call('network.interface.'+iface,'status',{});
    return {exists:type(net?.up)=='bool',up:net?.up===true,device:net?.l3_device,ip:net?.['ipv4-address']?.[0]?.address};
}
function tracker_running(iface) {
    let service=call('service','list',{name:'mwan3'});
    if (service?.mwan3?.instances?.['track_'+iface]?.running) return true;
    let pid=trim(fs.readfile('/var/run/mwan3track/'+iface+'/PID') || '');
    return !!match(pid,/^[0-9]+$/) && !!match(fs.readfile('/proc/'+pid+'/cmdline') || '',/mwan3track/);
}
function inventory() {
    // A new read-only cursor sees native config changes without RPC session ACLs.
    let cursor=uci.cursor(),interfaces=interface_catalog(cursor?.get_all('mwan3') || {});
    for (let target in interfaces) {
        let alias=route(target.name+'_4');
        target.network_interface=alias.exists?target.name+'_4':target.name;
        target.tracker_running=tracker_running(target.name);
        target.actual=trim(fs.readfile('/var/run/mwan3/iface_state/'+target.name) || 'unknown');
    }
    return interfaces;
}
function sources(snapshot) {
    let names=[];
    for (let c in (snapshot?.config?.connections || [])) if (index(names,c.interface)<0) push(names,c.interface);
    return names;
}
function backend_available() {return !!fs.stat('/lib/mwan3/mwan3.sh') && !!fs.stat('/lib/mwan3/mwan3-skeleton.nft') && !!fs.stat('/etc/hotplug.d/iface/25-mwan3');}
function active_rows() {return cfg.enabled?filter(cfg.mappings,(m)=>m.enabled):[];}
function tick() {
    let snapshot=fixture?read_json(fixture,null):call('campuslink','get',{});
    let valid=snapshot?.ok && type(snapshot.status)=='array' && type(snapshot.config?.connections)=='array';
    let interfaces=inventory(),plans=[],registry=[];statuses=[];
    for (let m in active_rows()) {
        let target=filter(interfaces,(t)=>t.name==m.mwan3_interface)[0];
        let actual=trim(fs.readfile('/var/run/mwan3/iface_state/'+m.mwan3_interface) || 'unknown');
        let row={source_interface:m.source_interface,mwan3_interface:m.mwan3_interface,actual,reason:'waiting_source',desired:null};
        push(statuses,row);
        if (!backend_available()) {row.reason='backend_unavailable';continue;}
        if (!target || !target.enabled || target.family!='ipv4') {row.reason='target_unavailable';continue;}
        if (!target.prepared || target.tracker_running) {row.reason='tracking_conflict';continue;}
        if (valid && index(sources(snapshot),m.source_interface)<0) {row.reason='source_removed';continue;}
        let src=route(m.source_interface),dst=route(target.network_interface);
        let previous=cache[target.name] || read_json(ROOT+'/'+target.name+'.json',null);
        if (previous && (previous.mapped_source!=m.source_interface || previous.target_network!=target.network_interface)) previous=null;
        if (!binding_allowed(m,target.network_interface,src,dst,previous)) {row.reason='binding_mismatch';continue;}
        let src_event=read_json(ROOT+'/events/'+m.source_interface+'.json',{}),dst_event=read_json(ROOT+'/events/'+target.network_interface+'.json',{});
        let event={time:max(int(src_event.time || 0),int(dst_event.time || 0)),token:'e:'+(cfg.epochs[target.name] ?? cfg.generation)+'|'+(src_event.token || '-')+'|'+(dst_event.token || '-')};
        let entries=valid?filter(snapshot.status,(s)=>s.interface==m.source_interface):[];
        let connections=valid?filter(snapshot.config.connections,(c)=>c.interface==m.source_interface && c.enabled):[];
        let entry=length(connections)==1?filter(entries,(s)=>s.id==connections[0].id)[0]:length(entries)==1?entries[0]:null;
        let next=decide(previous,entry,{...src,default_down:trim(fs.readfile('/var/run/mwan3track/'+target.name+'/ROUTE_STATUS') || '')=='down'},event,snapshot?.config?.generation);
        next.mapped_source=m.source_interface;next.target_network=target.network_interface;
        next.verified_binding=src.up && dst.up && src.device==dst.device && src.ip==dst.ip?src.device+'/'+src.ip:previous?.verified_binding;
        row.desired=next.eligible?'online':'offline';row.reason=next.reason;row.last_check=next.last_check;
        push(registry,{...m,network_interface:target.network_interface,verified_binding:next.verified_binding || ''});
        push(plans,{mapping:m,target,src,dst,entry,next,row,src_token:src_event.token || '-',dst_token:dst_event.token || '-'});
    }
    if (dry) {for (let row in statuses) print(sprintf('%J\n',row));return;}
    write_json(ROOT+'/active.json',{generation:cfg.generation,mappings:registry});
    for (let plan in plans) {
        let next=plan.next,entry=plan.entry,target=plan.target,src=plan.src;
        if (!fixture && entry && src.up && next.needs_refresh && next.floor>0 && time()>=next.floor && !next.refresh_requested && !entry.task_id && entry.state!='disabled') {
            let reply=call('campuslink','action',{id:entry.id,operation:'check'});
            if (reply?.ok) {next.refresh_requested=true;next.needs_refresh=false;}
        }
        let tracked=trim(fs.readfile('/var/run/mwan3track/'+target.name+'/STATUS') || '');
        if ((plan.row.actual!=plan.row.desired || tracked!=plan.row.desired) && fs.stat('/var/run/mwan3/iface_state')) {
            let device=plan.dst.device || '-',ip=plan.dst.ip || '-';
            if (!length(device) || length(device)>64 || match(device,/[^A-Za-z0-9_.:-]/) || !length(ip) || length(ip)>15 || match(ip,/[^0-9.-]/) ||
                !length(plan.src_token) || length(plan.src_token)>96 || match(plan.src_token,/[^A-Za-z0-9_.:-]/) ||
                !length(plan.dst_token) || length(plan.dst_token)>96 || match(plan.dst_token,/[^A-Za-z0-9_.:-]/)) {plan.row.reason='invalid_binding';continue;}
            let cmd='/usr/share/campuslink-mwan3/apply.sh '+target.name+' '+plan.row.desired+' '+plan.mapping.source_interface+' '+target.network_interface+' '+device+' '+ip+' '+plan.src_token+' '+plan.dst_token+' '+cfg.generation;
            let process=fs.popen(cmd,'r'),output=process?.read('all'),rc=process?.close();
            if (!process || rc) plan.row.reason='apply_deferred';
            else {plan.row.actual=plan.row.desired;if(output)print(trim(output)+'\n');}
        }
        cache[target.name]=next;write_json(ROOT+'/'+target.name+'.json',next);
    }
    write_json(ROOT+'/status.json',{generation:cfg.generation,status:statuses});
}
function snapshot() {
    return {ok:true,addon_version:'0.2.0',config:{schema_version:cfg.schema_version,generation:cfg.generation,enabled:cfg.enabled,mappings:cfg.mappings},config_error,interfaces:inventory(),status:statuses,
        backend:{available:backend_available(),running:!!fs.stat('/var/run/mwan3/iface_state'),name:'mwan3-nft'}};
}
if (once || dry) tick();
else {
    uloop.init();
    const object=bus.publish(OBJECT,{
        get:{args:{ubus_rpc_session:''},call:function(req){req.reply(snapshot());}},
        save:{args:{config:{},expected_generation:0,ubus_rpc_session:''},call:function(req){
            try {
                if (req.args.expected_generation!==cfg.generation) {req.reply({ok:false,reason_code:'config_changed',message:'联动配置已改变，请恢复已保存值后重试'});return;}
                let next=validate_settings(req.args.config,cfg.generation+1),campus=call('campuslink','get',{});
                if (next.enabled && length(filter(next.mappings,(m)=>m.enabled)) && (!backend_available() || !campus?.ok)) die('backend_unavailable');
                validate_selection(next,sources(campus),inventory());
                let previous=active_rows();next.epochs={};
                for (let m in (next.enabled?filter(next.mappings,(m)=>m.enabled):[]))
                    next.epochs[m.mwan3_interface]=length(filter(previous,(p)=>p.source_interface==m.source_interface && p.mwan3_interface==m.mwan3_interface))?(cfg.epochs[m.mwan3_interface] ?? cfg.generation):next.generation;
                fs.mkdir(fs.dirname(CONFIG),0700);write_json(CONFIG,next);
                // Only newly activated pairs invalidate evidence; unrelated saves do not flap.
                cfg=next;config_error=false;statuses=[];
                req.reply({ok:true,generation:cfg.generation});
            } catch(e){req.reply({ok:false,reason_code:'invalid_mapping',message:substr(e.message || '联动配置无效',0,160)});}
        }}
    });
    if (!object) die('mwan3_rpc_unavailable\n');
    let timer=uloop.interval(2000,function(){try{tick();}catch(e){print('controller iteration failed\n');}});
    tick();uloop.run();
}

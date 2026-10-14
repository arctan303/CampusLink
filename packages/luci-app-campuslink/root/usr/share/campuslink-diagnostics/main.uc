import * as fs from 'fs';
import * as ubus from 'ubus';
import {http} from '/usr/share/campuslink/transport.uc';
import {read_json,write_json,monotime} from '/usr/share/campuslink/common.uc';
import {diagnose} from './diagnostics.uc';

const ROOT=getenv('CAMPUSLINK_DIAGNOSTICS_RUNTIME') || '/var/run/campuslink-diagnostics';
if(ARGV[0]=='list') {
    print('{"get":{},"query":{"id":""}}\n');
}
else if(ARGV[0]=='call' && index(['get','query'],ARGV[1])>=0) {
    let bus=ubus.connect(),args={};
    try{args=json(fs.readfile('/dev/stdin',4096));}catch(e){}
    function call(object,method){try{return bus?.call(object,method,{});}catch(e){return null;}};
    let reply;
    try{reply=diagnose(ARGV[1],args?.id,{
        instance:trim(fs.readfile('/proc/sys/kernel/random/boot_id') || ''),now:monotime,wall:time,
        campus:()=>call('campuslink','get'),load:function(){try{return read_json(ROOT+'/state.json',null);}catch(e){return null;}},save:(v)=>write_json(ROOT+'/state.json',v),
        route:function(iface){let n=call('network.interface.'+iface,'status');return n?.up && n.l3_device && n['ipv4-address']?.[0]?.address?{device:n.l3_device,ip:n['ipv4-address'][0].address}:null;},
        http:function(route){
            let dir=fs.mkdtemp(ROOT+'/query-XXXXXX');if(!dir)return {ok:false,reason:'local_io_failed'};
            let reply;
            try{reply=http({route,workdir:dir},'https://myip.ipip.net/json',null);}
            catch(e){reply={ok:false,reason:'query_failed'};}
            for(let p in ['curl.conf','body','headers'])fs.unlink(dir+'/'+p);fs.rmdir(dir);
            return reply;
        }
    });}catch(e){reply={ok:false,reason_code:'diagnostics_failed'};}
    print(sprintf('%J\n',reply));
}
else print('{"ok":false,"reason_code":"invalid_action"}\n');

import {public_ipv4,diagnose} from '../packages/luci-app-campuslink/root/usr/share/campuslink-diagnostics/diagnostics.uc';
let count=0;
function check(v,m){count++;if(!v)die(m+'\n');};
for(let ip in ['8.8.8.8','183.1.2.3'])check(public_ipv4(ip),'public IPv4 accepted');
for(let ip in ['10.1.1.1','172.16.0.1','192.168.0.1','100.64.1.1','127.0.0.1','169.254.1.1','198.18.0.1','203.0.113.1','224.0.0.1','1.2.3.256','1.2.3.04','1.2.3.4\n','::1','<html>'])check(!public_ipv4(ip),'private/invalid IPv4 rejected');
let clock=100,store=null,calls=0,changed=false,configChanged=false;
let route={device:'vwan1',ip:'172.21.106.2'};
let campus={ok:true,config:{generation:3,connections:[{id:'c',interface:'campus_a'}]}};
let response={ok:true,code:200,body:'{"ret":"ok","data":{"ip":"183.1.2.3"}}'};
let io={instance:'test-boot',now:()=>clock,wall:()=>100000+clock,
    campus:()=>configChanged?{...campus,config:{...campus.config,generation:4}}:campus,
    route:()=>route,load:()=>store,save:(v)=>{store=json(sprintf('%J',v));},
    http:function(r){calls++;check(r.device=='vwan1' && r.ip=='172.21.106.2','selected route reaches transport');if(changed)route={...route,ip:'172.21.106.3'};return response;}};
let r=diagnose('get','',io);check(!r.entries[0].public_ipv4 && calls==0,'get never probes');
check(diagnose('query','missing',io).reason_code=='invalid_interface','unknown id cannot query');
r=diagnose('query','c',io);check(r.query_ok && r.entries[0].public_ipv4=='183.1.2.3','successful public IP');
let revision=r.revision;
r=diagnose('query','c',io);check(r.cached && calls==1 && r.revision==revision,'cooldown reuses cache');
clock=401;r=diagnose('get','',io);check(r.entries[0].stale && calls==1,'TTL only marks stale');
response={ok:false,reason:'timeout'};r=diagnose('query','c',io);
check(!r.query_ok && r.entries[0].public_ipv4=='183.1.2.3' && r.entries[0].error=='timeout','failure keeps explicitly old result');
clock=462;response={ok:true,code:200,body:'<html>portal</html>'};r=diagnose('query','c',io);check(!r.query_ok,'portal is not a public IP');
clock=523;response={ok:true,code:200,body:'{"ret":"ok","data":{"ip":"172.21.106.3"}}'};r=diagnose('query','c',io);check(!r.query_ok,'private service response rejected');
clock=584;response={ok:true,code:200,body:'{"ret":"ok","data":{"ip":"183.1.2.4"}}'};changed=true;
r=diagnose('query','c',io);check(!r.ok && r.reason_code=='binding_changed' && !r.entries[0].public_ipv4,'late result after route change discarded');
route=null;r=diagnose('query','c',io);check(r.reason_code=='interface_unavailable','missing lease cannot fall back');
route={device:'vwan1',ip:'172.21.106.2'};changed=false;configChanged=false;
io.http=function(){configChanged=true;return response;};r=diagnose('query','c',io);check(!r.ok && r.reason_code=='binding_changed','config race discarded');
print('PASS: '+count+' native public IP behavior checks\n');

// Run on an installed router. Temporary sessions only, no credential files.
import * as fs from 'fs';
import * as ubus from 'ubus';
let bus=ubus.connect(), dir=fs.mkdtemp('/tmp/cl-acl-XXXXXX');
fs.chmod(dir,0700);
function call(sid,method,args){
    let payload={jsonrpc:'2.0',id:1,method:'call',params:[sid,'campuslink',method,args || {}]};
    fs.writefile(dir+'/request',sprintf('%J',payload));fs.chmod(dir+'/request',0600);
    let p=fs.popen('exec curl -q -s --noproxy "*" --max-time 5 -H "Content-Type: application/json" --data-binary @'+dir+'/request http://127.0.0.1/ubus','r');
    let text=p.read('all'),rc=p.close();if(rc)die('http_rpc_failed');let frame=json(text);return frame.result || [frame.error?.code];
}
let sid=bus.call('session','create',{timeout:60}).ubus_rpc_session;
bus.call('session','grant',{ubus_rpc_session:sid,scope:'ubus',objects:[['campuslink','get']]});
let read=call(sid,'get',{});
if(read[0]!==0 || !read[1].config)die('read_acl_failed');
for(let a in read[1].config.accounts)if(a.values.password!=null)die('password_exposed');
let write=call(sid,'save',{config:{},expected_generation:0});
let action=call(sid,'action',{id:'nonexistent',operation:'disable'});
let anon=call('00000000000000000000000000000000','get',{});
print(sprintf('%J\n',{read:read[0],write:write[0],action:action[0],anonymous:anon[0]}));
for(let denied in [write,action,anon])if(index([6,-32002],denied[0])<0)die('acl_denial_failed');
bus.call('session','destroy',{ubus_rpc_session:sid});
fs.unlink(dir+'/request');fs.rmdir(dir);
print('PASS: HTTP ubus read-only get allowed without password; save/action denied; unauthenticated get denied\n');

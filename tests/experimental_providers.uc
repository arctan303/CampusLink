import * as fs from 'fs';
import * as srun from '../packages/campuslink/files/usr/share/campuslink/providers/srun-srbx1.uc';
import * as ruijie from '../packages/campuslink/files/usr/share/campuslink/providers/ruijie-eportal.uc';
import * as drcom from '../packages/campuslink/files/usr/share/campuslink/providers/drcom-http.uc';
import { handlers } from '../packages/campuslink/files/usr/share/campuslink/providers/registry.uc';
import { md5, hex, sha1, hmac_md5 } from '../packages/campuslink/files/usr/share/campuslink/providers/srun-crypto.uc';
import { request_options } from '../packages/campuslink/files/usr/share/campuslink/transport.uc';
import { rsa_encrypt } from '../packages/campuslink/files/usr/share/campuslink/providers/ruijie-rsa.uc';
import { percent_encode } from '../packages/campuslink/files/usr/share/campuslink/providers/portal-common.uc';
import { validate_provider, merge_params, validate_config, read_json } from '../packages/campuslink/files/usr/share/campuslink/common.uc';

let count=0;
function assert(ok,label) { if (!ok) die('FAIL: '+label+'\n');count++; }
function reject(fn,label) { let failed=false;try { fn(); } catch(e) { failed=true; }assert(failed,label); }
function repeated(text,n) { let out='';while(n-->0)out+=text;return out; }
let vectors=read_json('/workspace/tests/fixtures/srun-vectors.json');
for (let v in vectors.hashes) { assert(hex(md5(v.text))==v.md5,'MD5 vector');assert(sha1(v.text)==v.sha1,'SHA1 vector'); }
for (let v in vectors.hmacs) assert(hmac_md5(v.key,v.text)==v.expected,'HMAC vector');
function context(responses) {
    return {account:{values:{username:'fixture-user',password:'fixture-pass'}},params:{server_url:'http://portal.example:8080',probe_url:'http://probe.example/generate_204',ac_id:12,hmac_mode:'password'},route:{device:'wan-test',ip:'192.0.2.123'},workdir:'/tmp/cl-provider',_responses:responses || [],_requests:[]};
}
function reply(url,body,code) { return {url,reply:{body,code:code || 200}}; }
let base='http://portal.example:8080',probe='http://probe.example/generate_204';
for (let v in vectors.requests) {
    let ctx=context();ctx.account.values={username:v.username,password:v.password};ctx.params.hmac_mode=v.mode;
    let params=srun.login_params(ctx,v.token);
    assert(params.info==v.info,'SRBX1 independent ciphertext');
    assert(params.password==v.digest,'SRBX1 HMAC variant');
    assert(params.chksum==v.chksum,'SRBX1 independent checksum');
}
let providers={};
for (let id in keys(handlers)) {
    let p=read_json('/workspace/packages/campuslink/files/usr/share/campuslink/providers/'+id+'.json');
    providers[id]=validate_provider(p,handlers[id]);
    assert(p.id==id,'registry metadata');
}
for (let id in ['srun-srbx1','ruijie-eportal']) {
    let params={server_url:base+'/'};if(id=='srun-srbx1')params.ac_id=12;
    assert(merge_params(providers[id],null,params,handlers[id].resolve_params).server_url==base,'origin normalization');
    for (let url in ['http://user:pass@host','http://host/path','http://host?x=y','ftp://host','http://host:0','http://host:65536','http://host/#x','http://host\nheader:x'])
        reject(()=>handlers[id].resolve_params({server_url:url}),'unsafe origin rejected');
    let cfg={schema_version:2,settings:{provider:id,school:'',params,check_interval:60,retry_interval:30,retry_max:600},accounts:[{id:'a',label:'Fixture',credential_type:'username_password',values:{username:'fixture-user',password:'fixture-pass'}}],connections:[{id:'c',label:'Fixture',account:'a',interface:'wan1',params:{},enabled:false,auto_login:false}]};
    assert(validate_config(cfg,{generation:0,accounts:[]},providers,{},handlers).connections[0].enabled===false,'new provider configuration');
}
let ctx=context([reply(probe,'',204)]);assert(srun.check(ctx).outcome=='online','Srun online probe');
ctx=context([reply(probe,'<html>unrelated</html>'),reply(base+'/cgi-bin/rad_user_info','campuslink({"error":"not_online_error"});')]);
assert(srun.check(ctx).outcome=='unauthenticated','Srun explicit offline');
for (let body in ['{"error":"ok"}','{"error":"unknown"}','evil({"error":"not_online_error"})','[1,2]','<html>offline</html>']) {
    ctx=context([reply(probe,''),reply(base+'/cgi-bin/rad_user_info',body)]);assert(srun.check(ctx).outcome=='indeterminate','Srun unknown cannot authenticate');
}
for (let data in [{error:'ok'}, {error:'ok',challenge:'short'}, {error:'ok',challenge:vectors.requests[0].token+'\n'}, {error:'ok',challenge:vectors.requests[0].token,client_ip:'192.0.2.124'}, {error:'failed',challenge:vectors.requests[0].token}]) {
    ctx=context([reply(base+'/cgi-bin/get_challenge',sprintf('%J',data))]);assert(srun.login(ctx).outcome=='indeterminate' && length(ctx._requests)==1,'invalid challenge sends no login');
}
ctx=context([reply(base+'/cgi-bin/get_challenge',sprintf('%J',{error:'ok',challenge:vectors.requests[0].token,client_ip:'192.0.2.123'})),reply(base+'/cgi-bin/srun_portal','{"error":"ok"}')]);
assert(srun.login(ctx).outcome=='accepted' && length(ctx._responses)==0,'Srun challenge then login');
assert(ctx._requests[1].params.ip==ctx.route.ip && ctx._requests[1].params.info==vectors.requests[0].info,'Srun bound address and ciphertext');
for (let pair in [['{"error":"ok"}','accepted'],['{"error":"password_error"}','rejected'],['{"error":"speed_limit_error"}','rate_limited'],['{"error":"E9999","message":"fixture-pass TOKEN"}','indeterminate']])
    assert(srun.response_result({ok:true,code:200,body:pair[0]}).outcome==pair[1],'Srun response classification');
let redirect={ok:true,code:302,headers:'HTTP/1.1 302 Found\r\nLocation: '+base+'/eportal/index.jsp?wlanuserip=192.0.2.123&wlanacname=AC%26X&mac=aabb\r\n',body:''};
ctx=context([{url:probe,reply:redirect}]);assert(ruijie.check(ctx).outcome=='unauthenticated','Ruijie explicit portal redirect');
ctx=context([{url:probe,reply:redirect},{url:base+'/eportal/InterFace.do?method=login',method:'POST',reply:{body:'{"result":"success","userIndex":"SECRET"}'}}]);
assert(ruijie.login(ctx).outcome=='accepted','Ruijie current redirect then form');
assert(ctx._requests[1].params.queryString=='wlanuserip=192.0.2.123&wlanacname=AC%26X&mac=aabb' && ctx._requests[1].params.passwordEncrypt==='false','opaque query and explicit variant');
for (let headers in ['Location: http://attacker.example/eportal/index.jsp?wlanuserip=192.0.2.123','Location: '+base+'.attacker.example/eportal/index.jsp?wlanuserip=x','Location: '+base+'/other?wlanuserip=x','Location: '+base+'/eportal/index.jsp?wlanuserip=192.0.2.124','Location: '+base+'/eportal/index.jsp?wlanuserip=x#fragment']) {
    ctx=context([{url:probe,reply:{...redirect,headers}}]);assert(ruijie.login(ctx).outcome=='indeterminate' && length(ctx._requests)==1,'unsafe redirect sends no password');
}
ctx=context([reply(probe,'unrelated',200)]);assert(ruijie.check(ctx).outcome=='indeterminate','Ruijie unknown 200');
for (let pair in [['{"result":"success"}','accepted'],['{"result":"wait"}','indeterminate'],['{"result":"fail","message":"密码错误"}','rejected'],['{"result":"fail","message":"登录密码必须加密"}','rejected'],['{"result":"fail","message":"验证码错误"}','rejected'],['{"result":"fail","message":"操作频繁"}','rate_limited'],['{"result":"mystery","message":"fixture-pass TOKEN"}','indeterminate']]) {
    let r=ruijie.response_result({ok:true,code:200,body:pair[0]});
    assert(r.outcome==pair[1] && !match(r.message,/fixture-pass|TOKEN/),'Ruijie classification and no response secrets');
}
assert(ruijie.response_result({ok:true,code:500,body:'{"result":"success"}'}).outcome=='indeterminate','HTTP error never accepted');
assert(srun.response_result({ok:false,reason:'timeout'}).reason_code=='timeout','timeout preserved');
for (let pair in [['E2531','rejected'],['E2553','rejected'],['E2532','rate_limited'],['E2533','rate_limited'],['E9999','indeterminate']]) {
    let r=srun.response_result({ok:true,code:200,body:sprintf('%J',{error:'login_error',ecode:pair[0],error_msg:'fixture-pass TOKEN'})});
    assert(r.outcome==pair[1] && !match(r.message,/fixture-pass|TOKEN/),'known ecode whitelist');
    if(r.outcome=='rate_limited')assert(r.retry_after_s==90,'ecode cooldown');
}
assert(ruijie.response_result({ok:true,code:200,body:'{"result":"fail","message":"密码不匹配,请输入正确的密码!"}'}).reason_code=='invalid_credentials','real Ruijie password mismatch');
for (let query in ['wlanuserip=192.0.2.123&wlanuserip=192.0.2.124','wlanuserip=192.0.2.123&WLANUSERIP=192.0.2.124','wlanuserip=192.0.2.123&%77lanuserip=192.0.2.124','wlanuserip=192.0.2.123&wlanuserip=192.0.2.123','wlanuserip=%31%39%32.0.2.124']) {
    ctx=context([{url:probe,reply:{...redirect,headers:'Location: '+base+'/eportal/index.jsp?'+query}}]);
    assert(ruijie.login(ctx).outcome=='indeterminate' && length(ctx._requests)==1,'ambiguous/encoded IP sends no password');
}
let encoded_query='%77lanuserip=%31%39%32.0.2.123&mac=opaque';
assert(ruijie.portal_query({...redirect,headers:'Location: '+base+'/eportal/index.jsp?'+encoded_query},context())==encoded_query,'single encoded matching IP remains opaque on wire');
assert(drcom.response_result({ok:true,code:200,body:'dr1003({"result":1});'},context(),'login').outcome=='accepted','Drcom classification preserved');
ctx=context([reply(base+'/login','{"result":1}')]);ctx.params.auth_url=base+'/login';ctx.params.terminal_mode='mobile';
assert(drcom.login(ctx).outcome=='accepted' && ctx._requests[0].method=='GET' && ctx._requests[0].params.user_account==',1,fixture-user','Drcom login stays GET');
// Incremental variants: behavior, request sequence and credential omission.
let rsa=read_json('/workspace/tests/fixtures/rsa-vectors.json');
for(let v in rsa)assert(rsa_encrypt(v.password,v.mac,v.exponent,v.modulus)==v.expected,'RSA independent pow oracle');
let v=rsa[0];
assert(rsa_encrypt(v.password,v.mac,'00010001',v.modulus)==rsa_encrypt(v.password,v.mac,'10001',v.modulus),'exponent leading zeros');
assert(rsa_encrypt(v.password,v.mac,v.exponent,'00'+v.modulus)==v.expected,'modulus sign padding');
for(let pair in [['1',v.modulus],['100000001',v.modulus],['10001',repeated('f',254)+'fe'],['10001','7'+substr(v.modulus,1)],['10001',v.modulus+'00'],['10001',v.modulus+'\n'],['10001','bad']])
    reject(()=>rsa_encrypt(v.password,v.mac,pair[0],pair[1]),'invalid RSA key');
for(let pair in [['','mac'],['测试','mac'],['p',''],['p','mac\n'],[repeated('x',114),'aabbccddeeff']])
    reject(()=>rsa_encrypt(pair[0],pair[1],v.exponent,v.modulus),'unsupported RSA input lengths '+length(pair[0])+','+length(pair[1]));
assert(rsa_encrypt(repeated('x',113),'aabbccddeeff',v.exponent,v.modulus)!=null,'RSA exact block boundary');
let acid_reply={ok:true,code:302,headers:'Location: '+base+'/srun_portal_pc?ac_id=78'};
assert(srun.discover_ac_id(acid_reply,base)==78,'same-origin Location AC ID');
let srun_script='<script>window.location.href="/srun_portal_pc?ac_id=78";</script>';
assert(srun.discover_ac_id({ok:true,code:200,body:srun_script},base)==null,'Srun JS is outside discovery contract');
ctx=context([reply(base+'/',srun_script)]);ctx.params.ac_id='';
assert(srun.login(ctx).reason_code=='ac_id_unavailable' && length(ctx._requests)==1,'Srun JS sends no challenge or login');
for(let ecode in ['E2553','E9999',false,[],{}]) {
    ctx=context([reply(probe,''),reply(base+'/cgi-bin/rad_user_info',sprintf('%J',{error:'not_online_error',ecode}))]);
    assert(srun.check(ctx).outcome=='indeterminate','contradictory ecode cannot open authentication');
}
for(let ecode in [null,'',0,'0']) {
    ctx=context([reply(probe,''),reply(base+'/cgi-bin/rad_user_info',sprintf('%J',{res:'not_online_error',ecode}))]);
    assert(srun.check(ctx).outcome=='unauthenticated','known offline with absent/zero code');
}
assert(srun.discover_ac_id({ok:true,code:200,body:'<html><meta http-equiv="refresh" content="0;url=/index_1.html?ac_id=12&amp;foo=x"></html>'},base)==12,'meta AC ID');
for(let target in ['http://evil.example/srun_portal_pc?ac_id=1','//evil.example/srun_portal_pc?ac_id=1','/srun_portal_pc?ac_id=1&AC_ID=2','/srun_portal_pc?ac_id=1&%61c_id=2','/other?ac_id=1','/srun_portal_pc?ac_id=0','/srun_portal_pc?ac_id=65536','/srun_portal_pc?ac_id=1#x'])
    assert(srun.discover_ac_id({...acid_reply,headers:'Location: '+target},base)==null,'untrusted AC ID rejected');
assert(srun.discover_ac_id({...acid_reply,headers:acid_reply.headers+'\n'+acid_reply.headers},base)==null,'duplicate Location rejected');
for(let data in [{res:'ok',challenge:vectors.requests[0].token},{challenge:vectors.requests[0].token,client_ip:'192.0.2.123'},{error:'',res:'',challenge:vectors.requests[0].token,online_ip:'192.0.2.123'}]) {
    ctx=context([reply(base+'/', '',302),reply(base+'/cgi-bin/get_challenge',sprintf('%J',data)),reply(base+'/cgi-bin/srun_portal','{"res":"ok"}')]);
    ctx._responses[0].reply.headers=acid_reply.headers;ctx.params.ac_id='';
    assert(srun.login(ctx).outcome=='accepted' && ctx._requests[2].params.ac_id==='78','discover AC ID with challenge variants');
}
for(let data in [{error:false},{error:0},{res:[]},{error:'ok',res:'failed'},{ecode:'E2553'},{}]) {
    let challenge={challenge:vectors.requests[0].token,client_ip:'192.0.2.123',...data};
    // Empty status is accepted only with explicit matching IP; the final case removes it.
    if(!length(keys(data)))delete challenge.client_ip;
    ctx=context([reply(base+'/cgi-bin/get_challenge',sprintf('%J',challenge))]);
    assert(srun.login(ctx).outcome=='indeterminate' && length(ctx._requests)==1,'negative/ambiguous challenge no credentials');
}
ctx=context([reply(base+'/','unrelated')]);ctx.params.ac_id='';
assert(srun.login(ctx).reason_code=='ac_id_unavailable' && length(ctx._requests)==1,'no guessed AC ID');
for(let data in [{error:'ok',res:'failed'},{res:'ok',ecode:'E2553'},{res:false}])
    assert(srun.response_result({ok:true,code:200,body:sprintf('%J',data)}).outcome=='indeterminate','conflict/negative status not accepted');
assert(srun.response_result({ok:true,code:200,body:'{"res":"password_error"}'}).outcome=='rejected','res rejection');
let rsa_query='wlanuserip=192.0.2.123&mac='+v.mac+'&wlanacname=AC%26X';
let rsa_redirect={...redirect,headers:'Location: '+base+'/eportal/index.jsp?'+rsa_query};
let key_reply={url:base+'/eportal/InterFace.do?method=pageInfo',method:'POST',params:{queryString:rsa_query},reply:{body:sprintf('%J',{publicKeyExponent:v.exponent,publicKeyModulus:v.modulus})}};
for(let encoding in ['auto','single','double']) {
    ctx=context([{url:probe,reply:rsa_redirect},key_reply,{url:base+'/eportal/InterFace.do?method=login',method:'POST',reply:{body:'{"result":"success"}'}}]);
    ctx.params.password_mode='rsa';ctx.params.form_encoding=encoding;ctx.params.service='校园网 &+';
    assert(ruijie.login(ctx).outcome=='accepted','RSA portal flow');
    let params=ctx._requests[2].params;
    assert(params.password===v.expected && params.passwordEncrypt==='true','RSA ciphertext only');
    assert(params.queryString===(encoding=='single' ? rsa_query : percent_encode(rsa_query)),'explicit RSA query encoding');
    assert(params.service===(encoding=='single' ? '校园网 &+' : percent_encode('校园网 &+')),'UTF8 encoding variant');
    assert(index(sprintf('%J',ctx._requests[1]),'fixture-pass')<0,'pageInfo has no password');
}
for(let data in [{},{result:'fail',message:'captcha'},{publicKeyExponent:'1',publicKeyModulus:v.modulus},{publicKeyExponent:v.exponent,publicKeyModulus:'bad'},{publicKeyExponent:v.exponent,publicKeyModulus:v.modulus,validCodeUrl:'/eportal/validcode'}]) {
    ctx=context([{url:probe,reply:rsa_redirect},{...key_reply,reply:{body:sprintf('%J',data)}}]);ctx.params.password_mode='rsa';
    assert(ruijie.login(ctx).outcome=='rejected' && length(ctx._requests)==2,'invalid key never plaintext fallback');
}
for(let query in ['wlanuserip=192.0.2.123','wlanuserip=192.0.2.123&mac=a&MAC=b','wlanuserip=192.0.2.123&mac=a&%6dac=b','wlanuserip=192.0.2.123&mac=%0a']) {
    ctx=context([{url:probe,reply:{...rsa_redirect,headers:'Location: '+base+'/eportal/index.jsp?'+query}}]);ctx.params.password_mode='rsa';
    assert(ruijie.login(ctx).outcome=='rejected' && length(ctx._requests)==1,'missing/ambiguous MAC no key/login');
}
let script='<script>top.self.location.href="'+base+'/eportal/index.jsp?'+rsa_query+'";</script>';
assert(ruijie.portal_query({ok:true,code:200,body:script},context())==rsa_query,'restricted literal JS portal');
for(let body in [script+'<script>evil()</script>',replace(script,';</script>',';evil()</script>'),'<script>window.location.href="http://evil.example/eportal/index.jsp?'+rsa_query+'";</script>'])
    assert(ruijie.portal_query({ok:true,code:200,body},context())==null,'arbitrary JS rejected');
let configs={};
ctx=context();
for (let method in ['GET','POST']) {
    let options=request_options(ctx,'http://127.0.0.1:18080/form',{userId:'u&=+%/测试',password:'p"\\&=+%',queryString:'wlanuserip=192.0.2.123&x=AC%26X'},method);
    assert(index(options,'interface = "ifhost!wan-test!192.0.2.123"')>=0,'interface/source binding retained');
    assert(index(options,'proxy = ""')>=0 && index(options,'globoff')>=0 && index(options,'max-redirs = 0')>=0,'transport safety options retained');
    assert((index(options,'\nget\n')>=0)==(method=='GET'),'GET and POST method separation');
    configs[method]=options;
}
ctx=context();
configs.DOUBLE=request_options(ctx,'http://127.0.0.1:18080/form',{userId:percent_encode('u&=+%/测试'),password:rsa[0].expected,queryString:percent_encode(rsa_query)},'POST');
reject(()=>request_options(ctx,base,{},'PUT'),'unsupported method');
reject(()=>request_options(ctx,base,{'bad\nheader':'value'},'POST'),'parameter name injection');
print(sprintf('%J\n',{passed:count,curl_configs:configs}));

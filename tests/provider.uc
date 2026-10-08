import {parse_response,response_result} from '../packages/campuslink/files/usr/share/campuslink/providers/drcom-http.uc';
import * as mock from '../packages/campuslink/files/usr/share/campuslink/providers/mock.uc';
import {clean_message,field_value,validate_provider,validate_school,validate_result,validate_config,read_json,write_json} from '../packages/campuslink/files/usr/share/campuslink/common.uc';
import * as fs from 'fs';

let cases=[
    ['dr1003({"result":1,"msg":"ok"});',1],
    ['dr1003( {"result": "1"} );','1'],
    ['{"result":10}',10],
    ['{"result":0,"success":false}',0],
    ['evil({"result":1});',null],
    ['<html>success</html>',null]
];
for(let c in cases){let r=parse_response(c[0]);if((r?.result ?? null)!==c[1])die('parse_fixture_failed\n');}
if(clean_message('fake-user: fake-pass',{username:'fake-user',password:'fake-pass'})!='[已隐藏]: [已隐藏]')die('redaction_failed\n');
field_value({id:'url',type:'url',required:true},'http://1.1.1.1:801/eportal/portal/login');
let rejected=false;try{field_value({id:'url',type:'url',required:true},'http://user:pass@example.com/');}catch(e){rejected=true;}
if(!rejected)die('userinfo_allowed\n');
let ctx={account:{values:{username:'fake-user',password:'fake-pass'}}};
for(let c in [['{"result":10}','indeterminate'],['{"msg":"maintenance"}','indeterminate'],['{"result":0,"msg":"password incorrect"}','rejected'],['{"result":0,"msg":"interval is too short"}','rate_limited'],['{"result":1}','accepted']]){
    let r=response_result({ok:true,body:c[0]},ctx,'login');if(r.outcome!=c[1])die('classification_failed');
}
let base=ARGV[0] || '/tmp/cl-test/metadata-fixture';
let p=json(fs.readfile(base+'/mock.json'));validate_provider(p,mock);
let school={schema_version:1,id:'fixture',label:'Fixture',provider:'mock',defaults:{scenario:'online'},verification_status:'unverified'};
validate_school(school,{mock:p});
function must_reject(fn){let invalid=false;try{fn();}catch(e){invalid=true;}if(!invalid)die('invalid_contract_accepted');}
let bad=json(sprintf('%J',p));push(bad.connection_fields,bad.connection_fields[0]);must_reject(()=>validate_provider(bad,mock));
bad=json(sprintf('%J',p));bad.connection_fields[0].default='nonexistent';must_reject(()=>validate_provider(bad,mock));
bad=json(sprintf('%J',school));bad.defaults.password='forbidden';must_reject(()=>validate_school(bad,{mock:p}));
bad=json(sprintf('%J',school));bad.verification_status='verified';must_reject(()=>validate_school(bad,{mock:p}));
for(let r in [{outcome:'accepted',reason_code:'ok',message:'ok'},{outcome:'online',reason_code:'ok',message:'ok',retry_after_s:1.5},{outcome:'online',reason_code:'ok',message:'ok',retry_after_s:86401}])if(validate_result(r,'check',{}).reason_code!='provider_contract_error')die('invalid_result_accepted');
let rr=validate_result({outcome:'online',reason_code:'ok',message:'fake-pass'},'check',ctx.account.values);if(rr.message!='[已隐藏]')die('result_redaction_failed');

// A valid near-limit configuration roundtrips; oversized validation and write
// both reject it without damaging the previous file.
function repeat(s,n){let value='';for(let i=0;i<n;i++)value+=s;return value;}
let large={schema_version:1,accounts:[],connections:[]};
for(let i=0;i<64;i++)push(large.accounts,{id:'a'+i,label:'Fixture',credential_type:'username_password',values:{username:repeat('u',900),password:repeat('p',900)}});
let dp=json(fs.readfile(base+'/drcom-http.json'));
for(let i=0;i<32;i++)push(large.connections,{id:'c'+i,label:'Fixture',interface:'wan'+i,provider:'drcom-http',school:'',account:'a0',params:{auth_url:'http://host/'+repeat('a',900),status_url:'http://host/'+repeat('a',900),logout_url:'http://host/'+repeat('a',900),probe_url:'http://host/'+repeat('a',900),terminal_mode:'pc'},enabled:false,auto_login:false});
let valid=validate_config(large,{generation:0,accounts:[]},{'drcom-http':dp},{});
let path=fs.dirname(base)+'/size-fixture.json';write_json(path,valid);if(length(read_json(path).accounts)!=64)die('roundtrip_failed');
for(let a in large.accounts){a.values.username+=repeat('u',124);a.values.password+=repeat('p',124);a.label=repeat('l',128);}
for(let c in large.connections){for(let k in ['auth_url','status_url','logout_url','probe_url'])c.params[k]+=repeat('a',1024-length(c.params[k]));c.label=repeat('l',128);}
must_reject(()=>validate_config(large,{generation:0,accounts:[]},{'drcom-http':dp},{}));
must_reject(()=>write_json(path,large));if(read_json(path).generation!=valid.generation)die('old_config_damaged');fs.unlink(path);
print('PASS: protocol classification, metadata and result contracts, redaction, URL and size roundtrip/rejection\n');

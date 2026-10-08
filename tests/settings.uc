import {read_json,validate_config,upgrade_config,effective_connection,merge_params,public_config} from '../packages/campuslink/files/usr/share/campuslink/common.uc';
import * as drcom from '../packages/campuslink/files/usr/share/campuslink/providers/drcom-http.uc';
import * as mock from '../packages/campuslink/files/usr/share/campuslink/providers/mock.uc';
let base=ARGV[0],p=read_json(base+'/providers/drcom-http.json'),m=read_json(base+'/providers/mock.json'),school=read_json(base+'/schools/local-campus.json');
let providers={'drcom-http':p,mock:m},schools={'local-campus':school},handlers={'drcom-http':drcom,mock};
function clone(v){return json(sprintf('%J',v));}
function reject(fn){let failed=false;try{fn();}catch(e){failed=true;}if(!failed)die('invalid_settings_accepted');}
let legacy={schema_version:1,generation:9,accounts:[{id:'a',label:'Fake account',credential_type:'username_password',values:{username:'fake-user',password:'fake-password'}}],connections:[]};
for(let i=0;i<2;i++)push(legacy.connections,{id:'c'+i,label:'Fake WAN',interface:'wan'+(i+1),provider:'drcom-http',school:'local-campus',account:'a',params:{terminal_mode:i?'mobile':'pc'},enabled:true,auto_login:true,check_interval:60,retry_interval:30,retry_max:600});
let old=validate_config(legacy,{generation:8,accounts:[]},providers,schools,handlers),unchanged=sprintf('%J',old);
let next=upgrade_config(old,providers,schools,handlers);
if(next.schema_version!=2 || next.generation!=9 || next.settings.provider!='drcom-http' || next.connections[1].params.terminal_mode!='mobile' || sprintf('%J',old)!=unchanged)die('migration_failed');
for(let i=0;i<2;i++){
 let before=old.connections[i],after=effective_connection(next,next.connections[i]);
 if(after.interface!=before.interface || after.account!=before.account || after.check_interval!=60)die('binding_changed');
 let a=merge_params(p,school,before.params,drcom.resolve_params),b=merge_params(p,school,after.params,drcom.resolve_params);
 if(sprintf('%J',a)!=sprintf('%J',b))die('effective_params_changed');
}
for(let variant in ['server','period','provider']){
 let mixed=clone(old);
 if(variant=='server')mixed.connections[1].params.auth_server='2.2.2.2';
 if(variant=='period')mixed.connections[1].check_interval=120;
 if(variant=='provider'){mixed.connections[1].provider='mock';mixed.connections[1].school='';mixed.connections[1].params={scenario:'online'};}
 if(upgrade_config(mixed,providers,schools,handlers).schema_version!=1)die('mixed_configuration_migrated');
}
let shared=public_config(next);shared.settings.params.auth_server='2.2.2.2';shared.settings.check_interval=120;
let saved=validate_config(shared,next,providers,schools,handlers);
if(saved.accounts[0].values.password!='fake-password' || saved.generation!=10)die('password_or_generation_changed');
for(let c in saved.connections){let effective=effective_connection(saved,c);if(effective.check_interval!=120 || merge_params(p,school,effective.params,drcom.resolve_params).auth_url!='http://2.2.2.2:801/eportal/portal/login')die('global_setting_not_applied');}
for(let test in ['line_server','line_provider','local_null','global_mode','global_unknown','invalid_server','invalid_interval','downgrade']){
 let bad=clone(shared);
 if(test=='line_server')bad.connections[0].params.auth_server='3.3.3.3';
 if(test=='line_provider')bad.connections[0].provider='mock';
 if(test=='local_null')bad.connections[0].params=null;
 if(test=='global_mode')bad.settings.params.terminal_mode='mobile';
 if(test=='global_unknown')bad.settings.extra=true;
 if(test=='invalid_server')bad.settings.params.auth_server='bad/path';
 if(test=='invalid_interval')bad.settings.retry_max=20;
 if(test=='downgrade')bad=clone(old);
 reject(()=>validate_config(bad,next,providers,schools,handlers));
 if(next.generation!=9 || next.accounts[0].values.password!='fake-password')die('failed_save_mutated_original');
}
// A required per-line field without a default must not block global settings alone.
let custom=clone(p);delete custom.connection_fields[-1].default;
let empty=clone(shared);empty.settings.school='';empty.connections=[];
validate_config(empty,next,{'drcom-http':custom},schools,handlers);
print('PASS: uniform migration, mixed legacy preservation, global fan-out, scopes, password/conflict source, rejected downgrade and per-line required field\n');

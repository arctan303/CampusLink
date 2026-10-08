import {merge_params,validate_provider,validate_config} from '../packages/campuslink/files/usr/share/campuslink/common.uc';
import * as drcom from '../packages/campuslink/files/usr/share/campuslink/providers/drcom-http.uc';
import * as fs from 'fs';

let path = ARGV[0];
let provider = json(fs.readfile(path+'/providers/drcom-http.json'));
let school = json(fs.readfile(path+'/schools/local-campus.json'));
validate_provider(provider,drcom);
function merged(s,overrides){return merge_params(provider,s,overrides,drcom.resolve_params);}
function rejected(fn){let failed=false;try{fn();}catch(e){failed=true;}if(!failed)die('invalid_params_accepted');}
let p=merged(school,{});
if(p.auth_url!='http://1.1.1.1:801/eportal/portal/login' || p.status_url!='http://1.1.1.1/')die('preset_derivation_failed');
p=merged(school,{auth_server:'2.2.2.2'});
if(p.auth_url!='http://2.2.2.2:801/eportal/portal/login' || p.status_url!='http://2.2.2.2/' || p.logout_url!='http://2.2.2.2:801/eportal/portal/logout')die('server_propagation_failed');
let legacy={auth_url:'https://legacy.example:8443/custom',status_url:'https://legacy.example/status',terminal_mode:'mobile'};
p=merged(null,legacy);
if(p.auth_url!=legacy.auth_url || p.status_url!=legacy.status_url || !p.probe_url)die('legacy_urls_changed');
p=merged(school,{auth_server:'2.2.2.2',auth_url:legacy.auth_url,status_url:legacy.status_url});
if(p.auth_url!=legacy.auth_url || p.status_url!=legacy.status_url)die('custom_override_lost');
let old_school={defaults:{auth_url:'http://old.example:801/eportal/portal/login',status_url:'http://old.example/',logout_url:'http://old.example:801/eportal/portal/logout'}};
p=merged(old_school,{});
if(p.auth_server!='old.example' || p.auth_url!=old_school.defaults.auth_url)die('old_school_resolution_failed');
p=merged(old_school,{auth_server:'new.example'});
if(p.auth_url!='http://new.example:801/eportal/portal/login' || p.status_url!='http://new.example/')die('old_school_server_override_failed');
p=merged(old_school,{auth_server:'new.example',auth_url:legacy.auth_url});
if(p.auth_url!=legacy.auth_url || p.status_url!='http://new.example/')die('explicit_url_precedence_failed');
for(let server in ['user@host','http://host','host/path','host:801','a..b','x\n'])rejected(()=>merged(school,{auth_server:server}));
rejected(()=>merged(null,{}));
// No unused logout input is required for old or manual configuration.
merged(null,{auth_server:'auth.example'});
let old={generation:2,accounts:[{id:'a',values:{password:'fake-existing-pass'}}]};
let cfg={schema_version:1,accounts:[{id:'a',label:'A',credential_type:'username_password',values:{username:'fake-user'}}],connections:[{id:'c',label:'WAN',interface:'wan1',provider:'drcom-http',school:'',account:'a',params:{auth_server:'2.2.2.2'},enabled:false,auto_login:false}]};
let next=validate_config(cfg,old,{'drcom-http':provider},{},{'drcom-http':drcom});
if(next.accounts[0].values.password!='fake-existing-pass' || next.connections[0].params.auth_server!='2.2.2.2' || next.generation!=3)die('config_retention_failed');
cfg.connections[0].params.auth_server='bad/path';
rejected(()=>validate_config(cfg,old,{'drcom-http':provider},{},{'drcom-http':drcom}));
if(old.generation!=2 || old.accounts[0].values.password!='fake-existing-pass')die('failed_validation_mutated_old');
print('PASS: preset/manual/legacy server resolution, custom endpoints, rejected hosts, no logout input, password and failed-save retention\n');

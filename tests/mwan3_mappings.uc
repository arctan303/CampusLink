import {valid_name,validate_settings,interface_catalog,validate_selection,binding_allowed} from '../packages/campuslink-mwan3/files/usr/share/campuslink-mwan3/mappings.uc';
let count=0;
function check(value,message) {count++;if(!value)die(message+'\n');};
function rejects(fn,message) {let failed=false;try{fn();}catch(e){failed=true;}check(failed,message);};
check(valid_name('campus-5.1'),'dynamic interface name');
check(!valid_name('wan1\n'),'control character rejected');
let values={},rows=[];
for(let i=0;i<6;i++) {
    values['exit'+i]={'.type':'interface',enabled:'1',family:'ipv4',initial_state:'offline'};
    values['member'+i]={'.type':'member',interface:'exit'+i};
    push(rows,{source_interface:'source'+i,mwan3_interface:'exit'+i,enabled:true});
}
let cfg=validate_settings({schema_version:1,enabled:true,mappings:rows},1),catalog=interface_catalog(values);
check(length(cfg.mappings)==6,'more than four mappings');
check(catalog[5].members[0]=='member5','associated member catalog');
validate_selection(cfg,map(rows,(r)=>r.source_interface),catalog);
rejects(()=>validate_settings({schema_version:1,enabled:true,mappings:[rows[0],rows[0]]},1),'duplicate rejected');
rejects(()=>validate_selection(cfg,['source0'],catalog),'unknown source rejected');
catalog[0].tracker_running=true;
rejects(()=>validate_selection(cfg,map(rows,(r)=>r.source_interface),catalog),'active tracker rejected');
catalog[0].tracker_running=false;catalog[0].family='ipv6';
rejects(()=>validate_selection(cfg,map(rows,(r)=>r.source_interface),catalog),'IPv6 rejected');
let mapping={source_interface:'source',mwan3_interface:'target'},source={up:true,device:'vwan9',ip:'10.0.0.2'};
check(binding_allowed(mapping,'target_4',source,source,null),'same binding alias');
check(!binding_allowed(mapping,'target_4',source,{...source,ip:'10.0.0.3'},null),'wrong binding isolated');
check(binding_allowed(mapping,'target_4',{up:false},source,{mapped_source:'source',target_network:'target_4',verified_binding:'vwan9/10.0.0.2'}),'verified source-down removal');
print('PASS: '+count+' native mapping checks\n');

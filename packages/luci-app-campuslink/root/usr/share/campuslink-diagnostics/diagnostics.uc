// Read-only diagnostics; dependencies are injected for native behavior tests.
export function public_ipv4(ip) {
    if(type(ip)!='string' || match(ip,/[^0-9.]/))return false;
    let parts=split(ip,'.');if(length(parts)!=4)return false;
    let n=[];
    for(let p in parts){let v=int(p);if(!length(p) || v<0 || v>255 || ''+v!=p)return false;push(n,v);}
    if(n[0]==0 || n[0]==10 || n[0]==127 || n[0]>=224)return false;
    if(n[0]==100 && n[1]>=64 && n[1]<=127)return false;
    if(n[0]==169 && n[1]==254 || n[0]==172 && n[1]>=16 && n[1]<=31 || n[0]==192 && n[1]==168)return false;
    if(n[0]==198 && (n[1]==18 || n[1]==19) || n[0]==192 && n[1]==0 && (n[2]==0 || n[2]==2))return false;
    if(n[0]==198 && n[1]==51 && n[2]==100 || n[0]==203 && n[1]==0 && n[2]==113)return false;
    return true;
};
function same(a,b){return a && b && a.device==b.device && a.ip==b.ip;};
function valid_name(name){return type(name)=='string' && length(name)<=64 && !!match(name,/^[A-Za-z0-9_]/) && !match(name,/[^A-Za-z0-9_.-]/);};
export function diagnose(method,id,io) {
    let campus=io.campus();
    if(!campus?.ok || type(campus.config?.connections)!='array')return {ok:false,reason_code:'source_unavailable'};
    let store=io.load();
    if(type(store)!='object' || type(store.revision)!='int' || store.revision<0 || type(store.cache)!='object')store={revision:0,cache:{}};
    function entry(c) {
        let route=io.route(c.interface),cached=store.cache[c.interface];
        if(!route || !same(route,cached))return {id:c.id,interface:c.interface,public_ipv4:null,checked_at:0,error:route?'not_queried':'interface_unavailable',retry_after_s:0};
        return {id:c.id,interface:c.interface,public_ipv4:cached.public_ipv4 || null,checked_at:cached.checked_at || 0,
            stale:!!cached.public_ipv4 && io.now()-(cached.checked_mono || 0)>300,error:cached.error || '',
            retry_after_s:max(0,60-int(io.now()-(cached.attempted_mono || 0)))};
    };
    function snapshot(){return {ok:true,instance:io.instance,revision:store.revision,entries:map(campus.config.connections,entry)};};
    if(method=='get')return snapshot();
    if(method!='query')return {ok:false,reason_code:'invalid_action'};
    let c=filter(campus.config.connections,(c)=>c.id==id)[0];
    if(!c || !valid_name(c.interface))return {ok:false,reason_code:'invalid_interface'};
    let route=io.route(c.interface);
    if(!route)return {ok:false,reason_code:'interface_unavailable'};
    let previous=store.cache[c.interface];
    if(same(route,previous) && io.now()-previous.attempted_mono<60)return {ok:true,cached:true,...snapshot()};
    for(let name in keys(store.cache))if(!length(filter(campus.config.connections,(c)=>c.interface==name)))delete store.cache[name];
    let next=same(route,previous)?{...previous}:{...route};
    next.attempted_mono=io.now();next.error='querying';store.cache[c.interface]=next;store.revision++;io.save(store);
    let response;
    try{response=io.http(route);}catch(e){response={ok:false,reason:'query_failed'};}
    let current=io.campus();
    if(current?.config?.generation!==campus.config.generation || !same(route,io.route(c.interface))) {
        delete store.cache[c.interface];store.revision++;io.save(store);
        return {...snapshot(),ok:false,reason_code:'binding_changed'};
    }
    let ip=null;
    if(response?.ok && response.code==200){try{let value=json(response.body);if(value?.ret=='ok')ip=value.data?.ip;}catch(e){}}
    if(public_ipv4(ip)){next.public_ipv4=ip;next.checked_at=io.wall();next.checked_mono=io.now();next.error='';}
    else next.error=response?.ok?'invalid_response':response?.reason || 'query_failed';
    store.revision++;io.save(store);
    return {...snapshot(),query_ok:!next.error,reason_code:next.error || 'queried'};
};

// Runs real shells against local fake tools. No router or routing command.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const bash=process.env.CAMPUSLINK_TEST_BASH || 'C:/Program Files/Git/bin/bash.exe';
const root=path.resolve('.local/mwan3-mapping-tests/native-'+process.pid).replaceAll('\\','/'),runtime=root+'/addon',config=root+'/config.json';
function write(name,content){const p=root+'/'+name;fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,content);}
function json(name,value){write(name,JSON.stringify(value));}
write('lib/functions.sh',':\n');write('lib/functions/network.sh',':\n');write('lib/functions/procd.sh','procd_lock() { :; }\n');
write('lib/mwan3/mwan3.sh','mwan3_get_true_iface() { export "$1=$2"; }\n');
write('proc/uptime','1234.56 12.00\n');write('bin/nft','#!/bin/sh\nexit 0\n');write('bin/flock','#!/bin/sh\nexit 0\n');
write('bin/uci','#!/bin/sh\ncat "$CAMPUSLINK_MWAN3_SYSTEM_ROOT/uci.$3" 2>/dev/null\n');
write('bin/ubus','#!/bin/sh\ncat "$CAMPUSLINK_MWAN3_SYSTEM_ROOT/$3.json"\n');
write('bin/jsonfilter','#!/bin/sh\nexec node "$CAMPUSLINK_MWAN3_SYSTEM_ROOT/jsonfilter.cjs" "$@"\n');
write('jsonfilter.cjs',fs.readFileSync('tests/fixtures/mwan3-jsonfilter.cjs'));
write('etc/hotplug.d/iface/25-mwan3','#!/bin/sh\ncase "$ACTION" in connected) state=online ;; disconnected) state=offline ;; *) exit 9 ;; esac\nprintf "%s\\n" "$state" > "$CAMPUSLINK_MWAN3_SYSTEM_ROOT/var/run/mwan3/iface_state/$INTERFACE"\nprintf "%s %s %s\\n" "$ACTION" "$INTERFACE" "$DEVICE" >> "$CAMPUSLINK_MWAN3_SYSTEM_ROOT/native-trace"\n');
write('var/run/mwan3/iface_state/edge','offline\n');write('var/run/mwan3/iface_state/untouched','online\n');
for(const [suffix,value] of [['','interface'],['.enabled','1'],['.family','ipv4'],['.track_gateway','0'],['.initial_state','offline']])write('uci.mwan3.edge'+suffix,value+'\n');
const mapping={source_interface:'campus',mwan3_interface:'edge',network_interface:'edge',verified_binding:'vwan9/10.0.0.2',enabled:true};
json('addon/active.json',{generation:4,mappings:[mapping]});json('config.json',{schema_version:1,generation:4,enabled:true,mappings:[mapping]});
json('addon/events/campus.json',{time:100,token:'source:1'});json('addon/events/edge.json',{time:100,token:'target:1'});
const net={up:true,l3_device:'vwan9','ipv4-address':[{address:'10.0.0.2'}]};
json('network.interface.campus.json',net);json('network.interface.edge.json',net);
const environment={...process.env,PATH:root+'/bin;'+process.env.PATH,CAMPUSLINK_MWAN3_RUNTIME:runtime,CAMPUSLINK_MWAN3_CONFIG:config,CAMPUSLINK_MWAN3_SYSTEM_ROOT:root};
const script=path.resolve('packages/campuslink-mwan3/files/usr/share/campuslink-mwan3/apply-mapping.sh');
function run(args,expected){const p=spawnSync(bash,[script,...args],{encoding:'utf8',env:environment,timeout:15000});assert.equal(p.status,expected,p.stderr || p.error?.message || p.stdout);}
const args=['edge','online','campus','edge','vwan9','10.0.0.2','source:1','target:1','4'];
run(args,0);assert.equal(fs.readFileSync(root+'/var/run/mwan3/iface_state/edge','utf8').trim(),'online');
assert.equal(fs.readFileSync(root+'/native-trace','utf8').trim(),'connected edge vwan9');
let trace=fs.readFileSync(root+'/native-trace','utf8');
run([...args.slice(0,8),'3'],4);run(['not_selected',...args.slice(1)],3);run(['bad;name',...args.slice(1)],2);
write('uci.mwan3.edge.track_ip','8.8.8.8\n');run(args,3);write('uci.mwan3.edge.track_ip','');
write('var/run/mwan3track/edge/PID','321\n');write('proc/321/cmdline','mwan3track edge');run(args,3);write('var/run/mwan3track/edge/PID','');
json('network.interface.edge.json',{...net,'ipv4-address':[{address:'10.0.0.9'}]});run(args,4);json('network.interface.edge.json',net);
json('addon/events/campus.json',{time:101,token:'source:2'});run(args,4);json('addon/events/campus.json',{time:100,token:'source:1'});
assert.equal(fs.readFileSync(root+'/native-trace','utf8'),trace,'rejected transitions must leave the native handler untouched');
json('network.interface.campus.json',{up:false});run(['edge','offline',...args.slice(2)],0);
assert.equal(fs.readFileSync(root+'/var/run/mwan3/iface_state/edge','utf8').trim(),'offline');
assert.equal(fs.readFileSync(root+'/var/run/mwan3/iface_state/untouched','utf8').trim(),'online');
const hook=path.resolve('packages/campuslink-mwan3/files/usr/share/campuslink-mwan3/events.sh');
let p=spawnSync(bash,[hook],{encoding:'utf8',env:{...environment,INTERFACE:'untouched',ACTION:'ifdown'},timeout:15000});assert.equal(p.status,0,p.stderr);assert.equal(fs.existsSync(runtime+'/events/untouched.json'),false);
p=spawnSync(bash,[hook],{encoding:'utf8',env:{...environment,INTERFACE:'edge',ACTION:'ifdown'},timeout:15000});assert.equal(p.status,0,p.stderr);assert.notEqual(JSON.parse(fs.readFileSync(runtime+'/events/edge.json')).token,'target:1');
write('lib/mwan3/mwan3.sh','mwan3_get_true_iface() { export "$1=$2"_4; }\n');
mapping.network_interface='edge_4';json('addon/active.json',{generation:4,mappings:[mapping]});json('config.json',{generation:4,enabled:true,mappings:[mapping]});
json('network.interface.campus.json',net);json('network.interface.edge_4.json',net);json('addon/events/edge_4.json',{time:100,token:'alias:1'});
run(['edge','online','campus','edge_4','vwan9','10.0.0.2','source:1','alias:1','4'],0);
console.log('PASS: real shell execution with native mocks, selected target transition, binding, stale config/event rejection, tracking conflict, unselected isolation and selected hotplug');

"""Fake loopback HTTP trial: URL encoding, globoff and disabling an active curl.

Uses a transient ubus interface and SSH reverse forwarding; no network config edits.
"""
import argparse
import http.server
import json
from pathlib import Path
import shlex
import subprocess
import threading
import time
from urllib.parse import parse_qs, urlsplit

parser=argparse.ArgumentParser()
parser.add_argument('--key',default='.local/router-test-key')
parser.add_argument('--host',default='root@192.168.0.1')
args=parser.parse_args()
ssh=['ssh','-T','-i',args.key,'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',args.host]
requests=[]
started=threading.Event()
online=False
delay_login=True

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*unused): pass
    def do_GET(self):
        global online
        requests.append(self.path)
        if self.path.startswith('/login'):
            started.set()
            if delay_login: time.sleep(5)
            else: online=True
            body=b'dr1003({"result":1});'
        elif online and self.path.startswith('/probe'):
            self.send_response(204);self.end_headers();return
        else: body=b'Authentication is required'
        try:
            self.send_response(200);self.end_headers();self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError): pass

server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()

def remote(cmd):
    p=subprocess.run(ssh+[cmd],capture_output=True,timeout=15)
    if p.returncode: raise RuntimeError(p.stderr.decode('utf-8',errors='replace'))
    return p.stdout.decode('utf-8',errors='replace')
def call(method,data=None):
    return json.loads(remote('ubus call campuslink.test '+method+' '+shlex.quote(json.dumps(data or {}))))

tunnel=subprocess.Popen(ssh[:-1]+['-N','-o','ExitOnForwardFailure=yes','-R',f'127.0.0.1:18080:127.0.0.1:{server.server_port}',args.host],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
stub='''import * as u from 'uloop';import * as b from 'ubus';import * as f from 'fs';u.init();let c=b.connect();let o=c.publish('network.interface.cltest',{status:{args:{},call:function(r){r.reply({up:f.readfile('/tmp/cl-test/link-up')=='1',l3_device:'lo','ipv4-address':[{address:'127.0.0.1'}]});}}});u.run();'''
try:
    source=Path('.local/cancel-interface.uc');source.write_text(stub,encoding='utf-8')
    subprocess.run(['scp','-O','-q','-i',args.key,str(source),args.host+':/tmp/cl-test/interface.uc'],check=True,timeout=15)
    remote('ucode /tmp/cl-test/interface.uc >/tmp/cl-test/interface.log 2>&1 & echo $! >/tmp/cl-test/interface.pid')
    time.sleep(.5)
    assert tunnel.poll() is None
    c={'id':'cancel-test','label':'Cancellation fixture','interface':'cltest','provider':'drcom-http','school':'','account':'fake',
       'params':{'auth_url':'http://127.0.0.1:18080/login{a,b}','probe_url':'http://127.0.0.1:18080/probe','status_url':'http://127.0.0.1:18080/status','logout_url':'http://127.0.0.1:18080/logout','terminal_mode':'pc'},
       'enabled':True,'auto_login':False,'check_interval':60,'retry_interval':30,'retry_max':600}
    values={'username':'fake-user','password':'p&b#c+d"$'}
    seed={'schema_version':1,'accounts':[{'id':'fake','label':'Fake','credential_type':'username_password','values':values}],'connections':[c]}
    script="import * as f from 'fs';for(let path in f.glob('/proc/[0-9]*/cmdline')){let s=f.readfile(path);if(s && index(s,'/usr/bin/curl')==0 && index(s,'/tmp/cl-test/run/job-')>=0)print(path,'\\n');}"
    for mode in ['disable','save','link','stop']:
        requests.clear();started.clear();remote("printf 1 >/tmp/cl-test/link-up")
        assert call('save',{'config':seed,'expected_generation':call('get')['config']['generation']})['ok']
        deadline=time.monotonic()+6
        while time.monotonic()<deadline:
            status=call('get')['status'][0]
            if status['state']=='action_required' and not status['task_id']: break
            time.sleep(.2)
        assert call('action',{'id':c['id'],'operation':'login'})['ok']
        assert started.wait(6), 'fake login request not received'
        assert remote("pgrep -f '^/usr/bin/ucode /tmp/cl-src/worker.uc ' || true").strip(), 'no worker observed'
        if mode=='disable': assert call('action',{'id':c['id'],'operation':'disable'})['ok']
        elif mode=='save':
            cfg=call('get')['config'];cfg['connections'][0]['enabled']=False
            assert call('save',{'config':cfg,'expected_generation':cfg['generation']})['ok']
        elif mode=='link': remote("printf 0 >/tmp/cl-test/link-up")
        else: remote("for pid in $(pgrep -f '^ucode /tmp/cl-src/daemon.uc$'); do kill \"$pid\"; done")
        time.sleep(1.3 if mode=='link' else .3)
        assert not remote("pgrep -f '^/usr/bin/ucode /tmp/cl-src/worker.uc ' || true").strip()
        assert not remote('ucode -e '+shlex.quote(script)).strip(), 'curl survived '+mode
        time.sleep(5)
        logins=[p for p in requests if p.startswith('/login')]
        assert len(logins)==1 and urlsplit(logins[0]).path=='/login{a,b}', 'URL glob expansion'
        query=parse_qs(urlsplit(logins[0]).query)
        assert query['user_password']==[values['password']]
        assert query['user_account']==[',0,'+values['username']]
        assert len([p for p in requests if p.startswith('/probe')])==2, 'verification after '+mode
        assert not remote('find /tmp/cl-test/run -type f').strip(), 'private work files remain'
        print('PASS: worker/curl cancellation, no late verification, cleanup via '+mode,flush=True)
        if mode=='stop':
            remote('CAMPUSLINK_BASE=/tmp/cl-src CAMPUSLINK_CONFIG=/tmp/cl-test/config.json CAMPUSLINK_RUNTIME=/tmp/cl-test/run CAMPUSLINK_OBJECT=campuslink.test ucode /tmp/cl-src/daemon.uc >/tmp/cl-test/daemon.log 2>&1 &')
            time.sleep(1)
    # Recover a simulated campus logout twice through real HTTP and the scheduler.
    delay_login=False;online=False;requests.clear();remote("printf 1 >/tmp/cl-test/link-up")
    c['auto_login']=True
    assert call('save',{'config':seed,'expected_generation':call('get')['config']['generation']})['ok']
    def wait_online():
        deadline=time.monotonic()+18
        while time.monotonic()<deadline:
            if call('get')['status'][0]['state']=='online':return
            time.sleep(.25)
        raise AssertionError('automatic recovery failed')
    wait_online();assert len([p for p in requests if p.startswith('/login')])==1
    cfg=call('get')['config'];cfg['connections'][0]['check_interval']=10
    assert call('save',{'config':cfg,'expected_generation':cfg['generation']})['ok'];wait_online()
    online=False;time.sleep(1);wait_online()
    deadline=time.monotonic()+17
    while len([p for p in requests if p.startswith('/login')])<2 and time.monotonic()<deadline:time.sleep(.25)
    wait_online();assert len([p for p in requests if p.startswith('/login')])==2
    assert call('action',{'id':c['id'],'operation':'disable'})['ok']
    print('PASS: real HTTP periodic check, authenticated verification and automatic recovery',flush=True)
finally:
    try: remote('if [ -f /tmp/cl-test/interface.pid ]; then kill "$(cat /tmp/cl-test/interface.pid)"; fi')
    except Exception: pass
    tunnel.terminate()
    try: tunnel.wait(timeout=5)
    except subprocess.TimeoutExpired: tunnel.kill()
    server.shutdown()

"""Exercise an isolated campuslink.test ubus service with fake credentials."""
import argparse
import json
import shlex
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--host', default='root@192.168.0.1')
parser.add_argument('--key', default='.local/router-test-key')
parser.add_argument('--config',default='/tmp/cl-test/config.json')
args = parser.parse_args()

def remote(command):
    p = subprocess.run(['ssh', '-T', '-i', args.key, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', args.host, command], capture_output=True, timeout=20)
    if p.returncode: raise RuntimeError(p.stderr.decode('utf-8', errors='replace'))
    return p.stdout.decode('utf-8', errors='replace')

def call(method, data=None):
    payload = shlex.quote(json.dumps(data or {}, ensure_ascii=False))
    return json.loads(remote(f'ubus call campuslink.test {method} {payload}'))

def wait_idle(expected=None):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        snapshot = call('get')
        s = snapshot['status'][0]
        if not s['task_id'] and s['state'] in ('online','action_required','backoff','disabled') and (expected is None or s['state'] == expected): return snapshot
        time.sleep(.25)
    raise AssertionError('task did not settle')

def save(scenario='portal', automatic=False, iface='wan1'):
    old = call('get')['config']
    cfg = {'schema_version':1,'accounts':[{'id':'test-account','label':'Mock account','credential_type':'username_password','values':{'username':'fake-student','password':'p&b#c+d"$'}}],
           'connections':[{'id':'test-wan','label':'Mock WAN','interface':iface,'provider':'mock','school':'','account':'test-account','params':{'scenario':scenario},'enabled':True,'auto_login':automatic,'check_interval':10,'retry_interval':10,'retry_max':60}]}
    reply = call('save', {'config':cfg,'expected_generation':old['generation']})
    assert reply['ok'], reply
    return wait_idle()

snap = save()
assert snap['status'][0]['state'] == 'action_required'
assert 'password' not in snap['config']['accounts'][0]['values']
assert snap['config']['accounts'][0]['password_set'] is True
assert remote('ls -l '+shlex.quote(args.config)).startswith('-rw-------')

reply = call('action', {'id':'test-wan','operation':'login'})
assert reply['ok']
duplicate = call('action', {'id':'test-wan','operation':'login'})
assert duplicate.get('task_id') == reply['task_id'], duplicate
assert wait_idle('online')['status'][0]['identity_verified'] is False

public = call('get')['config']
assert call('save', {'config':public,'expected_generation':public['generation']})['ok']
snap = wait_idle()
assert snap['config']['accounts'][0]['password_set'] is True
stale = call('save', {'config':public,'expected_generation':public['generation']})
assert stale['reason_code'] == 'config_changed'

bad = call('get')['config']
bad['accounts'] = []
reply=call('save', {'config':bad,'expected_generation':bad['generation']})
assert reply['reason_code']=='account_in_use' and reply['references'][0]['id']=='test-wan'
bad = call('get')['config']
bad['connections'][0]['params']['unexpected'] = 'x'
assert call('save', {'config':bad,'expected_generation':bad['generation']})['ok'] is False

save('reject')
assert call('action', {'id':'test-wan','operation':'login'})['ok']
assert wait_idle('action_required')['status'][0]['reason_code'] == 'invalid_credentials'
save('rate_limit', True, 'wan2')
s = wait_idle('backoff')['status'][0]
assert s['cooldown_s'] > 80, s
assert call('action', {'id':'test-wan','operation':'login'})['reason_code'] == 'cooldown'
assert call('action', {'id':'test-wan','operation':'check'})['ok']
s = wait_idle()['status'][0]
assert s['cooldown_s'] > 75, s
save('timeout', True, 'wan2')
assert call('get')['status'][0]['cooldown_s'] > 70
assert call('action', {'id':'test-wan','operation':'disable'})['ok']
assert call('action', {'id':'test-wan','operation':'enable'})['ok']
assert call('action', {'id':'test-wan','operation':'login'})['reason_code']=='cooldown'

save('timeout', True)
assert wait_idle('backoff')['status'][0]['reason_code'] == 'timeout'
save('online')
assert wait_idle('online')['status'][0]['state'] == 'online'
assert call('action', {'id':'test-wan','operation':'logout'})['ok']
assert wait_idle('action_required')['status'][0]['reason_code'] == 'logout_verified'
assert call('action', {'id':'test-wan','operation':'disable'})['ok']
assert call('get')['status'][0]['state'] == 'disabled'
assert call('action', {'id':'test-wan','operation':'login'})['reason_code'] == 'disabled'

cfg=call('get')['config']
duplicate=json.loads(json.dumps(cfg['connections'][0]))
duplicate['id']='second-wan'
cfg['connections'].append(duplicate)
assert call('save', {'config':cfg,'expected_generation':cfg['generation']})['ok']
assert call('action', {'id':'test-wan','operation':'enable'})['ok']
assert call('action', {'id':'second-wan','operation':'enable'})['ok'] is False
assert call('get')['config']['connections'][1]['enabled'] is False
print('PASS: isolated mock configuration, secrecy, task locking, errors, cooldown, logout and disable')

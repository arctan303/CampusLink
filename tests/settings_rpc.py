"""Run only against the isolated campuslink.test service, using fake accounts."""
import argparse,json,shlex,subprocess,time
parser=argparse.ArgumentParser();parser.add_argument('--key',required=True);args=parser.parse_args()
def remote(command):
 p=subprocess.run(['ssh','-T','-i',args.key,'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','root@192.168.0.1',command],capture_output=True,timeout=20,check=True)
 return p.stdout.decode()
def call(method,data=None):return json.loads(remote('ubus call campuslink.test '+method+' '+shlex.quote(json.dumps(data or {}))))
def save(config):return call('save',{'config':config,'expected_generation':call('get')['config']['generation']})
def idle():
 deadline=time.monotonic()+12
 while time.monotonic()<deadline:
  state=call('get')
  if all(not s['task_id'] and s['state'] in ['disabled','online','action_required','backoff'] for s in state['status']):return state
  time.sleep(.2)
 raise AssertionError('jobs did not settle')
config={'schema_version':2,'settings':{'provider':'mock','school':'','params':{},'check_interval':10,'retry_interval':10,'retry_max':60},'accounts':[{'id':'a','label':'Fixture','credential_type':'username_password','values':{'username':'fake-user','password':'fake-password'}}],'connections':[{'id':'c'+str(i),'label':'Fixture'+str(i),'interface':'wan'+str(i+1),'account':'a','params':{'scenario':scenario},'enabled':True,'auto_login':False} for i,scenario in enumerate(['portal','online'])]}
assert save(config)['ok']
state=idle();assert [s['state'] for s in state['status']]==['action_required','online']
before=state['config'];assert before['schema_version']==2 and before['accounts'][0]['password_set'] and 'password' not in before['accounts'][0]['values']
assert all('provider' not in c and 'check_interval' not in c for c in before['connections'])
changed=json.loads(json.dumps(before));changed['settings']['check_interval']=120
assert save(changed)['ok'];state=idle();assert all(s['next_check_s']>100 for s in state['status'])
assert call('action',{'id':'c1','operation':'disable'})['ok'];assert call('get')['config']['connections'][1]['enabled'] is False
stable=call('get')['config'];bad=json.loads(json.dumps(stable));bad['connections'][0]['params']['auth_server']='bad.example'
assert not save(bad)['ok'];assert call('get')['config']==stable
assert call('save',{'config':stable,'expected_generation':stable['generation']-1})['reason_code']=='config_changed';assert call('get')['config']==stable
bad=json.loads(json.dumps(stable));bad['schema_version']=1;assert not save(bad)['ok']
switched=json.loads(json.dumps(stable));switched['settings'].update(provider='drcom-http',school='',params={'auth_server':'2.2.2.2'})
for i,c in enumerate(switched['connections']):c['enabled']=False;c['params']={'terminal_mode':'pc' if i==0 else 'mobile'}
assert save(switched)['ok'];state=idle();assert all(s['state']=='disabled' for s in state['status'])
assert state['config']['accounts'][0]['password_set'];assert [c['interface'] for c in state['config']['connections']]==['wan1','wan2']
print('PASS: real schema2 RPC shared scheduling, local modes, enable/disable, atomic failures, conflict, downgrade rejection, provider switch and password retention')

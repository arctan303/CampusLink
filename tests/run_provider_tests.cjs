/* Execute ucode modules using the official WASM interpreter, offline.
 * Usage: node tests/run_provider_tests.cjs /path/to/ucode.js
 * Download/verification instructions: docs/providers/experimental.md.
 */
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const {execFile}=require('node:child_process');
const {promisify}=require('node:util');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),runtime=process.argv[2];
if(!runtime)throw new Error('Pass the official ucode.js path; see docs/providers/experimental.md');
const sourceRoot='packages/campuslink/files/usr/share/campuslink';
// Optional extracted final IPK data root, mounted at the same virtual paths.
const payload=process.argv[3] ? path.join(path.resolve(process.argv[3]),'usr/share/campuslink') : path.join(root,sourceRoot);
const run=promisify(execFile);
(async()=>{
    const m=await require(path.resolve(runtime))();
    function ptr(s){const n=Buffer.byteLength(s),p=m._malloc(n+1);m.stringToUTF8(s,p,n+1);return p;}
    function mount(name,source){
        // WASM registers builtins through require(), without Linux .so import paths.
        // Only adapt this native module import; all tested function bodies stay intact.
        source=source.replace(/^import \* as fs from 'fs';\r?$/gm,"const fs=require('fs');");
        let a=ptr('/workspace/'+name),b=ptr(source);
        try{assert.equal(m._ucode_vfs_write(a,b,Buffer.byteLength(source)),0);}finally{m._free(a);m._free(b);}
    }
    for(const f of fs.readdirSync(payload,{recursive:true})) {
        const full=path.join(payload,f);if(!fs.statSync(full).isFile())continue;
        mount(sourceRoot+'/'+f.replaceAll('\\','/'),fs.readFileSync(full,'utf8'));
    }
    mount(sourceRoot+'/transport-real.uc',fs.readFileSync(path.join(payload,'transport.uc'),'utf8'));
    mount(sourceRoot+'/transport.uc',fs.readFileSync(path.join(__dirname,'fixtures/provider-transport.uc'),'utf8'));
    for(const f of ['experimental_providers.uc','fixtures/srun-vectors.json','fixtures/rsa-vectors.json'])mount('tests/'+f,fs.readFileSync(path.join(__dirname,f),'utf8'));
    let p=ptr('/workspace/tests/experimental_providers.uc');m._ucode_run_file(p);m._free(p);
    const error=m.UTF8ToString(m._ucode_get_error());if(error)throw new Error(error);
    const output=m.UTF8ToString(m._ucode_get_output());
    const report=JSON.parse(output);console.log(`PASS: ${report.passed} ucode assertions; VM ${m.UTF8ToString(m._ucode_version())}`);
    m._ucode_clear_output();
    // Exercise the real worker's check -> login -> verify gate, using queued replies.
    const base='http://portal.example:8080',probe='http://probe.example/generate_204';
    const response=(url,body,code=200)=>({url,reply:{body,code}});
    const offline=response(base+'/cgi-bin/rad_user_info','{"error":"not_online_error"}');
    const redirect={url:probe,reply:{code:302,headers:'Location: '+base+'/eportal/index.jsp?wlanuserip=192.0.2.123'}};
    const challenge=response(base+'/cgi-bin/get_challenge',JSON.stringify({error:'ok',challenge:'0123456789abcdef'.repeat(4),client_ip:'192.0.2.123'}));
    const rsa=JSON.parse(fs.readFileSync(path.join(__dirname,'fixtures/rsa-vectors.json')))[0];
    const query='wlanuserip=192.0.2.123&mac='+rsa.mac;
    const rsaRedirect={url:probe,reply:{code:200,body:'<script>top.self.location.href="'+base+'/eportal/index.jsp?'+query+'";</script>'}};
    const pageInfo={...response(base+'/eportal/InterFace.do?method=pageInfo',JSON.stringify({publicKeyExponent:rsa.exponent,publicKeyModulus:rsa.modulus})),method:'POST',params:{queryString:query}};
    const rsaLogin={...response(base+'/eportal/InterFace.do?method=login','{"result":"success"}'),method:'POST',params:{password:rsa.expected,passwordEncrypt:'true',queryString:encodeURIComponent(query)}};
    const cases=[
        {id:'srun-srbx1',op:'check',allow:false,replies:[response(probe,''),offline],outcome:'unauthenticated'},
        {id:'srun-srbx1',op:'login',replies:[response(probe,''),offline,challenge,response(base+'/cgi-bin/srun_portal','{"error":"ok"}'),response(probe,'',204)],outcome:'online'},
        {id:'srun-srbx1',op:'login',replies:[response(probe,''),offline,challenge,response(base+'/cgi-bin/srun_portal','{"error":"ok"}'),response(probe,''),offline],outcome:'indeterminate',reason:'verification_failed'},
        {id:'srun-srbx1',op:'login',replies:[response(probe,''),response(base+'/cgi-bin/rad_user_info','{"error":"mystery"}')],outcome:'indeterminate',reason:'unknown_response'},
        {id:'ruijie-eportal',op:'login',replies:[redirect,redirect,{...response(base+'/eportal/InterFace.do?method=login','{"result":"success"}'),method:'POST'},response(probe,'',204)],outcome:'online'},
        {id:'ruijie-eportal',op:'check',allow:true,replies:[redirect,redirect,{...response(base+'/eportal/InterFace.do?method=login','{"result":"success"}'),method:'POST'},response(probe,'' )],outcome:'indeterminate',reason:'verification_failed'},
        {id:'ruijie-eportal',op:'check',allow:true,replies:[redirect,redirect,{...response(base+'/eportal/InterFace.do?method=login','{"result":"fail","message":"密码不匹配,请输入正确的密码!"}'),method:'POST'}],outcome:'rejected',reason:'invalid_credentials'},
        ...['E2531','E2553','E2532','E2533'].map(ecode=>({id:'srun-srbx1',op:'check',allow:true,replies:[response(probe,''),offline,challenge,response(base+'/cgi-bin/srun_portal',JSON.stringify({error:'login_error',ecode}))],outcome:ecode==='E2531'||ecode==='E2553'?'rejected':'rate_limited',reason:ecode==='E2531'||ecode==='E2553'?'invalid_credentials':'rate_limited'})),
        {id:'ruijie-eportal',op:'login',params:{password_mode:'rsa'},replies:[rsaRedirect,rsaRedirect,pageInfo,rsaLogin,response(probe,'',204)],outcome:'online'},
        {id:'ruijie-eportal',op:'check',allow:true,params:{password_mode:'rsa'},replies:[rsaRedirect,rsaRedirect,pageInfo,rsaLogin,response(probe,'')],outcome:'indeterminate',reason:'verification_failed'},
        {id:'ruijie-eportal',op:'login',params:{password_mode:'rsa'},replies:[rsaRedirect,rsaRedirect,{...pageInfo,reply:{code:200,body:'{}'}}],outcome:'rejected',reason:'unsupported_rsa_variant'},
        {id:'srun-srbx1',op:'login',params:{ac_id:''},replies:[response(probe,''),{...offline,reply:{body:'{"res":"not_online_error"}',code:200}},{url:base+'/',reply:{code:302,headers:'Location: /srun_portal_pc?ac_id=78'}},{...challenge,reply:{code:200,body:JSON.stringify({challenge:'0123456789abcdef'.repeat(4),client_ip:'192.0.2.123'})}},{...response(base+'/cgi-bin/srun_portal','{"res":"ok"}'),params:{ac_id:'78'}},response(probe,'',204)],outcome:'online'},
        ...['E2553','E9999',false,[],{}].map(ecode=>({id:'srun-srbx1',op:'check',allow:true,replies:[response(probe,''),response(base+'/cgi-bin/rad_user_info',JSON.stringify({error:'not_online_error',ecode}))],outcome:'indeterminate',reason:'unknown_response'})),
        {id:'srun-srbx1',op:'check',allow:true,params:{ac_id:''},replies:[response(probe,''),offline,response(base+'/','<script>window.location.href="/srun_portal_pc?ac_id=78";</script>')],outcome:'indeterminate',reason:'ac_id_unavailable'},
    ];
    for(let i=0;i<cases.length;i++) {
        const c=cases[i],dir='/tmp/provider-worker-'+i;
        const ctx={connection:{provider:c.id},operation:c.op,allow_login:c.allow||false,account:{values:{username:'fixture-user',password:'fixture-pass'}},params:{server_url:base,probe_url:probe,ac_id:12,hmac_mode:'password',...c.params},route:{device:'wan-test',ip:'192.0.2.123'},workdir:dir,_responses:c.replies,_requests:[]};
        mount('context-'+i+'.json',JSON.stringify(ctx));
        // A distinct entry path bypasses require's module cache for each worker run.
        const worker=fs.readFileSync(path.join(payload,'worker.uc'),'utf8').replace('read_json(ARGV[0])',`read_json('/workspace/context-${i}.json')`);
        mount(sourceRoot+'/worker-test-'+i+'.uc',worker);
        let code=ptr(`require('fs').mkdir('${dir}',0700);`);m._ucode_run(code);m._free(code);
        code=ptr('/workspace/'+sourceRoot+'/worker-test-'+i+'.uc');m._ucode_run_file(code);m._free(code);
        const err=m.UTF8ToString(m._ucode_get_error());if(err)throw new Error(err);
        code=ptr(`print(require('fs').readfile('${dir}/result.json'));`);m._ucode_run(code);m._free(code);
        const result=JSON.parse(m.UTF8ToString(m._ucode_get_output()));m._ucode_clear_output();
        assert.equal(result.outcome,c.outcome,`worker case ${i}`);
        if(c.reason)assert.equal(result.reason_code,c.reason,`worker reason ${i}`);
        if(c.outcome==='rate_limited')assert.equal(result.retry_after_s,90,'worker retains cooldown');
        assert.ok(!JSON.stringify(result).includes('fixture-pass'),'worker result must not contain password');
    }
    console.log('PASS: real ucode worker manual/automatic login gates, unknown status and post-login connectivity verification');
    // Exercise generated curl configurations against a real local HTTP server.
    // Windows cannot use Linux ifhost binding; only this test removes that line.
    const temp=path.join(root,'.local/provider-curl-tests');fs.mkdirSync(temp,{recursive:true});
    const requests=[];
    const server=http.createServer((req,res)=>{let body='';req.setEncoding('utf8');req.on('data',s=>body+=s);req.on('end',()=>{requests.push({method:req.method,url:req.url,body});res.writeHead(204);res.end();});});
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    try {
        for(const variant of ['GET','POST','DOUBLE']) {
            const method=variant==='DOUBLE'?'POST':variant;
            const file=path.join(temp,variant+'.conf');
            const quote=s=>JSON.stringify(s.replaceAll('\\','/'));
            const config=report.curl_configs[variant].split('\n').filter(x=>!x.startsWith('interface = ')).map(x=>{
                if(x.startsWith('url = '))return 'url = '+quote(`http://127.0.0.1:${server.address().port}/form`);
                if(x.startsWith('output = '))return 'output = '+quote(path.join(temp,method+'.body'));
                if(x.startsWith('dump-header = '))return 'dump-header = '+quote(path.join(temp,method+'.headers'));
                return x;
            }).join('\n');
            fs.writeFileSync(file,config,{mode:0o600});
            const result=await run(process.env.CAMPUSLINK_CURL || 'curl.exe',['-q','--config',file],{timeout:12000});
            assert.equal(result.stdout,'204');
            const req=requests.at(-1);assert.equal(req.method,method);
            const fields=new URLSearchParams(method==='GET'?new URL(req.url,'http://fixture').search:req.body);
            if(variant==='DOUBLE') {
                assert.equal(fields.get('userId'),encodeURIComponent('u&=+%/测试'));
                assert.equal(decodeURIComponent(fields.get('userId')),'u&=+%/测试');
                assert.equal(fields.get('password'),rsa.expected);
                assert.equal(decodeURIComponent(fields.get('queryString')),'wlanuserip=192.0.2.123&mac='+rsa.mac+'&wlanacname=AC%26X');
            } else {
                assert.equal(fields.get('userId'),'u&=+%/测试');assert.equal(fields.get('password'),'p"\\&=+%');
                assert.equal(fields.get('queryString'),'wlanuserip=192.0.2.123&x=AC%26X');
            }
            assert.equal(fields.size,3);if(method==='POST')assert.equal(req.url,'/form');
        }
        console.log('PASS: real curl GET and POST encoding against loopback server (Linux interface binding excluded)');
    } finally {await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1;});

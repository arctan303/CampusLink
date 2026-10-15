// Cross-check the pinned MIT reference's pure arithmetic in a capability-free VM.
// Usage: node tests/rsa_reference.cjs .local/provider-research/auto-body.js
const fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2],'utf8');
assert.equal(crypto.createHash('sha256').update(source).digest('hex'),'ae0a4592916e33daf626cfec5c65ccae10dddebd46db3190773973d02921557f');
const start=source.indexOf('(function(global) {'),end=source.indexOf('})(typeof global',start);
assert.ok(start>0 && end>start);
const pure=source.slice(start,end)+ '})(global);';
const context=vm.createContext({global:{}},{codeGeneration:{strings:false,wasm:false}});
new vm.Script(pure).runInContext(context,{timeout:5000});
const vectors=JSON.parse(fs.readFileSync('tests/fixtures/rsa-vectors.json'));
for(const v of vectors) {
    context.input=v;
    const result=new vm.Script('global.RSAUtils.setMaxDigits(400); global.RSAUtils.encryptedString(global.RSAUtils.getKeyPair(input.exponent,"",input.modulus),(input.password+">"+input.mac).split("").reverse().join(""))').runInContext(context,{timeout:5000});
    assert.equal(result,v.expected);
}
console.log('PASS: independent Python pow agrees with pinned MIT browser RSA for all '+vectors.length+' synthetic vectors');

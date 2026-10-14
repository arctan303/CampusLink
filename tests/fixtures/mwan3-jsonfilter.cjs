// Minimal jsonfilter protocol mock for isolated native-shell tests.
const fs=require('node:fs');
let args=process.argv.slice(2),data,expressions=[];
try {
    for(let i=0;i<args.length;i++){
        if(args[i]==='-i')data=JSON.parse(fs.readFileSync(args[++i],'utf8'));
        else if(args[i]==='-s')data=JSON.parse(args[++i]);
        else if(args[i]==='-e')expressions.push(args[++i]);
    }
    for(const e of expressions){
        let value;
        if(e==='@.generation')value=data.generation;
        else if(e==='@.enabled')value=data.enabled;
        else if(e==='@.token')value=data.token;
        else if(e==='@.up')value=data.up;
        else if(e==='@.l3_device')value=data.l3_device;
        else if(e==='@["ipv4-address"][0].address')value=data['ipv4-address']?.[0]?.address;
        else {
            let m=e.match(/^@\.mappings\[@\.mwan3_interface="([^"]+)"\]\.(\w+)$/);
            if(m)value=data.mappings.find(x=>x.mwan3_interface===m[1])?.[m[2]];
            else {m=e.match(/^@\.mappings\[\*\]\.(\w+)$/);if(m)value=data.mappings.map(x=>x[m[1]]);}
        }
        if(value===undefined)process.exitCode=1;
        else if(Array.isArray(value))value.forEach(x=>console.log(x));
        else console.log(value);
    }
} catch {process.exitCode=1;}

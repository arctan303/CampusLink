// ePortal browser-compatible zero-padding RSA, independently implemented.
// One ASCII block only. Protocol references and limits: docs/providers/experimental.md.
function compare(a,b) {
    for(let i=length(a)-1;i>=0;i--)if(a[i]!=b[i])return a[i]>b[i] ? 1 : -1;
    return 0;
}
function subtract(a,b) {
    let out=[],borrow=0;
    for(let i=0;i<length(b);i++) { let v=a[i]-b[i]-borrow;push(out,v&65535);borrow=v<0 ? 1 : 0; }
    return out;
}
function doubled(a,n) {
    let out=[],carry=0;
    for(let v in a) { let x=2*v+carry;push(out,x&65535);carry=x>>16; }
    return carry || compare(out,n)>=0 ? subtract(out,n) : out;
}
function montgomery(a,b,n,inverse) {
    let size=length(n),t=[];
    for(let j=0;j<size+2;j++)push(t,0);
    for(let i=0;i<size;i++) {
        let carry=0;
        for(let j=0;j<size;j++) {
            let x=t[j]+a[j]*b[i]+carry;t[j]=x&65535;carry=x>>16;
        }
        let x=t[size]+carry;t[size]=x&65535;t[size+1]=x>>16;
        let m=(t[0]*inverse)&65535;carry=0;
        for(let j=0;j<size;j++) {
            x=t[j]+m*n[j]+carry;
            if(j>0)t[j-1]=x&65535;
            carry=x>>16;
        }
        x=t[size]+carry;t[size-1]=x&65535;t[size]=t[size+1]+(x>>16);t[size+1]=0;
    }
    let out=[];for(let i=0;i<size;i++)push(out,t[i]);
    return t[size] || compare(out,n)>=0 ? subtract(out,n) : out;
}
function words(text,size) {
    let out=[];
    for(let end=length(text);end>0;end-=4)push(out,int(substr(text,max(0,end-4),min(4,end)),16));
    while(length(out)<size)push(out,0);
    return out;
}
export function rsa_encrypt(password,mac,exponent,modulus) {
    if(type(exponent)!='string' || type(modulus)!='string' || length(exponent)>8 || length(modulus)>514 || match(exponent+modulus,/[[:cntrl:]]/))die('invalid_rsa_key');
    exponent=lc(replace(exponent,/^0+/,''));modulus=lc(replace(modulus,/^0+/,''));
    if(index(['3','10001'],exponent)<0 || index([256,512],length(modulus))<0 || !match(modulus,/^[89abcdef][0-9a-f]+$/) || (int(substr(modulus,-1),16)&1)!=1)die('invalid_rsa_key');
    if(type(password)!='string' || type(mac)!='string' || !length(password) || !length(mac) || length(mac)>128 || match(password+mac,/[[:cntrl:]]/) || match(password+mac,/[^ -~]/))die('unsupported_rsa_input');
    let message=password+'>'+mac;
    if(length(message)>length(modulus)/2-2)die('unsupported_rsa_input');
    // reverse(message) packed little-endian by the browser equals this integer.
    let value='';for(let i=0;i<length(message);i++)value+=sprintf('%02x',ord(message,i));
    let size=int(length(modulus)/4),n=words(modulus,size),one=[],inverse=1;
    for(let i=0;i<size;i++)push(one,i==0 ? 1 : 0);
    for(let i=0;i<4;i++)inverse=(inverse*(2-n[0]*inverse))&65535;
    inverse=(-inverse)&65535;
    let r2=[...one];for(let i=0;i<size*32;i++)r2=doubled(r2,n);
    let a=montgomery(words(value,size),r2,n,inverse),out=montgomery(one,r2,n,inverse),e=int(exponent,16);
    while(e>0) { if(e&1)out=montgomery(out,a,n,inverse);e>>=1;if(e)a=montgomery(a,a,n,inverse); }
    out=montgomery(out,one,n,inverse);
    let last=size-1;while(last>0 && out[last]==0)last--;
    let hex='';for(let i=last;i>=0;i--)hex+=sprintf('%04x',out[i]);
    return hex;
};

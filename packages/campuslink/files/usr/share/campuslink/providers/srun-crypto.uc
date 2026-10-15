// SRBX1 wire encoding; protocol references and licenses: docs/providers/experimental.md.
// MD5/SHA-1 here reproduce the portal protocol, not a new password storage scheme.
function u32(x) { return x & 0xffffffff; }
function rol(x, n) { return u32((x << n) | (x >> (32 - n))); }
function bytes(words, big) {
    let out = '';
    for (let w in words)
        for (let i = 0; i < 4; i++) out += chr((w >> (8 * (big ? 3-i : i))) & 255);
    return out;
}
function padded(text, big) {
    let size = length(text), value = text + chr(128);
    while (length(value) % 64 != 56) value += chr(0);
    let bits = size * 8;
    for (let i = 0; i < 8; i++) value += chr((bits >> (8 * (big ? 7-i : i))) & 255);
    let words = [];
    for (let i = 0; i < length(value); i += 4) {
        let w = 0;
        for (let j = 0; j < 4; j++) w |= ord(value, i+j) << (8 * (big ? 3-j : j));
        push(words, u32(w));
    }
    return words;
}
export function hex(raw) {
    let out = '';
    for (let i = 0; i < length(raw); i++) out += sprintf('%02x', ord(raw, i));
    return out;
};
export function md5(text) {
    let k = [
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
        0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
        0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
    ];
    let shifts = [[7,12,17,22],[5,9,14,20],[4,11,16,23],[6,10,15,21]];
    let words = padded(text, false), h = [0x67452301,0xefcdab89,0x98badcfe,0x10325476];
    for (let off = 0; off < length(words); off += 16) {
        let a=h[0], b=h[1], c=h[2], d=h[3];
        for (let i=0; i<64; i++) {
            let f, g, round=int(i/16);
            if (round==0) { f=(b&c)|((~b)&d); g=i; }
            else if (round==1) { f=(d&b)|((~d)&c); g=(5*i+1)%16; }
            else if (round==2) { f=b^c^d; g=(3*i+5)%16; }
            else { f=c^(b|(~d)); g=(7*i)%16; }
            let next=u32(b+rol(u32(a+u32(f)+k[i]+words[off+g]), shifts[round][i%4]));
            a=d; d=c; c=b; b=next;
        }
        h=[u32(h[0]+a),u32(h[1]+b),u32(h[2]+c),u32(h[3]+d)];
    }
    return bytes(h, false);
};
export function sha1(text) {
    let words=padded(text,true), h=[0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0];
    for (let off=0; off<length(words); off+=16) {
        let w=[];
        for (let i=0; i<80; i++) push(w, i<16 ? words[off+i] : rol(w[i-3]^w[i-8]^w[i-14]^w[i-16],1));
        let a=h[0],b=h[1],c=h[2],d=h[3],e=h[4];
        for (let i=0; i<80; i++) {
            let f=i<20 ? (b&c)|((~b)&d) : i<40 ? b^c^d : i<60 ? (b&c)|(b&d)|(c&d) : b^c^d;
            let k=i<20 ? 0x5a827999 : i<40 ? 0x6ed9eba1 : i<60 ? 0x8f1bbcdc : 0xca62c1d6;
            let next=u32(rol(a,5)+u32(f)+e+k+w[i]);
            e=d;d=c;c=rol(b,30);b=a;a=next;
        }
        h=[u32(h[0]+a),u32(h[1]+b),u32(h[2]+c),u32(h[3]+d),u32(h[4]+e)];
    }
    return hex(bytes(h,true));
};
export function hmac_md5(key, text) {
    if (length(key)>64) key=md5(key);
    let inner='',outer='';
    for (let i=0; i<64; i++) {
        let value=i<length(key) ? ord(key,i) : 0;
        inner+=chr(value^0x36);outer+=chr(value^0x5c);
    }
    return hex(md5(outer+md5(inner+text)));
};
function words_of(text, size) {
    let words=[];
    for (let i=0; i<length(text); i+=4) {
        let w=0;
        for (let j=0; j<4 && i+j<length(text); j++) w|=ord(text,i+j)<<(8*j);
        push(words,u32(w));
    }
    if (size) push(words,length(text));
    return words;
}
export function xencode(text, token) {
    if (!length(text)) return '';
    let v=words_of(text,true),k=words_of(token,false),count=length(v),z=v[count-1],sum=0;
    while (length(k)<4) push(k,0);
    for (let round=0; round<int(6+52/count); round++) {
        sum=u32(sum+0x9e3779b9);
        let e=(sum>>2)&3;
        for (let p=0; p<count; p++) {
            let y=v[(p+1)%count];
            // SRBX1 uses addition between these three terms (not standard XXTEA's XOR).
            let mix=((z>>5)^(y<<2))+(((y>>3)^(z<<4))^(sum^y))+(k[(p&3)^e]^z);
            z=v[p]=u32(v[p]+mix);
        }
    }
    return bytes(v,false);
};
export function encoded_info(text, token) {
    let encoded=b64enc(xencode(text,token)),out='{SRBX1}';
    let standard='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let alphabet='LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA';
    for (let i=0; i<length(encoded); i++) {
        let ch=substr(encoded,i,1),pos=index(standard,ch);
        out+=pos<0 ? ch : substr(alphabet,pos,1);
    }
    return out;
};

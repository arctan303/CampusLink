// Shared helpers for the experimental, explicitly configured HTTP portals.
export function origin(value) {
    if (type(value)!='string' || match(value,/[[:cntrl:]]/)) die('invalid_field:server_url');
    let m=match(value,/^(https?:\/\/[a-zA-Z0-9][a-zA-Z0-9.-]*(:[0-9]{1,5})?)\/?$/);
    if (!m || match(value,/\.\./)) die('invalid_field:server_url');
    if (m[2] && (int(substr(m[2],1))<1 || int(substr(m[2],1))>65535)) die('invalid_field:server_url');
    return m[1];
};
export function parse_json(text, callback) {
    let s=trim(text || '');
    if (callback && substr(s,0,length(callback)+1)==callback+'(' && match(s,/\)[[:space:]]*;?$/))
        s=trim(replace(substr(s,length(callback)+1),/\)[[:space:]]*;?$/,''));
    try { let value=json(s);return type(value)=='object' ? value : null; }
    catch (e) { return null; }
};
export function form_value(text) {
    let out='';
    for(let i=0;i<length(text);i++) {
        let ch=substr(text,i,1);
        if(ch=='%') {
            let pair=substr(text,i+1,2);
            if(length(pair)!=2 || !match(pair,/^[a-fA-F0-9]{2}$/))return null;
            out+=chr(int(pair,16));i+=2;
        } else out+=ch=='+' ? ' ' : ch;
    }
    return match(out,/[[:cntrl:]]/) ? null : out;
};
export function query_value(query,name) {
    let found=null;
    for(let field in split(query,'&')) {
        let separator=index(field,'='),key=form_value(separator<0 ? field : substr(field,0,separator));
        if(key==null)return null;
        if(lc(key)!=name)continue;
        if(found!=null || separator<0)return null;
        found=form_value(substr(field,separator+1));
        if(found==null)return null;
    }
    return found;
};
export function percent_encode(value) {
    let out='';
    for(let i=0;i<length(value);i++) {
        let ch=substr(value,i,1);
        out+=match(ch,/^[a-zA-Z0-9_.~-]$/) ? ch : sprintf('%%%02X',ord(value,i));
    }
    return out;
};
export function redirect_target(reply) {
    if(!reply.ok)return null;
    if(index([301,302,303,307,308],reply.code)>=0) {
        let lines=filter(split(reply.headers || '','\n'),(line)=>!!match(line,/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:/));
        if(length(lines)!=1)return null;
        let value=trim(substr(lines[0],index(lines[0],':')+1));
        return match(value,/[[:cntrl:]]/) ? null : value;
    }
    // A whole, literal redirect script only; never evaluate arbitrary page code.
    if(reply.code==200) {
        let text=trim(reply.body || '');
        let m=match(text,/^<script>[[:space:]]*(top\.self|window|self|top)\.location\.href[[:space:]]*=[[:space:]]*'([^'"]+)'[[:space:]]*;?[[:space:]]*<\/script>$/) ||
            match(text,/^<script>[[:space:]]*(top\.self|window|self|top)\.location\.href[[:space:]]*=[[:space:]]*"([^'"]+)"[[:space:]]*;?[[:space:]]*<\/script>$/);
        if(m && !match(m[2],/[[:cntrl:]\\]/))return m[2];
    }
    return null;
};
export function same_origin_url(target,server) {
    if(type(target)!='string' || match(target,/[[:cntrl:]#\\]/))return null;
    if(substr(target,0,1)=='/' && substr(target,0,2)!='//')target=server+target;
    return substr(target,0,length(server)+1)==server+'/' ? target : null;
};

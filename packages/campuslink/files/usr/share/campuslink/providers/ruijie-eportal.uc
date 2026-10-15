import { http } from '../transport.uc';
import { result } from '../common.uc';
import { origin, parse_json, query_value, percent_encode, redirect_target, same_origin_url } from './portal-common.uc';
import { rsa_encrypt } from './ruijie-rsa.uc';

export function resolve_params(params) { return {...params,server_url:origin(params.server_url)}; };
export function portal_query(reply, ctx) {
    let value=same_origin_url(redirect_target(reply),ctx.params.server_url),prefix=ctx.params.server_url+'/eportal/index.jsp?';
    // Never use a redirected authority to choose where to send credentials.
    if (value==null || substr(value,0,length(prefix))!=prefix) return null;
    let query=substr(value,length(prefix));
    if (!length(query) || length(query)>4096 || match(query,/[[:cntrl:]#]/)) return null;
    let ip=query_value(query,'wlanuserip');
    if(ip==null || !length(ip))return null;
    if(match(ip,/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) && ip!=ctx.route.ip)return null;
    return query;
};
export function check(ctx) {
    let probe=http(ctx,ctx.params.probe_url);
    if (probe.ok && probe.code==204) return result('online','already_online','已联网');
    if (portal_query(probe,ctx)!=null) return result('unauthenticated','portal_detected','锐捷门户要求当前出口登录');
    return result('indeterminate',probe.ok ? 'unknown_response' : probe.reason,'无法确认锐捷门户或联网状态');
};
export function response_result(reply) {
    if (!reply.ok) return result('indeterminate',reply.reason,'锐捷认证请求传输失败');
    let data=reply.code==200 ? parse_json(reply.body) : null;
    if (data?.result==='success') return result('accepted','auth_accepted','锐捷请求已接受，等待联网复查');
    let msg=type(data?.message)=='string' ? data.message : '';
    if (data?.result==='fail' && match(msg,/验证码|加密|encrypt|captcha/i)) return result('rejected','unsupported_auth_variant','锐捷要求验证码或其它密码编码，请核对所选模式');
    if (data?.result==='fail' && match(msg,/密码.*(错误|不正确|不匹配)|用户.*不存在|password.*(wrong|incorrect|invalid)/i)) return result('rejected','invalid_credentials','锐捷拒绝账号或密码，请核对配置');
    if (data?.result==='fail' && match(msg,/频繁|稍后|too many|too frequent/i)) return result('rate_limited','rate_limited','锐捷要求稍后重试',{retry_after_s:90});
    return result('indeterminate','unknown_response','锐捷返回未知结果，请核对协议变体');
};
export function login(ctx) {
    let query=portal_query(http(ctx,ctx.params.probe_url),ctx);
    if (query==null) return result('indeterminate','unknown_response','未获得当前出口的可信锐捷门户参数，未发送密码');
    let mode=ctx.params.password_mode || 'plain',encoding=ctx.params.form_encoding || 'auto';
    if(index(['plain','rsa'],mode)<0 || index(['auto','single','double'],encoding)<0)return result('rejected','unsupported_auth_variant','锐捷密码或表单模式无效');
    let password=ctx.account.values.password;
    if(mode=='rsa') {
        let mac=query_value(query,'mac');
        if(mac==null || !length(mac))return result('rejected','unsupported_rsa_variant','锐捷 RSA 缺少唯一有效 MAC 参数，未发送密码');
        let reply=http(ctx,ctx.params.server_url+'/eportal/InterFace.do?method=pageInfo',{queryString:query},'POST');
        if(!reply.ok)return result('indeterminate',reply.reason,'无法获取锐捷 RSA 公钥，未发送密码');
        let data=reply.code==200 ? parse_json(reply.body) : null;
        if(!data || (data.result!=null && data.result!=='success'))return result('rejected','public_key_unavailable','锐捷未返回有效公钥信息，未发送密码');
        if(data.validCodeUrl!=null && data.validCodeUrl!=='')return result('rejected','unsupported_auth_variant','锐捷要求验证码，未发送密码');
        try { password=rsa_encrypt(password,mac,data.publicKeyExponent,data.publicKeyModulus); }
        catch(e) { return result('rejected','unsupported_rsa_variant','锐捷 RSA 公钥或输入不受支持，未发送密码'); }
    }
    let params={userId:ctx.account.values.username,password,service:ctx.params.service || '',queryString:query,operatorPwd:'',operatorUserId:'',validcode:'',passwordEncrypt:mode=='rsa' ? 'true' : 'false'};
    if(encoding=='double' || (encoding=='auto' && mode=='rsa'))for(let key,value in params)params[key]=percent_encode(value);
    return response_result(http(ctx,ctx.params.server_url+'/eportal/InterFace.do?method=login',params,'POST'));
};

import { http } from '../transport.uc';
import { result } from '../common.uc';
import { origin, parse_json, query_value, redirect_target, same_origin_url } from './portal-common.uc';
import { hmac_md5, encoded_info, sha1 } from './srun-crypto.uc';

export function resolve_params(params) { return {...params,server_url:origin(params.server_url)}; };
export function response_status(data) {
    if(!data)return null;
    let error=data.error,res=data.res;
    if(error!=null && type(error)!='string')return null;
    if(res!=null && type(res)!='string')return null;
    if(error && res && error!=res)return null;
    return error || res || null;
};
export function check(ctx) {
    let probe=http(ctx,ctx.params.probe_url);
    if (probe.ok && probe.code==204) return result('online','already_online','已联网');
    let reply=http(ctx,ctx.params.server_url+'/cgi-bin/rad_user_info',{callback:'campuslink'});
    let data=reply.ok && reply.code==200 ? parse_json(reply.body,'campuslink') : null;
    let status=response_status(data),ecode=data?.ecode;
    if(!(ecode==null || ecode==='' || ecode===0 || ecode==='0'))status=null;
    if (status==='not_online_error') return result('unauthenticated','portal_detected','深澜门户显示当前出口未登录');
    if (status==='ok') return result('indeterminate','authenticated_no_connectivity','门户显示已登录，但联网探测未成功');
    return result('indeterminate',reply.ok ? 'unknown_response' : reply.reason,'无法确认深澜联网状态');
};
export function login_params(ctx, token, ac_id) {
    let username=ctx.account.values.username,password=ctx.account.values.password,ip=ctx.route.ip,acid=''+(ac_id || ctx.params.ac_id);
    let hmd5=hmac_md5(token,ctx.params.hmac_mode=='empty' ? '' : password);
    let payload=sprintf('{"username":%J,"password":%J,"ip":%J,"acid":%J,"enc_ver":"srun_bx1"}',username,password,ip,acid);
    let info=encoded_info(payload,token);
    let checksum='';
    for (let part in [username,hmd5,acid,ip,'200','1',info]) checksum+=token+part;
    return {callback:'campuslink',action:'login',username,password:'{MD5}'+hmd5,ac_id:acid,ip,n:'200',type:'1',info,chksum:sha1(checksum)};
};
export function response_result(reply) {
    if (!reply.ok) return result('indeterminate',reply.reason,'深澜认证请求传输失败');
    let data=reply.code==200 ? parse_json(reply.body,'campuslink') : null;
    let status=response_status(data),ecode=data?.ecode;
    let code_ok=ecode==null || ecode==='' || ecode===0 || ecode==='0';
    if ((status==='ok' || status==='ip_already_online_error') && code_ok) return result('accepted','auth_accepted','深澜请求已接受，等待联网复查');
    let known_credentials=status==='login_error' && index(['E2531','E2553'],ecode)>=0;
    let known_rate=status==='login_error' && index(['E2532','E2533'],ecode)>=0;
    if (status==='password_error' || status==='username_error' || known_credentials) return result('rejected','invalid_credentials','深澜拒绝账号或密码，请核对配置');
    if (status==='speed_limit_error' || known_rate) return result('rate_limited','rate_limited','深澜要求稍后重试',{retry_after_s:90});
    return result('indeterminate','unknown_response','深澜返回未知结果，请核对协议变体');
};
export function discover_ac_id(reply,server) {
    let target=index([301,302,303,307,308],reply.code)>=0 ? redirect_target(reply) : null;
    if(target==null && reply.ok && reply.code==200) {
        let tags=match(reply.body || '',/<meta[^>]+http-equiv=['"]refresh['"][^>]+content=['"]0;[[:space:]]*url=([^'"]+)['"][^>]*>/ig);
        if(length(tags)!=1)return null;
        target=replace(tags[0][1],/&amp;/g,'&');
    }
    let url=same_origin_url(target,server);
    if(!url)return null;
    let m=match(substr(url,length(server)),/^\/(srun_portal_pc|srun_portal_phone|index_1\.html)\?([^#]+)$/);
    if(!m)return null;
    let value=query_value(m[2],'ac_id');
    if(type(value)!='string' || !match(value,/^[0-9]{1,5}$/) || int(value)<1 || int(value)>65535)return null;
    return int(value);
};
export function login(ctx) {
    let acid=ctx.params.ac_id;
    if(acid==null || acid==='') {
        acid=discover_ac_id(http(ctx,ctx.params.server_url+'/'),ctx.params.server_url);
        if(acid==null)return result('indeterminate','ac_id_unavailable','无法自动获取 AC ID，请从登录页填写；未发送登录请求');
    }
    let reply=http(ctx,ctx.params.server_url+'/cgi-bin/get_challenge',{callback:'campuslink',username:ctx.account.values.username,ip:ctx.route.ip});
    if (!reply.ok) return result('indeterminate',reply.reason,'无法获取深澜认证挑战');
    let data=reply.code==200 ? parse_json(reply.body,'campuslink') : null;
    let status=response_status(data),status_absent=data && (data.error==null || data.error==='') && (data.res==null || data.res==='');
    let code_ok=data && (data.ecode==null || data.ecode==='' || data.ecode===0 || data.ecode==='0');
    let explicit_ip=data?.client_ip===ctx.route.ip || data?.online_ip===ctx.route.ip;
    if (!code_ok || (status!=='ok' && !(status_absent && explicit_ip)) || type(data?.challenge)!='string' || match(data.challenge,/[[:cntrl:]]/) || !match(data.challenge,/^[a-zA-Z0-9]{32,64}$/))
        return result('indeterminate','unknown_response','深澜认证挑战无效，未发送登录请求');
    if ((data.client_ip!=null && data.client_ip!=='' && data.client_ip!==ctx.route.ip) || (data.online_ip!=null && data.online_ip!=='' && data.online_ip!==ctx.route.ip))
        return result('indeterminate','binding_unavailable','深澜返回地址与当前 WAN 不一致，未发送登录请求');
    return response_result(http(ctx,ctx.params.server_url+'/cgi-bin/srun_portal',login_params(ctx,data.challenge,acid)));
};

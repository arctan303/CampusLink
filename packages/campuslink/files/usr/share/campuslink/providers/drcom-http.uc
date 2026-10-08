import { http } from '../transport.uc';
import { result, clean_message } from '../common.uc';

export function parse_response(text) {
    let s = trim(text || '');
    if (match(s, /^dr1003[[:space:]]*\(/) && match(s, /\)[[:space:]]*;?$/))
        s = trim(replace(replace(s, /^dr1003[[:space:]]*\(/, ''), /\)[[:space:]]*;?$/, ''));
    try { let data = json(s); return type(data) == 'object' ? data : null; }
    catch (e) { return null; }
};

export function resolve_params(params, context) {
    let resolved = {...params}, server = params.auth_server;
    let preset = context?.school?.defaults || {}, explicit = keys(context?.overrides || {});
    let legacy = match(preset.auth_url || '', /^http:\/\/([a-zA-Z0-9.-]+):801\/eportal\/portal\/login$/);
    if (legacy) {
        if (server == null) server = legacy[1];
        let canonical = {auth_url:'http://'+legacy[1]+':801/eportal/portal/login',status_url:'http://'+legacy[1]+'/',logout_url:'http://'+legacy[1]+':801/eportal/portal/logout'};
        // Canonical inherited URLs are protocol defaults, not user overrides.
        for (let key,value in canonical)
            if (index(explicit,key)<0 && preset[key]==value && resolved[key]==value) delete resolved[key];
    }
    if (server != null && server != '') {
        // A host only: paths, credentials, schemes and ports belong to URL overrides.
        if (!match(server, /^[a-zA-Z0-9][a-zA-Z0-9.-]{0,252}$/) || match(server, /\.\./)) die('invalid_field:auth_server');
        resolved.auth_server = server;
        if (!resolved.auth_url) resolved.auth_url = 'http://' + server + ':801/eportal/portal/login';
        if (!resolved.status_url) resolved.status_url = 'http://' + server + '/';
        if (!resolved.logout_url) resolved.logout_url = 'http://' + server + ':801/eportal/portal/logout';
    }
    if (!resolved.auth_url || !resolved.status_url) die('missing_field:auth_server');
    return resolved;
};

export function check(ctx) {
    let probe = http(ctx, ctx.params.probe_url);
    if (probe.ok && probe.code == 204) return result('online','already_online','已联网');
    let redirect = match(probe.headers, /[Ll]ocation:[[:space:]]*([^[:space:]\r\n]+)/);
    if (match(probe.body, /Dr\.COMWebLoginID_0\.htm|Authentication is required/) || (redirect && redirect[1] == ctx.params.status_url))
        return result('unauthenticated','portal_detected','当前出口需要校园网认证');
    let page = http(ctx, ctx.params.status_url);
    if (page.ok && match(page.body, /Dr\.COMWebLoginID_0\.htm/)) return result('unauthenticated','portal_detected','校园门户显示当前出口未登录');
    if (page.ok && match(page.body, /<!--[[:space:]]*Dr\.COMWebLoginID_1\.htm[[:space:]]*-->/)) return result('indeterminate','authenticated_no_connectivity','门户显示已登录，但联网探测未成功；不重复认证');
    return result('indeterminate', probe.ok ? 'unknown_response' : probe.reason, '无法确认联网状态，稍后重新检查');
};

export function response_result(reply, ctx, operation) {
    if (!reply.ok) return result('indeterminate',reply.reason,'认证请求传输失败');
    let data = parse_response(reply.body);
    if (!data) return result('indeterminate','unknown_response','服务器返回无法识别的响应');
    let msg = clean_message(data.msg, ctx.account.values);
    if (data.result === 1 || data.result === '1') return result('accepted','auth_accepted',operation == 'logout' ? '退出请求已接受' : '登录请求已接受');
    if (match(msg, /interval is too short|操作.*频繁|间隔.*短/i)) return result('rate_limited','rate_limited',msg || '服务器要求稍后重试',{retry_after_s:90});
    if (match(msg, /密码.*(错|不正确)|password.*(wrong|invalid|incorrect)|账号.*不存在|账户.*不存在/i)) return result('rejected','invalid_credentials',msg);
    if((data.result===0 || data.result==='0') && match(msg,/账号.*(使用|在线)|账户.*(停用|禁用)|account.*(in use|disabled)/i))return result('rejected','auth_rejected',msg);
    return result('indeterminate','unknown_response',msg || '校园服务器返回未知结果，稍后复查');
};

export function login(ctx) {
    let mobile = ctx.params.terminal_mode == 'mobile';
    let params = {
        callback:'dr1003',login_method:'1', user_account:(mobile ? ',1,' : ',0,') + ctx.account.values.username,
        user_password:ctx.account.values.password,wlan_user_ip:ctx.route.ip,wlan_user_ipv6:'',wlan_user_mac:'000000000000',
        wlan_ac_ip:'',wlan_ac_name:'',jsVersion:'4.2.1',terminal_type:mobile ? '2' : '1',lang:'zh-cn',v:mobile ? '3387' : '7169'
    };
    return response_result(http(ctx,ctx.params.auth_url,params),ctx,'login');
};

export function logout(ctx) {
    let reply = http(ctx, ctx.params.logout_url, {callback:'dr1003',login_method:'1',wlan_user_ip:ctx.route.ip,wlan_user_ipv6:'',wlan_user_mac:'000000000000',jsVersion:'4.2.1'});
    let response = response_result(reply,ctx,'logout');
    if (response.outcome == 'accepted') {
        sleep(1000);
        let verified = check(ctx);
        if (verified.outcome == 'unauthenticated') return result('unauthenticated','logout_verified','已退出当前出口，自动登录已暂停');
        return result('indeterminate','logout_unverified','退出请求已接受，但未确认当前出口已退出');
    }
    return response;
};

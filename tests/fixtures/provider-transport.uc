// Mounted in an isolated test tree; the production transport is preserved next to it.
import { request_options as build_options } from './transport-real.uc';
export function request_options(ctx,url,params,method) { return build_options(ctx,url,params,method); };
export function http(ctx,url,params,method) {
    let expected=shift(ctx._responses || []);
    if (!expected) die('unexpected_request');
    if (expected.url!=url || (expected.method || 'GET')!=(method || 'GET')) die('wrong_request_destination_or_method');
    push(ctx._requests || [],{url,params,method:method || 'GET',device:ctx.route.device,ip:ctx.route.ip});
    if (expected.params)
        for (let key,value in expected.params) if (params?.[key]!==value) die('wrong_request_parameter:'+key);
    return {ok:true,code:200,body:'',headers:'',...expected.reply};
};

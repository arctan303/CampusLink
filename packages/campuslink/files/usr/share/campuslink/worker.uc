import * as fs from 'fs';
import { handlers } from './providers/registry.uc';
import {read_json,write_json,result,validate_result} from './common.uc';

let ctx=read_json(ARGV[0]), operation=ctx.operation;
let provider=handlers[ctx.connection.provider];
function progress(phase){write_json(ctx.workdir+'/progress.json',{phase});}
function execute(){
    if(operation=='logout')return validate_result(provider.logout(ctx),'logout',ctx.account.values);
    let checked=validate_result(provider.check(ctx),'check',ctx.account.values);
    if(checked.outcome=='online')return checked;
    if(checked.outcome!='unauthenticated' || (operation!='login' && !ctx.allow_login))return checked;
    progress('authenticating');
    let auth=validate_result(provider.login(ctx),'login',ctx.account.values);
    if(auth.outcome!='accepted')return auth;
    progress('verifying');sleep(1000);
    if(ctx.connection.provider=='mock')return result('online','already_online','模拟登录后联网成功');
    let verified=validate_result(provider.check(ctx),'check',ctx.account.values);
    if(verified.outcome=='online')return result('online','login_verified','登录成功');
    return result('indeterminate','verification_failed','登录请求已接受，但联网复查未成功');
}
let reply;
try{reply=execute();}catch(e){reply=result('indeterminate','provider_error','提供商运行失败，请检查配置');}
write_json(ctx.workdir+'/result.json',reply);

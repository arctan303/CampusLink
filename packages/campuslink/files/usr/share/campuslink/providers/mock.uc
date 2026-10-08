import { result } from '../common.uc';

export function check(ctx) {
    if (ctx.params.scenario == 'online') return result('online','already_online','模拟已联网');
    if (ctx.params.scenario == 'timeout') return result('indeterminate','timeout','模拟超时');
    return result('unauthenticated','portal_detected','模拟未登录');
};
export function login(ctx) {
    if (ctx.params.scenario == 'reject') return result('rejected','invalid_credentials','模拟密码错误');
    if (ctx.params.scenario == 'rate_limit') return result('rate_limited','rate_limited','模拟限流',{retry_after_s:90});
    return result('accepted','auth_accepted','模拟登录成功');
};
export function logout(ctx) { return result('unauthenticated','logout_verified','模拟退出成功'); };

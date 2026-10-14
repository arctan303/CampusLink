// Pure eligibility decisions. No network requests or credentials.
export function decide(previous, status, route, event, generation) {
    let next = previous ? {...previous} : {eligible:false,last_check:0,floor:0};
    let binding = route?.up && route.device && route.ip ? route.device + '/' + route.ip : '';
    let token = event?.token || '';
    let changed = previous && (previous.binding != binding || previous.event_token != token);
    if (!previous || changed) {
        next.eligible=false;
        next.floor=changed ? max(int(previous.last_check || 0)+1,int(event?.time || 0)+1) : int(event?.time || 0)+1;
        if (!event?.time && !changed) next.floor=0;
        next.refresh_requested=false;
        next.needs_refresh=changed || !!event?.time;
    }
    next.binding=binding; next.event_token=token;
    next.generation=generation;
    next.reason='source_unknown';
    if (!binding || route.default_down) {
        if (route.default_down && previous?.reason!='default_route_unavailable') {
            next.floor=max(next.floor,int(next.last_check || 0)+1);
            next.refresh_requested=false;
            next.needs_refresh=true;
        }
        next.eligible=false;
        next.reason=!binding?'interface_unavailable':'default_route_unavailable';
        return next;
    }
    if (!status) return next;
    let matches=status.device==route.device && status.ip==route.ip;
    let checked=int(status.last_check || 0);
    let completed=!status.task_id && matches && checked>=next.floor;
    if (matches) next.last_check=max(int(next.last_check || 0),checked);
    if (status.state=='online' && completed && checked>0) {
        next.eligible=true; next.reason='online_verified'; next.refresh_requested=false;next.needs_refresh=false;
    }
    else if (matches && index(['authenticating','verifying','logging_out'],status.state)>=0) {
        // The installed worker enters these phases only after finding a portal.
        next.eligible=false; next.reason='authentication_pending';
        next.floor=max(next.floor,int(next.last_check || 0)+1);
        next.needs_refresh=false;
    }
    else if (completed && index(['portal_detected','invalid_credentials','auth_rejected','rate_limited','verification_failed'],status.reason_code)>=0 && status.state!='disabled') {
        next.eligible=false; next.reason='authentication_required';
        next.floor=max(next.floor,checked+1);
        next.needs_refresh=false;
    }
    else next.reason=matches?'retain_last_decision':'status_binding_mismatch';
    return next;
};

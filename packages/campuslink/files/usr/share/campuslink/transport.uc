import * as fs from 'fs';

function quote(s) { return '"' + replace(replace(replace(replace(s, /\\/g, '\\\\'), /"/g, '\\"'), /\r/g, '\\r'), /\n/g, '\\n') + '"'; }

export function http(ctx, url, params) {
    let dir = ctx.workdir, cfg = dir + '/curl.conf', body = dir + '/body', headers = dir + '/headers';
    let options = [
        'url = ' + quote(url), 'interface = ' + quote('ifhost!' + ctx.route.device + '!' + ctx.route.ip),
        'proxy = ""', 'noproxy = "*"', 'silent', 'compressed', 'globoff', 'connect-timeout = 4', 'max-time = 8',
        'max-filesize = 65536', 'proto = "=http,https"', 'max-redirs = 0', 'output = ' + quote(body),
        'dump-header = ' + quote(headers), 'write-out = "%{http_code}"'
    ];
    if (params) {
        push(options, 'get');
        for (let k, v in params) push(options, 'data-urlencode = ' + quote(k + '=' + v));
    }
    let f = fs.open(cfg, 'w', 0600);
    if (!f) return {ok:false, code:0, reason:'local_io_failed', body:'', headers:''};
    f.write(join('\n', options) + '\n'); f.close();
    // Older target ucode supports only string popen. The command contains only
    // a generated private path; all user values remain in the curl config.
    if (!match(cfg, /^\/[a-zA-Z0-9_\/.-]+$/)) { fs.unlink(cfg);return {ok:false,code:0,reason:'local_io_failed',body:'',headers:''}; }
    let proc = fs.popen('exec /usr/bin/curl -q --config ' + cfg, 'r');
    if (!proc) { fs.unlink(cfg); return {ok:false, code:0, reason:'transport_failed', body:'', headers:''}; }
    let status = trim(proc.read('all') || ''), rc = proc.close();
    fs.unlink(cfg);
    let reply = {ok:rc == 0, code:int(status), body:fs.readfile(body,65536) || '', headers:fs.readfile(headers,8192) || '', reason:rc == 28 ? 'timeout' : rc == 45 ? 'binding_unavailable' : rc == 6 ? 'dns_failed' : 'connect_failed'};
    fs.unlink(body); fs.unlink(headers);
    return reply;
};

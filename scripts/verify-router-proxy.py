"""TLS checks through a Windows WLAN, without changing host routes or proxy settings."""
import argparse
import concurrent.futures
import ipaddress
import json
import os
import socket
import ssl
import struct
import time
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--source', default='192.168.0.139')
p.add_argument('--if-index', type=int, default=8)
p.add_argument('--router', default='192.168.0.1')
p.add_argument('--dns-port', type=int, default=53, help='Use 1053 only if the host blocks standard DNS')
p.add_argument('--mode', choices=['explicit', 'transparent'], required=True)
p.add_argument('--count', type=int, default=32)
p.add_argument('--phase', required=True)
p.add_argument('--out', required=True)
p.add_argument('--hold', action='store_true')
p.add_argument('--stun-count', type=int, default=0, help='Also check transparent UDP through public STUN')
a = p.parse_args()
held = []


def lan_socket(kind=socket.SOCK_STREAM):
    s = socket.socket(socket.AF_INET, kind)
    s.settimeout(15)
    s.bind((a.source, 0))
    if os.name == 'nt':
        s.setsockopt(socket.IPPROTO_IP, 31, struct.pack('!I', a.if_index))
    return s


def dns_a(host):
    xid = os.urandom(2)
    qname = b''.join(bytes([len(x)]) + x.encode('ascii') for x in host.split('.')) + b'\0'
    query = xid + struct.pack('!HHHHH', 0x0100, 1, 0, 0, 0) + qname + struct.pack('!HH', 1, 1)
    with lan_socket(socket.SOCK_DGRAM) as s:
        s.sendto(query, (a.router, a.dns_port))
        data, peer = s.recvfrom(4096)
    if peer != (a.router, a.dns_port) or data[:2] != xid or data[3] & 15:
        raise RuntimeError('DNS response mismatch or error')

    def skip_name(pos):
        while data[pos]:
            if data[pos] & 0xC0 == 0xC0:
                return pos + 2
            pos += data[pos] + 1
        return pos + 1

    qd, an = struct.unpack_from('!HH', data, 4)
    pos = 12
    for _ in range(qd):
        pos = skip_name(pos) + 4
    ips = []
    for _ in range(an):
        pos = skip_name(pos)
        typ, cls, ttl, size = struct.unpack_from('!HHIH', data, pos)
        pos += 10
        if typ == 1 and cls == 1 and size == 4:
            ips.append(socket.inet_ntoa(data[pos:pos + 4]))
        pos += size
    if not ips:
        raise RuntimeError('DNS returned no IPv4 addresses')
    return ips


dns_results = {}
if a.mode == 'transparent':
    for host in ['www.gstatic.com', 'www.cloudflare.com', 'www.baidu.com']:
        dns_results[host] = dns_a(host)


def read_header(conn):
    data = b''
    while b'\r\n\r\n' not in data and len(data) < 65536:
        part = conn.recv(4096)
        if not part:
            break
        data += part
    return data


def request(n):
    host, path, status = ('www.gstatic.com', '/generate_204', 204)
    if n == a.count:
        host, path, status = ('www.cloudflare.com', '/cdn-cgi/trace', 200)
    elif n == a.count + 1:
        host, path, status = ('www.baidu.com', '/', 200)
    row = {'host': host, 'path': path, 'mode': a.mode}
    raw = None
    conn = None
    start = time.monotonic()
    try:
        raw = lan_socket()
        row['source_port'] = raw.getsockname()[1]
        if a.mode == 'explicit':
            raw.connect((a.router, 7890))
            raw.sendall(f'CONNECT {host}:443 HTTP/1.1\r\nHost: {host}:443\r\n\r\n'.encode('ascii'))
            hdr = read_header(raw)
            row['connect_status'] = hdr.split(b'\r\n', 1)[0].decode('ascii', 'replace')
            if b' 200 ' not in hdr.split(b'\r\n', 1)[0]:
                raise RuntimeError('Proxy CONNECT rejected')
        else:
            ip = dns_results[host][n % len(dns_results[host])]
            row['destination'] = ip
            row['fake_ip'] = ipaddress.ip_address(ip) in ipaddress.ip_network('198.18.0.0/16')
            raw.connect((ip, 443))
        conn = ssl.create_default_context().wrap_socket(raw, server_hostname=host)
        row['tls_verified'] = True
        row['tls_protocol'] = conn.version()
        conn.sendall((f'GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: keep-alive\r\n'
                      'User-Agent: CampusLink-proxy-validation\r\n\r\n').encode('ascii'))
        data = read_header(conn)
        row['status'] = data.split(b'\r\n', 1)[0].decode('ascii', 'replace')
        row['ok'] = row['status'].split(' ')[1] == str(status)
        if host == 'www.cloudflare.com':
            while len(data) < 32768 and b'loc=' not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            row['trace'] = data.split(b'\r\n\r\n', 1)[-1].decode('ascii', 'replace')
        if a.hold and row['ok']:
            held.append(conn)
            conn = None
            raw = None
    except Exception as e:
        row['ok'] = False
        row['error'] = type(e).__name__ + ': ' + str(e)
    finally:
        if conn:
            conn.close()
        elif raw:
            raw.close()
    row['seconds'] = round(time.monotonic() - start, 3)
    return row


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    rows = list(pool.map(request, range(a.count + 2)))
if a.stun_count:
    if a.mode != 'transparent':
        raise SystemExit('STUN check requires transparent mode')
    stun_host = 'stun.cloudflare.com'
    dns_results[stun_host] = dns_a(stun_host)
    for _ in range(a.stun_count):
        row = {'host': stun_host, 'protocol': 'udp', 'destination': dns_results[stun_host][0]}
        s = lan_socket(socket.SOCK_DGRAM)
        try:
            row['source_port'] = s.getsockname()[1]
            transaction = os.urandom(12)
            s.sendto(struct.pack('!HHI', 1, 0, 0x2112A442) + transaction,
                     (row['destination'], 3478))
            reply, peer = s.recvfrom(2048)
            row['ok'] = (peer == (row['destination'], 3478)
                         and len(reply) >= 20 and reply[:2] == b'\x01\x01'
                         and reply[4:8] == struct.pack('!I', 0x2112A442)
                         and reply[8:20] == transaction)
            if a.hold and row['ok']:
                held.append(s)
                s = None
        except Exception as e:
            row['ok'] = False
            row['error'] = type(e).__name__ + ': ' + str(e)
        finally:
            if s:
                s.close()
        rows.append(row)
report = {'phase': a.phase, 'mode': a.mode, 'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
          'source': a.source, 'interface_index': a.if_index, 'host_routes_modified': False,
          'dns_port': a.dns_port, 'dns': dns_results, 'connections': rows}
out = Path(a.out)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(report, ensure_ascii=True, indent=2), encoding='utf-8')
print(json.dumps({'phase': a.phase, 'success': sum(bool(r['ok']) for r in rows), 'total': len(rows),
                  'dns': dns_results, 'errors': [r for r in rows if not r['ok']],
                  'held': len(held)}, ensure_ascii=True), flush=True)
if a.hold:
    input('Connections held for passive router capture; Enter releases.\n')
for conn in held:
    conn.close()
if not all(r['ok'] for r in rows):
    raise SystemExit(1)

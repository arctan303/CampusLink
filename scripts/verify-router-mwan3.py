"""Probe this router through an existing Windows LAN adapter; change no host routes."""
import argparse, concurrent.futures, json, os, socket, ssl, struct, time
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--source", default="192.168.0.139")
p.add_argument("--if-index", type=int, default=8)
p.add_argument("--count", type=int, default=32)
p.add_argument("--phase", required=True)
p.add_argument("--out", required=True)
p.add_argument("--probe-ip", action="append")
p.add_argument("--tls-ip")
p.add_argument("--hold", action="store_true", help="Keep HTTP sockets alive until stdin confirms capture")
a = p.parse_args()
held = []

def lan_socket(kind=socket.SOCK_STREAM):
    s = socket.socket(socket.AF_INET, kind)
    s.settimeout(8)
    s.bind((a.source, 0))
    if os.name == "nt":
        s.setsockopt(socket.IPPROTO_IP, 31, struct.pack("!I", a.if_index))
    return s

def dns_a(host):
    xid = os.urandom(2)
    qname = b"".join(bytes([len(x)]) + x.encode("ascii") for x in host.split(".")) + b"\0"
    query = xid + struct.pack("!HHHHH", 0x0100, 1, 0, 0, 0) + qname + struct.pack("!HH", 1, 1)
    with lan_socket(socket.SOCK_DGRAM) as s:
        s.sendto(query, ("192.168.0.1", 53))
        data, peer = s.recvfrom(4096)
    if data[:2] != xid or data[3] & 15:
        raise RuntimeError("DNS response mismatch or error")
    def skip_name(pos):
        while data[pos]:
            if data[pos] & 0xC0 == 0xC0:
                return pos + 2
            pos += data[pos] + 1
        return pos + 1
    qd, an = struct.unpack_from("!HH", data, 4)
    pos = 12
    for _ in range(qd):
        pos = skip_name(pos) + 4
    ips = []
    for _ in range(an):
        pos = skip_name(pos)
        typ, cls, ttl, size = struct.unpack_from("!HHIH", data, pos)
        pos += 10
        if typ == 1 and cls == 1 and size == 4:
            ips.append(socket.inet_ntoa(data[pos:pos+4]))
        pos += size
    if not ips:
        raise RuntimeError("DNS returned no IPv4 addresses")
    return ips

probe_host = "connectivitycheck.platform.hicloud.com"
probe_ips = a.probe_ip or dns_a(probe_host)
tls_ips = [a.tls_ip] if a.tls_ip else dns_a("www.baidu.com")

def request(host, ip, path, tls=False):
    row = {"host": host, "destination": ip, "tls": tls}
    start = time.monotonic()
    try:
        with lan_socket() as raw:
            row["source_port"] = raw.getsockname()[1]
            raw.connect((ip, 443 if tls else 80))
            conn = ssl.create_default_context().wrap_socket(raw, server_hostname=host) if tls else raw
            if tls:
                row["tls_protocol"] = conn.version()
                row["tls_verified"] = True
            conn.sendall(("GET " + path + " HTTP/1.1\r\nHost: " + host +
                          "\r\nConnection: close\r\nUser-Agent: CampusLink-mwan-validation\r\n\r\n").encode("ascii"))
            data = b""
            while b"\r\n" not in data and len(data) < 8192:
                part = conn.recv(4096)
                if not part:
                    break
                data += part
            row["status"] = data.split(b"\r\n", 1)[0].decode("ascii", "replace")
            row["ok"] = row["status"].split(" ")[1] == ("200" if tls else "204")
            if a.hold and not tls:
                held.append(raw.dup())
            if tls:
                conn.close()
    except Exception as e:
        row["ok"] = False
        row["error"] = type(e).__name__ + ": " + str(e)
    row["seconds"] = round(time.monotonic() - start, 3)
    return row

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    rows = list(pool.map(lambda n: request(probe_host, probe_ips[n % len(probe_ips)], "/generate_204"),
                         range(a.count)))
rows.append(request("www.baidu.com", tls_ips[0], "/", True))
report = {"phase": a.phase, "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
          "source": a.source, "interface_index": a.if_index,
          "routing_table_modified": False, "dns_via_router_wlan": not bool(a.probe_ip or a.tls_ip),
          "probe_ips": probe_ips, "connections": rows}
out = Path(a.out)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"phase": a.phase, "success": sum(r["ok"] for r in rows),
                  "total": len(rows), "tls": rows[-1], "ports": [r["source_port"] for r in rows if "source_port" in r]},
                 ensure_ascii=False), flush=True)
if a.hold:
    input("HTTP connections held for passive router capture; press Enter to release.\n")
    for conn in held:
        conn.close()
if not all(r["ok"] for r in rows):
    raise SystemExit(1)

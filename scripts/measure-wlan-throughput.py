"""Bounded download benchmark through an existing Windows WLAN; no host route changes."""
import argparse, concurrent.futures, http.client, json, os, socket, struct, threading, time
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument("--source",default="192.168.0.139")
p.add_argument("--if-index",type=int,default=8)
p.add_argument("--ip",action="append",required=True)
p.add_argument("--workers",type=int,default=16)
p.add_argument("--seconds",type=float,default=14)
p.add_argument("--warmup",type=float,default=2)
p.add_argument("--out",required=True)
p.add_argument("--hold",action="store_true")
p.add_argument("--image-size",type=int,choices=[1000,4000],default=1000)
p.add_argument("--node",default="speedtest1.online.sh.cn")
p.add_argument("--port",type=int,default=8080)
p.add_argument("--download-path")
a=p.parse_args()
if not 1<=a.workers<=32 or not 2<=a.seconds<=30 or not 0<=a.warmup<a.seconds or not 1<=a.port<=65535:
    raise SystemExit("Invalid bounded test parameters")
host=a.node
port=a.port
path=a.download_path or f"/speedtest/random{a.image_size}x{a.image_size}.jpg"
lock=threading.Lock()
barrier=threading.Barrier(a.workers+1)
totals=[0]*a.workers
connections=[]
errors=[]
held=[]
start=0

class LanHTTP(http.client.HTTPConnection):
    def __init__(self,ip):
        super().__init__(host,port=port,timeout=6)
        self.ip=ip
    def connect(self):
        s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        s.settimeout(6)
        s.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1024*1024)
        s.bind((a.source,0))
        if os.name=="nt":
            s.setsockopt(socket.IPPROTO_IP,31,struct.pack("!I",a.if_index))
        s.connect((self.ip,port))
        self.sock=s

def worker(n):
    barrier.wait()
    conn=LanHTTP(a.ip[n%len(a.ip)])
    response=None
    phase="connect"
    received=0
    source_port=None
    try:
        while time.monotonic()-start<a.seconds:
            phase="request"
            received=0
            conn.request("GET",path,headers={"User-Agent":"curl/8.22.0","Accept":"*/*","Cache-Control":"no-cache"})
            source_port=conn.sock.getsockname()[1]
            phase="headers"
            response=conn.getresponse()
            with lock:
                connections.append({"worker":n,"destination":conn.ip,"source_port":source_port,
                                    "status":response.status})
            if response.status!=200:
                raise RuntimeError("HTTP "+str(response.status))
            phase="download"
            while time.monotonic()-start<a.seconds:
                chunk=response.read(262144)
                if not chunk:break
                received+=len(chunk)
                with lock:totals[n]+=len(chunk)
            response.close()
            response=None
        if a.hold and conn.sock:
            with lock:held.append(conn.sock.dup())
    except Exception as e:
        if a.hold and conn.sock:
            with lock:held.append(conn.sock.dup())
        with lock:errors.append({"worker":n,"phase":phase,"source_port":source_port,"received_bytes":received,
                                 "elapsed":round(time.monotonic()-start,3),"error":type(e).__name__+": "+str(e)})
    finally:
        if response:response.close()
        conn.close()

samples=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
    futures=[pool.submit(worker,n) for n in range(a.workers)]
    start=time.monotonic()
    barrier.wait()
    while time.monotonic()-start<a.seconds:
        with lock:count=sum(totals)
        samples.append({"seconds":round(time.monotonic()-start,6),"bytes":count})
        time.sleep(0.2)
    for future in futures:future.result()
    with lock:count=sum(totals)
    samples.append({"seconds":round(time.monotonic()-start,6),"bytes":count})
first=min((s for s in samples if s["seconds"]>=a.warmup),key=lambda s:s["seconds"])
last=max((s for s in samples if s["seconds"]<=a.seconds),key=lambda s:s["seconds"])
mbps=(last["bytes"]-first["bytes"])*8/(last["seconds"]-first["seconds"])/1e6
report={"timestamp":time.strftime("%Y-%m-%dT%H:%M:%S%z"),"source":a.source,"interface_index":a.if_index,
        "node":host,"port":port,"destination_ips":a.ip,"workers":a.workers,"duration":a.seconds,
        "download_path":path,"per_worker_bytes":totals,
        "warmup":a.warmup,"measured_seconds":last["seconds"]-first["seconds"],"payload_mbps":mbps,
        "payload_bytes":sum(totals),"routing_table_modified":False,"samples":samples,
        "connections":connections,"errors":errors}
out=Path(a.out);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2),encoding="utf-8")
print(json.dumps({"mbps":round(mbps,2),"payload_MB":round(sum(totals)/1e6,2),"requests":len(connections),
                  "errors":errors,"unique_connections":len(set((c['destination'],c['source_port']) for c in connections))}),flush=True)
if a.hold:
    input("Benchmark complete; sockets held for passive capture. Press Enter to release.\n")
for s in held:s.close()
if errors:raise SystemExit(1)

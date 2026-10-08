"""Inspect IPK payloads, compare reproducibility and produce a clean source ZIP.

Optional --secrets points to a private JSON outside the repository. Values are
checked without being printed or added to any artifact.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import zipfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--secrets',type=Path)
args=parser.parse_args()
inputs=sorted(p for name in ['packages','scripts','tests','docs'] for p in (ROOT/name).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
inputs += [ROOT/'README.md',ROOT/'LICENSE',ROOT/'.gitignore']
needles=[]
def values(v):
    if isinstance(v,dict):
        for item in v.values(): yield from values(item)
    elif isinstance(v,list):
        for item in v: yield from values(item)
    elif isinstance(v,str) and v: yield v.encode()
if args.secrets: needles=list(values(json.loads(args.secrets.read_text(encoding='utf-8-sig'))))
def inspect(data,name):
    marker=b'-----BEGIN OPENSSH PRIVATE KEY-----'
    if data.startswith(marker) or b'\n'+marker in data or any(x in data for x in needles):raise SystemExit('sensitive value detected in '+name)
for p in inputs:inspect(p.read_bytes(),p.relative_to(ROOT).as_posix())
subprocess.run([sys.executable,str(ROOT/'scripts/build_ipk.py')],check=True,stdout=subprocess.DEVNULL)
packages=[ROOT/'dist'/name for name in ['campuslink_0.3.0-1_all.ipk','luci-app-campuslink_0.3.0-1_all.ipk']]
before={p.name:p.read_bytes() for p in packages}
subprocess.run([sys.executable,str(ROOT/'scripts/build_ipk.py')],check=True,stdout=subprocess.DEVNULL)
for path in packages:
    assert path.read_bytes()==before[path.name], 'non-reproducible package'
    with tarfile.open(path,'r:gz') as outer:
        for archive in ['control.tar.gz','data.tar.gz']:
            with tarfile.open(fileobj=io.BytesIO(outer.extractfile(archive).read()),mode='r:gz') as inner:
                names=set()
                for member in inner:
                    assert not member.name.startswith('/') and '..' not in Path(member.name).parts
                    assert member.uid==0 and member.gid==0 and not member.issym() and not member.islnk()
                    if member.isfile():
                        parents=[parent.as_posix() for parent in Path(member.name).parents if parent.as_posix()!='.']
                        assert all(parent in names for parent in parents),'parent directory missing'
                        data=inner.extractfile(member).read();inspect(data,path.name+':'+member.name)
                        if member.name.endswith('.json'):json.loads(data)
                        assert '/etc/campuslink/config.json' not in '/'+member.name
                    names.add(member.name.rstrip('/'))
dest=ROOT/'dist/CampusLink-0.3.0-source.zip'
with zipfile.ZipFile(dest,'w',compression=zipfile.ZIP_DEFLATED) as z:
    for p in sorted(inputs):
        info=zipfile.ZipInfo('CampusLink/'+p.relative_to(ROOT).as_posix(),date_time=(2026,10,8,0,0,0))
        info.compress_type=zipfile.ZIP_DEFLATED
        info.external_attr=0o100644<<16
        z.writestr(info,p.read_bytes())
print('PASS: deterministic IPKs, parent directories, root ownership, clean payloads/source and no injected credentials')
print('Source archive: '+str(dest))

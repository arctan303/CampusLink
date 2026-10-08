"""Build deterministic, architecture-independent OpenWrt IPKs without a compiler.

The payload is exclusively ucode, JavaScript, JSON and a procd shell init script.
SDK Makefiles are also provided. This builder targets OPKG, not APK.
"""
from pathlib import Path
import gzip
import hashlib
import io
import tarfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.3.0-1'
DIST = ROOT / 'dist'
DIST.mkdir(exist_ok=True)

def archive(entries):
    entries = list(entries)
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w', format=tarfile.GNU_FORMAT) as tar:
        directories = {str(parent) for name, _, _ in entries for parent in Path(name).parents if str(parent) != '.'}
        for name in sorted(directories, key=lambda n:(n.count('/'),n)):
            info = tarfile.TarInfo(name.replace('\\','/')+'/')
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.uid = info.gid = info.mtime = 0
            tar.addfile(info)
        for name, content, mode in sorted(entries):
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = mode
            info.uid = info.gid = 0
            info.mtime = 0
            tar.addfile(info, io.BytesIO(content))
    return gzip.compress(buf.getvalue(), mtime=0)

def files(directory, prefix=''):
    for p in directory.rglob('*'):
        if p.is_file():
            mode = 0o755 if 'etc/init.d/' in p.as_posix() else 0o644
            yield prefix+p.relative_to(directory).as_posix(), p.read_bytes(), mode

def package(name, description, depends, entries, scripts):
    payload = archive(list(entries))
    control = f'Package: {name}\nVersion: {VERSION}\nArchitecture: all\nMaintainer: CampusLink contributors\nSection: net\nPriority: optional\nLicense: MIT\nDescription: {description}\nDepends: {depends}\n'
    meta = [('control',control.encode(),0o644)] + [(key,value.encode(),0o755) for key,value in scripts.items()]
    output = archive([('debian-binary',b'2.0\n',0o644),('control.tar.gz',archive(meta),0o644),('data.tar.gz',payload,0o644)])
    dest = DIST/f'{name}_{VERSION}_all.ipk'
    dest.write_bytes(output)
    print(f'{dest.name}: {len(output)} bytes sha256={hashlib.sha256(output).hexdigest()}')

package('campuslink','CampusLink campus authentication service',
        'ucode, ucode-mod-fs, ucode-mod-ubus, ucode-mod-uloop, curl, ca-bundle',
        files(ROOT/'packages/campuslink/files'),{
            'postinst':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { /etc/init.d/campuslink enable; /etc/init.d/campuslink start; }\nexit 0\n',
            'prerm':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { /etc/init.d/campuslink stop; /etc/init.d/campuslink disable; }\nexit 0\n'
        })
ui_entries = list(files(ROOT/'packages/luci-app-campuslink/root')) + list(files(ROOT/'packages/luci-app-campuslink/htdocs','www/'))
package('luci-app-campuslink','CampusLink LuCI campus authentication interface',
        'campuslink, luci-base', ui_entries,{
            'postinst':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { rm -f /tmp/luci-indexcache; /etc/init.d/rpcd reload; }\nexit 0\n',
            'postrm':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { rm -f /tmp/luci-indexcache; /etc/init.d/rpcd reload; }\nexit 0\n'
        })

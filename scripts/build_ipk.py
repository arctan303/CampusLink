"""Build deterministic, architecture-independent OpenWrt IPKs without a compiler.

The payload is exclusively ucode, JavaScript, JSON and a procd shell init script.
SDK Makefiles are also provided. This builder targets OPKG, not APK.
"""
from pathlib import Path
import argparse
import gzip
import hashlib
import io
import tarfile

ROOT = Path(__file__).resolve().parents[1]
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
            name = prefix+p.relative_to(directory).as_posix()
            content = p.read_bytes().replace(b'\r\n', b'\n')
            mode = 0o755 if content.startswith(b'#!/bin/sh') else 0o644
            yield name, content, mode

def version(name):
    fields = dict(line.split(':=', 1) for line in (ROOT/'packages'/name/'Makefile').read_text().splitlines() if ':=' in line)
    return fields['PKG_VERSION']+'-'+fields['PKG_RELEASE']

def package(name, description, depends, entries, scripts, conffiles=()):
    package_version = version(name)
    payload = archive(list(entries))
    control = f'Package: {name}\nVersion: {package_version}\nArchitecture: all\nMaintainer: CampusLink contributors\nSection: net\nPriority: optional\nLicense: MIT\nDescription: {description}\nDepends: {depends}\n'
    meta = [('control',control.encode(),0o644)] + [(key,value.encode(),0o755) for key,value in scripts.items()]
    if conffiles:
        meta.append(('conffiles', ('\n'.join(conffiles)+'\n').encode(), 0o644))
    output = archive([('debian-binary',b'2.0\n',0o644),('control.tar.gz',archive(meta),0o644),('data.tar.gz',payload,0o644)])
    dest = DIST/f'{name}_{package_version}_all.ipk'
    dest.write_bytes(output)
    print(f'{dest.name}: {len(output)} bytes sha256={hashlib.sha256(output).hexdigest()}')

def build(name):
    if name == 'campuslink':
        package('campuslink','CampusLink campus authentication service',
            'ucode, ucode-mod-fs, ucode-mod-ubus, ucode-mod-uloop, curl, ca-bundle',
            files(ROOT/'packages/campuslink/files'),{
                'postinst':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { /etc/init.d/campuslink enable; /etc/init.d/campuslink start; }\nexit 0\n',
                'prerm':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { /etc/init.d/campuslink stop; /etc/init.d/campuslink disable; }\nexit 0\n'
            })
    elif name == 'luci-app-campuslink':
        ui_entries = list(files(ROOT/'packages/luci-app-campuslink/root')) + list(files(ROOT/'packages/luci-app-campuslink/htdocs','www/'))
        package('luci-app-campuslink','CampusLink LuCI campus authentication interface',
            'campuslink, luci-base, rpcd, busybox', ui_entries,{
                'postinst':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { rm -f /tmp/luci-indexcache; /etc/init.d/rpcd reload; ubus list campuslink.diagnostics | grep -qx campuslink.diagnostics || /etc/init.d/rpcd restart; }\nexit 0\n',
                'postrm':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { rm -f /tmp/luci-indexcache; /etc/init.d/rpcd restart; }\nexit 0\n'
            })
    elif name == 'campuslink-mwan3':
        package(name, 'CampusLink integration for mwan3-nft',
                'campuslink, mwan3-nft, rpcd, ucode-mod-fs, ucode-mod-ubus, ucode-mod-uci, ucode-mod-uloop',
                files(ROOT/'packages/campuslink-mwan3/files'), {
                    'prerm':'#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || { /etc/init.d/campuslink-mwan3 stop; /etc/init.d/campuslink-mwan3 disable; }\nexit 0\n'
                }, conffiles=['/etc/campuslink-mwan3/config.json'])

PACKAGES = ['campuslink', 'luci-app-campuslink', 'campuslink-mwan3']
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', nargs='*', choices=PACKAGES)
    args = parser.parse_args()
    for name in args.packages or PACKAGES:
        build(name)

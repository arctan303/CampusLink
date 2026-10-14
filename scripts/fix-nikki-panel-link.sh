#!/bin/sh
# Match this installed MetaCubeXD's hash-route deep-link format.
set -eu
B=${1:?root-only panel backup directory required}
case "$B" in /root/campuslink-nikki-panel-*) ;; *) exit 2 ;; esac
[ -d "$B" ]
J=/www/luci-static/resources/tools/nikki.js
umask 077
[ -f "$J" ]
if grep -Fq '/ui/#/setup?${query}' "$J"; then
    printf 'Dashboard link already compatible.\n'
    exit 0
fi
grep -Fq '/ui/?${query}' "$J"
if [ -e "$B/nikki-tools.js.before" ]; then
    cmp -s "$J" "$B/nikki-tools.js.before"
else
    cp -p "$J" "$B/nikki-tools.js.before"
fi
cat > "$B/fix-link.uc" <<'UC'
import * as fs from 'fs';
let path = '/www/luci-static/resources/tools/nikki.js';
let old = 'url = `${protocol}://${window.location.hostname}:${port}/ui/?${query}`;';
let next = 'url = `${protocol}://${window.location.hostname}:${port}/ui/#/setup?${query}`;';
let parts = split(fs.readfile(path), old);
if (length(parts) != 2) die('Unexpected installed dashboard link; no replacement performed\n');
if (!fs.writefile(path, parts[0] + next + parts[1])) die('Dashboard link write failed\n');
UC
ucode "$B/fix-link.uc"
grep -Fq '/ui/#/setup?${query}' "$J"
printf 'Dashboard link updated for local hash-route auto-login.\n'

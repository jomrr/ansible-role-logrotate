#!/usr/bin/bash
set -euo pipefail

# logrotate-all does not forward arguments. Match the package's input selection
# and pass --debug to logrotate itself so the check cannot rotate live logs.
configs=(/usr/etc/logrotate.conf)
if [[ -e /etc/logrotate.conf ]]; then
    configs=(/etc/logrotate.conf)
fi

dirs=(/etc/logrotate.d)
if [[ -d /usr/etc/logrotate.d ]]; then
    dirs+=(/usr/etc/logrotate.d)
fi

# The package orders relative filenames across both trees. A local file or
# symlink shadows the vendor entry with the same relative name.
names=$(find "${dirs[@]}" -type f -printf '%P\n' | sort -u)
while IFS= read -r name; do
    [[ -n $name ]] || continue
    if [[ $name =~ [[:space:]] ]]; then
        printf 'logrotate-all cannot load a filename containing whitespace: %s\n' "$name" >&2
        exit 1
    fi
    if [[ -e /etc/logrotate.d/$name ]]; then
        configs+=("/etc/logrotate.d/$name")
    else
        configs+=("/usr/etc/logrotate.d/$name")
    fi
done <<< "$names"

exec /usr/sbin/logrotate --debug "${configs[@]}"

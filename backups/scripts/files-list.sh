#!/bin/sh
# runs inside the backup container as its own archive-pre hook, lists what the panel lets users pick from when restoring

META_DIR="/tmp/backup_meta"
[ -d "$META_DIR" ] || exit 0

# size, mtime and path relative to $1 per line, skipping what BACKUP_EXCLUDE_REGEXP keeps out of the archive
list_files() {
    find "$1" -type f -exec stat -c '%s %Y %n' {} + 2>/dev/null \
        | awk -v src="$1/" '{
            re = ENVIRON["BACKUP_EXCLUDE_REGEXP"]
            path = $0; sub(/^[0-9]+ [0-9]+ /, "", path)
            if (re != "" && path ~ re) next
            print $1 "\t" $2 "\t" substr(path, length(src) + 1)
        }'
}

# website files
if [ -d /backup/html ]; then
    list_files /backup/html > "$META_DIR/.files.tsv.tmp" && mv -f "$META_DIR/.files.tsv.tmp" "$META_DIR/files.tsv"
fi

# virtual host files, 01-vhosts sorts before html/ in the archive, plain vhosts is the old mount
for vhosts in /backup/01-vhosts /backup/vhosts; do
    [ -d "$vhosts" ] || continue
    list_files "$vhosts" > "$META_DIR/.vhosts.tsv.tmp" && mv -f "$META_DIR/.vhosts.tsv.tmp" "$META_DIR/vhosts.tsv"
    break
done

# dns zone files
if [ -d /backup/dns ]; then
    list_files /backup/dns > "$META_DIR/.dns.tsv.tmp" && mv -f "$META_DIR/.dns.tsv.tmp" "$META_DIR/dns.tsv"
fi

# one line per mailbox: size, message count and domain/user, from the real mail dirs mounted under /backup/emails
if [ -d /backup/emails ]; then
    {
        find /backup/emails -mindepth 2 -maxdepth 2 -type d | sed 's#^#D #'
        find /backup/emails -mindepth 3 -type f -exec stat -c 'F %s %n' {} + 2>/dev/null
    } | awk '
        $1 == "D" { box = substr($0, 3); sub(/^\/backup\/emails\//, "", box); size[box] += 0; count[box] += 0; next }
        {
            path = $0; sub(/^F [0-9]+ /, "", path); sub(/^\/backup\/emails\//, "", path)
            n = split(path, p, "/"); box = p[1] "/" p[2]
            size[box] += $2
            if (path ~ /\/(cur|new)\/[^\/]+$/) count[box]++
        }
        END { for (b in size) print size[b] "\t" count[b] "\t" b }
    ' > "$META_DIR/.mail.tsv.tmp" && mv -f "$META_DIR/.mail.tsv.tmp" "$META_DIR/mail.tsv"
fi

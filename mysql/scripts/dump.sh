#!/bin/bash
# runs inside the user's mysql/mariadb container as the backup's archive-pre hook

set -o pipefail

excluded_databases=("information_schema" "performance_schema" "mysql" "sys" "phpmyadmin")
DUMP_DIR="/tmp/dumps"
META_DIR="/tmp/backup_meta"

mkdir -p "$DUMP_DIR"

is_excluded() {
    local value="$1"
    for excluded in "${excluded_databases[@]}"; do
        [[ "$excluded" == "$value" ]] && return 0
    done
    return 1
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if command -v mariadb >/dev/null 2>&1; then
    echo "MariaDB detected"
    client="mariadb"
    dump_cmd="mariadb-dump"
    command -v mariadb-dump >/dev/null 2>&1 || { echo "mariadb-dump not found, falling back to mysqldump"; dump_cmd="mysqldump"; }
elif command -v mysql >/dev/null 2>&1; then
    echo "MySQL detected"
    client="mysql"
    dump_cmd="mysqldump"
else
    echo "MySQL/MariaDB not installed or not in PATH"
    exit 1
fi

databases=$("$client" -N -B -e "SHOW DATABASES;") || { echo "Could not list databases"; exit 1; }

dumped=()
failed=()
while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    if is_excluded "$db"; then
        echo "- Skipping excluded database: $db"
        continue
    fi
    echo "- Dumping database: $db"
    # single-transaction gives a consistent innodb snapshot without locking the site's tables
    if "$dump_cmd" --single-transaction --quick --routines --triggers --events "$db" > "$DUMP_DIR/$db.sql.tmp"; then
        mv -f "$DUMP_DIR/$db.sql.tmp" "$DUMP_DIR/$db.sql"
        dumped+=("$db")
    else
        echo "  ERROR: dump failed for database: $db"
        rm -f "$DUMP_DIR/$db.sql.tmp"
        failed+=("$db")
    fi
done <<< "$databases"

# keep going past a broken db so the log lists every failure, but still fail the run so the admin hears about it
if (( ${#failed[@]} )); then
    echo "Failed to dump ${#failed[@]} database(s): ${failed[*]}"
    exit 1
fi

# list of dumps for the archive's 00-meta/ folder, lets the panel index a backup without downloading it
if [[ -d "$META_DIR" ]]; then
    list=""
    sizes=""
    for db in "${dumped[@]}"; do
        name="\"$(json_escape "$db")\""
        list+="${list:+,}$name"
        sizes+="${sizes:+,}$name:$(wc -c < "$DUMP_DIR/$db.sql" | tr -d ' ')"
    done
    printf '{"format":1,"engine":"mysql","created_at":"%s","databases":[%s],"sizes":{%s}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$list" "$sizes" > "$META_DIR/.mysql.json.tmp" \
        && mv -f "$META_DIR/.mysql.json.tmp" "$META_DIR/mysql.json"
fi

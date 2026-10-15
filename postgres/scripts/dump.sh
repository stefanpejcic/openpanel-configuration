#!/bin/bash
# runs inside the user's postgres container as the backup's archive-pre hook

set -o pipefail

DUMP_DIR="/tmp/dumps"
META_DIR="/tmp/backup_meta"
PG_USER="${POSTGRES_USER:-postgres}"

mkdir -p "$DUMP_DIR"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

databases=$(psql -U "$PG_USER" -d postgres -X -A -t -c "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY datname;") \
    || { echo "Could not list databases"; exit 1; }

dumped=()
failed=()
while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    echo "- Dumping database: $db"
    # plain sql so the panel can restore it by piping into psql
    if pg_dump -U "$PG_USER" -d "$db" > "$DUMP_DIR/$db.sql.tmp"; then
        mv -f "$DUMP_DIR/$db.sql.tmp" "$DUMP_DIR/$db.sql"
        dumped+=("$db")
    else
        echo "  ERROR: dump failed for database: $db"
        rm -f "$DUMP_DIR/$db.sql.tmp"
        failed+=("$db")
    fi
done <<< "$databases"

if (( ${#failed[@]} )); then
    echo "Failed to dump ${#failed[@]} database(s): ${failed[*]}"
    exit 1
fi

if [[ -d "$META_DIR" ]]; then
    list=""
    sizes=""
    for db in "${dumped[@]}"; do
        name="\"$(json_escape "$db")\""
        list+="${list:+,}$name"
        sizes+="${sizes:+,}$name:$(wc -c < "$DUMP_DIR/$db.sql" | tr -d ' ')"
    done
    printf '{"format":1,"engine":"postgres","created_at":"%s","databases":[%s],"sizes":{%s}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$list" "$sizes" > "$META_DIR/.postgres.json.tmp" \
        && mv -f "$META_DIR/.postgres.json.tmp" "$META_DIR/postgres.json"
fi

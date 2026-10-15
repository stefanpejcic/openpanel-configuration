#!/usr/bin/env bash
# OpenPanel: size the PHP-FPM pool from this container's own cgroup limits.
# Mounted as /etc/hooks/bootstrap/05-openpanel-fpm-tuning so it runs right after the image's 00-php-config.
# Replaces the image's ENABLE_TUNING_FPM, which reads host cores from /proc/cpuinfo (18 cores -> 90 children in a 1G container).

has-cmd php-fpm || exit 0
has-cmd php-envvars || exit 0

worker_mb="${PHPFPM_WORKER_MB:-64}"     # average RAM per PHP worker
reserve_mb="${PHPFPM_RESERVE_MB:-64}"   # kept for the master process and opcache
children_cap="${PHPFPM_MAX_CHILDREN_CAP:-256}"

# container memory limit, or host RAM when the container is unlimited
mem_max="$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
if [[ "$mem_max" =~ ^[0-9]+$ ]]; then
    ram_mb=$(( mem_max / 1024 / 1024 ))
else
    ram_mb=$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)
fi

max_children=$(( (ram_mb - reserve_mb) / worker_mb ))
(( max_children < 2 )) && max_children=2
(( max_children > children_cap )) && max_children=$children_cap

start_servers=$(( max_children / 4 ));     (( start_servers < 2 )) && start_servers=2
min_spare=$(( max_children / 8 ));         (( min_spare < 1 )) && min_spare=1
max_spare=$(( max_children / 2 ));         (( max_spare <= min_spare )) && max_spare=$(( min_spare + 1 ))
(( start_servers > max_spare )) && start_servers=$max_spare

config_file="$(php-envvars fpm_conf)"
[ -n "$config_file" ] || exit 0
mkdir -p "$(dirname "$config_file")"
touch "$config_file"
# same marker as the image's own tuning, so 00-php-config strips this block on the next boot
sed -i '/^; Tuning PM/,$d' "$config_file" 2>/dev/null || true

cat <<EOF >> "$config_file"
; Tuning PM (OpenPanel: ${ram_mb}MB container, ${worker_mb}MB per worker)
[$(is-true "$ALLOW_RUNTIME_PHP_ENVVARS" && echo '${PHP_POOL_NAME}' || echo "${PHP_POOL_NAME}")]
pm = dynamic
pm.max_children      = $max_children
pm.start_servers     = $start_servers
pm.min_spare_servers = $min_spare
pm.max_spare_servers = $max_spare
pm.max_requests      = ${PHPFPM_MAX_REQUESTS:-500}
EOF

debug-echo -i "PHP-FPM tuned for ${ram_mb}MB: max_children=$max_children" 2>/dev/null || true

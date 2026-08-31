#!/bin/bash
echo "[*] Initializing.."

# Seed admin webadmin config/cert/htpasswd from the image's hidden template
# on first boot -- upstream's stock /entrypoint.sh does this (and we override
# that entrypoint entirely), so without it admin/conf stays empty forever and
# LSWS fails hard on every start with "missing configuration file for admin server".
if [ -z "$(ls -A -- "/usr/local/lsws/admin/conf/")" ]; then
  cp -R /usr/local/lsws/admin/.conf/* /usr/local/lsws/admin/conf/
fi

# Ensure permissions
chown -R 994:994 /usr/local/lsws/conf
chown -R lsadm:lsadm /usr/local/lsws/admin/conf
chmod -R u=rwX,go= /usr/local/lsws/admin/conf

# https://github.com/litespeedtech/ols-dockerfiles/issues/13
usermod -aG nogroup root
usermod -aG root nobody

HTTPD_CONF="/usr/local/lsws/conf/httpd_config.conf"

echo "[*] Checking include sections for all VHosts files.."

# Collect all missing vhTemplate blocks
new_blocks=""
domains=()
for vhfile in /usr/local/lsws/conf/vhosts/*.conf; do
  [ -e "$vhfile" ] || continue
  domain=$(basename "$vhfile" .conf)
  domains+=("$domain")

  if grep -q "virtualhost $domain {" "$HTTPD_CONF"; then
    echo "[✓] $domain already exists"
    continue
  fi

  echo "[!] Creating include section for domain: $domain"
  new_blocks+=$'virtualhost '"$domain"' {\n'
  new_blocks+=$'  vhRoot            /var/www/html/\n'
  new_blocks+=$'  configFile            /usr/local/lsws/conf/vhosts/'"$domain"'.conf\n'
  new_blocks+=$'  allowSymbolLink                    1\n'
  new_blocks+=$'  enableScript                    1\n'
  new_blocks+=$'  restrained                    1\n'
  new_blocks+=$'  setUIDMode                    2\n'
  new_blocks+=$'}\n\n'
done

# Insert new vhost blocks
if [ -n "$new_blocks" ]; then
  tmpfile=$(mktemp)
  awk -v block="$new_blocks" '
    /vhTemplate docker {/ { print block }
    { print }
  ' "$HTTPD_CONF" > "$tmpfile"
  if [ -s "$tmpfile" ]; then
    cat "$tmpfile" > "$HTTPD_CONF"
  else
    echo "[ERROR] vhost include rewrite produced empty output -- leaving $HTTPD_CONF untouched" >&2
  fi
  rm -f "$tmpfile"
fi

echo "[*] Updating listener mappings.."

update_listener_maps() {
  listener=$1
  tmpfile=$(mktemp)

  awk -v lst="$listener" -v domains="${domains[*]}" '
    BEGIN {
      split(domains, d_arr, " ")
      in_listener = 0
    }
    {
      if ($1 == "listener" && $2 == lst && $3 == "{") {
        in_listener = 1
        delete existing_map
        print
        next
      }

      if (in_listener) {
        if ($1 == "map") {
          existing_map[$2] = 1
        }
        if ($0 ~ /^\}/) {
          for (i in d_arr) {
            if (!(d_arr[i] in existing_map)) {
              print "  map                     " d_arr[i] " " d_arr[i]
            }
          }
          print
          in_listener = 0
          next
        }
      }

      print
    }
  ' "$HTTPD_CONF" > "$tmpfile"

  if [ -s "$tmpfile" ]; then
    cat "$tmpfile" > "$HTTPD_CONF"
  else
    echo "[ERROR] listener map rewrite ($listener) produced empty output -- leaving $HTTPD_CONF untouched" >&2
  fi
  rm -f "$tmpfile"
}

update_listener_maps "HTTP"
update_listener_maps "HTTPS"

echo "[*] Starting LSWS process.."
/usr/local/lsws/bin/lswsctrl start
"$@"

while true; do
  if ! /usr/local/lsws/bin/lswsctrl status | grep 'litespeed is running with PID' > /dev/null; then
    break
  fi
  sleep 60
done

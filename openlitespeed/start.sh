#!/bin/bash

if [ -d "/vhosts" ] && [ "$(ls -A /vhosts)" ]; then
  cp -R /vhosts/* /usr/local/lsws/conf/vhosts/
fi

# Ensure permissions
chown -R 994:994 /usr/local/lsws/conf
chown -R 994:1001 /usr/local/lsws/admin/conf

HTTPD_CONF="/usr/local/lsws/conf/httpd_config.conf"

# Collect all missing vhTemplate blocks
new_blocks=""
for vhfile in /usr/local/lsws/conf/vhosts/*.conf; do
  [ -e "$vhfile" ] || continue
  domain=$(basename "$vhfile" .conf)

  # Skip if already exists
  if grep -q "vhTemplate $domain {" "$HTTPD_CONF"; then
    continue
  fi

  # Create per-domain template file if missing
  if [ ! -f "$TEMPLATE_DIR/$domain.conf" ]; then
    cp "$TEMPLATE_DIR/docker.conf" "$TEMPLATE_DIR/$domain.conf"
  fi

  # Add block
  new_blocks+="vhTemplate $domain {\n"
  new_blocks+="  templateFile            conf/templates/$domain.conf\n"
  new_blocks+="  listeners               HTTP, HTTPS\n"
  new_blocks+="  note                    $domain\n"
  new_blocks+="\n"
  new_blocks+="  member localhost {\n"
  new_blocks+="    vhDomain              $domain\n"
  new_blocks+="  }\n"
  new_blocks+="}\n\n"
done

# Insert before 'vhTemplate docker {' in place
if [ -n "$new_blocks" ]; then
  # Escape for sed
  esc_blocks=$(printf '%s' "$new_blocks" | sed 's/[&/\]/\\&/g')
  sed -i "/vhTemplate docker {/i $esc_blocks" "$HTTPD_CONF"
fi

# Start the server
/usr/local/lsws/bin/lswsctrl start
$@

# Keep container running and monitor
while true; do
  if ! /usr/local/lsws/bin/lswsctrl status | /usr/bin/grep 'litespeed is running with PID *' > /dev/null; then
    break
  fi
  sleep 60
done

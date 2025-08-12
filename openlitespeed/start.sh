#!/bin/bash
set -e

CONF_DIR=/usr/local/lsws/conf
VHOST_DIR=$CONF_DIR/vhosts
OUTPUT_CONF=$CONF_DIR/httpd_config.conf

echo "Generating OpenLiteSpeed main config..."

mkdir -p /usr/local/lsws/logs/
touch /usr/local/lsws/logs/error.log /usr/local/lsws/logs/access.log

cat > $OUTPUT_CONF <<EOL
<server>

  <errorLog>
    <fileName>/usr/local/lsws/logs/error.log</fileName>
    <logLevel>INFO</logLevel>
    <rollingSize>10M</rollingSize>
  </errorLog>

  <accessLog>
    <fileName>/usr/local/lsws/logs/access.log</fileName>
    <rollingSize>10M</rollingSize>
  </accessLog>

  <listener>
    <name>Default</name>
    <address>*:80</address>
    <secure>0</secure>
EOL

# Loop over each vhost config file to parse domains and add listener mappings
for conf in "$VHOST_DIR"/*.conf; do
  # Extract virtualHost name
  vhname=$(grep -oP '(?<=<virtualHost name=")[^"]+' "$conf" || true)

  # Extract domains (remove spaces)
  domains=$(grep -oP '(?<=<domain>)[^<]+' "$conf" | tr -d ' ' || true)

  if [[ -n "$vhname" && -n "$domains" ]]; then
    IFS=',' read -ra domain_array <<< "$domains"
    for d in "${domain_array[@]}"; do
      echo "    <map>$d $vhname</map>" >> $OUTPUT_CONF
    done
  fi
done

# Close listener block
echo "  </listener>" >> $OUTPUT_CONF

# Include all virtual host configs
for conf in "$VHOST_DIR"/*.conf; do
  echo "" >> $OUTPUT_CONF
  cat "$conf" >> $OUTPUT_CONF
  echo "" >> $OUTPUT_CONF
done

# Close server block
echo "</server>" >> $OUTPUT_CONF

echo "Generated $OUTPUT_CONF successfully."
echo "=============================================="
cat $OUTPUT_CONF
echo "=============================================="


/usr/local/lsws/bin/openlitespeed -n



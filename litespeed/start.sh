#!/bin/bash
# entrypoint for LiteSpeed Enterprise, replaces the image's own /entrypoint.sh
LSDIR=/usr/local/lsws
CONF=$LSDIR/conf
XML=$CONF/httpd_config.xml

echo "[*] Initializing.."

# conf is a volume so the license survives restarts, seed it from the image on first boot
if [ -z "$(ls -A -- "$CONF/")" ]; then
  cp -R $LSDIR/.conf/* $CONF/
fi
if [ -z "$(ls -A -- "$LSDIR/admin/conf/")" ]; then
  cp -R $LSDIR/admin/.conf/* $LSDIR/admin/conf/
fi

echo "[*] Pointing LiteSpeed at the account's Apache config.."
# vhosts come from /etc/apache2/httpd.conf, so the stock listeners, vhosts and templates go and :80/:443 are taken from there
perl -0pi -e '
  s|<loadApacheConf>0</loadApacheConf>|<loadApacheConf>1</loadApacheConf>|;
  s|(<loadApacheConf>1</loadApacheConf>)(?!\s*<apacheConfFile>)|$1\n    <apacheConfFile>/etc/apache2/httpd.conf</apacheConfFile>\n    <apachePortOffset>0</apachePortOffset>\n    <autoReloadApacheConf>0</autoReloadApacheConf>|;
  s|\s*<listenerList>.*?</listenerList>||s;
  s|\s*<virtualHostList>.*?</virtualHostList>||s;
  s|\s*<vhTemplateList>.*?</vhTemplateList>||s;
' "$XML"

# php goes to the lsphp bundled with the image, litespeed only looks for old php7x handlers on its own
if ! grep -q '<name>lsphp</name>' "$XML"; then
  perl -0pi -e 's|</httpServerConfig>|  <extProcessorList>
    <extProcessor>
      <type>lsapi</type>
      <name>lsphp</name>
      <address>uds://tmp/lshttpd/lsphp.sock</address>
      <maxConns>10</maxConns>
      <env>PHP_LSAPI_CHILDREN=10</env>
      <initTimeout>60</initTimeout>
      <retryTimeout>0</retryTimeout>
      <persistConn>1</persistConn>
      <respBuffer>0</respBuffer>
      <autoStart>2</autoStart>
      <path>/usr/local/lsws/fcgi-bin/lsphp</path>
      <backlog>100</backlog>
      <instances>1</instances>
      <memSoftLimit>2047M</memSoftLimit>
      <memHardLimit>2047M</memHardLimit>
      <procSoftLimit>1400</procSoftLimit>
      <procHardLimit>1500</procHardLimit>
    </extProcessor>
  </extProcessorList>
  <scriptHandlerList>
    <scriptHandler>
      <suffix>php</suffix>
      <type>lsapi</type>
      <handler>lsphp</handler>
    </scriptHandler>
  </scriptHandlerList>
</httpServerConfig>|' "$XML"
fi

# lscache is off until the server has a storage path, 3 turns on the cache engine and the crawler the LiteSpeed Cache plugins use
if ! grep -q '<cacheEngine>' "$XML"; then
  perl -0pi -e 's|</httpServerConfig>|  <cache>
    <cacheEngine>3</cacheEngine>
    <storage>
      <cacheStorePath>/usr/local/lsws/cachedata</cacheStorePath>
    </storage>
  </cache>
</httpServerConfig>|' "$XML"
fi
mkdir -p $LSDIR/cachedata
chown nobody:nogroup $LSDIR/cachedata

# real visitor ip from caddy, trusted only from the private ranges caddy and varnish come from
perl -0pi -e 's|<useIpInProxyHeader>\d</useIpInProxyHeader>|<useIpInProxyHeader>2</useIpInProxyHeader>|; s|(<httpServerConfig>)(?![\s\S]*<useIpInProxyHeader>)|$1\n    <useIpInProxyHeader>2</useIpInProxyHeader>|' "$XML"
if ! grep -q '10.0.0.0/8T' "$XML"; then
  perl -0pi -e 's|(<accessControl>\s*<allow>)([^<]*)(</allow>)|$1$2, 10.0.0.0/8T, 172.16.0.0/12T, 192.168.0.0/16T$3|' "$XML"
fi

echo "[*] Checking license.."
# a serial the user set is always used as is, without one there's a trial key that gets refreshed once it runs out
if [ -s "$CONF/serial.no" ]; then
  [ -e "$CONF/license.key" ] || $LSDIR/bin/lshttpd -r
elif [ ! -e "$CONF/license.key" ]; then
  if [ ! -e "$CONF/trial.key" ] || ! $LSDIR/bin/lshttpd -V 2>&1 | grep -q 'will expire in'; then
    rm -f $CONF/trial.key*
    wget -q -P $CONF/ http://license.litespeedtech.com/reseller/trial.key
  fi
fi
$LSDIR/bin/lshttpd -V 2>&1 | grep -i 'license\|expire' | tail -1

chown -R lsadm:lsadm $CONF
chown -R lsadm:lsadm $LSDIR/admin/conf
chmod -R u=rwX,go= $LSDIR/admin/conf

# same as openlitespeed https://github.com/litespeedtech/ols-dockerfiles/issues/13
usermod -aG nogroup root
usermod -aG root nobody

echo "[*] Starting LiteSpeed.."
# resolved container names live in /dev/shm and outlast a restart, an app container recreated meanwhile has a new IP
rm -f /dev/shm/lsws/adns_cache.*
$LSDIR/bin/lswsctrl start
"$@"

while true; do
  if ! $LSDIR/bin/lswsctrl status | grep 'litespeed is running with PID' > /dev/null; then
    break
  fi
  sleep 60
done

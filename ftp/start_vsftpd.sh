#!/bin/sh

QUOTA_CONF_DIR=/etc/vsftpd/user_conf
QUOTA_INTERVAL=${QUOTA_INTERVAL:-60}

# drop active sessions of an ftp user, vsftpd titles them "vsftpd: <ip>/<user>: ..."
kill_sessions() {
  ps -o pid,args | grep -F "/$1: " | grep "vsftpd:" | grep -v grep | awk '{print $1}' | xargs -r kill 2>/dev/null
}

# 6th users.list field is the quota in MB, users over it get a per-user conf that denies uploads
check_quotas() {
  mkdir -p "$QUOTA_CONF_DIR"
  seen=" "
  for list in /etc/openpanel/ftp/users/*/users.list; do
    [ -f "$list" ] || continue
    dir=$(dirname "$list")
    ctx=$(basename "$dir")
    usage_tmp="$dir/.quota.usage.$$"
    : > "$usage_tmp"
    while IFS='|' read -r NAME _ FOLDER _ _ QUOTA || [ -n "$NAME" ]; do
      [ -z "$NAME" ] && continue
      case "$QUOTA" in ''|*[!0-9]*|0) continue ;; esac
      [ -z "$FOLDER" ] && FOLDER="/var/www/html/"
      FOLDER=$(echo "$FOLDER" | sed "s|/var/www/html/|/home/${ctx}/docker-data/volumes/${ctx}_html_data/_data/|g")
      USED_KB=$(du -sk "$FOLDER" 2>/dev/null | cut -f1)
      USED_KB=${USED_KB:-0}
      seen="$seen$NAME "
      OVER=0
      if [ "$USED_KB" -ge $((QUOTA * 1024)) ]; then
        OVER=1
        if [ ! -f "$QUOTA_CONF_DIR/$NAME" ]; then
          echo "[!] FTP user $NAME is over quota (${USED_KB}K of ${QUOTA}M), uploads disabled"
          echo "cmds_denied=STOR,STOU,APPE,MKD" > "$QUOTA_CONF_DIR/$NAME"
          kill_sessions "$NAME"
        fi
      elif [ -f "$QUOTA_CONF_DIR/$NAME" ]; then
        echo "[*] FTP user $NAME is under quota again (${USED_KB}K of ${QUOTA}M), uploads enabled"
        rm -f "$QUOTA_CONF_DIR/$NAME"
      fi
      echo "$NAME|$USED_KB|$QUOTA|$OVER" >> "$usage_tmp"
    done < "$list"
    mv -f "$usage_tmp" "$dir/quota.usage"
  done

  # unblock users that were deleted or had their quota removed
  for f in "$QUOTA_CONF_DIR"/*; do
    [ -f "$f" ] || continue
    case "$seen" in
      *" $(basename "$f") "*) ;;
      *) rm -f "$f" ;;
    esac
  done
}

# opencli ftp-quota runs this right after a quota change
if [ "$1" = "--check-quotas" ]; then
  check_quotas
  exit 0
fi

print_banner() {
  echo "-------------------------------------------"
  echo " Starting FTP server (vsftpd)"
  echo " Started at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "-------------------------------------------"
}


# 1. starting message
print_banner


# 2. combine all user files in one file used for the service
echo "[*] Collecting lists of FTP users from all OpenPanel accounts..."

USERS=""

for dir in /etc/openpanel/ftp/users/*; do
    file="$dir/users.list"
    user=$(basename "$dir")
    if [ -f "$file" ]; then
        while IFS= read -r line; do
            # Replace /var/www/html/ with /home/... docker path
            modified_line=$(echo "$line" | sed "s|/var/www/html/|/home/${user}/docker-data/volumes/${user}_html_data/_data/|g")
            USERS="$USERS$modified_line "
        done < "$file"
    fi
done

# 3. save the list for display on OpenAdmin
echo "[*] Updating cached list in '/etc/openpanel/ftp/all.users' file..."
echo "USERS=\"$USERS\"" > /etc/openpanel/ftp/all.users

# 4. remove all existing users
echo "[*] Removing all existing FTP users..."
grep -E ':/sbin/nologin$' /etc/passwd | cut -d':' -f1 | xargs -r -n1 userdel

# add nobody user for privilege droppping
grep -q '^nobody:' /etc/passwd || echo "nobody:x:65534:65534:nobody:/:/sbin/nologin" >> /etc/passwd

# 5. read from individual users.list files and create users
echo "[*] Checking for existing users..."
USER_LIST_FILES=$(find /etc/openpanel/ftp/users/ -name 'users.list')
TOTAL_USER_COUNT=0
for USER_LIST_FILE in $USER_LIST_FILES; do
  while IFS='|' read -r NAME _; do
    [ -z "$NAME" ] && continue  # empty
    TOTAL_USER_COUNT=$((TOTAL_USER_COUNT + 1))
  done < "$USER_LIST_FILE"
done

if [ "$TOTAL_USER_COUNT" -gt 0 ]; then
  echo "[*] Total users that will be created: $TOTAL_USER_COUNT"

  USER_COUNT=0
  echo "[*] Creating users from users.list files..."
  
  for USER_LIST_FILE in $USER_LIST_FILES; do
    BASE_DIR=$(dirname "$USER_LIST_FILE")
    OPENPANEL_USER=$(basename "$BASE_DIR")
    echo "[!] Processing users for OpenPanel account: $OPENPANEL_USER"
    while IFS='|' read -r NAME HASHED_PASS FOLDER UID GID QUOTA; do
      USER_COUNT=$((USER_COUNT + 1))
      [ -z "$NAME" ] && continue  # Skip empty lines
      GROUP="$OPENPANEL_USER"
      echo "[+] Creating user ${NAME} [${USER_COUNT}/${TOTAL_USER_COUNT}]"
      FAKE_FOLDER="$FOLDER" # used for display only!
      if [ -z "$FOLDER" ]; then
        FOLDER="/var/www/html/"
        echo "    - No folder specified, using default: $FOLDER"
      fi
  
      # Replace legacy path if needed
      FOLDER=$(echo "$FOLDER" | sed "s|/var/www/html/|/home/${GROUP}/docker-data/volumes/${GROUP}_html_data/_data/|g")
  
      # Validate folder starts with /home
      case "$FOLDER" in
        /home/*) ;;
        *)
          echo "    - Skipping user $NAME: folder $FOLDER is invalid"
          continue
          ;;
      esac
  
      UID_OPT=""
      GROUP_OPT=""
  
      if [ -n "$UID" ]; then
        UID_OPT="-u $UID"
      fi
  
      if [ -n "$GID" ]; then
        EXISTING_GROUP=$(getent group "$GID" | cut -d: -f1)
        if [ -n "$EXISTING_GROUP" ]; then
          echo "    - Group $EXISTING_GROUP already exists with GID $GID"
          GROUP_OPT="-G $EXISTING_GROUP"
        else
          echo "    - Creating group $GROUP with GID $GID"
          addgroup -g "$GID" "$GROUP"
          GROUP_OPT="-G $GROUP"
        fi
      fi
  
      echo "    - Adding user with home directory: $FAKE_FOLDER"

      # for user@domain format
      #useradd -d "$FOLDER" -s /sbin/nologin $UID_OPT $GROUP_OPT -M "$NAME" --badname
      #adduser -h "$FOLDER" -s /sbin/nologin $UID_OPT $GROUP_OPT --disabled-password --gecos "" "$NAME"
      echo "$NAME:x:${UID}:${GID}::${FOLDER}:/sbin/nologin" >> /etc/passwd

      echo "    - Setting encrypted password '$HASHED_PASS'"
      if usermod -p "$HASHED_PASS" "$NAME"; then
          echo "    - Password set successfully"
      else
          echo "    - Failed to set password, removing user $NAME"
          userdel "$NAME"
          continue
      fi
  
      echo "    - Ensuring folder exists and ownership is correct (${UID}:${GID})"
      mkdir -p "$FOLDER"
      chown "${UID}:${GID}" "$FOLDER"
  
      echo ""
      unset NAME HASHED_PASS FOLDER UID GID QUOTA GROUP UID_OPT GROUP_OPT
    done < "$USER_LIST_FILE"
  done
  
  if [ "$USER_COUNT" -gt 0 ]; then
    echo "[*] User creation complete: $USER_COUNT users created."
  else
    echo "[*] No users created."
  fi
else
  echo "[*] No users found to create."
fi


# 6. tweak settings
MIN_PORT=${MIN_PORT:-21000}
MAX_PORT=${MAX_PORT:-21010}
echo "[*] Passive mode port range: $MIN_PORT-$MAX_PORT"

# https://github.com/stefanpejcic/OpenPanel/issues/1280
if [ -z "$PASV_ADDRESS" ]; then
    PASV_ADDRESS=$(wget -qO- -T 3 https://ip.openpanel.com 2>/dev/null | tr -d '[:space:]')
fi

PASV_OPTS=""
# plain sh (busybox), so no [[ =~ ]] or <<<
if echo "$PASV_ADDRESS" | awk -F. 'NF != 4 { exit 1 } { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i > 255) exit 1 }'; then
    echo "[*] Passive mode address: $PASV_ADDRESS"
    PASV_OPTS="-opasv_address=$PASV_ADDRESS -opasv_addr_resolve=NO"
else
    echo "[!] Could not detect a valid public IPv4; passive mode will use the default address"
fi

# 7. quotas, checked now and then every QUOTA_INTERVAL seconds
echo "[*] Checking FTP quotas every ${QUOTA_INTERVAL}s..."
check_quotas
( while sleep "$QUOTA_INTERVAL"; do check_quotas; done ) &

# 8. start service
if [ -n "$1" ]; then
  echo "[*] Executing custom command: $*"
  exec "$@"
else
  echo "[*] Starting vsftpd and accepting user logins..."
  echo "-------------------------------------------"
  vsftpd -opasv_min_port=$MIN_PORT -opasv_max_port=$MAX_PORT -ouser_config_dir=$QUOTA_CONF_DIR $PASV_OPTS /etc/vsftpd/vsftpd.conf
fi

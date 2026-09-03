#!/bin/bash

# =============================================================================
# samba-share.sh — Easily manage Samba shares
# Usage:
#   ./samba-share.sh add     → interactive: add a new share
#   ./samba-share.sh list    → list all configured shares
#   ./samba-share.sh remove  → interactive: remove a share
#   ./samba-share.sh restart → restart the samba container
# =============================================================================

set -e

# --- Config ------------------------------------------------------------------
ENV_FILE="$(dirname "$0")/../.env"
SMB_CONF=""

# Load .env to resolve ROOT_CONFIG_DIR
if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

SMB_CONF="${ROOT_CONFIG_DIR:-./config}/samba/smb.conf"

# --- Helpers -----------------------------------------------------------------
separator() { echo "---------------------------------------"; }

ensure_conf() {
  mkdir -p "$(dirname "$SMB_CONF")"
  if [ ! -f "$SMB_CONF" ]; then
    cat >"$SMB_CONF" <<EOF
[global]
   workgroup = WORKGROUP
   server string = UndeadLab Samba
   security = user
   map to guest = Bad User
   dns proxy = no
   log level = 1
   max log size = 1000

EOF
    echo "Created new smb.conf at $SMB_CONF"
  fi
}

restart_samba() {
  echo "Restarting samba container..."
  docker restart samba
  echo "Done."
}

# --- Add share ---------------------------------------------------------------
add_share() {
  ensure_conf
  separator
  echo "=== Add a new Samba share ==="
  separator

  read -p "Share name (e.g. Media, Backups): " SHARE_NAME
  if grep -q "^\[${SHARE_NAME}\]" "$SMB_CONF" 2>/dev/null; then
    echo "ERROR: Share [$SHARE_NAME] already exists."
    exit 1
  fi

  read -p "Path inside container (e.g. /data/media): " SHARE_PATH
  read -p "Comment/description: " SHARE_COMMENT

  echo "Access type:"
  echo "  1) Public (no password, read-only)"
  echo "  2) Public (no password, read-write)"
  echo "  3) Private (requires user/password)"
  read -p "Select [1]: " ACCESS_TYPE
  ACCESS_TYPE=${ACCESS_TYPE:-1}

  case $ACCESS_TYPE in
  1)
    GUEST="yes"
    WRITABLE="no"
    VALID_USERS=""
    ;;
  2)
    GUEST="yes"
    WRITABLE="yes"
    VALID_USERS=""
    ;;
  3)
    GUEST="no"
    read -p "Samba username to allow: " SMB_USER
    VALID_USERS="   valid users = $SMB_USER"
    WRITABLE="yes"

    # Create samba user if not exists
    echo "Creating/updating Samba user '$SMB_USER'..."
    docker exec -it samba smbpasswd -a "$SMB_USER" || true
    ;;
  *)
    GUEST="yes"
    WRITABLE="no"
    VALID_USERS=""
    ;;
  esac

  # Append share block to smb.conf
  cat >>"$SMB_CONF" <<EOF

[$SHARE_NAME]
   comment = $SHARE_COMMENT
   path = $SHARE_PATH
   browsable = yes
   read only = $([ "$WRITABLE" = "yes" ] && echo "no" || echo "yes")
   guest ok = $GUEST
$VALID_USERS
EOF

  echo ""
  echo "✓ Share [$SHARE_NAME] added to $SMB_CONF"
  read -p "Restart Samba now? (y/n) [y]: " DO_RESTART
  DO_RESTART=${DO_RESTART:-y}
  if [[ "$DO_RESTART" == "y" ]]; then
    restart_samba
  fi
}

# --- List shares -------------------------------------------------------------
list_shares() {
  ensure_conf
  separator
  echo "=== Configured Samba shares ==="
  separator
  grep -E "^\[" "$SMB_CONF" | grep -v "\[global\]" | sed 's/[][]//g' | while read -r share; do
    echo "  • $share"
    # Print path and guest ok for each
    awk "/^\[$share\]/{found=1} found && /path/{print \"    path:  \" \$3} found && /guest ok/{print \"    guest: \" \$3} found && /read only/{print \"    write: \" (\$3==\"no\" ? \"yes\" : \"no\")} /^\[/ && !/^\[$share\]/ && found{found=0}" "$SMB_CONF"
    echo ""
  done
}

# --- Remove share ------------------------------------------------------------
remove_share() {
  ensure_conf
  separator
  echo "=== Remove a Samba share ==="
  separator

  SHARES=$(grep -E "^\[" "$SMB_CONF" | grep -v "\[global\]" | sed 's/[][]//g')
  if [ -z "$SHARES" ]; then
    echo "No shares configured."
    exit 0
  fi

  echo "Available shares:"
  echo "$SHARES" | nl -w2 -s') '

  read -p "Enter share name to remove: " SHARE_NAME
  if ! grep -q "^\[${SHARE_NAME}\]" "$SMB_CONF"; then
    echo "ERROR: Share [$SHARE_NAME] not found."
    exit 1
  fi

  # Remove the share block (from [ShareName] to next [ or EOF)
  awk "
    /^\[$SHARE_NAME\]/ { skip=1 }
    skip && /^\[/ && !/^\[$SHARE_NAME\]/ { skip=0 }
    !skip { print }
  " "$SMB_CONF" >"${SMB_CONF}.tmp" && mv "${SMB_CONF}.tmp" "$SMB_CONF"

  echo "✓ Share [$SHARE_NAME] removed."
  read -p "Restart Samba now? (y/n) [y]: " DO_RESTART
  DO_RESTART=${DO_RESTART:-y}
  if [[ "$DO_RESTART" == "y" ]]; then
    restart_samba
  fi
}

# --- Main --------------------------------------------------------------------
case "${1:-}" in
add) add_share ;;
list) list_shares ;;
remove) remove_share ;;
restart) restart_samba ;;
*)
  echo "Usage: $0 {add|list|remove|restart}"
  echo ""
  echo "  add     → interactively add a new share"
  echo "  list    → show all configured shares"
  echo "  remove  → interactively remove a share"
  echo "  restart → restart the samba container"
  exit 1
  ;;
esac

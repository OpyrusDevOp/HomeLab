#!/bin/bash

# =============================================================================
# samba-share.sh — Manage native Samba shares on Arch Linux
# Usage:
#   ./samba-share.sh add     → interactive: add a new share
#   ./samba-share.sh list    → list all configured shares
#   ./samba-share.sh remove  → interactive: remove a share
#   ./samba-share.sh restart → restart smb/nmb
# =============================================================================

set -e

SMB_CONF="/etc/samba/smb.conf"
separator() { echo "---------------------------------------"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo."
    exit 1
  fi
}

restart_samba() {
  echo "Restarting Samba..."
  systemctl restart smb nmb
  echo "✓ Done."
}

# --- List --------------------------------------------------------------------
list_shares() {
  separator
  echo "=== Configured Samba shares ==="
  separator
  grep -E "^\[" "$SMB_CONF" | grep -iv "\[global\]" | tr -d '[]' | while read -r share; do
    echo "  • $share"
    awk "/^\[$share\]/{f=1;next} f && /^\[/{f=0} f && /=/{gsub(/^[ \t]+/,\"\"); print \"    \" \$0}" "$SMB_CONF"
    echo ""
  done
}

# --- Add ---------------------------------------------------------------------
add_share() {
  check_root
  separator
  echo "=== Add a new Samba share ==="
  separator

  read -p "Share name (e.g. Media, DiskB): " SHARE_NAME
  if grep -q "^\[${SHARE_NAME}\]" "$SMB_CONF" 2>/dev/null; then
    echo "ERROR: Share [$SHARE_NAME] already exists."
    exit 1
  fi

  echo "Common paths: /mnt/diskA  /mnt/diskB  /mnt/diskC"
  read -p "Path to share: " SHARE_PATH
  if [ ! -d "$SHARE_PATH" ]; then
    echo "WARNING: Path $SHARE_PATH does not exist yet."
    read -p "Create it? (y/n) [y]: " MKDIR
    [ "${MKDIR:-y}" = "y" ] && mkdir -p "$SHARE_PATH"
  fi

  read -p "Comment/description: " SHARE_COMMENT

  echo ""
  echo "Access type:"
  echo "  1) Public read-only  (no password)"
  echo "  2) Public read-write (no password)"
  echo "  3) Private           (Samba user/password)"
  read -p "Select [1]: " ACCESS_TYPE
  ACCESS_TYPE=${ACCESS_TYPE:-1}

  case $ACCESS_TYPE in
  1)
    READONLY="yes"
    GUEST="yes"
    VALID_USERS_LINE=""
    WRITABLE_LINE="   read only = yes"
    ;;
  2)
    READONLY="no"
    GUEST="yes"
    VALID_USERS_LINE=""
    WRITABLE_LINE="   read only = no"
    # Ensure others can write
    chmod -R 0777 "$SHARE_PATH" 2>/dev/null || true
    ;;
  3)
    READONLY="no"
    GUEST="no"
    read -p "Samba username: " SMB_USER

    # Create system user if not exists
    if ! id "$SMB_USER" &>/dev/null; then
      echo "Creating system user '$SMB_USER' (no login shell)..."
      useradd -M -s /sbin/nologin "$SMB_USER"
    fi

    echo "Set Samba password for '$SMB_USER':"
    smbpasswd -a "$SMB_USER"

    VALID_USERS_LINE="   valid users = $SMB_USER"
    WRITABLE_LINE="   read only = no"
    ;;
  *)
    READONLY="yes"
    GUEST="yes"
    VALID_USERS_LINE=""
    WRITABLE_LINE="   read only = yes"
    ;;
  esac

  # Append share block
  cat >>"$SMB_CONF" <<SHAREBLOCK

[$SHARE_NAME]
   comment = $SHARE_COMMENT
   path = $SHARE_PATH
   browsable = yes
$WRITABLE_LINE
   guest ok = $GUEST
$VALID_USERS_LINE
SHAREBLOCK

  echo ""
  echo "✓ Share [$SHARE_NAME] → $SHARE_PATH added."
  read -p "Restart Samba now? (y/n) [y]: " DO_RESTART
  [ "${DO_RESTART:-y}" = "y" ] && restart_samba
}

# --- Remove ------------------------------------------------------------------
remove_share() {
  check_root
  separator
  echo "=== Remove a Samba share ==="
  separator

  SHARES=$(grep -E "^\[" "$SMB_CONF" | grep -iv "\[global\]" | tr -d '[]')
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

  # Remove the block from [ShareName] to the next [ or EOF
  awk "
    /^\[${SHARE_NAME}\]/ { skip=1; next }
    skip && /^\[/        { skip=0 }
    !skip                { print }
  " "$SMB_CONF" >"${SMB_CONF}.tmp" && mv "${SMB_CONF}.tmp" "$SMB_CONF"

  echo "✓ Share [$SHARE_NAME] removed."
  read -p "Restart Samba now? (y/n) [y]: " DO_RESTART
  [ "${DO_RESTART:-y}" = "y" ] && restart_samba
}

# --- Main --------------------------------------------------------------------
case "${1:-}" in
add) add_share ;;
list) list_shares ;;
remove) remove_share ;;
restart) check_root && restart_samba ;;
*)
  echo "Usage: $0 {add|list|remove|restart}"
  echo ""
  echo "  add     → interactively add a new share"
  echo "  list    → show all configured shares"
  echo "  remove  → interactively remove a share"
  echo "  restart → restart smb and nmb"
  exit 1
  ;;
esac

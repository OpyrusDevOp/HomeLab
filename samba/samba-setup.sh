#!/bin/bash

# =============================================================================
# setup-samba.sh — Install and configure native Samba on Arch Linux
# Run once as root or with sudo
# =============================================================================

set -e

separator() { echo "---------------------------------------"; }

# --- Install -----------------------------------------------------------------
separator
echo "=== Installing Samba ==="
separator
pacman -Sy --noconfirm samba

# --- Base smb.conf -----------------------------------------------------------
separator
echo "=== Writing base /etc/samba/smb.conf ==="
separator

cat >/etc/samba/smb.conf <<'SMBCONF'
[global]
   workgroup = WORKGROUP
   server string = UndeadLab
   server role = standalone server
   log file = /var/log/samba/%m.log
   max log size = 50
   dns proxy = no
   map to guest = Bad User

SMBCONF

echo "✓ Base config written."

# --- Enable & start ----------------------------------------------------------
separator
echo "=== Enabling Samba services ==="
separator
systemctl enable --now smb nmb
echo "✓ smb and nmb started."

separator
echo "=== Setup complete ==="
echo "Now use ./samba-share.sh to add shares."

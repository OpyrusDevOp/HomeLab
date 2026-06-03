#!/bin/bash

# Default values
DEFAULT_DATA_DIR="$(pwd)/data"
DEFAULT_CONFIG_DIR="$(pwd)/config"

echo "=== HomeLab Setup Script ==="

# Prompt for Data Directory
read -p "Enter the absolute path for your Data Directory (Media & Downloads) [$DEFAULT_DATA_DIR]: " DATA_DIR
DATA_DIR=${DATA_DIR:-$DEFAULT_DATA_DIR}

# Prompt for Config Directory
read -p "Enter the absolute path for your Configuration Directory [$DEFAULT_CONFIG_DIR]: " CONFIG_DIR
CONFIG_DIR=${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}

# Create directories if they don't exist
mkdir -p "$DATA_DIR"/{downloads,media/{movies,tv}}
mkdir -p "$CONFIG_DIR"/{npm/{data,letsencrypt},pihole,jellyfin,jellyseerr,sonarr,radarr,prowlarr,qbittorrent,certs}

# Function to handle SSL
setup_ssl() {
    echo "=== SSL Management ==="
    echo "1) Let's Encrypt (requires public domain & port 80)"
    echo "2) Self-Signed (best for VPN/Local use)"
    echo "3) Skip SSL setup"
    read -p "Select SSL option [2]: " SSL_CHOICE
    SSL_CHOICE=${SSL_CHOICE:-2}

    case $SSL_CHOICE in
        1)
            if ! command -v certbot &> /dev/null; then
                read -p "Certbot is not installed. Install it? (y/n): " INSTALL_CERT
                if [[ $INSTALL_CERT == "y" ]]; then
                    if [[ -f /etc/arch-release ]]; then sudo pacman -S --noconfirm certbot certbot-nginx
                    elif [[ -f /etc/lsb-release ]] || [[ -f /etc/debian_version ]]; then sudo apt update && sudo apt install -y certbot python3-certbot-nginx
                    fi
                fi
            fi
            read -p "Enter domain: " DOMAIN
            sudo certbot certonly --standalone -d "$DOMAIN"
            if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
                mkdir -p "$CONFIG_DIR/certs/$DOMAIN"
                sudo ln -sf "/etc/letsencrypt/live/$DOMAIN"/* "$CONFIG_DIR/certs/$DOMAIN/"
            fi
            ;;
        2)
            read -p "Enter domain/hostname for self-signed cert (e.g. homelab.local): " DOMAIN
            mkdir -p "$CONFIG_DIR/certs/$DOMAIN"
            openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                -keyout "$CONFIG_DIR/certs/$DOMAIN/privkey.pem" \
                -out "$CONFIG_DIR/certs/$DOMAIN/fullchain.pem" \
                -subj "/C=US/ST=Home/L=Lab/O=HomeLab/CN=$DOMAIN"
            echo "Self-signed certificate generated in $CONFIG_DIR/certs/$DOMAIN"
            ;;
        *)
            echo "Skipping SSL setup."
            ;;
    esac
}

setup_ssl

# Generate .env file
echo "ROOT_DATA_DIR=$DATA_DIR" >.env
echo "ROOT_CONFIG_DIR=$CONFIG_DIR" >>.env
echo "TZ=$(timedatectl | grep "Time zone" | awk '{print $3}' || echo "UTC")" >>.env

echo ".env file generated with:"
cat .env

# Create Docker network
if ! docker network ls | grep -q "homelab_net"; then
  echo "Creating docker network: homelab_net"
  docker network create homelab_net
else
  echo "Docker network 'homelab_net' already exists."
fi

echo "Setup complete. You can now start your services."

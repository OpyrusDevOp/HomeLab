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

# Function to handle Certbot
setup_certbot() {
    echo "=== Certbot Management ==="
    if ! command -v certbot &> /dev/null; then
        read -p "Certbot is not installed. Would you like to install it? (y/n): " INSTALL_CERT
        if [[ $INSTALL_CERT == "y" ]]; then
            if [[ -f /etc/arch-release ]]; then
                sudo pacman -S --noconfirm certbot certbot-nginx
            elif [[ -f /etc/lsb-release ]] || [[ -f /etc/debian_version ]]; then
                sudo apt update && sudo apt install -y certbot python3-certbot-nginx
            else
                echo "Unsupported OS for automatic installation. Please install certbot manually."
                return
            fi
        else
            return
        fi
    fi

    read -p "Would you like to create a new certificate? (y/n): " CREATE_CERT
    if [[ $CREATE_CERT == "y" ]]; then
        read -p "Enter the domain name (e.g., example.com): " DOMAIN
        echo "WARNING: 'certbot --nginx' requires port 80 to be free. If NPM is running, stop it first."
        sudo certbot certonly --standalone -d "$DOMAIN"
        
        # Link to our config dir for easy access by containers
        if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
            echo "Mapping certificates to $CONFIG_DIR/certs/$DOMAIN"
            mkdir -p "$CONFIG_DIR/certs/$DOMAIN"
            sudo ln -sf "/etc/letsencrypt/live/$DOMAIN"/* "$CONFIG_DIR/certs/$DOMAIN/"
        fi
    fi
}

setup_certbot

# Generate .env file
echo "ROOT_DATA_DIR=$DATA_DIR" > .env
echo "ROOT_CONFIG_DIR=$CONFIG_DIR" >> .env
echo "TZ=$(timedatectl | grep "Time zone" | awk '{print $3}' || echo "UTC")" >> .env

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

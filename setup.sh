#!/usr/bin/env bash

# Setup script environment
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap 'die "Script interrupted."' INT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

# Prepare container OS
msg "Setting up container OS..."
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
apt-get -y purge openssh-{client,server} >/dev/null
apt-get autoremove >/dev/null

# Update container OS
msg "Updating container OS..."
apt-get update >/dev/null
apt-get -qqy upgrade &>/dev/null

# Install prerequisites
msg "Installing prerequisites..."
apt-get -qqy install \
    curl &>/dev/null

# Customize Docker configuration
msg "Customizing Docker..."
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
cat >$DOCKER_CONFIG_PATH <<'EOF'
{
  "log-driver": "journald"
}
EOF

# Install Docker
msg "Installing Docker..."
sh <(curl -sSL https://get.docker.com) &>/dev/null

# Creating Folders
msg "Creating Docker and Media folders..."
DOCKER_PORTAINER_PATH='/home/docker/portainer'
DOCKER_JELLYFIN_PATH='/home/docker/jellyfin'
DOCKER_VSCODE_PATH='/home/docker/vscode'
DOCKER_SONARR_PATH='/home/docker/sonarr'
DOCKER_RADARR_PATH='/home/docker/radarr'
DOCKER_BAZARR_PATH='/home/docker/bazarr'
DOCKER_QBITTORRENT_PATH='/home/docker/qbittorrent'
MEDIA_TVSHOWS_PATH='/home/media/tvshows'
MEDIA_MOVIES_PATH='/home/media/movies'
MEDIA_DOWNLOADS_PATH='/home/downloads'
mkdir -p $(dirname $DOCKER_PORTAINER_PATH)
mkdir -p $(dirname $DOCKER_VSCODE_PATH)
mkdir -p $(dirname $DOCKER_JELLYFIN_PATH)
mkdir -p $(dirname $DOCKER_SONARR_PATH)
mkdir -p $(dirname $DOCKER_RADARR_PATH)
mkdir -p $(dirname $DOCKER_BAZARR_PATH)
mkdir -p $(dirname $DOCKER_QBITTORRENT_PATH)
mkdir -p $(dirname $MEDIA_TVSHOWS_PATH)
mkdir -p $(dirname $MEDIA_MOVIES_PATH)
mkdir -p $(dirname $MEDIA_DOWNLOADS_PATH)

# Install Portainer
msg "Installing Portainer..."
docker run -d \
  -p 8000:8000 \
  -p 9000:9000 \
  --label com.centurylinklabs.watchtower.enable=true \
  --name=portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /home/docker/portainer:/data \
  portainer/portainer-ce &>/dev/null

# Install Watchtower
msg "Installing Watchtower..."
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --cleanup \
  --label-enable &>/dev/null

# Installing VSCode
msg "Installing VSCode..."
docker run -d \
  --name=vscode \
  -e TZ=Europe/Amsterdam \
  -p 8443:8443 \
  -v /home/docker/vscode:/config \
  -v /home/:/config/workspace/Server \
  --restart unless-stopped \
  ghcr.io/linuxserver/code-server &>/dev/null

# Installing HTPC Containers
msg "Installing Jellyfin..."
docker run -d \
  --name=jellyfin \
  -e TZ=Europe/Amsterdam \
  -p 8096:8096 \
  -p 8920:8920 \
  -p 7359:7359/udp \
  -p 1900:1900/udp \
  -v /home/docker/jellyfin:/config \
  -v /home/media/tvshows:/data/tvshows \
  -v /home/media/movies:/data/movies \
  --restart unless-stopped \
  ghcr.io/linuxserver/jellyfin &>/dev/null

# Install qbittorrent
msg "Installing qbittorrent..."
docker run -d \
  --name=qbittorrent \
  -e TZ=Europe/Amsterdam \
  -e WEBUI_PORT=8080 \
  -p 6881:6881 \
  -p 6881:6881/udp \
  -p 8080:8080 \
  -v /home/docker/qbittorrent:/config \
  -v /home/downloads:/downloads \
  --restart unless-stopped \
  ghcr.io/linuxserver/qbittorrent &>/dev/null

# Install Sonarr
msg "Installing Sonarr..."
docker run -d \
  --name=sonarr \
  -e TZ=Europe/Amsterdam \
  -p 8989:8989 \
  -v /home/docker/sonarr:/config \
  -v /home/media/tvshows:/tv \
  -v /home/downloads:/downloads \
  --restart unless-stopped \
  ghcr.io/linuxserver/sonarr &>/dev/null

# Install Radarr
msg "Installing Radarr..."
docker run -d \
  --name=radarr \
  -e TZ=Europe/Amsterdam \
  -p 7878:7878 \
  -v /home/docker/radarr:/config \
  -v /home/media/movies:/movies \
  -v /home/downloads:/downloads \
  --restart unless-stopped \
  ghcr.io/linuxserver/radarr &>/dev/null

# Install Bazarr
msg "Installing Bazarr..."
docker run -d \
  --name=bazarr \
  -e TZ=Europe/Amsterdam \
  -p 6767:6767 \
  -v /home/docker/bazarr:/config \
  -v /home/media/movies:/movies \
  -v /home/media/tvshows:/tv \
  --restart unless-stopped \
  ghcr.io/linuxserver/bazarr &>/dev/null

# Customize container
msg "Customizing container..."
rm /etc/motd # Remove message of the day after login
rm /etc/update-motd.d/10-uname # Remove kernel information after login
touch ~/.hushlogin # Remove 'Last login: ' and mail notification after login
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')

# Cleanup container
msg "Cleanup..."
rm -rf /setup.sh /var/{cache,log}/* /var/lib/apt/lists/*
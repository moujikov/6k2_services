#!/usr/bin/env bash

set -eu -o pipefail

if [ $EUID -ne 0 ]; then
   echo "This script is not running as root. Please use sudo."
   exit 1
fi

REPO='https://download.docker.com/linux/ubuntu'
DOCKER_GPG='/etc/apt/keyrings/docker.gpg'
DOCKER_SOURCES='/etc/apt/sources.list.d/docker.list'
ARCH=$(dpkg --print-architecture)
OS_RELEASE=$(. /etc/os-release && echo $VERSION_CODENAME)


### INSTALLING PACKAGES

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg apache2-utils

install -m 0755 -d '/etc/apt/keyrings'

if [ ! -f $DOCKER_GPG ]; then
  curl -fsSL $REPO/gpg | gpg --dearmor -o $DOCKER_GPG
  chmod a+r $DOCKER_GPG
fi

if [ ! -f $DOCKER_SOURCES ]; then
  > $DOCKER_SOURCES echo "deb [arch=$ARCH signed-by=$DOCKER_GPG] $REPO $OS_RELEASE stable"
fi

apt-get update

if [ ! apt-cache policy docker-ce | grep -q "$REPO" ]; then
  echo "ERROR: Docker repository setup failed."
  exit 1
fi

apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


### SETTING UP ENVIRONMENT

ensure_secret_file() {  
  [ -f "$1" ] || install -m 0400 /dev/null "$1"
}

set_secret() {
  install -m 0400 /dev/null "$1"
  echo "$2" >> "$1"
}

generate_secret() {
  local file="$1"
  local length=${2:-16}
  local prefix="${3:-}"
  local permissions="${4:-0400}"

  if [ -f "$file" ]; then
    echo "File '$file' already exists. Delete it to regenerate. Skipping..."
  else
    install -m "$permissions" /dev/null "$file"
    printf "$prefix" >> "$file"
    (
      set +o pipefail   # Disable pipefail since cat will fail after SIGPIPE when head exits
      cat /dev/random | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c $length >> "$file"
    ) || exit $?
    echo "Generated secret in '$file'"
  fi
}

traefik_files='/usr/local/share/traefik'
install -m 0755 -d "$traefik_files"
install -m 0700 -d "$traefik_files/auth"

database_files='/usr/local/share/database'
install -m 0755 -d "$database_files"
install -m 0700 -d "$database_files/auth"

authelia_files='/usr/local/share/authelia'
install -m 0755 -d "$authelia_files"
install -m 0700 -d "$authelia_files/keys"


DOCKER_USER='moujikov'
read -s -p "Provide Docker Hub access token (empty to skip): " DOCKER_PAT
echo

if [ -n "$DOCKER_PAT" ]; then
  docker login --username "$DOCKER_USER" --password "$DOCKER_PAT"
  unset DOCKER_PAT
fi

read -s -p "Provide Timeweb Clound auth token (empty to skip): " TIMEWEB_AUTH_TOKEN
echo

if [ -n "$TIMEWEB_AUTH_TOKEN" ]; then
  set_secret "$traefik_files/auth/timeweb_auth_token" "$TIMEWEB_AUTH_TOKEN"
  unset TIMEWEB_AUTH_TOKEN
fi

ensure_secret_file "$traefik_files/auth/admins"
ensure_secret_file "$traefik_files/auth/users"

generate_secret "$database_files/auth/db_password_postgres" 32 __postgres_  
generate_secret "$database_files/auth/db_password_authelia" 32 __authelia_ 0444

generate_secret "$authelia_files/keys/authelia_jwt_secret" 64 '' 0444
generate_secret "$authelia_files/keys/authelia_session_secret" 64 '' 0444
generate_secret "$authelia_files/keys/authelia_storage_encryption_key" 64 '' 0444


DIR="$( cd "$( dirname "$0" )" && pwd )"
docker compose --file "$DIR/compose.yml" up --detach

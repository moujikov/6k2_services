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

DEFAULT_OWNERSHIP=1000:1000     # Owned and accessed by container mock user
DEFAULT_PERMISSIONS=0440        # Readable by owner and group

ensure_secret_file() {
  local file="$1"
  local ownership="${2:-$DEFAULT_OWNERSHIP}"
  local permissions="${3:-$DEFAULT_PERMISSIONS}"
  local owner="${ownership%:*}"
  local group="${ownership#*:}"

  [ -f "$file" ] || install -m "$permissions" -o "$owner" -g "$group" /dev/null "$file"
}

set_secret() {
  local file="$1"
  local content="$2"
  local ownership="${3:-$DEFAULT_OWNERSHIP}"
  local permissions="${4:-$DEFAULT_PERMISSIONS}"
  local owner="${ownership%:*}"
  local group="${ownership#*:}"

  install -m "$permissions" -o "$owner" -g "$group" /dev/null "$file"
  echo "$content" >> "$file"
}

generate_secret() {
  local file="$1"
  local length=${2:-16}
  local ownership="${3:-$DEFAULT_OWNERSHIP}"
  local permissions="${4:-$DEFAULT_PERMISSIONS}"
  local owner="${ownership%:*}"
  local group="${ownership#*:}"

  if [ -f "$file" ]; then
    echo "File '$file' already exists. Delete it to regenerate. Skipping..."
  else
    install -m "$permissions" -o "$owner" -g "$group" /dev/null "$file"
    printf "$prefix" >> "$file"
    (
      set +o pipefail   # Disable pipefail since cat will fail after SIGPIPE when head exits
      cat /dev/random | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c $length >> "$file"
    ) || exit $?
    echo "Generated secret in '$file'"
  fi
}

timeweb_files='/usr/local/share/timeweb'
install -m 0755 -d "$timeweb_files"
install -m 0700 -d "$timeweb_files/auth"

smtp_files='/usr/local/share/smtp'
install -m 0755 -d "$smtp_files"
install -m 0700 -d "$smtp_files/auth"

traefik_files='/usr/local/share/traefik'
install -m 0755 -d "$traefik_files"
install -m 0700 -d "$traefik_files/auth"

database_files='/usr/local/share/database'
install -m 0755 -d "$database_files"
install -m 0700 -d "$database_files/auth"

authelia_files='/usr/local/share/authelia'
install -m 0755 -d "$authelia_files"
install -m 0700 -d "$authelia_files/auth"
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
  set_secret "$timeweb_files/auth/token" "$TIMEWEB_AUTH_TOKEN"
  unset TIMEWEB_AUTH_TOKEN
fi

read -s -p "Provide SMTP password for Authelia (empty to skip): " SMTP_PASSWORD_AUTHELIA
echo
if [ -n "$SMTP_PASSWORD_AUTHELIA" ]; then
  set_secret "$smtp_files/auth/authelia_password" "$SMTP_PASSWORD_AUTHELIA"
  unset SMTP_PASSWORD_AUTHELIA
fi

ensure_secret_file "$traefik_files/auth/admins"
ensure_secret_file "$traefik_files/auth/users"

generate_secret "$database_files/auth/postgres_password" 32 70:70     # Read only by postgres
generate_secret "$database_files/auth/authelia_password" 32 70:1000   # Read by postgres and authelia

ensure_secret_file "$authelia_files/auth/users.yml" '' 0640   # Read and writen by authelia

generate_secret "$authelia_files/keys/authelia_storage_encryption_key" 64
generate_secret "$authelia_files/keys/authelia_session_secret" 64
generate_secret "$authelia_files/keys/authelia_reset_password_secret" 64


DIR="$( cd "$( dirname "$0" )" && pwd )"
docker compose --file "$DIR/compose.yml" up --detach

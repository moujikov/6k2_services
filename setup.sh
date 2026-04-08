#!/usr/bin/env bash

set -eu -o pipefail

if [ "$TERM" != 'dumb' ] && [ "$TERM" != 'unknown' ]; then
  black=$(tput setaf 0); red=$(tput setaf 1); green=$(tput setaf 2); yellow=$(tput setaf 3); blue=$(tput setaf 4); magenta=$(tput setaf 5); cyan=$(tput setaf 6); white=$(tput setaf 7)
  bold=$(tput bold); ul=$(tput smul); reset=$(tput sgr 0)
  nl=$'\n'
fi

if [ $EUID -ne 0 ]; then
   echo "${bold}This script is not running as root. Please use sudo.${reset}"
   exit 1
fi

REPO='https://download.docker.com/linux/ubuntu'
DOCKER_GPG='/etc/apt/keyrings/docker.gpg'
DOCKER_SOURCES='/etc/apt/sources.list.d/docker.list'
ARCH=$(dpkg --print-architecture)
OS_RELEASE=$(. /etc/os-release && echo $VERSION_CODENAME)


#######################  INSTALLING SYSTEM PACKAGES  #######################

echo "${nl}${nl}${bold}Installing system packages:${reset}"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg apache2-utils tree

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


#######################  SETTING UP SECRETS  #######################

echo "${nl}${nl}${bold}Setting up secrets:${reset}"

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

services_files='/usr/local/share/services'
install -m 0755 -d "$services_files"

postgres_files="$services_files/postgres"
install -m 0755 -d "$postgres_files"
install -m 0700 -d "$postgres_files/auth"

redis_files="$services_files/redis"
install -m 0755 -d "$redis_files"
install -m 0700 -d "$redis_files/auth"

authelia_files="$services_files/authelia"
install -m 0755 -d "$authelia_files"
install -m 0700 -d "$authelia_files/keys"

authentik_files="$services_files/authentik"
install -m 0755 -d "$authentik_files"
install -m 0700 -d "$authentik_files/auth"
install -m 0700 -d "$authentik_files/keys"

lldap_files="$services_files/lldap"
install -m 0755 -d "$lldap_files"
install -m 0700 -d "$lldap_files/auth"
install -m 0700 -d "$lldap_files/keys"

oauth_files="$services_files/oauth"
install -m 0755 -d "$oauth_files"
install -m 0700 -d "$oauth_files/tokens"
install -m 0700 -d "$oauth_files/secrets"

smtp_files="$services_files/smtp"
install -m 0755 -d "$smtp_files"
install -m 0700 -d "$smtp_files/auth"


DOCKER_USER='moujikov'
read -s -p "Provide Docker Hub access token (empty to skip): " DOCKER_PAT
echo
if [ -n "$DOCKER_PAT" ]; then
  docker login --username "$DOCKER_USER" --password "$DOCKER_PAT"
fi

read -s -p "Provide Timeweb Cloud auth token (empty to skip): " TIMEWEB_AUTH_TOKEN
echo
if [ -n "$TIMEWEB_AUTH_TOKEN" ]; then
  set_secret "$oauth_files/tokens/timeweb" "$TIMEWEB_AUTH_TOKEN"
fi

read -s -p "Provide Yandex OAuth Client secret (empty to skip): " OAUTH_SECRET_YANDEX
echo
if [ -n "$OAUTH_SECRET_YANDEX" ]; then
  set_secret "$oauth_files/secrets/yandex" "$OAUTH_SECRET_YANDEX" 1001:1001
fi

read -s -p "Provide SMTP password for Authelia (empty to skip): " SMTP_PASSWORD_AUTHELIA
echo
if [ -n "$SMTP_PASSWORD_AUTHELIA" ]; then
  set_secret "$smtp_files/auth/authelia_password" "$SMTP_PASSWORD_AUTHELIA"
fi



generate_secret "$postgres_files/auth/postgres_password" 32 70:70     # Read only by postgres
generate_secret "$postgres_files/auth/authelia_password" 32 70:1000   # Read by postgres and authelia
generate_secret "$postgres_files/auth/authentik_password" 32 70:1000   # Read by postgres and authentik
generate_secret "$postgres_files/auth/lldap_password" 32 70:1000      # Read by postgres and lldap

lldap_database_url="postgres://lldap:$(cat $postgres_files/auth/lldap_password)@postgres/lldap"
set_secret "$postgres_files/auth/lldap_url.env" "LLDAP_DATABASE_URL='$lldap_database_url'"

generate_secret "$redis_files/auth/redis_password" 64 1001:1000       # Read by redis and authelia


authelia_storage_encryption_key="$authelia_files/keys/storage_encryption_key"
if [ -f "$authelia_storage_encryption_key" ]; then
  echo "File '$authelia_storage_encryption_key' already exists. Delete it to regenerate. Skipping..."
else
  read -s -p "Provide Authelia storage encryption key (empty to generate): " AUTHELIA_STORAGE_ENCRYPTION_KEY
  echo
  if [ -n "$AUTHELIA_STORAGE_ENCRYPTION_KEY" ]; then
    set_secret "$authelia_storage_encryption_key" "$AUTHELIA_STORAGE_ENCRYPTION_KEY"
    echo "Save Authelia storage encryption key in a safe place:"
    echo "  $AUTHELIA_STORAGE_ENCRYPTION_KEY"
    echo "It will be required to decrypt Authelia database in case of migration or recovery."
  else
    generate_secret "$authelia_storage_encryption_key" 64
  fi
fi

generate_secret "$authelia_files/keys/session_secret" 64
generate_secret "$authelia_files/keys/reset_password_secret" 64

generate_secret "$authentik_files/keys/session_secret" 64
generate_secret "$authentik_files/auth/admin_password" 16

generate_secret "$lldap_files/keys/key_seed" 64
generate_secret "$lldap_files/keys/jwt_secret" 64
generate_secret "$lldap_files/auth/admin_password" 16
generate_secret "$lldap_files/auth/authelia_password" 16

echo "${nl}${bold}All secrets have been set up. Current file structure:${reset}"
tree $services_files



# Temporary workaround for https://github.com/goauthentik/authentik/issues/20270
docker volume create 6k2-services_authentik_data
mountpoint=$(docker volume inspect 6k2-services_authentik_data --format '{{ .Mountpoint }}')
install -m 0755 -o 1000 -g 1000 -d "$mountpoint/media"



#######################  STARTING SERVICES  #######################

echo "${nl}${nl}${bold}Starting up services:${reset}"

DIR="$( cd "$( dirname "$0" )" && pwd )"
docker compose --file "$DIR/compose.yml" up --detach

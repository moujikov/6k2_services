#!/usr/bin/env bash

set -eu -o pipefail

REPO='https://download.docker.com/linux/ubuntu'
DOCKER_GPG='/etc/apt/keyrings/docker.gpg'
DOCKER_SOURCES='/etc/apt/sources.list.d/docker.list'
ARCH=$(dpkg --print-architecture)
OS_RELEASE=$(. /etc/os-release && echo $VERSION_CODENAME)

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg apache2-utils

if [ ! -d '/etc/apt/keyrings' ]; then
  install -m 0755 -d '/etc/apt/keyrings'
fi

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


install -m 0755 -d '/usr/local/share/traefik'
install -m 0700 -d '/usr/local/share/traefik/auth'
install -m 0600 /dev/null '/usr/local/share/traefik/auth/admins'
install -m 0600 /dev/null '/usr/local/share/traefik/auth/users'
install -m 0600 /dev/null '/usr/local/share/traefik/auth/timeweb_auth_token'


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
  echo "$TIMEWEB_AUTH_TOKEN" > '/usr/local/share/traefik/auth/timeweb_auth_token'
  unset TIMEWEB_AUTH_TOKEN
fi


DIR="$( cd "$( dirname "$0" )" && pwd )"
docker compose --file "$DIR/compose.yml" up --detach

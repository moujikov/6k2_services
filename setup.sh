#!/usr/bin/env bash

set -eu -o pipefail

REPO='https://download.docker.com/linux/ubuntu'
DOCKER_GPG='/etc/apt/keyrings/docker.gpg'
DOCKER_SOURCES='/etc/apt/sources.list.d/docker.list'
ARCH=$(dpkg --print-architecture)
OS_RELEASE=$(. /etc/os-release && echo $VERSION_CODENAME)

DOCKER_USER='moujikov'
DOCKER_PAT="$1"

if [ -z "$DOCKER_PAT" ]; then
  echo "ERROR: No Docker Hub access token provided."
  exit 1
fi

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg

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

docker login --username "$DOCKER_USER" --password "$DOCKER_PAT"

DIR="$( cd "$( dirname "$0" )" && pwd )"
docker compose --file "$DIR/compose.yml" up --detach

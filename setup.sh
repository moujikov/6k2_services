#!/usr/bin/env bash

set -eu -o pipefail

apt update
apt install -y --no-install-recommends \
  ca-certificates curl gnupg

if [ ! -d '/etc/apt/keyrings' ]; then
  install -m 0755 -d '/etc/apt/keyrings'
fi

REPO='https://download.docker.com/linux/ubuntu'
DOCKER_GPG='/etc/apt/keyrings/docker.gpg'
DOCKER_SOURCES='/etc/apt/sources.list.d/docker.list'
ARCH=$(dpkg --print-architecture)
OS_RELEASE=$(. /etc/os-release && echo $VERSION_CODENAME)

if [ ! -f $DOCKER_GPG ]; then
  curl -fsSL $REPO/gpg | gpg --dearmor -o $DOCKER_GPG
  chmod a+r $DOCKER_GPG
fi

if [ ! -f $DOCKER_SOURCES ]; then
  > $DOCKER_SOURCES echo "deb [arch=$ARCH signed-by=$DOCKER_GPG] $REPO $OS_RELEASE stable"
fi

apt update

if [ ! apt-cache policy docker-ce | grep -q "$REPO" ]; then
  echo "ERROR: Docker repository setup failed."
  exit 1
fi

apt install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

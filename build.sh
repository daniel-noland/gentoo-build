#!/usr/bin/env bash

set -euxETo pipefail

docker buildx use insecure-builder
docker buildx build \
  --allow security.insecure \
  --tag gentoo-build \
  --output type=docker,dest=/run/gentoo-build.tar .

docker load </run/gentoo-build.tar

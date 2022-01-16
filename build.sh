#!/usr/bin/env bash

set -euxETo pipefail

docker buildx use insecure-builder
docker buildx build --allow security.insecure --tag gentoo-build .
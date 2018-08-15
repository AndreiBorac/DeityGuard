#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

tar -xf ./../../../ithird/deityguard.tar.xz --strip-components=2 deityguard/2-fingen/
tar -xf ./../../../ithird/overlay.tar.gz    --strip-components=2          ./2-fingen/ || true

set +o xtrace
echo "note: errors from unpacking overlay.tar.gz are normal under some circumstances"

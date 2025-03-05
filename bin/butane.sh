#!/bin/sh

set -e

download_butane() {
  BUTANE="$PWD/build/butane"
  VERSION="v0.23.0"
  BUTANE_PATH="$(dirname $BUTANE)"

  if [ -f "$BUTANE" ]; then
    return 0
  fi

  if [ ! -d "$BUTANE_PATH" ]; then
    mkdir -p "$BUTANE_PATH"
  fi

  curl -Ls -o $BUTANE \
    https://github.com/coreos/butane/releases/download/$VERSION/butane-x86_64-unknown-linux-gnu
  curl -Ls -O https://github.com/coreos/butane/releases/download/$VERSION/butane-x86_64-unknown-linux-gnu.asc
  curl -s https://fedoraproject.org/fedora.gpg | gpg -q --import
  gpg -q --verify butane-x86_64-unknown-linux-gnu.asc $BUTANE
  chmod +x $BUTANE
  rm butane-x86_64-unknown-linux-gnu.asc
}

wrap_ignition() {
  # https://search.opentofu.org/provider/opentofu/external/latest/docs/datasources/external#processing-json-in-shell-scripts
  jq -nc --arg ign "$1" '{"ign":$ign}'
}

BUTANE=$(which butane || true)

if [ -z "$BUTANE" ]; then
  download_butane
fi

RES="$($BUTANE $@)"
wrap_ignition "$RES"

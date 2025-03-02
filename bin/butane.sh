#!/bin/sh

set -e

download_butane() {
  BUTANE="$PWD/build/butane"
  BUTANE_PATH="$(dirname $BUTANE)"

  if [ -f "$BUTANE" ]; then
    return 0
  fi

  if [ ! -d "$BUTANE_PATH" ]; then
    mkdir -p "$BUTANE_PATH"
  fi

  wget -q -O $BUTANE \
    https://github.com/coreos/butane/releases/download/v0.23.0/butane-x86_64-unknown-linux-gnu
  wget -q https://github.com/coreos/butane/releases/download/v0.23.0/butane-x86_64-unknown-linux-gnu.asc
  curl -s https://fedoraproject.org/fedora.gpg | gpg --import
  gpg --verify butane-x86_64-unknown-linux-gnu.asc $BUTANE
  chmod +x $BUTANE
  rm butane-x86_64-unknown-linux-gnu.asc
}

wrap_ignition() {
  # https://search.opentofu.org/provider/opentofu/external/latest/docs/datasources/external#processing-json-in-shell-scripts
  jq -nc --arg ign "$1" '{"ign":$ign}'
}

BUTANE=$(which butane)

if [ ! -z "$BUTANE" ]; then
  wrap_ignition "$($BUTANE $@)"
  exit 0
fi

download_butane
wrap_ignition "$($BUTANE $@)"

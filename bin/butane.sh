#!/bin/sh
# https://search.opentofu.org/provider/opentofu/external/latest/docs/datasources/external#processing-json-in-shell-scripts

set -e

if [ ! -f /usr/local/bin/butane ]; then
	wget -q -O /usr/local/bin/butane \
		https://github.com/coreos/butane/releases/download/v0.23.0/butane-x86_64-unknown-linux-gnu
	wget -q https://github.com/coreos/butane/releases/download/v0.23.0/butane-x86_64-unknown-linux-gnu.asc
	curl -s https://fedoraproject.org/fedora.gpg | gpg --import
	gpg --verify butane-x86_64-unknown-linux-gnu.asc /usr/local/bin/butane
	chmod +x /usr/local/bin/butane
fi

IGN=$(butane $@)

jq -nc --arg ign "$IGN" '{"ign":$ign}'

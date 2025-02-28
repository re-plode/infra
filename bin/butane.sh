#!/bin/sh
# https://search.opentofu.org/provider/opentofu/external/latest/docs/datasources/external#processing-json-in-shell-scripts

set -e

IGN=$(butane $@)

jq -nc --arg ign "$IGN" '{"ign":$ign}'

#!/bin/sh

set -e

aws s3api put-object --bucket infra --key terraform.tfstate --body terraform.tfstate \
  --endpoint-url $CLOUDFLARE_R2_ENDPOINT \
  --checksum-algorithm CRC32

#!/bin/sh

set -e

aws s3api get-object --bucket infra --key terraform.tfstate \
	--endpoint-url $CLOUDFLARE_R2_ENDPOINT \
	terraform.tfstate

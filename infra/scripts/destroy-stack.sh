#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/scripts/destroy-stack.sh STACK_NAME
#
# Example:
#   ./infra/scripts/destroy-stack.sh rekognition-network-dev

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 STACK_NAME" >&2
  exit 1
fi

STACK_NAME="$1"
REGION="${AWS_REGION:-us-east-1}"

echo "======================================"
echo " Deleting stack: $STACK_NAME"
echo " Region        : $REGION"
echo "======================================"

aws cloudformation delete-stack \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo "🕒 Delete request sent. Check CloudFormation console for progress."

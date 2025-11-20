#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/scripts/deploy-stack.sh STACK_NAME TEMPLATE_FILE Param1=Value1 Param2=Value2 ...
#
# Example:
#   ./infra/scripts/deploy-stack.sh \
#     rekognition-network-dev \
#     infra/cfn/00-network.yaml \
#     ProjectName=rekognition-project \
#     Environment=dev

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 STACK_NAME TEMPLATE_FILE [PARAM=VALUE ...]" >&2
  exit 1
fi

STACK_NAME="$1"
TEMPLATE_FILE="$2"
shift 2

REGION="${AWS_REGION:-us-east-1}"

echo "======================================"
echo " Deploying stack: $STACK_NAME"
echo " Template      : $TEMPLATE_FILE"
echo " Region        : $REGION"
echo " Parameters    : $*"
echo "======================================"

aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "$@" \
  --region "$REGION"

echo "✅ Stack $STACK_NAME deployed."

#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/scripts/destroy-all.sh
#
# Variables:
#   PROJECT_NAME (default: rekognition-project)
#   ENVIRONMENT  (default: dev)
#   AWS_REGION   (default: us-east-1)

PROJECT_NAME="${PROJECT_NAME:-rekognition-project}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-us-east-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESTROY_SCRIPT="$ROOT_DIR/infra/scripts/destroy-stack.sh"

if [ ! -x "$DESTROY_SCRIPT" ]; then
  echo "ERROR: $DESTROY_SCRIPT is not executable. Run: chmod +x $DESTROY_SCRIPT" >&2
  exit 1
fi

export AWS_REGION="$REGION"

STACK_UPLOAD="${PROJECT_NAME}-upload-web-${ENVIRONMENT}"
STACK_SEARCH="${PROJECT_NAME}-search-web-${ENVIRONMENT}"
STACK_DB="${PROJECT_NAME}-database-${ENVIRONMENT}"
STACK_S3_EVENTS="${PROJECT_NAME}-s3-events-${ENVIRONMENT}"
STACK_LAMBDAS="${PROJECT_NAME}-lambdas-${ENVIRONMENT}"
STACK_STORAGE="${PROJECT_NAME}-storage-${ENVIRONMENT}"
STACK_NETWORK="${PROJECT_NAME}-network-${ENVIRONMENT}"

destroy_if_exists () {
  local stack_name="$1"
  echo "---- Checking stack: $stack_name ----"
  if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" >/dev/null 2>&1; then
    echo "Stack $stack_name exists. Deleting..."
    "$DESTROY_SCRIPT" "$stack_name"
  else
    echo "Stack $stack_name does not exist. Skipping."
  fi
}

echo "======================================"
echo " Destroying all stacks for:"
echo "   Project    : $PROJECT_NAME"
echo "   Environment: $ENVIRONMENT"
echo "   Region     : $REGION"
echo "======================================"

# Ordre inverse de création:
echo "-> Destroy search-web stack"
destroy_if_exists "$STACK_SEARCH"

echo "-> Destroy upload-web stack"
destroy_if_exists "$STACK_UPLOAD"

echo "-> Destroy database stack"
destroy_if_exists "$STACK_DB"

echo "-> Destroy S3 events stack"
destroy_if_exists "$STACK_S3_EVENTS"

echo "-> Destroy lambdas stack"
destroy_if_exists "$STACK_LAMBDAS"

echo "-> Destroy storage stack"
destroy_if_exists "$STACK_STORAGE"

echo "-> Destroy network stack"
destroy_if_exists "$STACK_NETWORK"

echo "✅ All destroy requests sent (where stacks existed)."
echo "   Check CloudFormation console for actual deletion progress."

#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/scripts/destroy-all.sh
#
# Variables configurables :
#   PROJECT_NAME (default: rekognition-project)
#   ENVIRONMENT  (default: dev)
#
# Prérequis :
#   - infra/scripts/destroy-stack.sh doit exister et être exécutable
#   - AWS_REGION doit être défini ou us-east-1 sera utilisé

REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-rekognition-project}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DESTROY_SCRIPT="$ROOT_DIR/infra/scripts/destroy-stack.sh"

if [ ! -x "$DESTROY_SCRIPT" ]; then
  echo "ERROR: $DESTROY_SCRIPT is not executable. Run: chmod +x $DESTROY_SCRIPT" >&2
  exit 1
fi

echo "======================================"
echo " Destroying all stacks for:"
echo "   Project    : $PROJECT_NAME"
echo "   Environment: $ENVIRONMENT"
echo "   Region     : $REGION"
echo "======================================"

export AWS_REGION="$REGION"

# Ordre inverse de création :
# 1) EC2
# 2) S3 events
# 3) Lambdas
# 4) Storage
# 5) Network

STACK_EC2="${PROJECT_NAME}-ec2-${ENVIRONMENT}"
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

echo "-> Destroy EC2 stack"
destroy_if_exists "$STACK_EC2"

echo "-> Destroy S3 events stack"
destroy_if_exists "$STACK_S3_EVENTS"

echo "-> Destroy Lambdas stack"
destroy_if_exists "$STACK_LAMBDAS"

echo "-> Destroy Storage stack"
destroy_if_exists "$STACK_STORAGE"

echo "-> Destroy Network stack"
destroy_if_exists "$STACK_NETWORK"

echo "✅ All destroy requests sent (where stacks existed)."
echo "   Check CloudFormation console for actual deletion progress."

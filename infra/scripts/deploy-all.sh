#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/scripts/deploy-all.sh
#
# Prérequis:
#   - AWS_REGION exporté ou par défaut us-east-1
#   - bucket d'artefacts lambdas existant (LAMBDA_ARTIFACTS_BUCKET)
#   - variables DB & repo définies ci-dessous

REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="rekognition-project"
ENVIRONMENT="dev"
LAMBDA_ARTIFACTS_BUCKET="rekognition-lambda-artifacts"

# DB config (met ce que tu veux ici ou passe-les en env)
DB_HOST="your-db-host"
DB_PORT="3306"
DB_USER="youruser"
DB_PASS="yourpass"
DB_NAME="rekognition_db"

# Rekognition collection
COLLECTION_ID="${PROJECT_NAME}-${ENVIRONMENT}-faces"

# Repo & EC2
GIT_REPO_URL="https://github.com/AzizBenMallouk/rekognition-project.git"
BRANCH_NAME="main"
EC2_KEYPAIR_NAME="your-keypair-name"

export AWS_REGION="$REGION"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "======================================"
echo " Packaging lambdas"
echo "======================================"
"$ROOT_DIR/infra/scripts/package-lambdas.sh" "$LAMBDA_ARTIFACTS_BUCKET"

# 1) Network
echo "======================================"
echo " Deploying 00-network"
echo "======================================"
"$ROOT_DIR/infra/scripts/deploy-stack.sh" \
  "${PROJECT_NAME}-network-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/00-network.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT"

# Récupérer les outputs (via CLI jq)
NET_STACK="${PROJECT_NAME}-network-${ENVIRONMENT}"
NETWORK_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$NET_STACK" --region "$REGION" --query "Stacks[0].Outputs" --output json)

VPC_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="VPCIdOut") | .OutputValue')
PUBLIC_SUBNET_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="PublicSubnetIdOut") | .OutputValue')
WEB_SG_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="WebSecurityGroupIdOut") | .OutputValue')
NODE_SG_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="NodeSecurityGroupIdOut") | .OutputValue')

# 2) Storage
echo "======================================"
echo " Deploying 10-storage"
echo "======================================"
"$ROOT_DIR/infra/scripts/deploy-stack.sh" \
  "${PROJECT_NAME}-storage-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/10-storage.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT"

STOR_STACK="${PROJECT_NAME}-storage-${ENVIRONMENT}"
STOR_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STOR_STACK" --region "$REGION" --query "Stacks[0].Outputs" --output json)

UPLOAD_BUCKET_NAME=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="UploadBucketNameOut") | .OutputValue')
UPLOAD_BUCKET_ARN=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="UploadBucketArnOut") | .OutputValue')
SEARCH_BUCKET_NAME=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SearchBucketNameOut") | .OutputValue')
SEARCH_BUCKET_ARN=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SearchBucketArnOut") | .OutputValue')

# 3) Lambdas
echo "======================================"
echo " Deploying 20-lambdas"
echo "======================================"
"$ROOT_DIR/infra/scripts/deploy-stack.sh" \
  "${PROJECT_NAME}-lambdas-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/20-lambdas.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT" \
  DbHost="$DB_HOST" \
  DbPort="$DB_PORT" \
  DbUser="$DB_USER" \
  DbPass="$DB_PASS" \
  DbName="$DB_NAME" \
  CollectionId="$COLLECTION_ID" \
  UiNotifyUrl="http://CHANGE_ME_LATER:3000/lambda-result" \
  LambdaCodeBucket="$LAMBDA_ARTIFACTS_BUCKET" \
  IndexFaceKey="lambda-index-face.zip" \
  SearchFaceKey="lambda-search-face.zip" \
  UploadBucketArn="$UPLOAD_BUCKET_ARN" \
  SearchBucketArn="$SEARCH_BUCKET_ARN"

LAMBDA_STACK="${PROJECT_NAME}-lambdas-${ENVIRONMENT}"
LAMBDA_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$LAMBDA_STACK" --region "$REGION" --query "Stacks[0].Outputs" --output json)

INDEX_LAMBDA_ARN=$(echo "$LAMBDA_OUTPUTS" | jq -r '.[] | select(.OutputKey=="IndexFaceFunctionArnOut") | .OutputValue')
SEARCH_LAMBDA_ARN=$(echo "$LAMBDA_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SearchFaceFunctionArnOut") | .OutputValue')

# 4) S3 Events
echo "======================================"
echo " Deploying 30-s3-events"
echo "======================================"
"$ROOT_DIR/infra/scripts/deploy-stack.sh" \
  "${PROJECT_NAME}-s3-events-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/30-s3-events.yaml" \
  UploadBucketName="$UPLOAD_BUCKET_NAME" \
  SearchBucketName="$SEARCH_BUCKET_NAME" \
  IndexFaceFunctionArn="$INDEX_LAMBDA_ARN" \
  SearchFaceFunctionArn="$SEARCH_LAMBDA_ARN"

# 5) EC2 Web
echo "======================================"
echo " Deploying 40-ec2-web"
echo "======================================"
"$ROOT_DIR/infra/scripts/deploy-stack.sh" \
  "${PROJECT_NAME}-ec2-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/40-ec2-web.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT" \
  VPCId="$VPC_ID" \
  PublicSubnetId="$PUBLIC_SUBNET_ID" \
  WebSecurityGroupId="$WEB_SG_ID" \
  NodeSecurityGroupId="$NODE_SG_ID" \
  EC2KeyPairName="$EC2_KEYPAIR_NAME" \
  GitRepositoryUrl="$GIT_REPO_URL" \
  BranchName="$BRANCH_NAME"

echo "✅ All stacks deployed successfully."

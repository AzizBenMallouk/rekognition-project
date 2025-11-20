#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/scripts/deploy-all.sh
#
# Variables configurables via env:
#   PROJECT_NAME (default: rekognition-project)
#   ENVIRONMENT  (default: dev)
#   AWS_REGION   (default: us-east-1)
#   LAMBDA_ARTIFACTS_BUCKET (default: rekognition-lambda-artifacts)
#   DB_NAME (default: rekognition_db)
#   DB_USER (default: appuser)
#   DB_PASS (default: SuperSecret123!)
#   GIT_REPO_URL (default: ton repo GitHub)
#   BRANCH_NAME (default: main)
#   EC2_KEYPAIR_NAME (obligatoire – pas de default réaliste)

PROJECT_NAME="${PROJECT_NAME:-rekognition-project}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-us-east-1}"
LAMBDA_ARTIFACTS_BUCKET="${LAMBDA_ARTIFACTS_BUCKET:-rekognition-lambda-artifacts}"

DB_NAME="${DB_NAME:-rekognition_db}"
DB_USER="${DB_USER:-appuser}"
DB_PASS="${DB_PASS:-SuperSecret123!}"

COLLECTION_ID="${COLLECTION_ID:-${PROJECT_NAME}-${ENVIRONMENT}-faces}"

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/AzizBenMallouk/rekognition-project.git}"
BRANCH_NAME="${BRANCH_NAME:-main}"
EC2_KEYPAIR_NAME="${EC2_KEYPAIR_NAME:-your-keypair-name}"

export AWS_REGION="$REGION"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEPLOY_SCRIPT="$ROOT_DIR/infra/scripts/deploy-stack.sh"
PKG_LAMBDA_SCRIPT="$ROOT_DIR/infra/scripts/package-lambdas.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (sudo yum/apt/brew install jq)" >&2
  exit 1
fi

echo "======================================"
echo " Project      : $PROJECT_NAME"
echo " Environment  : $ENVIRONMENT"
echo " Region       : $REGION"
echo "======================================"

echo "======================================"
echo " Packaging lambdas"
echo "======================================"
"$PKG_LAMBDA_SCRIPT" "$LAMBDA_ARTIFACTS_BUCKET"

# 1) Network
echo "======================================"
echo " Deploying 00-network"
echo "======================================"
"$DEPLOY_SCRIPT" \
  "${PROJECT_NAME}-network-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/00-network.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT"

NET_STACK="${PROJECT_NAME}-network-${ENVIRONMENT}"
NETWORK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$NET_STACK" \
  --region "$REGION" \
  --query "Stacks[0].Outputs" \
  --output json)

VPC_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="VPCIdOut") | .OutputValue')
PUBLIC_SUBNET_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="PublicSubnetIdOut") | .OutputValue')
WEB_SG_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="WebSecurityGroupIdOut") | .OutputValue')
NODE_SG_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="NodeSecurityGroupIdOut") | .OutputValue')
DB_SG_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="DbSecurityGroupIdOut") | .OutputValue')

echo "VPC_ID          = $VPC_ID"
echo "PUBLIC_SUBNET   = $PUBLIC_SUBNET_ID"
echo "WEB_SG_ID       = $WEB_SG_ID"
echo "NODE_SG_ID      = $NODE_SG_ID"
echo "DB_SG_ID        = $DB_SG_ID"

# 2) Storage
echo "======================================"
echo " Deploying 10-storage"
echo "======================================"
"$DEPLOY_SCRIPT" \
  "${PROJECT_NAME}-storage-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/10-storage.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT"

STOR_STACK="${PROJECT_NAME}-storage-${ENVIRONMENT}"
STOR_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STOR_STACK" \
  --region "$REGION" \
  --query "Stacks[0].Outputs" \
  --output json)

UPLOAD_BUCKET_NAME=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="UploadBucketNameOut") | .OutputValue')
UPLOAD_BUCKET_ARN=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="UploadBucketArnOut") | .OutputValue')
SEARCH_BUCKET_NAME=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SearchBucketNameOut") | .OutputValue')
SEARCH_BUCKET_ARN=$(echo "$STOR_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SearchBucketArnOut") | .OutputValue')

echo "UPLOAD_BUCKET_NAME = $UPLOAD_BUCKET_NAME"
echo "SEARCH_BUCKET_NAME = $SEARCH_BUCKET_NAME"

# 3) Upload Web EC2
echo "======================================"
echo " Deploying 40-upload-web"
echo "======================================"
"$DEPLOY_SCRIPT" \
  "${PROJECT_NAME}-upload-web-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/40-upload-web.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT" \
  VPCId="$VPC_ID" \
  PublicSubnetId="$PUBLIC_SUBNET_ID" \
  WebSecurityGroupId="$WEB_SG_ID" \
  EC2KeyPairName="$EC2_KEYPAIR_NAME" \
  GitRepositoryUrl="$GIT_REPO_URL" \
  BranchName="$BRANCH_NAME"

UPLOAD_STACK="${PROJECT_NAME}-upload-web-${ENVIRONMENT}"
UPLOAD_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$UPLOAD_STACK" \
  --region "$REGION" \
  --query "Stacks[0].Outputs" \
  --output json)

UPLOAD_WEB_PUBLIC_IP=$(echo "$UPLOAD_OUTPUTS" | jq -r '.[] | select(.OutputKey=="UploadWebPublicIP") | .OutputValue')
echo "Upload Web Public IP = $UPLOAD_WEB_PUBLIC_IP"

# 4) Search Web EC2
echo "======================================"
echo " Deploying 41-search-web"
echo "======================================"
"$DEPLOY_SCRIPT" \
  "${PROJECT_NAME}-search-web-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/41-search-web.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT" \
  VPCId="$VPC_ID" \
  PublicSubnetId="$PUBLIC_SUBNET_ID" \
  NodeSecurityGroupId="$NODE_SG_ID" \
  EC2KeyPairName="$EC2_KEYPAIR_NAME" \
  GitRepositoryUrl="$GIT_REPO_URL" \
  BranchName="$BRANCH_NAME"

SEARCH_STACK="${PROJECT_NAME}-search-web-${ENVIRONMENT}"
SEARCH_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$SEARCH_STACK" \
  --region "$REGION" \
  --query "Stacks[0].Outputs" \
  --output json)

SEARCH_WEB_PUBLIC_IP=$(echo "$SEARCH_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SearchWebPublicIP") | .OutputValue')
echo "Search Web Public IP = $SEARCH_WEB_PUBLIC_IP"

# 5) Database EC2
echo "======================================"
echo " Deploying 42-database"
echo "======================================"
"$DEPLOY_SCRIPT" \
  "${PROJECT_NAME}-database-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/42-database.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT" \
  VPCId="$VPC_ID" \
  PublicSubnetId="$PUBLIC_SUBNET_ID" \
  DbSecurityGroupId="$DB_SG_ID" \
  EC2KeyPairName="$EC2_KEYPAIR_NAME" \
  DbName="$DB_NAME" \
  DbUser="$DB_USER" \
  DbPassword="$DB_PASS"

DB_STACK="${PROJECT_NAME}-database-${ENVIRONMENT}"
DB_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$DB_STACK" \
  --region "$REGION" \
  --query "Stacks[0].Outputs" \
  --output json)

DB_PRIVATE_IP=$(echo "$DB_OUTPUTS" | jq -r '.[] | select(.OutputKey=="DatabasePrivateIP") | .OutputValue')
DB_PUBLIC_IP=$(echo "$DB_OUTPUTS" | jq -r '.[] | select(.OutputKey=="DatabasePublicIP") | .OutputValue')

echo "DB Private IP = $DB_PRIVATE_IP"
echo "DB Public  IP = $DB_PUBLIC_IP"

UI_NOTIFY_URL="http://${SEARCH_WEB_PUBLIC_IP}:3000/lambda-result"
echo "UI_NOTIFY_URL = $UI_NOTIFY_URL"

# 6) Lambdas
echo "======================================"
echo " Deploying 20-lambdas"
echo "======================================"
"$DEPLOY_SCRIPT" \
  "${PROJECT_NAME}-lambdas-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/20-lambdas.yaml" \
  ProjectName="$PROJECT_NAME" \
  Environment="$ENVIRONMENT" \
  DbHost="$DB_PRIVATE_IP" \
  DbPort="3306" \
  DbUser="$DB_USER" \
  DbPass="$DB_PASS" \
  DbName="$DB_NAME" \
  CollectionId="$COLLECTION_ID" \
  UiNotifyUrl="$UI_NOTIFY_URL" \
  LambdaCodeBucket="$LAMBDA_ARTIFACTS_BUCKET" \
  IndexFaceKey="lambda-index-face.zip" \
  SearchFaceKey="lambda-search-face.zip" \
  UploadBucketArn="$UPLOAD_BUCKET_ARN" \
  SearchBucketArn="$SEARCH_BUCKET_ARN"

LAMBDA_STACK="${PROJECT_NAME}-lambdas-${ENVIRONMENT}"
LAMBDA_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$LAMBDA_STACK" \
  --region "$REGION" \
  --query "Stacks[0].Outputs" \
  --output json)

INDEX_LAMBDA_ARN=$(echo "$LAMBDA_OUTPUTS" | jq -r '.[] | select(.OutputKey=="IndexFaceFunctionArnOut") | .OutputValue')
SEARCH_LAMBDA_ARN=$(echo "$LAMBDA_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SearchFaceFunctionArnOut") | .OutputValue')

echo "Index Lambda ARN  = $INDEX_LAMBDA_ARN"
echo "Search Lambda ARN = $SEARCH_LAMBDA_ARN"

# 7) S3 Events
echo "======================================"
echo " Deploying 30-s3-events"
echo "======================================"
"$DEPLOY_SCRIPT" \
  "${PROJECT_NAME}-s3-events-${ENVIRONMENT}" \
  "$ROOT_DIR/infra/cfn/30-s3-events.yaml" \
  UploadBucketName="$UPLOAD_BUCKET_NAME" \
  SearchBucketName="$SEARCH_BUCKET_NAME" \
  IndexFaceFunctionArn="$INDEX_LAMBDA_ARN" \
  SearchFaceFunctionArn="$SEARCH_LAMBDA_ARN"

echo "======================================"
echo " ✅ All stacks deployed successfully."
echo " Upload Web  : http://$UPLOAD_WEB_PUBLIC_IP/"
echo " Search Web  : http://$SEARCH_WEB_PUBLIC_IP:3000/"
echo " DB (public) : $DB_PUBLIC_IP"
echo "======================================"

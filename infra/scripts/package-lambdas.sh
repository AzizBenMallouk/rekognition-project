#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/scripts/package-lambdas.sh LAMBDA_ARTIFACTS_BUCKET
#
# Example:
#   ./infra/scripts/package-lambdas.sh rekognition-lambda-artifacts

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 LAMBDA_ARTIFACTS_BUCKET" >&2
  exit 1
fi

ARTIFACT_BUCKET="$1"
REGION="${AWS_REGION:-us-east-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR/lambdas"

for fn in index-face search-face; do
  echo "Packaging lambda: $fn"

  cd "$fn"
  ZIP_NAME="lambda-${fn}.zip"
  rm -f "../$ZIP_NAME"

  if [ -f requirements.txt ]; then
    rm -rf package
    mkdir package
    pip install -r requirements.txt -t package
    cd package
    zip -r "../$ZIP_NAME" .
    cd ..
    zip -g "$ZIP_NAME" handler.py
  else
    zip -r "$ZIP_NAME" handler.py
  fi

  echo "Uploading $ZIP_NAME to s3://$ARTIFACT_BUCKET/$ZIP_NAME"
  aws s3 cp "$ZIP_NAME" "s3://$ARTIFACT_BUCKET/$ZIP_NAME" --region "$REGION"

  cd ..
done

echo "✅ Lambdas packaged & uploaded."

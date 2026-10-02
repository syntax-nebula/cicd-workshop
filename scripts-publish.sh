#!/usr/bin/env bash
set -euo pipefail   # stop at the first failing command (-e), an unset variable (-u), or a failure inside a pipe (pipefail)

BUCKET=$(aws cloudformation describe-stacks --stack-name cicd-workshop-pipeline \
  --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucket`].OutputValue' --output text)

TMP=$(mktemp -d)
git archive --format=zip HEAD > "$TMP/source.zip"
aws s3 cp "$TMP/source.zip" "s3://${BUCKET}/source/source.zip"
rm -rf "$TMP"

echo "Published $(git rev-parse --short HEAD) to s3://${BUCKET}/source/source.zip"

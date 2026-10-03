#!/usr/bin/env bash
# Terraform creates the CodeDeploy resources; this performs the deployment.
set -euo pipefail

FUNCTION="cicd-workshop-tfdev-order-api"
CURRENT=$(aws lambda get-alias --function-name "$FUNCTION" --name live \
  --query 'FunctionVersion' --output text)
TARGET=$(aws lambda list-versions-by-function --function-name "$FUNCTION" \
  --query 'Versions[-1].Version' --output text)

if [ "$CURRENT" = "$TARGET" ]; then
  echo "Alias already on version ${TARGET}; nothing to shift."
  exit 0
fi

echo "Shifting traffic ${CURRENT} -> ${TARGET}"

APPSPEC=$(python3 -c "
import json
print(json.dumps({'version':0.0,'Resources':[{'OrderApi':{'Type':'AWS::Lambda::Function',
  'Properties':{'Name':'${FUNCTION}','Alias':'live',
  'CurrentVersion':'${CURRENT}','TargetVersion':'${TARGET}'}}}]}))")

DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name "$FUNCTION" \
  --deployment-group-name live \
  --revision "revisionType=AppSpecContent,appSpecContent={content='${APPSPEC}'}" \
  --query 'deploymentId' --output text)

echo "CodeDeploy deployment ${DEPLOYMENT_ID} started"
aws deploy wait deployment-successful --deployment-id "$DEPLOYMENT_ID"
echo "Traffic shift complete"

#!/usr/bin/env bash
# Post-deploy synthetic check: publish one event, assert it reaches the far end.
set -euo pipefail   # stop at the first failing command (-e), an unset variable (-u), or a failure inside a pipe (pipefail)

ENVIRONMENT="${1:?usage: verify-flow.sh <environment>}"
STACK="cicd-workshop-${ENVIRONMENT}"
TIMEOUT_S="${2:-90}"

QUEUE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`ShippingQueueUrl`].OutputValue' --output text)
BUS_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' --output text)

CORRELATION_ID="synthetic-$(date +%s)-$RANDOM"
echo "Publishing synthetic OrderPlaced with correlationId=${CORRELATION_ID}"

DETAIL=$(python3 -c "
import json,sys
print(json.dumps(json.dumps({
  'schemaVersion': '1.0',
  'orderId': 'synthetic',
  'total': 1,
  'highValue': False,
  'synthetic': True,
  'correlationId': '${CORRELATION_ID}'
})))")

aws events put-events --entries "[{
  \"Source\": \"cicd-workshop.orders\",
  \"DetailType\": \"OrderPlaced\",
  \"EventBusName\": \"${BUS_NAME}\",
  \"Detail\": ${DETAIL}
}]" --query 'FailedEntryCount' --output text

DEADLINE=$(( $(date +%s) + TIMEOUT_S ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  BODIES=$(aws sqs receive-message --queue-url "$QUEUE_URL" \
    --max-number-of-messages 10 --wait-time-seconds 5 \
    --query 'Messages[].Body' --output text 2>/dev/null || true)

  if echo "$BODIES" | grep -q "$CORRELATION_ID"; then
    echo "OK: synthetic event reached the shipping queue."
    exit 0
  fi
done

echo "FAIL: synthetic event did not reach the shipping queue within ${TIMEOUT_S}s."
echo "The deployment succeeded but the event chain is broken. Investigate:"
echo "  - EventBridge rule pattern on bus ${BUS_NAME}"
echo "  - the rule's target permission"
echo "  - /aws/lambda/cicd-workshop-${ENVIRONMENT}-fulfilment"
exit 1

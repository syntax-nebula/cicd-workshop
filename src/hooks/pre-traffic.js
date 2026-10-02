import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';
import { CodeDeployClient, PutLifecycleEventHookExecutionStatusCommand }
  from '@aws-sdk/client-codedeploy';

const lambda = new LambdaClient({});
const codedeploy = new CodeDeployClient({});

export const handler = async (event) => {
  let status = 'Succeeded';

  try {
    // Invoke the NEW version directly, before any traffic is shifted to it.
    const res = await lambda.send(new InvokeCommand({
      FunctionName: process.env.NEW_VERSION_ARN,
      Payload: Buffer.from(JSON.stringify({
        body: JSON.stringify({
          correlationId: `pretraffic-${Date.now()}`,
          items: [{ sku: 'SMOKE', price: 1, qty: 1 }],
        }),
      })),
    }));

    const payload = JSON.parse(Buffer.from(res.Payload).toString());
    console.log('Smoke test response', JSON.stringify(payload));

    if (res.FunctionError || payload.statusCode !== 201) {
      console.error('Smoke test failed', res.FunctionError, payload.statusCode);
      status = 'Failed';
    }
  } catch (err) {
    console.error('Smoke test threw', err);
    status = 'Failed';
  }

  await codedeploy.send(new PutLifecycleEventHookExecutionStatusCommand({
    deploymentId: event.DeploymentId,
    lifecycleEventHookExecutionId: event.LifecycleEventHookExecutionId,
    status,
  }));

  return status;
};

import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';

const sqs = new SQSClient({});

export const handler = async (event) => {
  const detail = event.detail ?? {};
  console.log('Received OrderPlaced', JSON.stringify(detail));

  await sqs.send(new SendMessageCommand({
    QueueUrl: process.env.SHIPPING_QUEUE_URL,
    MessageBody: JSON.stringify({
      orderId: detail.orderId,
      correlationId: detail.correlationId,
      status: 'READY_TO_SHIP',
      priority: detail.highValue ? 'EXPRESS' : 'STANDARD',
    }),
  }));

  return { status: 'READY_TO_SHIP' };
};

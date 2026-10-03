import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';

const sqs = new SQSClient({});

export const handler = async (event) => {
  const detail = event.detail ?? {};
  console.log('Received OrderPlaced', JSON.stringify(detail));

  // Tolerant read: prefer the new field, fall back to the deprecated one.
  // The fallback is removed once the producer contracts (see docs/events.md).
  const orderTotal = detail.orderTotal ?? detail.total;

  await sqs.send(new SendMessageCommand({
    QueueUrl: process.env.SHIPPING_QUEUE_URL,
    MessageBody: JSON.stringify({
      orderId: detail.orderId,
      orderTotal,
      correlationId: detail.correlationId,
      status: 'READY_TO_SHIP',
      priority: detail.highValue ? 'EXPRESS' : 'STANDARD',
    }),
  }));

  return { status: 'READY_TO_SHIP' };
};

import { mockClient } from 'aws-sdk-client-mock';
import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';
import { handler } from '../../src/fulfilment/index.js';

const sqsMock = mockClient(SQSClient);

const ebEvent = (detail) => ({ detail });

beforeEach(() => {
  sqsMock.reset();
  sqsMock.on(SendMessageCommand).resolves({ MessageId: 'm-1' });
  process.env.SHIPPING_QUEUE_URL = 'https://sqs.invalid/queue';
});

const sentBody = () =>
  JSON.parse(sqsMock.commandCalls(SendMessageCommand)[0].args[0].input.MessageBody);

test('reads orderTotal from a v1.1 event', async () => {
  await handler(ebEvent({
    schemaVersion: '1.1', orderId: 'o-1', correlationId: 'c-1',
    total: 50, orderTotal: 50, highValue: false,
  }));
  expect(sentBody().orderTotal).toBe(50);
});

// The compatibility guarantee: an old event must still work.
test('falls back to total for a v1.0 event', async () => {
  await handler(ebEvent({
    schemaVersion: '1.0', orderId: 'o-2', correlationId: 'c-2',
    total: 75, highValue: false,
  }));
  expect(sentBody().orderTotal).toBe(75);
});

test('marks high-value orders EXPRESS', async () => {
  await handler(ebEvent({
    schemaVersion: '1.1', orderId: 'o-3', correlationId: 'c-3',
    orderTotal: 5000, highValue: true,
  }));
  expect(sentBody().priority).toBe('EXPRESS');
});

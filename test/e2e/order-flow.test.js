import { randomUUID } from 'node:crypto';
import { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } from '@aws-sdk/client-sqs';

const sqs = new SQSClient({ region: process.env.AWS_REGION ?? 'eu-central-1' });
const API_URL = process.env.API_URL;
const QUEUE_URL = process.env.QUEUE_URL;

async function waitFor(assertion, { timeout = 60000, interval = 2000 } = {}) {
  const deadline = Date.now() + timeout;
  let lastError;
  while (Date.now() < deadline) {
    try {
      return await assertion();
    } catch (err) {
      lastError = err;
      await new Promise((r) => setTimeout(r, interval));
    }
  }
  throw new Error(`Condition not met within ${timeout}ms. Last: ${lastError?.message}`);
}

async function findMessage(correlationId) {
  const res = await sqs.send(new ReceiveMessageCommand({
    QueueUrl: QUEUE_URL,
    MaxNumberOfMessages: 10,
    WaitTimeSeconds: 5,
  }));
  for (const m of res.Messages ?? []) {
    const body = JSON.parse(m.Body);
    if (body.correlationId === correlationId) {
      await sqs.send(new DeleteMessageCommand({
        QueueUrl: QUEUE_URL, ReceiptHandle: m.ReceiptHandle,
      }));
      return body;
    }
  }
  throw new Error('message not on the queue yet');
}

test('a standard order reaches the shipping queue', async () => {
  const correlationId = randomUUID();

  const res = await fetch(`${API_URL}/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ correlationId, items: [{ sku: 'ABC', price: 10, qty: 2 }] }),
  });
  expect(res.status).toBe(201);

  const message = await waitFor(() => findMessage(correlationId));

  expect(message.status).toBe('READY_TO_SHIP');
  expect(message.priority).toBe('STANDARD');
});

test('a high-value order is marked EXPRESS end to end', async () => {
  const correlationId = randomUUID();

  await fetch(`${API_URL}/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ correlationId, items: [{ sku: 'LUX', price: 900, qty: 2 }] }),
  });

  const message = await waitFor(() => findMessage(correlationId));
  expect(message.priority).toBe('EXPRESS');
});

test('an invalid order never reaches the queue', async () => {
  const correlationId = randomUUID();

  const res = await fetch(`${API_URL}/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ correlationId, items: [] }),
  });
  expect(res.status).toBe(400);

  // Give the system a chance to be wrong, then assert nothing arrived.
  await new Promise((r) => setTimeout(r, 15000));
  await expect(findMessage(correlationId)).rejects.toThrow();
});

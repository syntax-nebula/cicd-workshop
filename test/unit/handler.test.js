import { mockClient } from 'aws-sdk-client-mock';
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { _resetCacheForTests } from '../../src/order-api/secrets.js';
import { handler } from '../../src/order-api/index.js';

const ddbMock = mockClient(DynamoDBClient);
const ebMock = mockClient(EventBridgeClient);
const smMock = mockClient(SecretsManagerClient);

const apiEvent = (body) => ({ body: JSON.stringify(body) });

beforeEach(() => {
  ddbMock.reset();
  ebMock.reset();
  smMock.reset();
  _resetCacheForTests();
  smMock.on(GetSecretValueCommand).resolves({
    SecretString: JSON.stringify({ apiKey: 'k', endpoint: 'https://e.invalid' }),
  });
  process.env.ORDERS_TABLE = 'cicd-workshop-orders';
  process.env.EVENT_BUS_NAME = 'cicd-workshop-bus';
});

test('returns 400 and touches nothing when the order is invalid', async () => {
  const res = await handler(apiEvent({ items: [] }));

  expect(res.statusCode).toBe(400);
  expect(ddbMock.commandCalls(PutItemCommand)).toHaveLength(0);
  expect(ebMock.commandCalls(PutEventsCommand)).toHaveLength(0);
});

test('stores the order and publishes OrderPlaced', async () => {
  ddbMock.on(PutItemCommand).resolves({});
  ebMock.on(PutEventsCommand).resolves({ FailedEntryCount: 0 });

  const res = await handler(apiEvent({ items: [{ price: 10, qty: 2 }] }));

  expect(res.statusCode).toBe(201);
  expect(JSON.parse(res.body).total).toBe(20);

  const published = ebMock.commandCalls(PutEventsCommand);
  expect(published).toHaveLength(1);

  const entry = published[0].args[0].input.Entries[0];
  expect(entry.DetailType).toBe('OrderPlaced');
  expect(entry.Source).toBe('cicd-workshop.orders');

  const detail = JSON.parse(entry.Detail);
  expect(detail.schemaVersion).toBe('2.0');
  // Contract phase: the deprecated field is gone.
  expect(detail.total).toBeUndefined();
  expect(detail.orderTotal).toBe(20);
  expect(detail.highValue).toBe(false);
});

test('marks high-value orders in the event', async () => {
  ddbMock.on(PutItemCommand).resolves({});
  ebMock.on(PutEventsCommand).resolves({ FailedEntryCount: 0 });

  await handler(apiEvent({ items: [{ price: 600, qty: 2 }] }));

  const detail = JSON.parse(ebMock.commandCalls(PutEventsCommand)[0].args[0].input.Entries[0].Detail);
  expect(detail.highValue).toBe(true);
});

test('propagates the caller correlation id into the event', async () => {
  ddbMock.on(PutItemCommand).resolves({});
  ebMock.on(PutEventsCommand).resolves({ FailedEntryCount: 0 });

  await handler(apiEvent({ correlationId: 'abc-123', items: [{ price: 10, qty: 1 }] }));

  const detail = JSON.parse(ebMock.commandCalls(PutEventsCommand)[0].args[0].input.Entries[0].Detail);
  expect(detail.correlationId).toBe('abc-123');
});

// The important one: an ordering guarantee, not an implementation detail.
test('does NOT publish an event when the write fails', async () => {
  ddbMock.on(PutItemCommand).rejects(new Error('ProvisionedThroughputExceededException'));

  await expect(handler(apiEvent({ items: [{ price: 10, qty: 1 }] }))).rejects.toThrow();

  expect(ebMock.commandCalls(PutEventsCommand)).toHaveLength(0);
});

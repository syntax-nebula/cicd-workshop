import { randomUUID } from 'node:crypto';
import { getPaymentSecret } from './secrets.js';
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';

const ddb = new DynamoDBClient({});
const eb = new EventBridgeClient({});

export function calculateTotal(items) {
  return items.reduce((sum, i) => sum + i.price * i.qty, 0);
}

export function validateOrder(order) {
  const errors = [];
  if (!Array.isArray(order.items) || order.items.length === 0) {
    errors.push('Order must contain items');
  }
  if (calculateTotal(Array.isArray(order.items) ? order.items : []) <= 0) {
    errors.push('Total must be positive');
  }
  return { valid: errors.length === 0, errors };
}

export function isHighValue(order) {
  return calculateTotal(Array.isArray(order.items) ? order.items : []) > 1000;
}

export const handler = async (event) => {
  const order = JSON.parse(event.body ?? '{}');
  const { valid, errors } = validateOrder(order);
  if (!valid) {
    return { statusCode: 400, body: JSON.stringify({ errors }) };
  }

  // Resolve the credential at runtime. Never log it.
  const { endpoint } = await getPaymentSecret();
  console.log(JSON.stringify({ msg: 'payment endpoint resolved', endpoint }));

  const orderId = randomUUID();
  const total = calculateTotal(order.items);

  // Persist first. Only publish if the write succeeded.
  await ddb.send(new PutItemCommand({
    TableName: process.env.ORDERS_TABLE,
    Item: {
      orderId: { S: orderId },
      total: { N: String(total) },
      correlationId: { S: order.correlationId ?? orderId },
    },
  }));

  await eb.send(new PutEventsCommand({
    Entries: [{
      Source: 'cicd-workshop.orders',
      DetailType: 'OrderPlaced',
      EventBusName: process.env.EVENT_BUS_NAME,
      Detail: JSON.stringify({
        schemaVersion: '1.0',
        orderId,
        total,
        highValue: isHighValue(order),
        correlationId: order.correlationId ?? orderId,
      }),
    }],
  }));

  return { statusCode: 201, body: JSON.stringify({ orderId, total }) };
};

export function calculateTotal(items) {
  return items.reduce((sum, i) => sum + i.price * i.qty, 0);
}

export function validateOrder(order) {
  const errors = [];
  if (!order.items?.length) errors.push('Order must contain items');
  if (calculateTotal(order.items ?? []) <= 0) errors.push('Total must be positive');
  return { valid: errors.length === 0, errors };
}

export const handler = async (event) => {
  const order = JSON.parse(event.body ?? '{}');
  const { valid, errors } = validateOrder(order);
  if (!valid) {
    return { statusCode: 400, body: JSON.stringify({ errors }) };
  }
  return {
    statusCode: 201,
    body: JSON.stringify({ orderId: 'placeholder', total: calculateTotal(order.items) }),
  };
};

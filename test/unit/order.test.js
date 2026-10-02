import { calculateTotal, validateOrder, isHighValue } from '../../src/order-api/index.js';

describe('calculateTotal', () => {
  test('sums price times quantity', () => {
    expect(calculateTotal([{ price: 10, qty: 2 }, { price: 5, qty: 3 }])).toBe(35);
  });

  test('returns 0 for an empty basket', () => {
    expect(calculateTotal([])).toBe(0);
  });
});

describe('validateOrder', () => {
  test('accepts a well-formed order', () => {
    const result = validateOrder({ items: [{ price: 10, qty: 1 }] });
    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
  });

  test('rejects an order with no items', () => {
    const result = validateOrder({ items: [] });
    expect(result.valid).toBe(false);
    expect(result.errors).toContain('Order must contain items');
  });

  test('rejects a zero-value order', () => {
    const result = validateOrder({ items: [{ price: 0, qty: 5 }] });
    expect(result.valid).toBe(false);
    expect(result.errors).toContain('Total must be positive');
  });

  test('rejects a non-array items payload', () => {
    expect(validateOrder({ items: 'not-an-array' }).valid).toBe(false);
  });
});

describe('isHighValue', () => {
  test.each([
    [[{ price: 500, qty: 3 }], true],
    [[{ price: 500, qty: 2 }], false],
    [[], false],
  ])('%j -> %s', (items, expected) => {
    expect(isHighValue({ items })).toBe(expected);
  });
});

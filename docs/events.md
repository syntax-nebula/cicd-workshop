# Event catalogue — cicd-workshop

Every event published on `cicd-workshop-<env>-bus` is documented here.
**A pull request that changes a published event MUST update this file.**

---

## OrderPlaced

| | |
| --- | --- |
| Source | `cicd-workshop.orders` |
| Detail type | `OrderPlaced` |
| Producer | `order-api` |
| Current schema version | 1.0 |

### Schema 1.0

```json
{
  "schemaVersion": "1.0",
  "orderId": "string (uuid)",
  "total": "number",
  "highValue": "boolean",
  "correlationId": "string"
}
```

### Known consumers

| Consumer | Owner | Fields read | Migrated to 1.1? |
| --- | --- | --- | --- |
| `fulfilment` | Fulfilment team | `orderId`, `correlationId`, `highValue` | n/a |

### Deprecations in flight

_None._

---

## Change rules

- **Adding** an optional field is backward compatible. Ship it.
- **Removing** or **renaming** a field is breaking. Use expand/contract:
  1. Publish both old and new. Deploy the producer.
  2. Migrate every consumer in the table above.
  3. Verify the old field is unread (metric at zero for the agreed window).
  4. Stop publishing the old field.
- **Adding a value to an enum** is breaking for consumers that `switch` without a
  `default`. Treat it as breaking unless you have checked.
- There is no `410 Gone` for an event. A consumer reading a removed field gets
  `undefined` and reports nothing.

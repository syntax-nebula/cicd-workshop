# Deployment record — v2.0.0

- Deployed: 2026-10-03T08:35:18Z
- Commit:   16be99eb8239a17b6984708a6ebcd4c3939d692e
- Range:    v1.0.0..v2.0.0

## Changes
- chore(release): 2.0.0 (16be99e)
- feat(events)!: remove the deprecated total field (contract phase) (bb9df08)
- feat(fulfilment): read orderTotal with a fallback to total (migrate phase) (aced1dc)
- feat(events): publish orderTotal alongside total (expand phase) (4b02103)
- docs(events): add the event catalogue (14fa461)
- ci: add manual approval gate before production (bd3752a)
- ci: verify the event chain after every deploy (9eda4ab)
- fix(events): restore the OrderPlaced detail-type in the rule (956aaeb)
- chore: lab 6 - move to the v2 event type (5e169db)
- fix(iam): restore DynamoDB write permission on the orders table (7c060c9)
- chore: lab 6 - tighten the table policy (17555a2)
- fix: restore correct secrets module path (9132049)
- chore: lab 6 - break the build (406eba8)
- chore: trigger a cached build (d86f031)
- ci: add source publish script (1ba0d61)
- ci: add multi-stage pipeline as code (0bd5b98)
- chore: add samconfig for three environments (a48ed95)
- feat(iac): parameterise the template by environment (878c1f6)
- feat(deploy): add PreTraffic smoke-test hook (1ccf390)
- feat(order-api): include apiVersion in validation errors (f90e16e)
- feat(deploy): canary preference with version-scoped alarms (9cfbab5)
- feat(deploy): publish versions and a live alias (19422ce)
- ci: add pre-commit secret scan (6dd9ba9)
- ci: resolve build credentials from Parameter Store and Secrets Manager (c57ec2b)
- fix(security): resolve payment credentials from Secrets Manager at runtime (b1722c8)
- feat: add payment API key (DO NOT DO THIS) (b2fb248)
- ci: add build stage with dependency, template, and policy gates (8781036)
- fix(security): add fulfilment DLQ and PITR; document VPC exemption (6bdd589)
- test: enforce coverage thresholds (f0793b3)
- test(e2e): end-to-end assertions across the event chain (85ffc56)
- feat: complete event-driven reference application (f16369a)
- test: add generated event fixtures (040cb6b)
- test(order-api): unit tests for validation, publishing, and ordering guarantee (6e1b4ec)
- chore: add jest and aws-sdk-client-mock (ac65080)

## Breaking changes
- feat(events)!: remove the deprecated total field (contract phase) (bb9df08)

## Event schema
| Current schema version | 2.0 |

### Schema 2.0

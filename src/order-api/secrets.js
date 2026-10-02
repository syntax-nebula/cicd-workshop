import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const client = new SecretsManagerClient({});

// Module scope: survives warm invocations, so we do not call Secrets Manager
// on every request. The TTL means a rotated secret is picked up without a
// redeploy — a cache with no TTL turns rotation into an outage.
let cached = null;
let cachedAt = 0;
const TTL_MS = 5 * 60 * 1000;

export async function getPaymentSecret() {
  if (cached && Date.now() - cachedAt < TTL_MS) return cached;

  const res = await client.send(new GetSecretValueCommand({
    SecretId: process.env.PAYMENT_SECRET_ID,
  }));

  cached = JSON.parse(res.SecretString);
  cachedAt = Date.now();
  return cached;
}

export function _resetCacheForTests() {
  cached = null;
  cachedAt = 0;
}

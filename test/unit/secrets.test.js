import { mockClient } from 'aws-sdk-client-mock';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { getPaymentSecret, _resetCacheForTests } from '../../src/order-api/secrets.js';

const smMock = mockClient(SecretsManagerClient);

beforeEach(() => {
  smMock.reset();
  _resetCacheForTests();
  process.env.PAYMENT_SECRET_ID = 'cicd-workshop/payment-api';
});

test('fetches the secret and parses it', async () => {
  smMock.on(GetSecretValueCommand).resolves({
    SecretString: JSON.stringify({ apiKey: 'k', endpoint: 'https://e.invalid' }),
  });

  const secret = await getPaymentSecret();
  expect(secret.apiKey).toBe('k');
});

test('caches within the TTL — one call, not two', async () => {
  smMock.on(GetSecretValueCommand).resolves({
    SecretString: JSON.stringify({ apiKey: 'k', endpoint: 'https://e.invalid' }),
  });

  await getPaymentSecret();
  await getPaymentSecret();

  expect(smMock.commandCalls(GetSecretValueCommand)).toHaveLength(1);
});

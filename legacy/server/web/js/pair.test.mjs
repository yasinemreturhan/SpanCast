import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { pinProof } from './pair.js';

// Sunucudaki Go testiyle (TestProofKnownVector) aynı bilinen vektör:
test('pinProof: Go implementasyonuyla aynı bilinen vektörü üretir', async () => {
  assert.equal(
    await pinProof('123456', '00ff10'),
    '517366fe3e42e24656f7bafdde7e4b1bf3be181c2326211fae7cef3042ef53cf',
  );
});

test('pinProof: node:crypto referansıyla rastgele girdilerde eşleşir', async () => {
  for (const [pin, salt] of [['000001', 'aa'], ['987654', 'deadbeef00112233']]) {
    const want = createHmac('sha256', pin).update(salt).digest('hex');
    assert.equal(await pinProof(pin, salt), want);
  }
});

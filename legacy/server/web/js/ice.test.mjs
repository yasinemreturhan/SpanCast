import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { fetchIceServers } from './ice.js';

function mockFetch(status, body) {
  return () => Promise.resolve({ ok: status < 400, json: () => Promise.resolve(body) });
}

describe('fetchIceServers', () => {
  it('STUN sunucusu döner', async () => {
    const servers = [{ urls: ['stun:stun.l.google.com:19302'] }];
    const result = await fetchIceServers(mockFetch(200, { iceServers: servers }));
    assert.deepEqual(result, servers);
  });

  it('API başarısız olursa boş dizi döner', async () => {
    const result = await fetchIceServers(() => Promise.resolve({ ok: false }));
    assert.deepEqual(result, []);
  });

  it('fetch fırlatırsa boş dizi döner', async () => {
    const result = await fetchIceServers(() => Promise.reject(new Error('ağ hatası')));
    assert.deepEqual(result, []);
  });

  it('iceServers alanı yoksa boş dizi döner', async () => {
    const result = await fetchIceServers(mockFetch(200, {}));
    assert.deepEqual(result, []);
  });
});

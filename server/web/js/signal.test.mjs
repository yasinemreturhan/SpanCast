import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SignalClient, backoffMs } from './signal.js';

// Sahte WebSocket: bağlantı davranışı testten yönetilir.
class FakeWS {
  static instances = [];
  constructor(url) {
    this.url = url;
    this.sent = [];
    this.readyState = 0; // CONNECTING
    FakeWS.instances.push(this);
  }
  send(data) { this.sent.push(JSON.parse(data)); }
  close() { this.readyState = 3; this.onclose?.(); }
  // test yardımcıları
  fireOpen() { this.readyState = 1; this.onopen?.(); }
  fireMessage(obj) { this.onmessage?.({ data: JSON.stringify(obj) }); }
  fireClose() { this.readyState = 3; this.onclose?.(); }
}

function newClient(overrides = {}) {
  FakeWS.instances = [];
  const timers = [];
  const client = new SignalClient('ws://x/ws?role=sender', {
    WebSocketImpl: FakeWS,
    setTimeoutImpl: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    ...overrides,
  });
  return { client, timers, ws: () => FakeWS.instances.at(-1) };
}

test('backoffMs: üstel 500ms→8s, sonra sabit', () => {
  assert.equal(backoffMs(0), 500);
  assert.equal(backoffMs(1), 1000);
  assert.equal(backoffMs(2), 2000);
  assert.equal(backoffMs(3), 4000);
  assert.equal(backoffMs(4), 8000);
  assert.equal(backoffMs(9), 8000);
});

test('bağlantı öncesi send kuyruğa girer, open olunca boşalır', () => {
  const { client, ws } = newClient();
  client.connect();
  client.send({ type: 'offer', payload: { sdp: 'x' } });
  assert.equal(ws().sent.length, 0);
  ws().fireOpen();
  assert.equal(ws().sent.length, 1);
  assert.equal(ws().sent[0].type, 'offer');
});

test('mesajlar tip bazlı dinleyicilere dağıtılır', () => {
  const { client, ws } = newClient();
  const got = [];
  client.on('pin', m => got.push(m));
  client.connect();
  ws().fireOpen();
  ws().fireMessage({ type: 'pin', pin: '123456' });
  ws().fireMessage({ type: 'other' });
  assert.equal(got.length, 1);
  assert.equal(got[0].pin, '123456');
});

test('kopunca backoff ile yeniden bağlanır ve kuyruk yeni sokete akar', () => {
  const { client, timers, ws } = newClient();
  client.connect();
  ws().fireOpen();
  ws().fireClose();               // kopuş → zamanlayıcı kurulmalı
  assert.equal(timers.length, 1);
  assert.equal(timers[0].ms, 500);

  client.send({ type: 'ice' });   // kopukken gönder → kuyruk
  timers[0].fn();                 // zamanlayıcı ateşle → yeni WS
  const ws2 = ws();
  ws2.fireOpen();
  assert.equal(ws2.sent.length, 1);
  assert.equal(ws2.sent[0].type, 'ice');
});

test('close() sonrası yeniden bağlanmaz', () => {
  const { client, timers, ws } = newClient();
  client.connect();
  ws().fireOpen();
  client.close();
  assert.equal(timers.length, 0, 'kapatınca zamanlayıcı kurulmamalı');
});

test('başarılı bağlantı backoff sayacını sıfırlar', () => {
  const { client, timers, ws } = newClient();
  client.connect();
  ws().fireClose();  // deneme 1 → 500ms
  timers[0].fn();
  ws().fireClose();  // deneme 2 → 1000ms
  timers[1].fn();
  ws().fireOpen();   // bağlandı → sayaç sıfır
  ws().fireClose();  // tekrar kopuş → yine 500ms'ten başlamalı
  assert.equal(timers.at(-1).ms, 500);
});

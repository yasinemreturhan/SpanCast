// PIN proof: HMAC-SHA256(key=PIN, msg=saltHex) → hex.
// Sunucudaki signal.Proof ile birebir aynı tanım — PIN ağdan hiç geçmez.

// Tarayıcıda globalThis.crypto hazır; node 18'de (test) webcrypto modülden gelir.
const subtle = globalThis.crypto?.subtle
  ?? (await import('node:crypto')).webcrypto.subtle;

export async function pinProof(pin, saltHex) {
  const enc = new TextEncoder();
  const key = await subtle.importKey(
    'raw', enc.encode(pin), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await subtle.sign('HMAC', key, enc.encode(saltHex));
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, '0')).join('');
}

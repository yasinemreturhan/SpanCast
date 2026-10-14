// Sender: PIN ile odaya katılır (challenge-response — PIN ağdan geçmez),
// ekranı yakalar ve WebRTC ile akıtır. Signaling koparsa SignalClient
// yeniden bağlanır ve akış yeniden kurulur.
import { SignalClient } from './signal.js';
import { pinProof } from './pair.js';
import { fetchIceServers } from './ice.js';

const $ = id => document.getElementById(id);
const status = m => { $('status').textContent = m; };

let client = null;
let pc = null;
let stream = null;

// ─── Güvenilir cihaz (TOFU) ─────────────────────────────────────────────────
const TRUST_KEY = `ushare_trust_${location.host}`;

function loadToken()  { try { return localStorage.getItem(TRUST_KEY) || null; } catch { return null; } }
function saveToken(t) { try { localStorage.setItem(TRUST_KEY, t); } catch {} }
function clearToken() { try { localStorage.removeItem(TRUST_KEY); } catch {} }

// Kayıtlı cihaz rozeti: token varsa göster.
function refreshTrustBadge() {
  const badge = $('trustBadge');
  if (!badge) return;
  const tok = loadToken();
  badge.style.display = tok ? 'block' : 'none';
}
// Rozete tıklanınca PIN adımı atlanır.
window.addEventListener('DOMContentLoaded', () => {
  refreshTrustBadge();
  const badge = $('trustBadge');
  if (badge) badge.onclick = () => startWithToken();
  const forgetBtn = $('forgetBtn');
  if (forgetBtn) forgetBtn.onclick = () => { clearToken(); refreshTrustBadge(); status('Cihaz kaydı silindi.'); };
});

// --- 6 kutulu PIN girişi -----------------------------------------------------
const boxes = [...document.querySelectorAll('.pinbox')];
boxes.forEach((b, i) => {
  b.addEventListener('input', () => {
    b.value = b.value.replace(/\D/g, '').slice(-1);
    if (b.value && i < boxes.length - 1) boxes[i + 1].focus();
    if (pinValue().length === 6) $('startBtn').focus();
  });
  b.addEventListener('keydown', e => {
    if (e.key === 'Backspace' && !b.value && i > 0) boxes[i - 1].focus();
  });
  b.addEventListener('paste', e => {
    const digits = (e.clipboardData.getData('text').match(/\d/g) ?? []).slice(0, 6);
    if (!digits.length) return;
    e.preventDefault();
    digits.forEach((d, j) => { if (boxes[j]) boxes[j].value = d; });
    boxes[Math.min(digits.length, 5)].focus();
  });
});
const pinValue = () => boxes.map(b => b.value).join('');

// --- Akış kurulumu -----------------------------------------------------------
async function captureScreen() {
  // Üretimde: yerel capture katmanı (DXGI/ScreenCaptureKit). PoC: getDisplayMedia.
  return navigator.mediaDevices.getDisplayMedia({
    video: { frameRate: { ideal: 60 }, cursor: 'always' },
    audio: true,
  });
}

async function buildPeer() {
  pc?.close();
  const iceServers = await fetchIceServers();
  pc = new RTCPeerConnection({ iceServers });
  stream.getTracks().forEach(t => pc.addTrack(t, stream));

  pc.getSenders().forEach(s => {
    if (s.track?.kind === 'video') {
      const p = s.getParameters();
      p.degradationPreference = 'maintain-framerate';
      s.setParameters(p).catch(() => {});
    }
  });

  pc.onicecandidate = ev =>
    ev.candidate && client.send({ type: 'ice', payload: ev.candidate });
  pc.onconnectionstatechange = () => {
    if (pc.connectionState === 'connected') status('🟢 Yayında');
    if (pc.connectionState === 'failed') status('Medya bağlantısı koptu…');
  };

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  client.send({ type: 'offer', payload: offer });
}

// --- Başlat / durdur ---------------------------------------------------------

// PIN ile başlatma (normal akış).
$('startBtn').onclick = async () => {
  const pin = pinValue();
  if (!/^\d{6}$/.test(pin)) return status('6 haneli PIN gerekli.');

  try { stream = await captureScreen(); } catch (e) {
    return status('Ekran yakalama iptal edildi: ' + e.message);
  }
  $('preview').srcObject = stream;
  $('startBtn').disabled = true;
  $('stopBtn').style.display = 'inline-block';

  const name = $('deviceName').value.trim() || 'Tarayıcı';
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  client = new SignalClient(
    `${proto}://${location.host}/ws?role=sender&name=${encodeURIComponent(name)}`,
  );

  // Kimlik doğrulama: challenge'a PIN ile HMAC proof gönder.
  client.on('challenge', async msg => {
    const proof = await pinProof(pin, msg.payload.salt);
    client.send({ type: 'auth', payload: { proof } });
  });
  client.on('paired', msg => {
    // Başarılı PIN doğrulamasından sonra sunucu güven jetonu gönderir; sakla.
    if (msg.payload?.token) { saveToken(msg.payload.token); refreshTrustBadge(); }
    status('Eşleşti, akış kuruluyor…');
    buildPeer();
  });
  attachCommonHandlers();
  client.connect();
  stream.getVideoTracks()[0].onended = stop;
};

// Kayıtlı cihaz ile başlatma (token akışı — PIN gerekmez).
async function startWithToken() {
  const tok = loadToken();
  if (!tok) return;

  try { stream = await captureScreen(); } catch (e) {
    return status('Ekran yakalama iptal edildi: ' + e.message);
  }
  $('preview').srcObject = stream;
  $('startBtn').disabled = true;
  $('stopBtn').style.display = 'inline-block';

  const name = $('deviceName').value.trim() || 'Tarayıcı';
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  client = new SignalClient(
    `${proto}://${location.host}/ws?role=sender&name=${encodeURIComponent(name)}`,
  );

  client.on('challenge', () => {
    // challenge alındığında auth yerine trust gönder.
    client.send({ type: 'trust', payload: { token: tok } });
  });
  client.on('paired', () => {
    status('🔒 Kayıtlı cihaz olarak bağlandı, akış kuruluyor…');
    buildPeer();
  });
  // Jeton reddedilirse sil ve kullanıcıya PIN ile devam etmesini söyle.
  client.on('error', msg => {
    if (msg.reason === 'bad-token') {
      clearToken(); refreshTrustBadge();
      stop();
      return status('❌ Cihaz kaydı sona erdi. Lütfen PIN ile bağlan.');
    }
    const errs = {
      'room-full': 'Oda dolu (en fazla 4 kaynak).', 'receiver-gone': 'Alıcı kapandı.',
    };
    status('❌ ' + (errs[msg.reason] ?? msg.reason));
    stop();
  });
  attachCommonHandlers();
  client.on('_close', () => status('Bağlantı koptu, yeniden deneniyor…'));
  client.connect();
  stream.getVideoTracks()[0].onended = stop;
}

function attachCommonHandlers() {
  client.on('answer', msg => pc?.setRemoteDescription(msg.payload));
  client.on('ice', msg => pc?.addIceCandidate(msg.payload).catch(() => {}));
}

function stop() {
  client?.close();
  pc?.close();
  stream?.getTracks().forEach(t => t.stop());
  client = pc = stream = null;
  $('preview').srcObject = null;
  $('startBtn').disabled = false;
  $('stopBtn').style.display = 'none';
  if (!$('status').textContent.startsWith('❌')) status('Paylaşım durdu.');
}
$('stopBtn').onclick = stop;

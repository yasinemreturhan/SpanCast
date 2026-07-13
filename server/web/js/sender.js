// Sender: PIN ile odaya katılır (challenge-response — PIN ağdan geçmez),
// ekranı yakalar ve WebRTC ile akıtır. Signaling koparsa SignalClient
// yeniden bağlanır ve akış yeniden kurulur.
import { SignalClient } from './signal.js';
import { pinProof } from './pair.js';

const $ = id => document.getElementById(id);
const status = m => { $('status').textContent = m; };

let client = null;
let pc = null;
let stream = null;

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
  pc = new RTCPeerConnection({ iceServers: [] }); // LAN: STUN gereksiz
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
$('startBtn').onclick = async () => {
  const pin = pinValue();
  if (!/^\d{6}$/.test(pin)) return status('6 haneli PIN gerekli.');

  try {
    stream = await captureScreen();
  } catch (e) {
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

  // Kimlik doğrulama: sunucunun salt'ına PIN'le HMAC proof üret.
  client.on('challenge', async msg => {
    const proof = await pinProof(pin, msg.payload.salt);
    client.send({ type: 'auth', payload: { proof } });
  });
  client.on('paired', () => { status('Eşleşti, akış kuruluyor…'); buildPeer(); });
  client.on('answer', msg => pc?.setRemoteDescription(msg.payload));
  client.on('ice', msg => pc?.addIceCandidate(msg.payload).catch(() => {}));
  client.on('error', msg => {
    const errs = {
      'bad-pin': 'PIN hatalı.', 'pin-expired': 'PIN süresi dolmuş — alıcıda yeni kod alın.',
      'room-full': 'Oda dolu (en fazla 4 kaynak).', 'receiver-gone': 'Alıcı kapandı.',
    };
    status('❌ ' + (errs[msg.reason] ?? msg.reason));
    stop();
  });
  client.on('_close', () => status('Bağlantı koptu, yeniden deneniyor…'));
  client.connect();

  stream.getVideoTracks()[0].onended = stop; // kullanıcı paylaşımı tarayıcıdan keserse
};

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

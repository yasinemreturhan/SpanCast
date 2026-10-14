// UniversalShare — Electron renderer
// WebRTC + WebSocket signaling (same protocol as web sender.html).
// desktopCapturer: DXGI (Windows) / ScreenCaptureKit (macOS) / X11+PipeWire (Linux)

'use strict';

// ─── HMAC-SHA256 proof (same algorithm as server/internal/signal/proof.go) ───

async function pinProof(pin, saltHex) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(pin), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(saltHex));
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');
}

// ─── Simple SignalClient with auto-reconnect ──────────────────────────────────

class SignalClient {
  constructor(url) {
    this._url = url;
    this._handlers = {};
    this._queue = [];
    this._ws = null;
    this._closed = false;
    this._attempt = 0;
  }

  on(type, cb) { this._handlers[type] = cb; return this; }

  send(obj) {
    if (this._ws?.readyState === WebSocket.OPEN) {
      this._ws.send(JSON.stringify(obj));
    } else {
      this._queue.push(obj);
    }
  }

  connect() {
    if (this._closed) return;
    const ws = new WebSocket(this._url);
    this._ws = ws;
    ws.onopen = () => {
      this._attempt = 0;
      this._queue.splice(0).forEach(m => ws.send(JSON.stringify(m)));
    };
    ws.onmessage = ev => {
      try {
        const m = JSON.parse(ev.data);
        const h = this._handlers[m.type] || this._handlers['*'];
        if (h) h(m);
      } catch {}
    };
    ws.onclose = () => {
      if (this._closed) return;
      const delay = Math.min(500 * 2 ** this._attempt++, 8000);
      this._handlers['_close']?.({ type: '_close' });
      setTimeout(() => this.connect(), delay);
    };
  }

  close() { this._closed = true; this._ws?.close(); }
}

// ─── Fetch ICE config from server ────────────────────────────────────────────

async function fetchIceServers(baseUrl) {
  try {
    const r = await fetch(`${baseUrl}/api/ice`);
    if (!r.ok) return [];
    const d = await r.json();
    return Array.isArray(d.iceServers) ? d.iceServers : [];
  } catch { return []; }
}

// ─── UI helpers ──────────────────────────────────────────────────────────────

const $ = id => document.getElementById(id);
let serverBase = '';   // e.g. "https://192.168.1.20:8788"
let selectedSourceId = null;
let client = null;
let pc = null;
let stream = null;

function showStep(id) {
  document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
  $(id).classList.add('active');
}

function setStatus(msg) { $('statusMsg').textContent = msg; }

// ─── Step 1: Connect ─────────────────────────────────────────────────────────

$('connectBtn').onclick = async () => {
  const raw = $('serverAddr').value.trim();
  if (!raw) return;
  $('connectErr').textContent = '';
  $('connectBtn').disabled = true;

  const base = raw.startsWith('http') ? raw : `https://${raw}`;
  try {
    const r = await fetch(`${base}/healthz`);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const txt = await r.text();
    if (txt.trim() !== 'ok') throw new Error('sunucu yanıtı geçersiz');
    serverBase = base;

    // Fetch + display TLS fingerprint for trust verification
    try {
      const info = await (await fetch(`${base}/api/info`)).json();
      if (info.fp) $('fpBadge').textContent = `Sertifika: ${info.fp.slice(0, 32)}…`;
    } catch {}

    await loadSources();
    showStep('step-source');
  } catch (e) {
    $('connectErr').textContent = 'Bağlanamadı: ' + e.message;
  } finally {
    $('connectBtn').disabled = false;
  }
};

$('serverAddr').addEventListener('keydown', e => {
  if (e.key === 'Enter') $('connectBtn').click();
});

// ─── Step 2: Source picker ────────────────────────────────────────────────────

async function loadSources() {
  $('sourceGrid').innerHTML = '<p style="color:#9aa3b2;grid-column:1/-1">Yükleniyor…</p>';
  selectedSourceId = null;
  $('selectBtn').disabled = true;

  const sources = await window.ushare.getSources(['screen', 'window']);
  $('sourceGrid').innerHTML = '';

  sources.forEach(src => {
    const card = document.createElement('div');
    card.className = 'src-card';
    card.innerHTML = `<img src="${src.thumbnail}" alt="${src.name}"><span>${src.name}</span>`;
    card.onclick = () => {
      document.querySelectorAll('.src-card').forEach(c => c.classList.remove('selected'));
      card.classList.add('selected');
      selectedSourceId = src.id;
      $('selectBtn').disabled = false;
    };
    $('sourceGrid').appendChild(card);
  });
}

$('backBtn').onclick = () => showStep('step-connect');

$('selectBtn').onclick = () => {
  if (!selectedSourceId) return;
  showStep('step-pin');
  $('pinBoxes')[0]?.focus();
};

// ─── Step 3: PIN ─────────────────────────────────────────────────────────────

const pinBoxes = [...document.querySelectorAll('.pinbox')];
// expose for selectBtn focus
$('step-pin')._pinBoxes = pinBoxes;

pinBoxes.forEach((b, i) => {
  b.addEventListener('input', () => {
    b.value = b.value.replace(/\D/g, '').slice(-1);
    if (b.value && i < pinBoxes.length - 1) pinBoxes[i + 1].focus();
    $('shareBtn').disabled = pinValue().length < 6;
  });
  b.addEventListener('keydown', e => {
    if (e.key === 'Backspace' && !b.value && i > 0) pinBoxes[i - 1].focus();
  });
  b.addEventListener('paste', e => {
    const digits = (e.clipboardData.getData('text').match(/\d/g) ?? []).slice(0, 6);
    if (!digits.length) return;
    e.preventDefault();
    digits.forEach((d, j) => { if (pinBoxes[j]) pinBoxes[j].value = d; });
    pinBoxes[Math.min(digits.length, 5)].focus();
    $('shareBtn').disabled = pinValue().length < 6;
  });
});

const pinValue = () => pinBoxes.map(b => b.value).join('');

$('shareBtn').onclick = async () => {
  const pin = pinValue();
  if (pin.length < 6) return;
  await startSharing(pin);
};

// ─── Step 4: Sharing ─────────────────────────────────────────────────────────

async function startSharing(pin) {
  showStep('step-sharing');
  setStatus('Ekran yakalanıyor…');

  try {
    // desktopCapturer: DXGI / ScreenCaptureKit / X11+PipeWire
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        mandatory: {
          chromeMediaSource: 'desktop',
          chromeMediaSourceId: selectedSourceId,
          maxWidth: 1920,
          maxHeight: 1080,
          maxFrameRate: 60,
        },
      },
    });
  } catch (e) {
    showStep('step-pin');
    setStatus('Ekran yakalanamadı: ' + e.message);
    return;
  }

  $('sharingInfo').textContent = stream.getVideoTracks()[0]?.label ?? selectedSourceId;
  setStatus('Sunucuya bağlanılıyor…');

  const wsBase = serverBase.replace(/^https/, 'wss').replace(/^http/, 'ws');
  client = new SignalClient(`${wsBase}/ws?role=sender&name=Electron`);

  client.on('challenge', async msg => {
    setStatus('Kimlik doğrulanıyor…');
    const proof = await pinProof(pin, msg.payload.salt);
    client.send({ type: 'auth', payload: { proof } });
  });

  client.on('paired', async () => {
    setStatus('Eşleşti, medya bağlantısı kuruluyor…');
    await buildPeer();
  });

  client.on('answer', msg => pc?.setRemoteDescription(msg.payload));
  client.on('ice', msg => pc?.addIceCandidate(msg.payload).catch(() => {}));

  client.on('error', msg => {
    const errs = {
      'bad-pin': 'PIN hatalı.',
      'pin-expired': 'PIN süresi dolmuş — alıcıda yeni kod alın.',
      'room-full': 'Oda dolu (en fazla 4 kaynak).',
      'receiver-gone': 'Alıcı kapandı.',
      'rate-limited': 'Çok fazla deneme. Bir dakika bekle.',
    };
    setStatus('❌ ' + (errs[msg.reason] ?? msg.reason));
    stopSharing();
  });

  client.on('_close', () => setStatus('Bağlantı koptu, yeniden deneniyor…'));

  client.connect();
  stream.getVideoTracks()[0].onended = stopSharing;
}

async function buildPeer() {
  const iceServers = await fetchIceServers(serverBase);
  pc = new RTCPeerConnection({ iceServers });
  stream.getTracks().forEach(t => pc.addTrack(t, stream));

  pc.onicecandidate = ev =>
    ev.candidate && client.send({ type: 'ice', payload: ev.candidate });

  pc.onconnectionstatechange = () => {
    if (pc.connectionState === 'connected') setStatus('');
    if (pc.connectionState === 'failed') setStatus('Medya bağlantısı kurulamadı.');
  };

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  client.send({ type: 'offer', payload: offer });
}

function stopSharing() {
  client?.close();
  pc?.close();
  stream?.getTracks().forEach(t => t.stop());
  client = pc = stream = null;
  pinBoxes.forEach(b => { b.value = ''; });
  $('shareBtn').disabled = true;
  showStep('step-connect');
}

$('stopBtn').onclick = stopSharing;

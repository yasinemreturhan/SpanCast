// Receiver: oda açar, PIN+QR gösterir, katılan her sender için ayrı
// RTCPeerConnection kurar ve akışları CSS grid'de karo olarak yerleştirir.
import { SignalClient } from './signal.js';
import { gridFor } from './layout.js';

const $ = id => document.getElementById(id);
const status = m => { $('status').textContent = m; };

const tiles = new Map(); // senderId → { pc, el, video, statTimer }

const client = new SignalClient(
  `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws?role=receiver`,
);

client.on('pin', async msg => {
  $('pinBox').textContent = msg.pin;
  // Sertifika parmak izi QR'a gömülür → okutulan cihaz TLS pinning yapabilir.
  let fp = '';
  try { fp = (await (await fetch('/api/info')).json()).fp ?? ''; } catch {}
  const pairUrl = `ushare://pair?host=${location.hostname}&port=${location.port}&pin=${msg.pin}`
    + (fp ? `&fp=${fp}` : '');
  $('qr').src = `/api/qr?data=${encodeURIComponent(pairUrl)}`;
  $('qr').style.display = 'inline-block';
  status('Gönderen bekleniyor…');
});

client.on('joined', msg => {
  status(`${msg.name} katıldı, akış kuruluyor…`);
  addTile(msg.from, msg.name);
});

client.on('offer', async msg => {
  const t = tiles.get(msg.from);
  if (!t) return;
  await t.pc.setRemoteDescription(msg.payload);
  const answer = await t.pc.createAnswer();
  await t.pc.setLocalDescription(answer);
  client.send({ type: 'answer', to: msg.from, payload: answer });
});

client.on('ice', msg => {
  tiles.get(msg.from)?.pc.addIceCandidate(msg.payload).catch(() => {});
});

client.on('left', msg => removeTile(msg.from));
client.on('_close', () => status('Bağlantı koptu, yeniden deneniyor…'));

function addTile(id, name) {
  const pc = new RTCPeerConnection({ iceServers: [] }); // LAN: STUN gereksiz

  const el = document.createElement('div');
  el.className = 'tile';
  el.innerHTML = `
    <video autoplay playsinline></video>
    <div class="label">${name}</div>
    <div class="stat"></div>`;
  $('grid').appendChild(el);
  const video = el.querySelector('video');

  pc.ontrack = ev => { video.srcObject = ev.streams[0]; reflow(); };
  pc.onicecandidate = ev =>
    ev.candidate && client.send({ type: 'ice', to: id, payload: ev.candidate });

  // Karo başına canlı istatistik (çözünürlük/fps/bitrate).
  let lastBytes = 0, lastTs = 0;
  const statTimer = setInterval(async () => {
    if (pc.connectionState !== 'connected') return;
    const stats = await pc.getStats();
    stats.forEach(r => {
      if (r.type === 'inbound-rtp' && r.kind === 'video') {
        const kbps = lastTs ? Math.round(8 * (r.bytesReceived - lastBytes) / (r.timestamp - lastTs)) : 0;
        lastBytes = r.bytesReceived; lastTs = r.timestamp;
        el.querySelector('.stat').textContent =
          `${r.frameWidth ?? '?'}×${r.frameHeight ?? '?'} @ ${r.framesPerSecond ?? '-'}fps · ${kbps} kbps`;
      }
    });
  }, 1000);

  tiles.set(id, { pc, el, video, statTimer });
  reflow();
}

function removeTile(id) {
  const t = tiles.get(id);
  if (!t) return;
  clearInterval(t.statTimer);
  t.pc.close();
  t.el.remove();
  tiles.delete(id);
  reflow();
}

// Grid'i kaynak sayısına göre yeniden düzenle; 0 kaynakta eşleşme ekranı büyür.
function reflow() {
  const n = tiles.size;
  const { rows, cols } = gridFor(n);
  const grid = $('grid');
  grid.style.gridTemplateRows = `repeat(${rows}, 1fr)`;
  grid.style.gridTemplateColumns = `repeat(${cols}, 1fr)`;
  document.body.classList.toggle('streaming', n > 0);
  if (n > 0) status('');
}

client.connect();

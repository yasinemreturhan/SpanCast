// SignalClient: sunucuyla WebSocket signaling — otomatik yeniden bağlanma
// (üstel backoff), tip bazlı dinleyiciler ve bağlantı yokken send kuyruğu.
// WebSocket ve setTimeout enjekte edilebilir → node testinde sahteleriyle çalışır.

const BASE_MS = 500;
const MAX_MS = 8000;

/** attempt. yeniden bağlanma denemesinin bekleme süresi (ms). */
export function backoffMs(attempt) {
  return Math.min(BASE_MS * 2 ** attempt, MAX_MS);
}

export class SignalClient {
  constructor(url, opts = {}) {
    this.url = url;
    this.WS = opts.WebSocketImpl ?? globalThis.WebSocket;
    this.setTimeout = opts.setTimeoutImpl ?? ((fn, ms) => setTimeout(fn, ms));
    this.listeners = new Map(); // type → [cb]
    this.queue = [];
    this.attempt = 0;
    this.closed = false;
    this.ws = null;
  }

  /** type mesajları için dinleyici ekler. '*' tüm mesajları alır. */
  on(type, cb) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(cb);
    return this;
  }

  connect() {
    if (this.closed) return;
    const ws = new this.WS(this.url);
    this.ws = ws;

    ws.onopen = () => {
      this.attempt = 0;
      this.emit('_open', {});
      const pending = this.queue.splice(0);
      for (const m of pending) ws.send(JSON.stringify(m));
    };

    ws.onmessage = ev => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      this.emit(msg.type, msg);
      this.emit('*', msg);
    };

    ws.onclose = () => {
      if (this.closed) return;
      this.emit('_close', {});
      const wait = backoffMs(this.attempt++);
      this.setTimeout(() => this.connect(), wait);
    };
  }

  /** Mesaj gönderir; bağlantı yoksa kuyruğa alır (open'da otomatik akar). */
  send(obj) {
    if (this.ws && this.ws.readyState === 1) {
      this.ws.send(JSON.stringify(obj));
    } else {
      this.queue.push(obj);
    }
  }

  /** Kalıcı kapatma — yeniden bağlanma yapılmaz. */
  close() {
    this.closed = true;
    this.ws?.close();
  }

  emit(type, msg) {
    for (const cb of this.listeners.get(type) ?? []) cb(msg);
  }
}

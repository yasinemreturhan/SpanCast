# UniversalShare

Ekosistem bağımsız, evrensel ekran paylaşımı ve ekran genişletme platformu.
AirPlay/Miracast/Chromecast duvarları olmadan: **her cihazdan her cihaza.**

| Doküman | İçerik |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Ürün gereksinimleri: kullanım senaryoları, gereksinimler, yol haritası, riskler |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Teknik mimari: capture/encode/transport katmanları, sanal ekran sürücüleri, stack kararları |
| [server/](server/) | **Faz 1 MVP sunucusu:** multi-share odalar, PIN/QR eşleşme, mDNS+broadcast keşif, gömülü web istemciler |
| [poc/](poc/) | Faz 0 konsept kanıtı (tarihsel; güncel kod `server/`) |

## MVP'yi çalıştırma

```bash
make build          # → bin/ushare
./bin/ushare        # varsayılan port 8788
```

- Sunucu **varsayılan olarak TLS ile** çalışır (ilk açılışta cihaz başına kalıcı
  self-signed sertifika üretilir; tarayıcıda bir kez "yine de devam et" demeniz yeterli —
  böylece `getDisplayMedia` her cihazda çalışır). Geliştirme için `-no-tls` bayrağı var.
- Alıcı cihazda `https://<sunucu-ip>:8788/receiver.html` → 6 haneli PIN + QR görünür
  ("↻ Yeni kod" ile PIN yenilenebilir)
- Gönderen cihaz(lar)da `https://<sunucu-ip>:8788/sender.html` → PIN'i gir, ekranı seç
- Aynı PIN ile **4 kaynağa kadar** katılım: alıcı otomatik grid'e böler (1→tam, 2→yan yana, 3-4→2×2)
- Signaling koparsa istemciler üstel backoff ile kendini toparlar

**Güvenlik (MVP):**
- PIN ağdan hiç geçmez: sunucu rastgele salt gönderir, istemci
  `HMAC-SHA256(PIN, salt)` proof'uyla doğrulanır (testle sözleşmeli: `TestPinNeverOnWire`)
- IP başına dakikada 10 hatalı deneme sınırı (kaba kuvvet koruması)
- Sertifika SHA-256 parmak izi `/api/info` ve eşleşme QR'ında (`fp=`) — istemci pinning'e hazır
- Tam PAKE (SPAKE2) Rust çekirdek fazında gelecek

**Testler:** `make test` (Go: birimler + gerçek WebSocket uçtan uca akış),
`make webtest` (node: grid layout, reconnect, PIN proof vektörleri).

## Özet stack kararları

- **Çekirdek:** Rust (capture, encode, transport, discovery) — tüm platformlara tek core
- **Taşıma:** WebRTC (DTLS-SRTP, ICE) — LAN'da P2P, tarayıcı alıcı desteği bedava
- **UI:** Flutter (Win/mac/Linux/iOS/Android/Android TV) + kurulumsuz web receiver
- **Extend:** Windows IddCx (C++), macOS CGVirtualDisplay (Swift) sanal ekran sürücüleri
- **Keşif/Eşleşme:** mDNS/DNS-SD + 6 haneli PIN (SPAKE2) / QR

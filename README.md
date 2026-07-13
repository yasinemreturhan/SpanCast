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

- Alıcı cihazda `http://<sunucu-ip>:8788/receiver.html` → 6 haneli PIN + QR görünür
- Gönderen cihaz(lar)da `http://<sunucu-ip>:8788/sender.html` → PIN'i gir, ekranı seç
- Aynı PIN ile **4 kaynağa kadar** katılım: alıcı otomatik grid'e böler (1→tam, 2→yan yana, 3-4→2×2)
- Signaling koparsa istemciler üstel backoff ile kendini toparlar
- Not: `getDisplayMedia` güvenli bağlam ister; localhost dışında Chrome bayrağı
  (`#unsafely-treat-insecure-origin-as-secure`) veya TLS gerekir.

**Testler:** `make test` (23 Go testi: oda/hub birimleri + gerçek WebSocket uçtan uca akış),
`make webtest` (12 node testi: grid layout + reconnect'li SignalClient).

## Özet stack kararları

- **Çekirdek:** Rust (capture, encode, transport, discovery) — tüm platformlara tek core
- **Taşıma:** WebRTC (DTLS-SRTP, ICE) — LAN'da P2P, tarayıcı alıcı desteği bedava
- **UI:** Flutter (Win/mac/Linux/iOS/Android/Android TV) + kurulumsuz web receiver
- **Extend:** Windows IddCx (C++), macOS CGVirtualDisplay (Swift) sanal ekran sürücüleri
- **Keşif/Eşleşme:** mDNS/DNS-SD + 6 haneli PIN (SPAKE2) / QR

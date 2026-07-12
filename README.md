# UniversalShare

Ekosistem bağımsız, evrensel ekran paylaşımı ve ekran genişletme platformu.
AirPlay/Miracast/Chromecast duvarları olmadan: **her cihazdan her cihaza.**

| Doküman | İçerik |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Ürün gereksinimleri: kullanım senaryoları, gereksinimler, yol haritası, riskler |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Teknik mimari: capture/encode/transport katmanları, sanal ekran sürücüleri, stack kararları |
| [poc/](poc/) | Faz 0 konsept kanıtı: mDNS keşif + PIN eşleşme + WebRTC mirroring |

## Özet stack kararları

- **Çekirdek:** Rust (capture, encode, transport, discovery) — tüm platformlara tek core
- **Taşıma:** WebRTC (DTLS-SRTP, ICE) — LAN'da P2P, tarayıcı alıcı desteği bedava
- **UI:** Flutter (Win/mac/Linux/iOS/Android/Android TV) + kurulumsuz web receiver
- **Extend:** Windows IddCx (C++), macOS CGVirtualDisplay (Swift) sanal ekran sürücüleri
- **Keşif/Eşleşme:** mDNS/DNS-SD + 6 haneli PIN (SPAKE2) / QR

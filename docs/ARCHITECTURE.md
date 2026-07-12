# UniversalShare — Teknik Mimari

**Sürüm:** 0.1 · **Tarih:** 2026-07-13

---

## 1. Genel Bakış

```
┌─────────────── KAYNAK (Sender) ───────────────┐      ┌────────────── HEDEF (Receiver) ─────────────┐
│  UI Kabuğu (Flutter)                           │      │  UI Kabuğu (Flutter / Web)                   │
│  ────────────────────────────────────────────  │      │  ──────────────────────────────────────────  │
│  Core Engine (Rust, FFI)                       │      │  Core Engine (Rust) veya Tarayıcı WebRTC     │
│   ├─ Capture  (OS API adaptörleri)             │      │   ├─ Jitter buffer + HW decode               │
│   ├─ Encode   (HW encoder: NVENC/QSV/VT/MC)    │◄────►│   ├─ Renderer / Compositor (multi-share)     │
│   ├─ Transport (WebRTC: DTLS-SRTP, ICE)        │ P2P  │   └─ Input backchannel (touch→sender)        │
│   ├─ Discovery (mDNS/DNS-SD + UDP broadcast)   │      │                                              │
│   └─ Pairing  (PIN/QR, SPAKE2)                 │      │  Sanal Ekran Sürücüsü YOK (yalnız sender'da) │
│  Sanal Ekran Sürücüsü (extend modu, OS-özel)   │      │                                              │
└────────────────────────────────────────────────┘      └──────────────────────────────────────────────┘
                     │                                                     │
                     └────────── Signaling (LAN: doğrudan WS; WAN: hafif bulut signaling + TURN) ───────┘
```

**Temel karar: protokol bağımsızlık = kendi taşıma katmanımız WebRTC üstünde.**
AirPlay/Miracast/Cast birer *uygulama protokolü*; biz IETF standartları
(ICE, DTLS-SRTP, RTP) üzerine kendi hafif kontrol protokolümüzü koyuyoruz.
Böylece her platformda aynı stack, tarayıcı dahil.

## 2. Katmanlar

### 2.1 Discovery (Keşif)
- **Birincil:** mDNS/DNS-SD — servis tipi `_ushare._tcp.local`
  - TXT kayıtları: `ver`, `name`, `caps=mirror,extend,multi`, `port`, `fp` (sertifika parmak izi)
- **Fallback:** UDP broadcast (255.255.255.255:5353 engelli kurumsal ağlar için özel port 41337)
- **Manuel:** PIN ile bağlanma her zaman mümkün (keşif tamamen kapalıysa bile)

### 2.2 Pairing (Eşleşme) ve Güvenlik
1. Receiver 6 haneli PIN üretir (30 sn TTL) ve ekranda + QR olarak gösterir.
   QR içeriği: `ushare://pair?host=…&port=…&pin=…&fp=…`
2. Sender PIN'i girer → **SPAKE2** (password-authenticated key exchange) ile PIN'den
   MITM'e dayanıklı ortak anahtar türetilir. PIN ağdan asla düz geçmez.
3. Türetilen anahtar, DTLS sertifika parmak izlerini karşılıklı imzalar → WebRTC
   oturumu uçtan uca doğrulanmış olur.
4. "Bu cihaza güven" → kalıcı anahtar çifti kaydedilir, sonraki bağlantılar tek tık.

### 2.3 Capture (Ekran Yakalama)
| Platform | API | Not |
|---|---|---|
| Windows | DXGI Desktop Duplication (+ Windows.Graphics.Capture) | GPU'da sıfır kopya, dirty-rect desteği |
| macOS | ScreenCaptureKit | 12.3+, donanım yolunda IOSurface |
| Linux | PipeWire + xdg-desktop-portal | Wayland ve X11'i tek API'yle kapsar |
| Android | MediaProjection → MediaCodec | Foreground service zorunlu |
| iOS | ReplayKit Broadcast Upload Extension | Sistem geneli yakalama yalnız bu yolla |

Yakalanan kare **GPU belleğinde kalır** ve doğrudan donanım encoder'a verilir
(zero-copy). CPU'ya inen yol yalnız fallback.

### 2.4 Encode / Decode
- **Codec önceliği:** AV1 (varsa) → HEVC → H.264 (evrensel fallback, web receiver için zorunlu)
- **Donanım:** NVENC, Intel QSV, AMD AMF (Win/Linux); VideoToolbox (Apple); MediaCodec (Android)
- **Ayar:** düşük gecikme profili — B-frame yok, intra-refresh, 1 kare lookahead,
  hedef bitrate ağ geri bildirimiyle (TWCC/REMB) saniyede güncellenir
- Kütüphane: FFmpeg (libavcodec) sarmalayıcı — tek API, tüm encoder'lar; Rust tarafında `ffmpeg-next`

### 2.5 Transport
- **WebRTC** (Rust: `webrtc-rs`; tarayıcıda native):
  - LAN'da ICE host candidate'ları ile doğrudan P2P — sunucusuz
  - WAN'da STUN ile NAT geçişi, olmadı TURN relay
  - Video/ses: SRTP; kontrol + input backchannel: SCTP DataChannel (sıralı, güvenilir)
- **Neden ham UDP/QUIC değil?** Tarayıcı alıcı (Tizen/misafir) ancak WebRTC ile mümkün;
  NAT geçişi, şifreleme, tıkanıklık kontrolü hazır. QUIC (MoQ) v2'de değerlendirilir.

### 2.6 Sanal Ekran Sürücüsü (Extend modu)
| Platform | Teknoloji | Dil |
|---|---|---|
| Windows | **IddCx** (Indirect Display Driver, UMDF) | C++ (imzalama: attestation/WHQL) |
| macOS | CoreGraphics Virtual Display (CGVirtualDisplay) | Swift/ObjC — Duet/Luna'nın kullandığı yol |
| Linux | Wayland headless output / X11 xrandr sanal çıkış | C/Rust |

Sürücü, OS'e gerçek bir monitör olarak EDID sunar (çözünürlük listesi hedef cihazdan
alınır). Sürücünün frame buffer'ı doğrudan encoder'a bağlanır → capture katmanı bypass
edilir, gecikme düşer.

### 2.7 Input Backchannel (Extend + uzaktan kontrol)
- Receiver'daki dokunma/kalem/fare olayları DataChannel üzerinden normalize edilmiş
  koordinatlarla sender'a gider; sender OS'ine enjekte edilir
  (Win: `SendInput`, macOS: CGEvent, Linux: uinput).

### 2.8 Multi-Share Kompozisyonu
- Kompozisyon **alıcıda** yapılır: her kaynak ayrı WebRTC oturumu, GPU'da grid/PiP yerleşimi.
- Alıcı zayıfsa (TV), sender'lardan düşük çözünürlük istenir (simulcast katmanları).

## 3. UI Kabuğu Teknoloji Karşılaştırması

| Kriter | **Flutter** (öneri) | Electron | Tauri |
|---|---|---|---|
| Platform kapsamı | Win/mac/Linux/iOS/Android/**Android TV**/embedded (+Tizen topluluk) | Yalnız masaüstü | Masaüstü + mobil (v2, genç) |
| Bellek/başlangıç | ~80 MB, hızlı | 200–400 MB (Chromium) | ~50 MB, hızlı |
| Rust core ile entegrasyon | `flutter_rust_bridge` (olgun FFI) | N-API (JS köprüsü, kopya maliyeti) | Doğal (Rust host) |
| Video render | Texture API ile sıfır kopya GPU yolu | `<video>` etiketi (yeterli ama ağır) | Webview codec desteği platforma göre değişken (risk) |
| TV / D-pad UI | Var (focus sistemi) | Yok | Yok |

**Karar:** UI = **Flutter**, çekirdek = **Rust** (tek core, FFI ile tüm platformlara).
Electron yalnız masaüstü olduğundan elenir; Tauri'nin webview tabanlı video render'ı
düşük gecikme hedefiyle çelişir. **Web receiver** (kurulumsuz alıcı) ayrıca saf
TypeScript + tarayıcı WebRTC olarak yaşar — Tizen/webOS/misafir cihazları kurulumsuz kapsar.

## 4. Depo Yapısı (hedef)

```
core/            Rust: capture, encode, transport, discovery, pairing
  ├─ capture/    (platform adaptörleri, feature-gated)
  ├─ media/      (encoder/decoder, FFmpeg sarmalayıcı)
  ├─ net/        (webrtc-rs, signaling istemcisi, mDNS)
  └─ ffi/        (flutter_rust_bridge tanımları)
drivers/
  ├─ windows-idd/   C++ IddCx sürücüsü
  └─ macos-vdisplay/ Swift sanal ekran
apps/
  ├─ mobile_desktop/  Flutter (tek kod tabanı: Win/mac/Linux/iOS/Android/ATV)
  └─ web_receiver/    TypeScript, kurulumsuz alıcı
signaling/       Go/Rust hafif WS sunucusu (yalnız WAN modu; LAN'da gerek yok)
poc/             Faz-0 kanıt kodu (bu repoda mevcut)
```

## 5. Gecikme Bütçesi (LAN, 1080p60 hedef ≤ 50 ms)

| Aşama | Bütçe |
|---|---|
| Yakalama (vsync bekleme dahil) | ~8 ms |
| Encode (HW, low-latency) | ~5 ms |
| Paketleme + ağ (LAN) | ~3 ms |
| Jitter buffer (adaptif, min) | ~10 ms |
| Decode (HW) | ~4 ms |
| Render (vsync) | ~8 ms |
| **Toplam** | **~38 ms** (pay: 12 ms) |

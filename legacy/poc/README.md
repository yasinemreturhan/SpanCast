# UniversalShare — Faz 0 PoC

Konsept kanıtı: **cihaz keşfi (mDNS)** + **PIN eşleşmesi** + **ekran yakalayıp
WebRTC ile stream etme**. Tek Go binary'si signaling ve keşfi yapar; sender ve
receiver herhangi bir tarayıcıda çalışır — yani ağdaki *her* cihaz (telefon,
TV tarayıcısı, başka bir bilgisayar) kurulumsuz alıcı olabilir.

## Çalıştırma

```bash
cd poc
go mod tidy
go run .
```

1. **Alıcı cihazda** tarayıcıdan `http://<sunucu-ip>:8788/receiver.html` aç → 6 haneli PIN görünür.
2. **Gönderen cihazda** `http://<sunucu-ip>:8788/sender.html` aç → PIN'i gir → paylaşılacak ekranı seç.
3. Görüntü, WebRTC P2P ile (LAN'da doğrudan, sunucu üzerinden geçmeden) alıcıya akar.
   Sağ üstte çözünürlük/fps/bitrate istatistikleri görünür.

Ana sayfa (`/`) mDNS ile ağda keşfedilen diğer UniversalShare örneklerini listeler —
aynı binary'yi iki makinede çalıştırarak otomatik keşfi görebilirsin.

## Bu PoC neyi kanıtlıyor / neyi kanıtlamıyor?

| Kanıtlıyor | Üretimde yerini alacak olan |
|---|---|
| mDNS ile sıfır-konfigürasyon keşif | Aynı mekanizma, Rust core içinde |
| PIN ile eşleşme + signaling akışı | SPAKE2 ile kriptografik PIN doğrulama |
| Düşük gecikmeli P2P video (WebRTC) | Aynı WebRTC stack'i, `webrtc-rs` + HW encoder |
| Tarayıcı = evrensel alıcı | Kalıcı web receiver ürün bileşeni |
| — (yakalama tarayıcıda) | DXGI / ScreenCaptureKit / PipeWire yerel yakalama |
| — (extend yok) | IddCx / CGVirtualDisplay sanal ekran sürücüleri |

Notlar: `getUserMedia`/`getDisplayMedia` güvenli bağlam ister; `localhost` dışında
HTTP ile açarken Chrome'da `chrome://flags/#unsafely-treat-insecure-origin-as-secure`
bayrağına sunucu adresini eklemen ya da self-signed TLS kullanman gerekebilir.

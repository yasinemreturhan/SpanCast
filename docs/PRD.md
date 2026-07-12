# UniversalShare — Ürün Gereksinim Dokümanı (PRD)

**Sürüm:** 0.1 (Taslak) · **Tarih:** 2026-07-13 · **Durum:** İnceleme bekliyor

---

## 1. Vizyon

Ekosistem duvarlarını (AirPlay → Apple, Miracast → Windows/Android, Chromecast → Google)
ortadan kaldıran, **her cihazın her cihaza** ekran yansıtabildiği ve ekran
genişletebildiği, protokol bağımsız, düşük gecikmeli evrensel bir ekran paylaşım
platformu.

> "Kablosuz HDMI kablosu gibi: hangi marka olursa olsun tak, çalışsın."

## 2. Problem

| Mevcut Durum | Sonuç |
|---|---|
| AirPlay yalnız Apple alıcılarına yansıtır | iPhone → Windows TV yok |
| Miracast, macOS/iOS'ta yok | MacBook → Miracast TV yok |
| Chromecast alıcı tarafında Google Cast zorunlu | Cihazlar arası tam matris kurulamaz |
| Ekran genişletme (2. monitör) çözümleri tek yönlü ve tek platform (Sidecar: sadece Mac+iPad) | MacBook'u Windows'a ikinci ekran yapmak imkânsız |
| Üçüncü parti araçlar (Duet, Spacedesk) kapalı, sınırlı platform matrisi | Parçalı deneyim |

## 3. Hedef Kullanıcılar (Persona)

1. **Hibrit Çalışan (Elif, 32):** MacBook + Windows masaüstü + iPad. Hepsini tek masada
   tek ekran düzenine bağlamak istiyor.
2. **Eğitmen (Murat, 45):** Sınıftaki herhangi bir TV/projektöre, öğrenci cihazları dahil
   herhangi bir cihazdan hızla yansıtma.
3. **Toplantı Odası (Kurumsal):** Odaya giren herkes (misafir dahil) 6 haneli kod/QR ile
   5 saniyede ekranını paylaşır; IT departmanı dongle yönetmez.
4. **Oyuncu/Yaratıcı (Deniz, 24):** Düşük gecikmeli mirroring (oyun, çizim tableti senaryosu).

## 4. Kullanım Senaryoları (Use Cases)

### UC-1: Yansıtma (Mirroring)
- **Aktörler:** Kaynak cihaz (sender), hedef cihaz (receiver)
- **Akış:** Kaynak "Yansıt" → keşfedilen cihaz listesi → hedef seçilir → PIN/QR onayı →
  yansıtma başlar (< 3 sn kurulum, < 50 ms uçtan uca gecikme LAN'da).
- **Platform matrisi:** Windows, macOS, Linux, iOS, Android → Windows, macOS, Linux,
  Android TV, Tizen (web receiver ile herhangi bir tarayıcı).
- **Kabul kriteri:** 1080p60'ta LAN üzerinde ≤ 50 ms gecikme; ses + video senkron (< 40 ms drift).

### UC-2: Ekran Genişletme (Extend Display)
- Hedef cihaz, kaynak cihazın işletim sistemine **gerçek bir ikinci monitör** olarak görünür
  (sanal ekran sürücüsü). Pencere taşıma, farklı çözünürlük/ölçek, ayrı duvar kâğıdı desteklenir.
- Örnekler: iPad → Windows yan ekranı, MacBook → Windows'un 2. ekranı, Windows tablet → Mac yan ekranı.
- **Ek gereksinim:** Hedef dokunmatikse dokunma/kalem girdisi kaynağa geri iletilir (input backchannel).
- **Kabul kriteri:** OS ekran ayarlarında gerçek monitör olarak listelenme; 1080p60 ≤ 60 ms.

### UC-3: Çoklu Paylaşım (Multi-Share)
- Tek alıcı (TV/büyük monitör) aynı anda N kaynağı (MVP: 4) bölünmüş düzende (grid, PiP,
  odak+şerit) gösterir. Moderatör düzeni değiştirebilir, bir kaynağı tam ekrana alabilir.
- **Kabul kriteri:** 4×720p30 eşzamanlı akış, alıcıda kompozisyon; kaynak ekleme/çıkarma
  akışı kesintiye uğratmaz.

### İkincil senaryolar (v1 sonrası)
- UC-4: İnternet üzerinden uzak paylaşım (TURN relay ile)
- UC-5: Yalnız uygulama penceresi paylaşımı
- UC-6: Kayıt ve anlık görüntü

## 5. Fonksiyonel Gereksinimler

| ID | Gereksinim | Öncelik |
|---|---|---|
| F-1 | mDNS/DNS-SD ile otomatik cihaz keşfi (`_ushare._tcp.local`) | P0 |
| F-2 | 6 haneli PIN ve QR kod ile eşleşme; güvenilir cihaz hatırlama | P0 |
| F-3 | Ekran yakalama: DXGI (Win), ScreenCaptureKit (macOS), PipeWire (Linux), MediaProjection (Android), ReplayKit (iOS) | P0 |
| F-4 | H.264/HEVC/AV1 donanım hızlandırmalı kodlama, dinamik bitrate (ABR) | P0 |
| F-5 | WebRTC tabanlı P2P taşıma; LAN'da doğrudan, gerekirse STUN/TURN | P0 |
| F-6 | Web alıcı: kurulumsuz, tarayıcıda çalışan receiver (Tizen/webOS/misafir cihaz) | P1 |
| F-7 | Sanal ekran sürücüsü: IddCx (Win), Virtual Display (macOS), DRM lease/xrandr (Linux) | P1 |
| F-8 | Extend modunda geri kanal: dokunma, kalem, fare, klavye | P1 |
| F-9 | Multi-share kompozisyon (grid/PiP/odak) | P1 |
| F-10 | Ses yakalama ve senkron aktarım (WASAPI loopback, CoreAudio tap, PulseAudio monitor) | P1 |
| F-11 | Uçtan uca şifreleme (DTLS-SRTP) + kısa doğrulama dizisi (SAS) | P0 |
| F-12 | Kurumsal mod: MDM dağıtımı, sabit oda kodları, keşif kısıtlama | P2 |

## 6. Fonksiyonel Olmayan Gereksinimler

- **Gecikme:** LAN mirroring ≤ 50 ms, extend ≤ 60 ms, internet ≤ 150 ms (hedef p95)
- **Kalite:** 4K30 / 1080p60'a kadar; ağ daraldığında çözünürlük değil önce bitrate düşer
- **CPU bütçesi:** Kaynakta ≤ %15 tek çekirdek (donanım encoder ile)
- **Güvenlik:** Varsayılan şifreli; keşif yanıtları kişisel veri sızdırmaz; PIN 30 sn'de yenilenir
- **Erişilebilirlik:** TV arayüzü D-pad ile tam kullanılabilir; WCAG AA kontrast
- **Çevrimdışılık:** LAN modu hiçbir bulut servisine ihtiyaç duymaz

## 7. Başarı Metrikleri

- İlk bağlantıya kadar geçen süre (TTFC) medyanı < 10 sn (ilk kurulum dahil < 60 sn)
- Bağlantı başarı oranı ≥ %97 (aynı LAN)
- Haftalık aktif cihaz çifti; oturum başına ortalama süre
- NPS ≥ 50; mağaza puanı ≥ 4,5

## 8. Kapsam Dışı (v1)

- DRM'li içerik yakalama (Netflix vb. korumalı yüzeyler)
- 8K, HDR passthrough
- Bulut tabanlı toplantı/konferans (Zoom alternatifi değiliz)

## 9. Yol Haritası

| Faz | Süre | Çıktı |
|---|---|---|
| **0 — PoC** | 4 hafta | Masaüstü → tarayıcı mirroring (bu repodaki `poc/`), keşif + PIN |
| **1 — MVP** | 3 ay | Win/macOS sender+receiver, Android receiver, mirroring + multi-share (2 kaynak) |
| **2 — Extend** | +3 ay | Sanal ekran sürücüleri (Win IddCx, macOS), input backchannel, iPad/Android sender |
| **3 — TV & Kurumsal** | +3 ay | Android TV/Tizen alıcı, 4'lü multi-share, MDM, TURN relay |

## 10. Riskler

| Risk | Etki | Azaltma |
|---|---|---|
| iOS arka plan yakalama kısıtları (ReplayKit) | iOS sender deneyimi sınırlı | Broadcast Upload Extension; beklentiyi UX'te yönet |
| macOS sanal ekran API'lerinin yarı-resmi olması | Extend kırılganlığı | DriverKit + her OS sürümünde regresyon testi |
| Sürücü imzalama (Win WHQL, macOS notarization) | Dağıtım gecikmesi | Erken sertifikasyon süreci, EV sertifika |
| TV tarafında codec çeşitliliği | Alıcı uyumsuzluğu | Web receiver fallback (WebRTC + H.264 baseline) |
| Kurumsal ağlarda mDNS engelli | Keşif başarısız | UDP broadcast + manuel PIN fallback |

# RESUME

_Bu dosya `dev` dalının kökünde, bir supermux oturumu tarafından otomatik olarak
oluşturuldu (2026-07-25). Amaç: bir sonraki oturumun (insan ya da ajan) kaldığımız
yeri hızlıca anlaması._

## Şu an nerede kaldık / Sıradaki adım

`main` dalı GitHub'a (origin) güncel: iki yeni özellik push edildi:

1. **STUN/TURN WAN desteği + Electron native sender + iOS sender (ReplayKit)**
   (`c01ecbb`) — paylaşımın artık aynı LAN dışından da (WAN) çalışabilmesi için
   STUN/TURN desteği; masaüstü için native Electron gönderen; iOS için
   ReplayKit tabanlı ekran yakalama gönderen.
2. **Samsung Tizen alıcısı + Trusted Device (TOFU)** (`8847af9`) — Samsung Tizen
   TV'ler için alıcı uygulaması ve "trust on first use" modeliyle bir kez PIN
   girilen cihazın PIN'siz yeniden bağlanabilmesi.

Bunlar bu oturumda `origin/main`'e temiz bir fast-forward ile push edildi
(`de6eb18..8847af9`).

**Yarım kalan / dikkat edilmesi gereken durum — GitHub Actions workflow'ları:**

Oturum başladığında repo kökünde commit'lenmemiş bir `.github/workflows/`
dizini bulundu (`ci.yml` + `release.yml`). İçerikleri incelendi: geçerli YAML,
repodaki gerçek yollara (`server/go.sum`, `apps/android`, `apps/webos`,
`Makefile`'daki `dist` hedefi) doğru şekilde referans veriyor, yarım kalmış bir
iş izlenimi yok. Bu yüzden **`main` dalında commit'lendi** (`b9b6ea5`,
"ci: GitHub Actions CI ve release workflow'ları").

Ancak bu commit **origin'e push edilemedi**:

```
! [remote rejected] main -> main (refusing to allow an OAuth App to create or
  update workflow `.github/workflows/ci.yml` without `workflow` scope)
```

Sebep: `gh` CLI'de aktif hesap olan `yasinemreturhan` için kayıtlı token'ın
scope'ları `gist, read:org, repo` — GitHub, `.github/workflows/` altında
dosya oluşturan/değiştiren push'lar için ayrıca `workflow` scope'u istiyor
(bu OAuth App kaynaklı, repo yetkisiyle ilgisi yok). Not: `gh`'de kayıtlı
ikinci bir hesap (`asyapasifikyazilim`, aktif değil) `workflow` scope'una
sahip görünüyor ama farklı bir GitHub kimliği olduğu ve aktif hesabı
değiştirmek bu dizini kullanan diğer oturumları/repoları etkileyebileceği
için bu oturum aktif hesabı değiştirmedi.

**Şu an durum:**
- `origin/main` ve `origin/dev` → `8847af9` (workflow commit'i içermiyor)
- Yerel `main` → `b9b6ea5` (workflow commit'ini içeriyor, push edilmedi)
- Yerel/uzak `dev` → bilerek `8847af9`'dan dallandırıldı, yani bu blokajı
  miras almıyor

**Sıradaki adım:** Birisi `workflow` scope'unu aktif `gh` hesabına eklemeli
(`gh auth refresh -h github.com -s workflow` — tarayıcıda cihaz kodu onayı
gerektirir, bu yüzden otomatik yapılamadı) veya `workflow` scope'lu bir PAT
kullanmalı. Sonra:
- `git checkout main && git push origin main` ile `b9b6ea5`'i `origin/main`'e
  fast-forward etmek yeterli, **veya**
- `b9b6ea5`'i `dev` üzerine cherry-pick edip oradan push etmek.

Ayrıca dikkat: `refs/original/refs/heads/main` diye bir yedek ref var — bu,
geçmişte bir `git filter-branch`/`filter-repo` tipi history rewrite
yapıldığının izi. O eski geçmişte (`2d72a8b`, `5c86d61`, `d0ee3e2`) aynı
`.github/workflows/` dosyaları zaten mevcuttu; günümüz `main` geçmişinde
(`bbfd3e8` ve sonrası) bu dosyalar temizlenmiş. Bu oturumun bulduğu
commit'lenmemiş `ci.yml`/`release.yml` muhtemelen o eski içeriğin bilinçli bir
şekilde geri getirilmiş hali — yani muhtemelen bir önceki oturumun (aşağıya
bakın) kasıtlı işiydi, yarım kalmış rastgele bir dosya değil.

İçerik olarak README'de belirtilen ve henüz yapılmamış bir sonraki büyük adım:
**tam PAKE (SPAKE2)** — şu an PIN doğrulaması HMAC-SHA256 proof ile yapılıyor,
tam SPAKE2 "Rust çekirdek fazına" bırakılmış (bkz. README "Güvenlik (MVP)").
Rust çekirdek / Flutter UI / native sanal ekran sürücüleri (Windows IddCx,
macOS CGVirtualDisplay) de README'de tarif edilen ama henüz koda dökülmemiş
uzun vadeli mimari hedefler.

## Proje özeti

**DoScreen / UniversalShare** — ekosistem bağımsız, evrensel ekran paylaşımı
ve ekran genişletme platformu. Hedef: AirPlay/Miracast/Chromecast gibi
kapalı ekosistem duvarları olmadan "her cihazdan her cihaza" ekran
paylaşabilmek.

- **Şu anki (Faz 1 MVP) yığın:** Go sunucu (`server/`) + gömülü web
  istemcileri (`sender.html` / `receiver.html`). Sunucu varsayılan olarak
  TLS ile çalışır (cihaz başına kalıcı self-signed sertifika). Eşleşme:
  6 haneli PIN + QR; PIN ağdan hiç geçmiyor (HMAC-SHA256(PIN, salt) proof).
  Keşif: mDNS + UDP broadcast fallback. Sinyalleşme: WebSocket. Taşıma:
  WebRTC (artık STUN/TURN ile WAN'da da). Aynı PIN ile 4 kaynağa kadar
  multi-share, alıcı otomatik grid'e bölüyor (1/2/3-4 kaynak düzenleri).
- **Alıcı/gönderen uygulamaları (`apps/`):** Android & Android TV (Kotlin,
  mDNS keşifli), webOS/LG TV (`.ipk` paketleniyor), Samsung Tizen
  (+ Trusted Device TOFU ile PIN'siz yeniden bağlanma), Electron (native
  masaüstü gönderen), iOS (ReplayKit tabanlı gönderen).
- **Uzun vadeli mimari hedefi (README'ye göre, henüz kodda değil):** Rust
  çekirdek (capture/encode/transport/discovery, tüm platformlarda ortak),
  WebRTC (DTLS-SRTP/ICE) taşıma, Flutter UI (Win/mac/Linux/iOS/Android/
  Android TV), Windows için IddCx (C++) ve macOS için CGVirtualDisplay
  (Swift) sanal ekran sürücüleriyle "ekran genişletme", mDNS/DNS-SD keşif +
  PIN(SPAKE2)/QR eşleşme.
- **Dizin haritası:** `server/` = güncel Faz 1 Go sunucusu + testler;
  `server/web/js/` = gömülü web istemci kodu (node --test ile test
  ediliyor); `poc/` = Faz 0 tarihsel kavram kanıtı (güncel kod değil);
  `docs/PRD.md`, `docs/ARCHITECTURE.md` = ürün/mimari dokümanları;
  `apps/{android,electron,ios,tizen,webos}` = platform istemcileri;
  `Makefile` = build/test/vet/dist hedefleri (5 platform cross-compile).
- **Test:** `make test` (Go birim + gerçek WebSocket uçtan uca), `make
  webtest` (node: grid layout, reconnect, PIN proof vektörleri).

## Bilinen paralel session

**Önemli:** Bu dizin (worktree değil, tam olarak aynı klasör) aynı zamanda
"**UniversalShare Gap Analysis**" adlı başka bir supermux oturumunun da canlı
çalışma dizini. O oturum şu an boşta (idle) olabilir ya da her an devam
edebilir. Muhtemelen `.github/workflows/` dosyalarını (bkz. yukarıdaki bölüm)
o oturum bırakmıştı.

Bu RESUME.md'yi okuyan yeni bir oturum (veya kullanıcı adına devam eden bir
ajan): bu dizindeki commit'lenmemiş/yarım değişiklikleri tek başına sahiplenip
üzerine yazmadan/commit'lemeden/silmeden önce **kullanıcıyla teyit etsin** —
paralel oturum aynı anda farklı bir şey üzerinde çalışıyor olabilir.

## Geçmiş (git log'dan)

Kronolojik özet (tarihler commit author date'inden; ilk seri aynı gün
içinde yoğun şekilde ilerlemiş):

**2026-07-13 — Faz 0 → Faz 1 MVP, tek günde yoğun bir seri:**
- `722c2aa` PRD, teknik mimari ve Faz-0 PoC (mDNS keşif + PIN eşleşme +
  WebRTC mirroring) ile proje başlangıcı
- `543b1f9` Faz-1 MVP server + web istemciler için uygulama planı
- `3137f56` server modül iskeleti + Makefile
- TDD ile çekirdek sunucu modülleri: `fcc8314` (PIN yaşam döngülü / oda
  modeli), `cea3859` (oda içi mesaj yönlendirme hub'ı), `8305060`
  (WebSocket taşıma katmanı + uçtan uca test), `71476c3` (mDNS + UDP
  broadcast keşif), `784c114` (healthz/info/peers/QR API uçları)
- Web istemciler: `d9dbcec` (reconnect'li SignalClient + grid layout),
  `5b0f9fb` (multi-share grid receiver arayüzü), `8da7a9c` (PIN girişli
  sender arayüzü)
- `4d48d9f` server main wiring — gömülü web + keşif + signaling tek
  binary'de birleşti
- Güvenlik: `8f898ea` (kalıcı self-signed sertifika + parmak izi),
  `079d22d` (PIN challenge-response HMAC proof + hız sınırı), `1d4f41b`
  (node 18 webcrypto fallback fix)
- `c30185e` PIN yenileme özelliği (receiver'da "regen" butonu)
- `7ba4360` güvenlik turu dokümantasyonu + v0.3.0 sürüm notu
- `bbfd3e8` cross-compile (5 platform) + CI/release hattı (Makefile/
  gitignore değişiklikleri; o zamanki workflow dosyaları sonradan bir
  history rewrite ile temizlenmiş — bkz. yukarıdaki not)
- `8e3cdac` Android & Android TV alıcı uygulaması (Kotlin, mDNS keşifli)
- `de6eb18` webOS/LG TV alıcı uygulaması (.ipk paketlenip doğrulandı) —
  bu commit uzun süre `origin/main`'in ucuydu

**2026-07-21 — WAN + yeni platformlar:**
- `c01ecbb` STUN/TURN WAN desteği, Electron native sender, iOS sender
  (ReplayKit)
- `8847af9` Samsung Tizen alıcısı + Trusted Device (TOFU) — PIN olmadan
  yeniden bağlanma

**2026-07-25 (bugün) — bu supermux oturumu:**
- `c01ecbb` ve `8847af9` `origin/main`'e push edildi (temiz fast-forward)
- `origin/dev` dalı `8847af9`'dan oluşturuldu ve push edildi
- `b9b6ea5` GitHub Actions CI/release workflow'ları `main`'de commit'lendi
  ama `workflow` OAuth scope eksikliği yüzünden push edilemedi (yukarıya
  bakın) — sadece yerel `main`'de mevcut
- Bu `RESUME.md` `dev` dalına eklendi

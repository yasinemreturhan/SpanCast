# UniversalShare — LG webOS TV istemcisi

Ekran **alıcısı**: LG TV'de UniversalShare sunucusunun receiver arayüzünü açar.
webOS uygulamaları Chromium tabanlı web uygulamalarıdır — WebRTC alıcı doğrudan
çalışır, ek çalışma zamanı gerekmez.

## Paketleme
```bash
npm exec --yes --package=@webos-tools/cli -- ares-package apps/webos -o dist
# → dist/com.universalshare.receiver_<sürüm>_all.ipk
```
CI, her `v*` tag'inde .ipk'yı release'e ekler.

## TV'ye kurulum (Developer Mode)
1. LG Content Store'dan **Developer Mode** uygulamasını kur, LG hesabıyla aç
2. Bilgisayarda: `ares-setup-device` ile TV'yi ekle (TV ekranındaki passphrase)
3. `ares-install --device tv dist/com.universalshare.receiver_0.3.0_all.ipk`
4. Uygulamayı aç → sunucu adresini gir (örn. `192.168.1.20:8788`) → PIN ekranda

## Notlar
- Self-signed sertifika ilk bağlantıda TV tarayıcı onayı ister ("Güvenli değil →
  yine de devam"); bir kez kabul edilir
- Adres localStorage'da hatırlanır; kumandayla giriş için input odaklı açılır
- mDNS keşfi web uygulamasından yapılamadığı için adres elle girilir
  (gelecek: sunucu tarafı "TV'ye gönder" — sunucu SSDP ile TV'yi bulur)

# UniversalShare — Android / Android TV / Google TV istemcisi

Ekran **alıcısı**: LAN'daki `ushare` sunucusunun receiver arayüzünü tam ekran
WebView'da açar. Telefon, tablet ve TV'de (LEANBACK_LAUNCHER + D-pad desteği)
çalışır.

## Özellikler
- 🔎 **Otomatik keşif:** `NsdManager` ile `_ushare._tcp` sunucuları bulunur,
  adres kutusu otomatik dolar
- 📺 **TV hazır:** leanback launcher girişi, kumandayla gezinme, banner
- 🔐 Self-signed sertifika onay diyaloğu (ilk bağlantıda bir kez)
- 💾 Son sunucu adresi hatırlanır

## Derleme
Yerelde Android SDK gerekir:
```bash
cd apps/android && gradle assembleDebug
```
CI'da her push'ta debug APK, her `v*` tag'inde release APK otomatik derlenir
(GitHub Actions → Artifacts / Releases).

## Kurulum (TV)
1. TV'de "Bilinmeyen kaynaklar"a izin ver
2. APK'yı USB/`adb install` ile yükle: `adb connect <tv-ip> && adb install ushare.apk`
3. Uygulamayı aç → sunucu otomatik bulunur → Bağlan → PIN ekranda

## Yol haritası
- Gönderici modu: `MediaProjection` + native WebRTC (Faz 2 — WebView
  `getDisplayMedia`'yı desteklemediği için native gerekir)
- Sertifika parmak izi sabitleme (QR'daki `fp` ile otomatik doğrulama)

# UniversalShare — Samsung Tizen TV Alıcısı

Ekran **alıcısı**: Samsung TV'de UniversalShare sunucusunun receiver arayüzünü açar.
Tizen Web App (`.wgt`) — Chromium tabanlı, WebRTC doğrudan çalışır.

## Paketleme

Tizen Studio CLI gerekir (`tizen` komutu PATH'de olmalı).

```bash
# Proje klasöründen:
tizen package -t wgt -o dist -- apps/tizen
# → dist/UniversalShare.wgt
```

Veya Tizen Studio IDE ile: File → Import → Tizen → Tizen Web Project

## TV'ye Kurulum (Developer Mode)

Samsung Tizen TV'de Developer Mode:

1. **TV'de**: Ayarlar → Destek → Yazılım Güncelleme → "12345" tuşla (gizli menü)  
   → Geliştirici Modu Aç → Bilgisayar IP'sini gir (aynı ağda olmalı)
2. **Bilgisayarda**: Tizen Studio → Device Manager → TV'yi ekle (IP ile)
3. **SDB ile bağlan**:
   ```bash
   sdb connect <TV_IP>:26101
   sdb devices   # tv listede görünmeli
   ```
4. **Kurulum**:
   ```bash
   tizen install -n UniversalShare.wgt -t <device_id>
   ```
5. Uygulamayı aç → Sunucu adresini gir → PIN ekranda görünür

## Notlar

- Self-signed sertifika ilk bağlantıda Tizen tarayıcı uyarısı gösterir;
  "İlerle" ile kabul edilir (adres localStorage'da hatırlanır)
- Samsung QLED/Neo QLED 2018+ modellerinde Tizen 4+ WebRTC desteği vardır
- mDNS web uygulamasından yapılamaz — adres elle girilir
- Samsung imzalı yayın için Tizen Studio'da Certificate Manager ile
  `distributor1.p12` oluştur

## Tizen Remote tuşları

| Tuş | Davranış |
|-----|---------|
| ← BACK | Bağlantıyı kes, adres ekranına dön |
| OK / Enter | Bağlan |
| ↑↓←→ | Odak gezintisi |

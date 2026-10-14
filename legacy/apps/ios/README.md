# UniversalShare — iOS Gönderici

ReplayKit Broadcast Upload Extension ile sistem genelinde ekran kaydı.
WebRTC üzerinden UniversalShare sunucusuna iletir.

## Xcode Proje Kurulumu

### 1. Yeni proje oluştur
- File → New → Project → App (SwiftUI, iOS 16+)
- Ürün adı: `UniversalShare`
- Bundle ID: `com.universalshare.sender`

### 2. Dosyaları ekle
`UniversalShare/` klasöründeki Swift dosyalarını projeye sürükle:
- `ContentView.swift`
- `SignalClient.swift`
- `PairUtil.swift`

### 3. Broadcast Extension ekle
- File → New → Target → Broadcast Upload Extension
- Ürün adı: `UniversalShareBroadcast`
- `UniversalShareBroadcast/BroadcastHandler.swift` dosyasını ekle
- Extension'ın Info.plist'inde `NSExtensionPrincipalClass` →
  `$(PRODUCT_MODULE_NAME).BroadcastHandler` olarak ayarla

### 4. App Group
- Her iki hedef için Signing & Capabilities → App Groups ekle
- Aynı App Group ID kullan: `group.com.universalshare`
- Bu sayede ana uygulama ile extension arasında pin/sinyal bilgisi paylaşılır

### 5. WebRTC SDK
Gerçek medya aktarımı için [GoogleWebRTC](https://cocoapods.org/pods/GoogleWebRTC)
veya [WebRTC-iOS](https://github.com/stasel/WebRTC) ekle:

```ruby
# Podfile
pod 'GoogleWebRTC'
```

`BroadcastHandler.swift` içindeki `// TODO` satırlarını WebRTC track'e bağla.

### 6. Info.plist izinleri
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Ses kaydı için mikrofon gerekli.</string>
```

### 7. Derleme ve test
```bash
xcodebuild -scheme UniversalShare -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Akış

```
ReplayKit kare → VideoToolbox H.264 → WebRTC track
                                       ↓
                              signaling (WS + PIN auth)
                                       ↓
                              UniversalShare sunucusu
                                       ↓
                              Alıcı (browser/Android/webOS)
```

## Notlar
- iOS 16+ gerektirir (URLSession WebSocket built-in)
- Self-signed TLS: `InsecureSessionDelegate` sertifikayı kabul eder;
  parmak izi gösterimi ContentView'da yapılır
- WAN kullanımı için sunucuda `-turn` bayrağı gerekli

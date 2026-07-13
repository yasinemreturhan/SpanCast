# UniversalShare Faz-1 MVP (Server + Web İstemciler) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PoC'u üretime yaklaşan bir MVP'ye dönüştür: çok-göndericili (multi-share) oda modeli, PIN yaşam döngüsü, mDNS + UDP broadcast keşif, QR eşleşme ve yeniden bağlanabilen web sender/receiver — tamamı testli.

**Architecture:** Tek Go binary (`server/`) — oda/signaling çekirdeği (`internal/room`, `internal/signal`), WebSocket taşıma, keşif (`internal/discovery`), REST API ve `go:embed` ile gömülü web istemcileri. Web tarafında saf-JS `SignalClient` (reconnect'li) + grid yerleşim mantığı `node --test` ile test edilir. Ortam headless olduğundan görsel doğrulama yerine Go entegrasyon testleri gerçek WebSocket akışını (offer/answer/ICE relay, join/leave) uçtan uca doğrular.

**Tech Stack:** Go 1.22 (gorilla/websocket, grandcat/zeroconf, skip2/go-qrcode), vanilla JS + WebRTC, node --test.

---

### Task 1: `server/` modül iskeleti
**Files:** Create `server/go.mod`, `server/main.go` (boş wiring), `Makefile`
- [ ] `server/go.mod` (module `github.com/yasinemreturhan/DoScreen/server`, go 1.22)
- [ ] `make build` / `make test` hedefleri (PATH'e ~/toolchains/go/bin ekleyerek)
- [ ] Commit

### Task 2: Oda modeli — `server/internal/room`
**Files:** Create `internal/room/room.go`, `internal/room/room_test.go`
Davranış: `Manager.CreateRoom()` → 6 haneli PIN (kriptografik rastgele), oda yaşadıkça PIN geçerli; `Manager.Join(pin)` → oda döner; kullanılmayan oda `pinTTL` (2 dk) sonra `Join`'i reddeder (test için enjekte edilebilir `now func() time.Time`); `Room.AddSender` en fazla 4 gönderici (`ErrRoomFull`), `RemoveSender` slot boşaltır; `Regenerate()` yeni PIN verir, eskisi geçersiz.
- [ ] Failing testler: `TestPinFormat`, `TestJoinOK`, `TestJoinWrongPin`, `TestJoinExpired`, `TestMaxSenders`, `TestSenderLeaveFreesSlot`, `TestRegenerateInvalidatesOldPin`
- [ ] Minimal implementasyon, testler yeşil
- [ ] Commit

### Task 3: Signaling hub — `server/internal/signal`
**Files:** Create `internal/signal/hub.go`, `internal/signal/hub_test.go`
Zarf: `{"type":"offer|answer|ice|joined|left|pin|roster|error","from":senderID,"to":senderID,"payload":...}`. Hub, `Conn` arayüzü (`Send(v any) error`, `Close()`) üzerinden çalışır → testte sahte conn. Kurallar: sender→receiver'a `from` damgalı iletilir; receiver→`to` alanındaki sender'a iletilir; sender katılınca receiver'a `joined`, ayrılınca `left`; receiver düşerse tüm sender'lara `error:receiver-gone` ve oda kapanır.
- [ ] Failing testler: `TestSenderToReceiverStampsFrom`, `TestReceiverRoutesToSender`, `TestJoinedLeftNotifications`, `TestReceiverGoneClosesRoom`
- [ ] Implementasyon, testler yeşil
- [ ] Commit

### Task 4: WebSocket taşıma + entegrasyon testi
**Files:** Create `internal/ws/handler.go`, `internal/ws/handler_test.go`
`/ws?role=receiver` → `{"type":"pin","pin":…,"roomId":…}`; `/ws?role=sender&pin=…&name=…`. gorilla conn'ları hub `Conn`'a adapte edilir (yazma goroutine + kanal). Entegrasyon testi `httptest.NewServer` + gorilla dialer ile: receiver PIN alır → 2 sender katılır → receiver 2 `joined` görür → sender-1 offer → receiver `from` ile alır → receiver answer(`to`=1) → sender-1 alır, sender-2 almaz → sender-1 kopar → receiver `left` alır.
- [ ] Failing entegrasyon testi `TestFullSignalingFlow`, `TestBadPinRejected`
- [ ] Implementasyon, testler yeşil
- [ ] Commit

### Task 5: Keşif — `server/internal/discovery`
**Files:** Create `internal/discovery/mdns.go`, `internal/discovery/broadcast.go`, `internal/discovery/broadcast_test.go`
mDNS: `_ushare._tcp` ilan + browse (PoC'takinin paketlenmiş hali, context'li, `Peers()` snapshot). UDP fallback: 41337 portuna 3 sn'de bir JSON beacon `{"name","port","ver"}`; dinleyici peers tablosuna işler (TTL 10 sn). Test (loopback): beacon gönder → dinleyicide peer görünür; TTL sonrası düşer (enjekte saat).
- [ ] Failing testler: `TestBroadcastDiscovery`, `TestPeerExpiry`
- [ ] Implementasyon, testler yeşil (mDNS için ağ gerektirmeyen smoke: Register hata dönmüyor)
- [ ] Commit

### Task 6: HTTP API + QR
**Files:** Create `internal/api/api.go`, `internal/api/api_test.go`
`GET /healthz` → 200 "ok"; `GET /api/info` → `{name, version, caps}`; `GET /api/peers` → keşif snapshot'ı; `GET /api/qr?data=…` → PNG (skip2/go-qrcode, 256px, data ≤ 512B sınırı).
- [ ] Failing testler: `TestHealthz`, `TestInfo`, `TestPeersEmpty`, `TestQRPng`, `TestQRTooLong`
- [ ] Implementasyon, testler yeşil
- [ ] Commit

### Task 7: Web ortak katman — `server/web/js/`
**Files:** Create `web/js/layout.js`, `web/js/signal.js`, `web/js/layout.test.mjs`, `web/js/signal.test.mjs`
`layout.js`: saf fonksiyon `gridFor(n)` → `{rows, cols}` (1→1×1, 2→1×2, 3–4→2×2); `tileRect(i,n,W,H)`. `signal.js`: `SignalClient(url)` — otomatik yeniden bağlanma (üstel backoff 0.5→8 sn), `on(type,cb)`, `send(obj)`, kuyruklama (bağlantı yokken send buffer). WS'i enjekte edilebilir yap (`opts.WebSocketImpl`) → node testinde sahte WS.
- [ ] Failing node testleri: grid hesapları, backoff dizisi, reconnect sonrası buffer flush
- [ ] Implementasyon, `node --test web/js/` yeşil
- [ ] Commit

### Task 8: Receiver (multi-share grid)
**Files:** Rewrite `web/receiver.html` (+`web/js/receiver.js`)
PIN + QR (`/api/qr?data=ushare://pair?...`) gösterimi; her `joined` için `RTCPeerConnection` + grid'e video tile (layout.js); `left`te tile kaldır, grid yeniden akar; tile başına ad + fps/bitrate; ilk sender bağlandığında eşleşme ekranı köşeye küçülür (yeni katılımlar için PIN görünür kalır).
- [ ] Implementasyon (mantık signal.js/layout.js üzerinden, sayfa ince)
- [ ] `node --check` ile sözdizimi + sunucu embed'den 200 döndürme testi
- [ ] Commit

### Task 9: Sender
**Files:** Rewrite `web/sender.html` (+`web/js/sender.js`)
PIN girişi (6 kutu otomatik ilerleyen), `getDisplayMedia`, SignalClient ile offer/ICE, kopunca otomatik yeniden bağlanıp akışı yeniden kurma, canlı durum/istatistik, "Durdur".
- [ ] Implementasyon
- [ ] `node --check` + embed 200 testi
- [ ] Commit

### Task 10: main.go wiring, embed, dokümantasyon
**Files:** Modify `server/main.go`, Create `server/web/index.html`, Modify `README.md`, `poc/README.md`
`go:embed web` → FileServer; `/ws`, `/api/*` bağla; mDNS+broadcast başlat; `-port` bayrağı (vars. 8788). Tüm paket testleri + `go vet` yeşil; binary'yi başlatıp curl smoke (healthz, index, qr). README'ye MVP çalıştırma bölümü.
- [ ] Implementasyon + `make test` tamamı yeşil
- [ ] Canlı smoke test
- [ ] Commit

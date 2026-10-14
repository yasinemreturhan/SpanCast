// UniversalShare PoC — cihaz keşfi (mDNS) + PIN eşleşmeli WebRTC signaling.
//
// Tek binary iki işi yapar:
//  1. Kendini mDNS ile `_ushare._tcp.local` olarak ilan eder ve ağdaki
//     diğer UniversalShare cihazlarını keşfeder (/api/peers).
//  2. Tarayıcı tabanlı sender/receiver sayfalarını sunar ve aralarındaki
//     WebRTC signaling'i (SDP/ICE) 6 haneli PIN üzerinden eşleştirerek taşır.
//
// Çalıştırma:  go run .   → http://<bu-makine>:8787
package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/grandcat/zeroconf"
)

const (
	serviceType = "_ushare._tcp"
	httpPort    = 8788
	pinTTL      = 120 * time.Second
)

// ---- Eşleşme (PIN → oturum) ----------------------------------------------

// session: bir receiver'ın beklediği, sender'ın PIN ile katıldığı signaling odası.
type session struct {
	pin      string
	receiver *websocket.Conn
	sender   *websocket.Conn
	created  time.Time
	mu       sync.Mutex
}

var (
	sessions   = map[string]*session{}
	sessionsMu sync.Mutex
	upgrader   = websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
)

func newPIN() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1_000_000))
	return fmt.Sprintf("%06d", n.Int64())
}

// wsHandler: /ws?role=receiver  → PIN üretilir ve istemciye gönderilir.
//            /ws?role=sender&pin=123456 → oturuma katılır.
// Sonrasında iki soket arasındaki tüm mesajlar (SDP offer/answer, ICE) aynen aktarılır.
func wsHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	role := r.URL.Query().Get("role")
	switch role {
	case "receiver":
		s := &session{pin: newPIN(), receiver: conn, created: time.Now()}
		sessionsMu.Lock()
		sessions[s.pin] = s
		sessionsMu.Unlock()
		conn.WriteJSON(map[string]string{"type": "pin", "pin": s.pin})
		relay(conn, s, true)

	case "sender":
		pin := r.URL.Query().Get("pin")
		sessionsMu.Lock()
		s := sessions[pin]
		sessionsMu.Unlock()
		if s == nil || time.Since(s.created) > pinTTL {
			conn.WriteJSON(map[string]string{"type": "error", "message": "geçersiz veya süresi dolmuş PIN"})
			conn.Close()
			return
		}
		s.mu.Lock()
		s.sender = conn
		s.mu.Unlock()
		conn.WriteJSON(map[string]string{"type": "paired"})
		s.receiver.WriteJSON(map[string]string{"type": "paired"})
		relay(conn, s, false)

	default:
		conn.Close()
	}
}

// relay: gelen her mesajı oturumdaki karşı tarafa iletir.
func relay(conn *websocket.Conn, s *session, isReceiver bool) {
	defer func() {
		conn.Close()
		sessionsMu.Lock()
		delete(sessions, s.pin)
		sessionsMu.Unlock()
	}()
	for {
		mt, msg, err := conn.ReadMessage()
		if err != nil {
			return
		}
		s.mu.Lock()
		peer := s.sender
		if !isReceiver {
			peer = s.receiver
		}
		s.mu.Unlock()
		if peer != nil {
			peer.WriteMessage(mt, msg)
		}
	}
}

// ---- Keşif (mDNS) ----------------------------------------------------------

type peer struct {
	Name string `json:"name"`
	Host string `json:"host"`
	Addr string `json:"addr"`
	Port int    `json:"port"`
}

var (
	peers   = map[string]peer{}
	peersMu sync.Mutex
)

// advertise: bu cihazı ağda UniversalShare alıcısı/vericisi olarak duyurur.
func advertise() (*zeroconf.Server, error) {
	host, _ := os.Hostname()
	return zeroconf.Register(
		host, serviceType, "local.", httpPort,
		[]string{"ver=0.1", "caps=mirror"}, nil,
	)
}

// browse: ağdaki diğer UniversalShare örneklerini sürekli dinler.
func browse() {
	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		log.Printf("mDNS resolver hatası: %v", err)
		return
	}
	entries := make(chan *zeroconf.ServiceEntry)
	go func() {
		for e := range entries {
			if len(e.AddrIPv4) == 0 {
				continue
			}
			peersMu.Lock()
			peers[e.Instance] = peer{
				Name: e.Instance,
				Host: e.HostName,
				Addr: e.AddrIPv4[0].String(),
				Port: e.Port,
			}
			peersMu.Unlock()
			log.Printf("keşfedildi: %s @ %s:%d", e.Instance, e.AddrIPv4[0], e.Port)
		}
	}()
	if err := resolver.Browse(context.Background(), serviceType, "local.", entries); err != nil {
		log.Printf("mDNS browse hatası: %v", err)
	}
	select {} // sonsuza dek dinle
}

func peersHandler(w http.ResponseWriter, _ *http.Request) {
	peersMu.Lock()
	defer peersMu.Unlock()
	list := make([]peer, 0, len(peers))
	for _, p := range peers {
		list = append(list, p)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(list)
}

// ---- main -------------------------------------------------------------------

func main() {
	srv, err := advertise()
	if err != nil {
		log.Printf("mDNS ilan hatası (devam ediliyor): %v", err)
	} else {
		defer srv.Shutdown()
	}
	go browse()

	http.Handle("/", http.FileServer(http.Dir("web")))
	http.HandleFunc("/ws", wsHandler)
	http.HandleFunc("/api/peers", peersHandler)

	log.Printf("UniversalShare PoC hazır → http://localhost:%d", httpPort)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", httpPort), nil))
}

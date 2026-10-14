// Package api: sağlık, cihaz bilgisi, keşfedilen peer listesi ve QR üretimi
// için REST uçları. PeerSource arayüzü sayesinde keşif katmanından bağımsız
// test edilir.
package api

import (
	"encoding/json"
	"net/http"

	qrcode "github.com/skip2/go-qrcode"
	"github.com/yasinemreturhan/DoScreen/server/internal/discovery"
)

// maxQRData: QR içeriği üst sınırı (kötüye kullanım ve dev QR'ları engeller).
const maxQRData = 512

// PeerSource: keşif katmanının API'ye bakan yüzü.
type PeerSource interface {
	Peers() []discovery.Peer
}

// ICEServer: tek bir WebRTC ICE sunucusu (STUN veya TURN).
type ICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

// New, /healthz ve /api/* uçlarını içeren bir handler döner. fp, TLS
// sertifikasının SHA-256 parmak izidir (TLS kapalıysa boş). iceServers
// nil ise boş liste döner.
func New(name, version, fp string, peers PeerSource, iceServers []ICEServer) http.Handler {
	if iceServers == nil {
		iceServers = []ICEServer{}
	}
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("GET /api/info", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{
			"name":    name,
			"version": version,
			"caps":    []string{"mirror", "multi"},
			"fp":      fp,
		})
	})

	mux.HandleFunc("GET /api/ice", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"iceServers": iceServers})
	})

	mux.HandleFunc("GET /api/peers", func(w http.ResponseWriter, _ *http.Request) {
		list := peers.Peers()
		if list == nil {
			list = []discovery.Peer{}
		}
		writeJSON(w, list)
	})

	mux.HandleFunc("GET /api/qr", func(w http.ResponseWriter, r *http.Request) {
		data := r.URL.Query().Get("data")
		if data == "" || len(data) > maxQRData {
			http.Error(w, "data parametresi gerekli (≤512 bayt)", http.StatusBadRequest)
			return
		}
		png, err := qrcode.Encode(data, qrcode.Medium, 256)
		if err != nil {
			http.Error(w, "QR üretilemedi", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Cache-Control", "no-store")
		w.Write(png)
	})

	return mux
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

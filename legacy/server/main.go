// UniversalShare MVP sunucusu: gömülü web istemciler, WebSocket signaling,
// keşif (mDNS + UDP broadcast) ve REST API — tek binary.
package main

import (
	"crypto/tls"
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/yasinemreturhan/DoScreen/server/internal/api"
	"github.com/yasinemreturhan/DoScreen/server/internal/discovery"
	"github.com/yasinemreturhan/DoScreen/server/internal/signal"
	"github.com/yasinemreturhan/DoScreen/server/internal/tlscert"
	"github.com/yasinemreturhan/DoScreen/server/internal/ws"
)

const version = "0.3.0"

//go:embed web
var webFS embed.FS

func main() {
	port := flag.Int("port", 8788, "HTTPS/WS dinleme portu")
	name := flag.String("name", "", "cihaz adı (varsayılan: hostname)")
	noTLS := flag.Bool("no-tls", false, "TLS'siz çalış (yalnız geliştirme)")
	certDir := flag.String("cert-dir", defaultCertDir(), "TLS sertifika dizini")
	stunURL := flag.String("stun", "stun:stun.l.google.com:19302", "STUN sunucu URL (boş=kapalı)")
	turnURL := flag.String("turn", "", "TURN sunucu URL (örn. turn:hostname:3478)")
	turnUser := flag.String("turn-user", "", "TURN kullanıcı adı")
	turnPass := flag.String("turn-pass", "", "TURN şifresi")
	flag.Parse()

	if *name == "" {
		*name, _ = os.Hostname()
	}

	// TLS kimliği: cihaz başına kalıcı self-signed sertifika.
	var ident *tlscert.Identity
	if !*noTLS {
		var err error
		if ident, err = tlscert.LoadOrCreate(*certDir); err != nil {
			log.Fatalf("TLS kimliği hazırlanamadı: %v", err)
		}
	}

	// Keşif: mDNS ilanı + tarama, UDP broadcast fallback.
	disc := discovery.Start(*name, *port)
	defer disc.Stop()

	// Signaling.
	hub := signal.NewHub()

	// ICE sunucuları: STUN (varsayılan açık) + opsiyonel TURN.
	var iceServers []api.ICEServer
	if *stunURL != "" {
		iceServers = append(iceServers, api.ICEServer{URLs: []string{*stunURL}})
	}
	if *turnURL != "" {
		iceServers = append(iceServers, api.ICEServer{
			URLs:       []string{*turnURL},
			Username:   *turnUser,
			Credential: *turnPass,
		})
	}

	// HTTP yönlendirme.
	mux := http.NewServeMux()
	web, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatal(err)
	}
	fp := ""
	if ident != nil {
		fp = ident.Fingerprint
	}
	apiHandler := api.New(*name, version, fp, disc, iceServers)
	mux.Handle("/", http.FileServer(http.FS(web)))
	mux.Handle("/ws", ws.NewHandler(hub))
	mux.Handle("/healthz", apiHandler)
	mux.Handle("/api/", apiHandler)

	addr := fmt.Sprintf(":%d", *port)
	if ident == nil {
		log.Printf("UniversalShare %s hazır → http://localhost%s (cihaz: %s, TLS KAPALI)", version, addr, *name)
		log.Fatal(http.ListenAndServe(addr, mux))
	}
	srv := &http.Server{
		Addr:      addr,
		Handler:   mux,
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{ident.Cert}},
	}
	log.Printf("UniversalShare %s hazır → https://localhost%s (cihaz: %s, fp: %s…)",
		version, addr, *name, ident.Fingerprint[:16])
	log.Fatal(srv.ListenAndServeTLS("", ""))
}

// defaultCertDir: kullanıcı yapılandırma dizini altında ushare klasörü.
func defaultCertDir() string {
	base, err := os.UserConfigDir()
	if err != nil {
		base = "."
	}
	return filepath.Join(base, "ushare")
}

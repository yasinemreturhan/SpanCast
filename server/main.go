// UniversalShare MVP sunucusu: gömülü web istemciler, WebSocket signaling,
// keşif (mDNS + UDP broadcast) ve REST API — tek binary.
package main

import (
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"

	"github.com/yasinemreturhan/DoScreen/server/internal/api"
	"github.com/yasinemreturhan/DoScreen/server/internal/discovery"
	"github.com/yasinemreturhan/DoScreen/server/internal/signal"
	"github.com/yasinemreturhan/DoScreen/server/internal/ws"
)

const version = "0.2.0"

//go:embed web
var webFS embed.FS

func main() {
	port := flag.Int("port", 8788, "HTTP/WS dinleme portu")
	name := flag.String("name", "", "cihaz adı (varsayılan: hostname)")
	flag.Parse()

	if *name == "" {
		*name, _ = os.Hostname()
	}

	// Keşif: mDNS ilanı + tarama, UDP broadcast fallback.
	disc := discovery.Start(*name, *port)
	defer disc.Stop()

	// Signaling.
	hub := signal.NewHub()

	// HTTP yönlendirme.
	mux := http.NewServeMux()
	web, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatal(err)
	}
	mux.Handle("/", http.FileServer(http.FS(web)))
	mux.Handle("/ws", ws.NewHandler(hub))
	mux.Handle("/healthz", api.New(*name, version, disc))
	mux.Handle("/api/", api.New(*name, version, disc))

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("UniversalShare %s hazır → http://localhost%s (cihaz: %s)", version, addr, *name)
	log.Fatal(http.ListenAndServe(addr, mux))
}

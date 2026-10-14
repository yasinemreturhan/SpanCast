// mDNS/DNS-SD keşfi (birincil yol) + UDP broadcast (fallback) birleşimi.
// Service, her iki mekanizmayı yönetir ve tek bir Peers() görünümü sunar.
package discovery

import (
	"context"
	"log"
	"os"
	"sync"

	"github.com/grandcat/zeroconf"
)

const mdnsService = "_ushare._tcp"

// Service: bu cihazın ilanı + ağdaki diğer cihazların birleşik görünümü.
type Service struct {
	name   string
	port   int
	server *zeroconf.Server
	bcast  *Listener
	cancel context.CancelFunc
	stopFn func()

	mu        sync.Mutex
	mdnsPeers map[string]Peer
}

// Start, mDNS ilanını/taramasını ve UDP beacon yayınını/dinleyicisini başlatır.
// mDNS başarısız olsa da broadcast fallback ile devam eder.
func Start(name string, port int) *Service {
	if name == "" {
		name, _ = os.Hostname()
	}
	s := &Service{name: name, port: port, mdnsPeers: map[string]Peer{}}

	// mDNS ilanı (best effort).
	srv, err := zeroconf.Register(name, mdnsService, "local.", port,
		[]string{"ver=0.2", "caps=mirror,multi"}, nil)
	if err != nil {
		log.Printf("keşif: mDNS ilanı başarısız (broadcast ile devam): %v", err)
	} else {
		s.server = srv
	}

	// mDNS tarama (best effort).
	ctx, cancel := context.WithCancel(context.Background())
	s.cancel = cancel
	go s.browse(ctx)

	// UDP broadcast fallback.
	if l, err := ListenBeacons(BeaconPort); err != nil {
		log.Printf("keşif: beacon dinleyici açılamadı: %v", err)
	} else {
		s.bcast = l
	}
	s.stopFn = Announce(Beacon{Name: name, Port: port, Ver: "0.2"})

	return s
}

func (s *Service) browse(ctx context.Context) {
	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		log.Printf("keşif: mDNS resolver hatası: %v", err)
		return
	}
	entries := make(chan *zeroconf.ServiceEntry)
	go func() {
		for e := range entries {
			if len(e.AddrIPv4) == 0 || e.Instance == s.name {
				continue // kendimizi listelemeyiz
			}
			s.mu.Lock()
			s.mdnsPeers[e.Instance] = Peer{
				Name: e.Instance, Addr: e.AddrIPv4[0].String(), Port: e.Port,
			}
			s.mu.Unlock()
		}
	}()
	if err := resolver.Browse(ctx, mdnsService, "local.", entries); err != nil {
		log.Printf("keşif: mDNS browse hatası: %v", err)
	}
	<-ctx.Done()
}

// Peers: mDNS + broadcast kaynaklarının birleşik, tekilleştirilmiş listesi.
func (s *Service) Peers() []Peer {
	seen := map[string]bool{}
	var out []Peer

	s.mu.Lock()
	for _, p := range s.mdnsPeers {
		out = append(out, p)
		seen[p.Addr+"|"+p.Name] = true
	}
	s.mu.Unlock()

	if s.bcast != nil {
		for _, p := range s.bcast.Peers() {
			if p.Name == s.name || seen[p.Addr+"|"+p.Name] {
				continue
			}
			out = append(out, p)
		}
	}
	if out == nil {
		out = []Peer{}
	}
	return out
}

// Stop tüm keşif etkinliğini durdurur.
func (s *Service) Stop() {
	if s.server != nil {
		s.server.Shutdown()
	}
	if s.cancel != nil {
		s.cancel()
	}
	if s.bcast != nil {
		s.bcast.Close()
	}
	if s.stopFn != nil {
		s.stopFn()
	}
}

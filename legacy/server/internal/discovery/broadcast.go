// UDP broadcast fallback keşfi: mDNS'in engellendiği ağlarda cihazlar
// BeaconPort'a periyodik JSON beacon yayınlar; dinleyen taraf peers tablosunu
// besler. Beacon görülmeyen peer PeerTTL sonra listeden düşer.
package discovery

import (
	"encoding/json"
	"fmt"
	"net"
	"sync"
	"time"
)

const (
	// BeaconPort: broadcast beacon'larının varsayılan UDP portu.
	BeaconPort = 41337
	// BeaconInterval: yayın aralığı.
	BeaconInterval = 3 * time.Second
	// PeerTTL: beacon görülmeyen peer'ın listeden düşme süresi.
	PeerTTL = 10 * time.Second
)

// Beacon: ağda yayınlanan tanıtım paketi.
type Beacon struct {
	Name string `json:"name"`
	Port int    `json:"port"` // HTTP/WS servis portu
	Ver  string `json:"ver"`
}

// Peer: keşfedilmiş bir cihaz.
type Peer struct {
	Name string `json:"name"`
	Addr string `json:"addr"`
	Port int    `json:"port"`
	Ver  string `json:"ver"`

	lastSeen time.Time
}

// Listener: beacon dinleyicisi.
type Listener struct {
	conn *net.UDPConn

	mu    sync.Mutex
	peers map[string]Peer // anahtar: addr+name

	now func() time.Time // testlerde enjekte edilir
}

// ListenBeacons verilen UDP portunu dinlemeye başlar (0 → rastgele port).
func ListenBeacons(port int) (*Listener, error) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: port})
	if err != nil {
		return nil, fmt.Errorf("beacon dinleyici açılamadı: %w", err)
	}
	l := &Listener{conn: conn, peers: map[string]Peer{}, now: time.Now}
	go l.readLoop()
	return l, nil
}

func (l *Listener) Port() int { return l.conn.LocalAddr().(*net.UDPAddr).Port }

func (l *Listener) Close() { l.conn.Close() }

func (l *Listener) readLoop() {
	buf := make([]byte, 1024)
	for {
		n, src, err := l.conn.ReadFromUDP(buf)
		if err != nil {
			return // soket kapandı
		}
		var b Beacon
		if json.Unmarshal(buf[:n], &b) != nil || b.Name == "" {
			continue // bozuk paketleri sessizce at
		}
		key := src.IP.String() + "|" + b.Name
		l.mu.Lock()
		l.peers[key] = Peer{
			Name: b.Name, Addr: src.IP.String(), Port: b.Port, Ver: b.Ver,
			lastSeen: l.now(),
		}
		l.mu.Unlock()
	}
}

// Peers: TTL'i geçmemiş peer'ların anlık listesi (süresi geçenler temizlenir).
func (l *Listener) Peers() []Peer {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	out := make([]Peer, 0, len(l.peers))
	for k, p := range l.peers {
		if now.Sub(p.lastSeen) > PeerTTL {
			delete(l.peers, k)
			continue
		}
		out = append(out, p)
	}
	return out
}

// SendBeacon tek bir beacon paketi gönderir (testlerde unicast; üretimde
// Announce broadcast adresini kullanır).
func SendBeacon(host string, port int, b Beacon) error {
	data, err := json.Marshal(b)
	if err != nil {
		return err
	}
	conn, err := net.Dial("udp4", fmt.Sprintf("%s:%d", host, port))
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write(data)
	return err
}

// Announce, durdurulana dek BeaconInterval'de bir broadcast beacon yayınlar.
// Dönen fonksiyon yayını durdurur.
func Announce(b Beacon) (stop func()) {
	done := make(chan struct{})
	go func() {
		t := time.NewTicker(BeaconInterval)
		defer t.Stop()
		for {
			SendBeacon("255.255.255.255", BeaconPort, b)
			select {
			case <-done:
				return
			case <-t.C:
			}
		}
	}()
	return func() { close(done) }
}

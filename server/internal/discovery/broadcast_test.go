package discovery

import (
	"testing"
	"time"
)

// Testler loopback üzerinde çalışır: dinleyici rastgele bir porta bağlanır,
// beacon doğrudan o adrese gönderilir (broadcast yerine unicast — aynı format).

func TestBroadcastDiscovery(t *testing.T) {
	l, err := ListenBeacons(0) // 0 → rastgele port
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()

	b := Beacon{Name: "test-cihaz", Port: 8788, Ver: "0.2"}
	if err := SendBeacon("127.0.0.1", l.Port(), b); err != nil {
		t.Fatal(err)
	}

	deadline := time.After(2 * time.Second)
	for {
		peers := l.Peers()
		if len(peers) == 1 {
			if peers[0].Name != "test-cihaz" || peers[0].Port != 8788 {
				t.Fatalf("peer alanları yanlış: %+v", peers[0])
			}
			return
		}
		select {
		case <-deadline:
			t.Fatalf("peer görünmedi, mevcut: %+v", peers)
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func TestPeerExpiry(t *testing.T) {
	now := time.Now()
	l, err := ListenBeacons(0)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	l.now = func() time.Time { return now }

	if err := SendBeacon("127.0.0.1", l.Port(), Beacon{Name: "x", Port: 1, Ver: "0.2"}); err != nil {
		t.Fatal(err)
	}
	// Peer'ın işlenmesini bekle.
	deadline := time.After(2 * time.Second)
	for len(l.Peers()) == 0 {
		select {
		case <-deadline:
			t.Fatal("peer hiç görünmedi")
		case <-time.After(20 * time.Millisecond):
		}
	}

	now = now.Add(PeerTTL + time.Second)
	if got := l.Peers(); len(got) != 0 {
		t.Fatalf("TTL sonrası peer düşmeliydi: %+v", got)
	}
}

package ws

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/yasinemreturhan/DoScreen/server/internal/signal"
)

func dial(t *testing.T, url, query string) *websocket.Conn {
	t.Helper()
	c, _, err := websocket.DefaultDialer.Dial(url+"?"+query, nil)
	if err != nil {
		t.Fatalf("dial(%s): %v", query, err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

func readMsg(t *testing.T, c *websocket.Conn) signal.Message {
	t.Helper()
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	var m signal.Message
	if err := c.ReadJSON(&m); err != nil {
		t.Fatalf("readMsg: %v", err)
	}
	return m
}

// readUntil: istenen tipteki mesaja kadar okur (ara mesajları atlar).
func readUntil(t *testing.T, c *websocket.Conn, typ string) signal.Message {
	t.Helper()
	for i := 0; i < 10; i++ {
		m := readMsg(t, c)
		if m.Type == typ {
			return m
		}
	}
	t.Fatalf("%q tipli mesaj gelmedi", typ)
	return signal.Message{}
}

func newServer(t *testing.T) string {
	t.Helper()
	h := NewHandler(signal.NewHub())
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return "ws" + strings.TrimPrefix(srv.URL, "http")
}

func TestFullSignalingFlow(t *testing.T) {
	url := newServer(t)

	// Receiver oda açar, PIN alır.
	recv := dial(t, url, "role=receiver")
	pinMsg := readMsg(t, recv)
	if pinMsg.Type != "pin" || len(pinMsg.PIN) != 6 {
		t.Fatalf("pin mesajı bekleniyordu: %+v", pinMsg)
	}

	// İki sender katılır; receiver iki joined görür.
	s1 := dial(t, url, "role=sender&pin="+pinMsg.PIN+"&name=laptop")
	readUntil(t, s1, "paired")
	j1 := readUntil(t, recv, "joined")
	if j1.Name != "laptop" {
		t.Fatalf("joined adı yanlış: %+v", j1)
	}
	s2 := dial(t, url, "role=sender&pin="+pinMsg.PIN+"&name=tablet")
	readUntil(t, s2, "paired")
	j2 := readUntil(t, recv, "joined")

	// sender-1 offer gönderir → receiver from damgalı alır.
	if err := s1.WriteJSON(map[string]any{"type": "offer", "payload": map[string]string{"sdp": "o1"}}); err != nil {
		t.Fatal(err)
	}
	off := readUntil(t, recv, "offer")
	if off.From != j1.From {
		t.Fatalf("offer.from=%q, joined.from=%q eşleşmeli", off.From, j1.From)
	}

	// receiver answer'ı yalnız sender-1'e yollar.
	if err := recv.WriteJSON(map[string]any{"type": "answer", "to": j1.From}); err != nil {
		t.Fatal(err)
	}
	ans := readUntil(t, s1, "answer")
	if ans.Type != "answer" {
		t.Fatalf("sender-1 answer almalıydı: %+v", ans)
	}
	// sender-2'ye bir şey gelmemeli (kısa süre dinle).
	s2.SetReadDeadline(time.Now().Add(300 * time.Millisecond))
	var leak signal.Message
	if err := s2.ReadJSON(&leak); err == nil {
		t.Fatalf("sender-2'ye sızıntı: %+v", leak)
	}

	// sender-1 kopar → receiver left alır.
	s1.Close()
	l := readUntil(t, recv, "left")
	if l.From != j1.From {
		t.Fatalf("left.from yanlış: %+v (beklenen %s)", l, j1.From)
	}
	_ = j2
}

func TestBadPinRejected(t *testing.T) {
	url := newServer(t)
	c := dial(t, url, "role=sender&pin=000000&name=x")
	m := readMsg(t, c)
	if m.Type != "error" {
		t.Fatalf("error mesajı bekleniyordu: %+v", m)
	}
}

func TestBadRoleRejected(t *testing.T) {
	h := NewHandler(signal.NewHub())
	srv := httptest.NewServer(h)
	defer srv.Close()
	resp, err := http.Get(srv.URL + "?role=alien")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("400 bekleniyordu, geldi: %d", resp.StatusCode)
	}
}

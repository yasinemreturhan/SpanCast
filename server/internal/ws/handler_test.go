package ws

import (
	"encoding/json"
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

// joinSender: challenge-response akışıyla odaya katılır ve paired bekler.
// wrongPin true ise kasıtlı yanlış PIN'le proof üretir.
func joinSender(t *testing.T, url, pin, name string, wrongPin bool) (*websocket.Conn, signal.Message) {
	t.Helper()
	c := dial(t, url, "role=sender&name="+name)
	ch := readUntil(t, c, "challenge")
	var salt struct {
		Salt string `json:"salt"`
	}
	if err := json.Unmarshal(ch.Payload, &salt); err != nil || salt.Salt == "" {
		t.Fatalf("challenge salt eksik: %+v", ch)
	}
	if wrongPin {
		pin = "000000"
	}
	proof := signal.Proof(pin, salt.Salt)
	if err := c.WriteJSON(map[string]any{"type": "auth", "payload": map[string]string{"proof": proof}}); err != nil {
		t.Fatal(err)
	}
	return c, readMsg(t, c) // paired ya da error
}

func TestFullSignalingFlow(t *testing.T) {
	url := newServer(t)

	// Receiver oda açar, PIN alır.
	recv := dial(t, url, "role=receiver")
	pinMsg := readMsg(t, recv)
	if pinMsg.Type != "pin" || len(pinMsg.PIN) != 6 {
		t.Fatalf("pin mesajı bekleniyordu: %+v", pinMsg)
	}

	// İki sender challenge-response ile katılır; receiver iki joined görür.
	s1, p1 := joinSender(t, url, pinMsg.PIN, "laptop", false)
	if p1.Type != "paired" {
		t.Fatalf("paired bekleniyordu: %+v", p1)
	}
	j1 := readUntil(t, recv, "joined")
	if j1.Name != "laptop" {
		t.Fatalf("joined adı yanlış: %+v", j1)
	}
	s2, _ := joinSender(t, url, pinMsg.PIN, "tablet", false)
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
	recv := dial(t, url, "role=receiver")
	pinMsg := readMsg(t, recv)

	_, m := joinSender(t, url, pinMsg.PIN, "x", true /* yanlış PIN */)
	if m.Type != "error" || m.Reason != "bad-pin" {
		t.Fatalf("bad-pin hatası bekleniyordu: %+v", m)
	}
}

func TestPinNeverOnWire(t *testing.T) {
	// Sözleşme: sender URL'inde ve auth mesajında PIN bulunmaz.
	url := newServer(t)
	recv := dial(t, url, "role=receiver")
	pinMsg := readMsg(t, recv)

	c := dial(t, url, "role=sender&name=x")
	ch := readUntil(t, c, "challenge")
	if strings.Contains(string(ch.Payload), pinMsg.PIN) {
		t.Fatal("challenge PIN içermemeli")
	}
	// (URL zaten pin parametresi olmadan kuruldu — derleme zamanı sözleşme.)
}

func TestRateLimitAfterRepeatedBadPins(t *testing.T) {
	url := newServer(t)
	recv := dial(t, url, "role=receiver")
	pinMsg := readMsg(t, recv)

	// Sınıra kadar yanlış dene.
	for i := 0; i < maxPinFails; i++ {
		_, m := joinSender(t, url, pinMsg.PIN, "x", true)
		if m.Reason != "bad-pin" {
			t.Fatalf("%d. denemede bad-pin bekleniyordu: %+v", i+1, m)
		}
	}
	// Sınır aşıldı: doğru PIN bile artık challenge alamadan reddedilir.
	c := dial(t, url, "role=sender&name=x")
	m := readMsg(t, c)
	if m.Type != "error" || m.Reason != "rate-limited" {
		t.Fatalf("rate-limited bekleniyordu: %+v", m)
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

package signal

import (
	"encoding/json"
	"sync"
	"testing"
)

// fakeConn: Conn arayüzünün test kopyası — gönderilen mesajları biriktirir.
type fakeConn struct {
	mu     sync.Mutex
	msgs   []Message
	closed bool
}

func (f *fakeConn) Send(m Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.msgs = append(f.msgs, m)
	return nil
}

func (f *fakeConn) Close() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.closed = true
}

func (f *fakeConn) received() []Message {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]Message(nil), f.msgs...)
}

func (f *fakeConn) lastOfType(t string) *Message {
	for _, m := range f.received() {
		if m.Type == t {
			mm := m
			return &mm
		}
	}
	return nil
}

func setupRoom(t *testing.T) (h *Hub, recv *fakeConn, sess *ReceiverSession) {
	t.Helper()
	h = NewHub()
	recv = &fakeConn{}
	sess = h.OpenRoom(recv)
	if sess == nil {
		t.Fatal("OpenRoom nil döndü")
	}
	if m := recv.lastOfType("pin"); m == nil {
		t.Fatal("receiver'a pin mesajı gitmedi")
	}
	return h, recv, sess
}

func TestSenderToReceiverStampsFrom(t *testing.T) {
	h, recv, sess := setupRoom(t)
	sc := &fakeConn{}
	ss, err := h.JoinRoom(sess.PIN(), "laptop", sc)
	if err != nil {
		t.Fatal(err)
	}

	payload := json.RawMessage(`{"sdp":"offer-sdp"}`)
	h.FromSender(ss, Message{Type: "offer", Payload: payload})

	m := recv.lastOfType("offer")
	if m == nil {
		t.Fatal("receiver offer almadı")
	}
	if m.From != ss.ID() {
		t.Fatalf("from=%q bekleniyordu, geldi %q", ss.ID(), m.From)
	}
}

func TestReceiverRoutesToSender(t *testing.T) {
	h, _, sess := setupRoom(t)
	sc1, sc2 := &fakeConn{}, &fakeConn{}
	ss1, _ := h.JoinRoom(sess.PIN(), "a", sc1)
	if _, err := h.JoinRoom(sess.PIN(), "b", sc2); err != nil {
		t.Fatal(err)
	}

	h.FromReceiver(sess, Message{Type: "answer", To: ss1.ID()})

	if sc1.lastOfType("answer") == nil {
		t.Fatal("hedef sender answer almadı")
	}
	if sc2.lastOfType("answer") != nil {
		t.Fatal("diğer sender answer almamalıydı")
	}
}

func TestJoinedLeftNotifications(t *testing.T) {
	h, recv, sess := setupRoom(t)
	sc := &fakeConn{}
	ss, _ := h.JoinRoom(sess.PIN(), "tablet", sc)

	j := recv.lastOfType("joined")
	if j == nil {
		t.Fatal("receiver joined bildirimi almadı")
	}
	if j.From != ss.ID() || j.Name != "tablet" {
		t.Fatalf("joined kimliği yanlış: %+v", j)
	}

	h.SenderGone(ss)
	if l := recv.lastOfType("left"); l == nil || l.From != ss.ID() {
		t.Fatalf("receiver left bildirimi almadı: %+v", l)
	}
}

func TestReceiverGoneClosesRoom(t *testing.T) {
	h, _, sess := setupRoom(t)
	sc := &fakeConn{}
	_, _ = h.JoinRoom(sess.PIN(), "a", sc)

	h.ReceiverGone(sess)

	m := sc.lastOfType("error")
	if m == nil || m.Reason != "receiver-gone" {
		t.Fatalf("sender'a receiver-gone hatası gitmedi: %+v", m)
	}
	if !sc.closed {
		t.Fatal("sender bağlantısı kapatılmalıydı")
	}
	if _, err := h.JoinRoom(sess.PIN(), "geç", &fakeConn{}); err == nil {
		t.Fatal("kapanan odaya katılım reddedilmeliydi")
	}
}

func TestBadPinRejected(t *testing.T) {
	h := NewHub()
	if _, err := h.JoinRoom("999999", "x", &fakeConn{}); err == nil {
		t.Fatal("geçersiz PIN reddedilmeliydi")
	}
}

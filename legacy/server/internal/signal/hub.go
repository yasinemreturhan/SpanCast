// Package signal, oda içi mesaj yönlendirmesini yapar: sender'dan gelen
// mesajlar "from" damgasıyla receiver'a, receiver'dan gelenler "to" alanındaki
// sender'a iletilir. Taşıma katmanından bağımsızdır — bağlantılar Conn
// arayüzüyle temsil edilir (gerçekte WebSocket, testte sahte).
package signal

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sync"

	"github.com/yasinemreturhan/DoScreen/server/internal/room"
)

// ErrBadToken: sunulan güvenilir cihaz jetonu geçersiz veya süresi dolmuş.
var ErrBadToken = errors.New("güvenilir cihaz jetonu geçersiz")

// Message: tarafların konuştuğu tek zarf tipi.
type Message struct {
	Type    string          `json:"type"` // pin|joined|left|offer|answer|ice|error
	From    string          `json:"from,omitempty"`
	To      string          `json:"to,omitempty"`
	Name    string          `json:"name,omitempty"`
	PIN     string          `json:"pin,omitempty"`
	RoomID  string          `json:"roomId,omitempty"`
	Reason  string          `json:"reason,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// Conn: hub'ın bir uca mesaj göndermek için kullandığı soyutlama.
type Conn interface {
	Send(Message) error
	Close()
}

// ReceiverSession: bir odanın receiver ucu.
type ReceiverSession struct {
	rm   *room.Room
	conn Conn

	mu      sync.Mutex
	senders map[string]*SenderSession
	closed  bool
}

func (rs *ReceiverSession) PIN() string { return rs.rm.PIN() }

func (rs *ReceiverSession) isClosed() bool {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	return rs.closed
}

// SenderSession: odaya katılmış bir gönderici ucu.
type SenderSession struct {
	sender   *room.Sender
	conn     Conn
	receiver *ReceiverSession
}

func (ss *SenderSession) ID() string { return ss.sender.ID }

// Hub: oda yöneticisinin üstünde yönlendirme katmanı.
type Hub struct {
	rooms *room.Manager

	mu          sync.Mutex
	sessions    map[*room.Room]*ReceiverSession
	trustTokens map[string]*ReceiverSession // token → receiver oturumu
}

func NewHub() *Hub {
	return &Hub{
		rooms:       room.NewManager(),
		sessions:    map[*room.Room]*ReceiverSession{},
		trustTokens: map[string]*ReceiverSession{},
	}
}

// OpenRoom yeni oda açar ve receiver'a PIN'ini bildirir.
func (h *Hub) OpenRoom(conn Conn) *ReceiverSession {
	r := h.rooms.CreateRoom()
	rs := &ReceiverSession{rm: r, conn: conn, senders: map[string]*SenderSession{}}
	h.mu.Lock()
	h.sessions[r] = rs
	h.mu.Unlock()
	conn.Send(Message{Type: "pin", PIN: r.PIN(), RoomID: r.ID})
	return rs
}

// JoinRoom, PIN doğrulaması yapıp göndericiyi odaya ekler ve receiver'a
// "joined" bildirir.
func (h *Hub) JoinRoom(pin, name string, conn Conn) (*SenderSession, error) {
	r, err := h.rooms.Join(pin)
	if err != nil {
		return nil, err
	}
	h.mu.Lock()
	rs := h.sessions[r]
	h.mu.Unlock()
	if rs == nil || rs.isClosed() {
		return nil, room.ErrNotFound
	}
	s, err := r.AddSender(name)
	if err != nil {
		return nil, err
	}
	ss := &SenderSession{sender: s, conn: conn, receiver: rs}
	rs.mu.Lock()
	rs.senders[s.ID] = ss
	rs.mu.Unlock()
	rs.conn.Send(Message{Type: "joined", From: s.ID, Name: name})
	return ss, nil
}

// FromSender: göndericiden gelen mesajı from damgasıyla receiver'a iletir.
func (h *Hub) FromSender(ss *SenderSession, m Message) {
	m.From = ss.sender.ID
	m.To = ""
	ss.receiver.conn.Send(m)
}

// FromReceiver: receiver'dan gelen mesajı to alanındaki sender'a iletir.
func (h *Hub) FromReceiver(rs *ReceiverSession, m Message) {
	rs.mu.Lock()
	target := rs.senders[m.To]
	rs.mu.Unlock()
	if target == nil {
		return
	}
	m.To = ""
	target.conn.Send(m)
}

// SenderGone: gönderici koptu — odadan düşür, receiver'a "left" bildir.
func (h *Hub) SenderGone(ss *SenderSession) {
	rs := ss.receiver
	rs.mu.Lock()
	delete(rs.senders, ss.sender.ID)
	closed := rs.closed
	rs.mu.Unlock()
	rs.rm.RemoveSender(ss.sender.ID)
	if !closed {
		rs.conn.Send(Message{Type: "left", From: ss.sender.ID})
	}
}

// RegeneratePIN: odaya yeni PIN atar ve receiver'a bildirir. Eski PIN anında
// geçersizleşir; bağlı sender'lar etkilenmez.
func (h *Hub) RegeneratePIN(rs *ReceiverSession) {
	pin := h.rooms.Regenerate(rs.rm)
	rs.conn.Send(Message{Type: "pin", PIN: pin, RoomID: rs.rm.ID})
}

// ReceiverGone: receiver koptu — tüm sender'lara hata bildirilir, bağlantıları
// kapatılır ve oda kayıttan düşürülür.
func (h *Hub) ReceiverGone(rs *ReceiverSession) {
	rs.mu.Lock()
	rs.closed = true
	senders := make([]*SenderSession, 0, len(rs.senders))
	for _, ss := range rs.senders {
		senders = append(senders, ss)
	}
	rs.senders = map[string]*SenderSession{}
	rs.mu.Unlock()

	for _, ss := range senders {
		ss.conn.Send(Message{Type: "error", Reason: "receiver-gone"})
		ss.conn.Close()
	}
	h.mu.Lock()
	delete(h.sessions, rs.rm)
	// Alıcı oturumu kapandığında ilişkili tüm güven jetonları geçersiz olur.
	for tok, session := range h.trustTokens {
		if session == rs {
			delete(h.trustTokens, tok)
		}
	}
	h.mu.Unlock()
	h.rooms.Close(rs.rm)
}

// IssueToken: başarılı PIN doğrulaması sonrası bu gönderici için 256-bit
// güven jetonu üretir ve alıcı oturumuna bağlar.
func (h *Hub) IssueToken(ss *SenderSession) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	tok := hex.EncodeToString(b)
	h.mu.Lock()
	h.trustTokens[tok] = ss.receiver
	h.mu.Unlock()
	return tok, nil
}

// JoinByToken: geçerli bir güven jetonuyla göndericiyi odaya ekler; PIN
// doğrulaması atlanır. Jeton geçersizse veya alıcı kapandıysa ErrBadToken döner.
func (h *Hub) JoinByToken(token, name string, conn Conn) (*SenderSession, error) {
	h.mu.Lock()
	rs := h.trustTokens[token]
	h.mu.Unlock()
	if rs == nil || rs.isClosed() {
		return nil, ErrBadToken
	}
	s, err := rs.rm.AddSender(name)
	if err != nil {
		return nil, err
	}
	ss := &SenderSession{sender: s, conn: conn, receiver: rs}
	rs.mu.Lock()
	rs.senders[s.ID] = ss
	rs.mu.Unlock()
	rs.conn.Send(Message{Type: "joined", From: s.ID, Name: name})
	return ss, nil
}

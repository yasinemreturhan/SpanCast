// Package room, multi-share oda modelini yönetir: bir receiver oda açar,
// en fazla MaxSenders gönderici PIN ile katılır. Hiç sender bağlanmamış bir
// odanın PIN'i PinTTL sonra kullanılamaz; aktif odada PIN yaşamaya devam eder
// (yeni katılımcılar aynı kodla eklenebilsin diye).
package room

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"sync"
	"time"
)

const (
	// PinTTL: hiç sender katılmamış odanın PIN geçerlilik süresi.
	PinTTL = 2 * time.Minute
	// MaxSenders: bir odaya aynı anda bağlanabilecek gönderici sayısı.
	MaxSenders = 4
)

var (
	ErrNotFound = errors.New("oda bulunamadı")
	ErrExpired  = errors.New("PIN süresi doldu")
	ErrRoomFull = errors.New("oda dolu")
)

// Sender: odaya katılmış bir göndericinin kimliği.
type Sender struct {
	ID   string
	Name string
}

// Room: tek receiver + N sender'lık bir paylaşım oturumu.
type Room struct {
	ID string

	mu      sync.Mutex
	pin     string
	created time.Time
	senders map[string]*Sender
	everHad bool // en az bir sender katıldı mı (TTL muafiyeti için)
	nextSeq int
}

// Manager: PIN → oda kayıt defteri.
type Manager struct {
	mu    sync.Mutex
	byPin map[string]*Room
	now   func() time.Time // testlerde enjekte edilir
}

func NewManager() *Manager {
	return &Manager{byPin: map[string]*Room{}, now: time.Now}
}

func randomPIN() string {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		panic(fmt.Sprintf("crypto/rand kullanılamıyor: %v", err))
	}
	return fmt.Sprintf("%06d", n.Int64())
}

func randomID(prefix string) string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1<<48))
	return fmt.Sprintf("%s-%012x", prefix, n.Int64())
}

// CreateRoom yeni bir oda açar ve benzersiz bir PIN atar.
func (m *Manager) CreateRoom() *Room {
	m.mu.Lock()
	defer m.mu.Unlock()
	r := &Room{
		ID:      randomID("room"),
		created: m.now(),
		senders: map[string]*Sender{},
	}
	for {
		pin := randomPIN()
		if _, taken := m.byPin[pin]; !taken {
			r.pin = pin
			m.byPin[pin] = r
			return r
		}
	}
}

// Join, PIN ile odayı bulur. Hiç sender görmemiş ve TTL'i geçmiş odalar
// kayıttan düşürülür ve ErrExpired döner.
func (m *Manager) Join(pin string) (*Room, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.byPin[pin]
	if !ok {
		return nil, ErrNotFound
	}
	r.mu.Lock()
	expired := !r.everHad && m.now().Sub(r.created) > PinTTL
	r.mu.Unlock()
	if expired {
		delete(m.byPin, pin)
		return nil, ErrExpired
	}
	return r, nil
}

// Regenerate odaya yeni PIN atar; eski PIN anında geçersizleşir.
func (m *Manager) Regenerate(r *Room) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.byPin, r.pin)
	for {
		pin := randomPIN()
		if _, taken := m.byPin[pin]; !taken {
			r.mu.Lock()
			r.pin = pin
			r.created = m.now()
			r.mu.Unlock()
			m.byPin[pin] = r
			return pin
		}
	}
}

// Close odayı kayıttan düşürür.
func (m *Manager) Close(r *Room) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.byPin, r.pin)
}

func (r *Room) PIN() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.pin
}

// AddSender odaya yeni gönderici ekler; oda doluysa ErrRoomFull.
func (r *Room) AddSender(name string) (*Sender, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.senders) >= MaxSenders {
		return nil, ErrRoomFull
	}
	r.nextSeq++
	s := &Sender{ID: fmt.Sprintf("s%d", r.nextSeq), Name: name}
	r.senders[s.ID] = s
	r.everHad = true
	return s, nil
}

func (r *Room) RemoveSender(id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.senders, id)
}

// Senders, mevcut göndericilerin anlık kopyasını döner.
func (r *Room) Senders() []*Sender {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]*Sender, 0, len(r.senders))
	for _, s := range r.senders {
		out = append(out, s)
	}
	return out
}

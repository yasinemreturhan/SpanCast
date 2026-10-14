// PIN challenge-response: PIN ağdan hiç geçmez. Sunucu rastgele bir salt
// (challenge) gönderir; istemci HMAC-SHA256(key=PIN, msg=saltHex) proof'unu
// döner. Sunucu, açık odaların PIN'leriyle aynı HMAC'i hesaplayıp sabit
// zamanlı karşılaştırır. (Tam PAKE — SPAKE2 — Rust çekirdeğiyle gelecek;
// bu şema TLS + hız sınırıyla birlikte MVP için yeterlidir.)
package signal

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"

	"github.com/yasinemreturhan/DoScreen/server/internal/room"
)

// Proof: HMAC-SHA256(key=pin, msg=saltHex) → hex. Web istemcisiyle birebir
// aynı tanım (bkz. web/js/pair.js).
func Proof(pin, saltHex string) string {
	mac := hmac.New(sha256.New, []byte(pin))
	mac.Write([]byte(saltHex))
	return hex.EncodeToString(mac.Sum(nil))
}

// NewSalt: 16 baytlık rastgele challenge (hex).
func NewSalt() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand kullanılamıyor: " + err.Error())
	}
	return hex.EncodeToString(b)
}

// JoinByProof: proof'u açık odaların PIN'leriyle eşleştirir; bulursa normal
// JoinRoom akışını çalıştırır. Eşleşme yoksa room.ErrNotFound döner.
func (h *Hub) JoinByProof(saltHex, proof, name string, conn Conn) (*SenderSession, error) {
	h.mu.Lock()
	var pin string
	for rm := range h.sessions {
		want := Proof(rm.PIN(), saltHex)
		if hmac.Equal([]byte(want), []byte(proof)) {
			pin = rm.PIN()
			break
		}
	}
	h.mu.Unlock()
	if pin == "" {
		return nil, room.ErrNotFound
	}
	return h.JoinRoom(pin, name, conn)
}

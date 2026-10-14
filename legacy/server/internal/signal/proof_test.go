package signal

import "testing"

func TestProofDeterministicAndSaltSensitive(t *testing.T) {
	p1 := Proof("123456", "aabbcc")
	p2 := Proof("123456", "aabbcc")
	if p1 != p2 {
		t.Fatal("aynı girdi aynı proof üretmeli")
	}
	if Proof("123456", "ddeeff") == p1 {
		t.Fatal("farklı salt farklı proof üretmeli")
	}
	if Proof("654321", "aabbcc") == p1 {
		t.Fatal("farklı PIN farklı proof üretmeli")
	}
	if len(p1) != 64 { // hex(SHA-256)
		t.Fatalf("proof 64 hex karakter olmalı: %d", len(p1))
	}
}

// Bilinen vektör: web tarafındaki (crypto.subtle) implementasyonla aynı
// sonucu üretmeli. Vektör node:crypto ile üretildi:
//   HMAC-SHA256(key="123456", msg="00ff10") =
//   517366fe3e42e24656f7bafdde7e4b1bf3be181c2326211fae7cef3042ef53cf
func TestProofKnownVector(t *testing.T) {
	want := "517366fe3e42e24656f7bafdde7e4b1bf3be181c2326211fae7cef3042ef53cf"
	if got := Proof("123456", "00ff10"); got != want {
		t.Fatalf("vektör uyuşmadı:\n got=%s\nwant=%s", got, want)
	}
}

func TestJoinByProof(t *testing.T) {
	h := NewHub()
	recv := &fakeConn{}
	sess := h.OpenRoom(recv)
	pin := sess.PIN()
	salt := "0011223344556677"

	// Doğru proof → katılır.
	sc := &fakeConn{}
	ss, err := h.JoinByProof(salt, Proof(pin, salt), "laptop", sc)
	if err != nil {
		t.Fatalf("doğru proof reddedildi: %v", err)
	}
	if ss == nil || ss.ID() == "" {
		t.Fatal("geçerli oturum dönmeliydi")
	}

	// Yanlış proof → reddedilir.
	if _, err := h.JoinByProof(salt, Proof("000000", salt), "x", &fakeConn{}); err == nil {
		t.Fatal("yanlış proof kabul edilmemeliydi")
	}
}

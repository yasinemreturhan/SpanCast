package ws

import (
	"testing"
	"time"
)

func TestLimiterBlocksAfterMax(t *testing.T) {
	now := time.Now()
	l := NewLimiter(3, time.Minute)
	l.now = func() time.Time { return now }

	ip := "10.0.0.9"
	for i := 0; i < 3; i++ {
		if !l.Allowed(ip) {
			t.Fatalf("%d. denemede henüz engellenmemeliydi", i+1)
		}
		l.Fail(ip)
	}
	if l.Allowed(ip) {
		t.Fatal("3 başarısız denemeden sonra engellenmeli")
	}
	if !l.Allowed("10.0.0.10") {
		t.Fatal("başka IP etkilenmemeli")
	}
}

func TestLimiterWindowSlides(t *testing.T) {
	now := time.Now()
	l := NewLimiter(2, time.Minute)
	l.now = func() time.Time { return now }

	ip := "10.0.0.9"
	l.Fail(ip)
	l.Fail(ip)
	if l.Allowed(ip) {
		t.Fatal("pencere içinde engellenmeli")
	}
	now = now.Add(61 * time.Second)
	if !l.Allowed(ip) {
		t.Fatal("pencere geçince izin verilmeli")
	}
}

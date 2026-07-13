package ws

import (
	"sync"
	"time"
)

// Limiter: IP başına kayan pencereli başarısız deneme sınırı — PIN kaba
// kuvvet denemelerini durdurur.
type Limiter struct {
	mu     sync.Mutex
	fails  map[string][]time.Time
	max    int
	window time.Duration
	now    func() time.Time // testlerde enjekte edilir
}

func NewLimiter(max int, window time.Duration) *Limiter {
	return &Limiter{fails: map[string][]time.Time{}, max: max, window: window, now: time.Now}
}

// Allowed: ip yeni bir deneme yapabilir mi? (Süresi geçen kayıtlar temizlenir.)
func (l *Limiter) Allowed(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	cutoff := l.now().Add(-l.window)
	recent := l.fails[ip][:0:0]
	for _, t := range l.fails[ip] {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	if len(recent) == 0 {
		delete(l.fails, ip)
	} else {
		l.fails[ip] = recent
	}
	return len(recent) < l.max
}

// Fail: başarısız denemeyi kaydeder.
func (l *Limiter) Fail(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.fails[ip] = append(l.fails[ip], l.now())
}
